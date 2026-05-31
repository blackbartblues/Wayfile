#include "services/fileoperations.h"
#include "services/fileoperations_helpers.h"
#include "services/giotransferworker.h"
#include <QClipboard>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QStandardPaths>
#include <QThread>
#include <QUuid>
#include <algorithm>

// Shared path/URI helpers now live in their own translation unit; the engine
// methods and the two engine-local helpers below call them unqualified.
using namespace FileOperationsHelpers;

namespace {

void appendUniqueLocation(QStringList *paths, const QString &path)
{
    const QString normalized = normalizeLocation(path);
    if (normalized.isEmpty() || paths->contains(normalized))
        return;

    paths->append(normalized);
}

QStringList uniqueLocations(const QStringList &paths)
{
    QStringList result;
    for (const QString &path : paths)
        appendUniqueLocation(&result, path);
    return result;
}

}

FileOperations::FileOperations(QObject *parent)
    : QObject(parent)
{
    // Keep the cached clipboard-image flag current: re-probe whenever the
    // clipboard changes. On Wayland this fires on focus-in, so by the time the
    // user opens a menu or presses Ctrl+V the flag is usually already fresh;
    // the paste UI also refreshes on demand. The probe is async, so nothing
    // blocks on wl-paste.
    if (QClipboard *clipboard = QGuiApplication::clipboard())
        connect(clipboard, &QClipboard::dataChanged, this,
                &FileOperations::refreshClipboardImageAvailable);
    refreshClipboardImageAvailable();
}

FileOperations::~FileOperations()
{
    // Cancel in-flight transfers and join their threads before this object is
    // destroyed: the worker connections and queued lambdas capture `this`, so
    // a thread still running after destruction would dereference a dangling
    // pointer. Gio workers respond to cancel() promptly via their cancellable;
    // simple operations have no cancellation channel, so we bound the wait.
    for (auto &t : m_activeTransfers) {
        if (t.worker)
            t.worker->cancel();
    }
    for (auto &t : m_activeTransfers) {
        if (t.thread) {
            t.thread->quit();
            // Bounded wait: gio workers exit promptly after cancel(); a simple
            // operation has no cancellation channel, so cap the shutdown stall.
            // If it does not stop in time we leave the thread object to leak
            // (the process is exiting) rather than terminate() it mid-syscall.
            t.thread->wait(5000);
        }
    }
    m_activeTransfers.clear();

    // Stop any in-flight async archive-root listings: their finished/error
    // lambdas capture `this`, so they must not outlive this object.
    const QList<QProcess *> archiveProcs = m_archiveRootProcs.values();
    m_archiveRootProcs.clear();
    for (QProcess *proc : archiveProcs) {
        proc->disconnect(this);
        proc->kill();
        proc->waitForFinished(100);
        delete proc;
    }

    // Same for the in-flight clipboard-image probe.
    if (m_clipboardProbeProcess) {
        m_clipboardProbeProcess->disconnect(this);
        m_clipboardProbeProcess->kill();
        m_clipboardProbeProcess->waitForFinished(100);
        delete m_clipboardProbeProcess;
        m_clipboardProbeProcess = nullptr;
    }
}

bool FileOperations::busy() const { return m_busy; }
double FileOperations::progress() const { return m_progress; }
QString FileOperations::statusText() const { return m_statusText; }
QString FileOperations::speed() const { return m_speed; }
QString FileOperations::eta() const { return m_eta; }
bool FileOperations::paused() const { return m_paused; }
QString FileOperations::currentFile() const { return m_currentFile; }

QVariantList FileOperations::activeTransfers() const
{
    QVariantList list;
    for (const auto &t : m_activeTransfers) {
        QVariantMap map;
        map["id"] = t.id;
        map["statusText"] = t.statusText;
        map["progress"] = t.progress;
        map["speed"] = t.speed;
        map["eta"] = t.eta;
        map["currentFile"] = t.currentFile;
        map["paused"] = t.paused;
        list.append(map);
    }
    return list;
}

QStringList FileOperations::pendingTargetPaths() const
{
    QStringList paths;
    for (const auto &transfer : m_activeTransfers) {
        for (const QString &path : transfer.targetPaths) {
            if (!path.isEmpty() && !paths.contains(path))
                paths.append(path);
        }
    }
    return paths;
}

FileOperations::ActiveTransfer *FileOperations::findTransfer(int id)
{
    for (auto &t : m_activeTransfers) {
        if (t.id == id)
            return &t;
    }
    return nullptr;
}

void FileOperations::emitAggregatedState()
{
    const bool wasBusy = m_busy;
    m_busy = !m_activeTransfers.isEmpty();

    if (m_activeTransfers.isEmpty()) {
        // Don't reset m_progress — leave at 1.0 after completion for UI linger
        m_statusText.clear();
        m_speed.clear();
        m_eta.clear();
        m_currentFile.clear();
        m_paused = false;
    } else if (m_activeTransfers.size() == 1) {
        const auto &t = m_activeTransfers.first();
        m_progress = t.progress;
        m_statusText = t.statusText;
        m_speed = t.speed;
        m_eta = t.eta;
        m_currentFile = t.currentFile;
        m_paused = t.paused;
    } else {
        // Multiple transfers: show aggregate
        m_statusText = QString("%1 transfers active").arg(m_activeTransfers.size());
        m_paused = std::all_of(m_activeTransfers.begin(), m_activeTransfers.end(),
                               [](const ActiveTransfer &t) { return t.paused; });

        // Aggregate progress as average
        double totalProgress = 0;
        int countWithProgress = 0;
        for (const auto &t : m_activeTransfers) {
            if (t.progress >= 0) {
                totalProgress += t.progress;
                ++countWithProgress;
            }
        }
        m_progress = countWithProgress > 0 ? totalProgress / countWithProgress : -1.0;
        m_speed.clear();
        m_eta.clear();
        m_currentFile.clear();
    }

    if (wasBusy != m_busy) emit busyChanged();
    emit progressChanged();
    emit statusTextChanged();
    emit speedChanged();
    emit etaChanged();
    emit pausedChanged();
    emit currentFileChanged();
    emit activeTransfersChanged();
}

void FileOperations::transferResolvedItems(const QVariantList &operations, bool moveOperation)
{
    if (operations.isEmpty()) {
        emit operationFinished(true, QString());
        return;
    }

    QVariantList preparedOperations;

    for (const QVariant &variant : operations) {
        QVariantMap item = variant.toMap();
        const QString sourcePath = normalizeLocation(item.value("sourcePath").toString());
        const QString targetPath = normalizeLocation(item.value("targetPath").toString());
        const QString backupPath = normalizeLocation(item.value("backupPath").toString());
        const bool overwrite = item.value("overwrite").toBool();

        if (sourcePath.isEmpty() || targetPath.isEmpty()) {
            emit operationFinished(false, "Transfer operation is missing a source or destination path");
            return;
        }

        if (sourcePath == targetPath) {
            emit operationFinished(false, QString("Source and destination are the same for %1").arg(locationFileName(sourcePath)));
            return;
        }

        item["sourcePath"] = sourcePath;
        item["targetPath"] = targetPath;
        item["backupPath"] = backupPath;
        item["overwrite"] = overwrite;

        preparedOperations.append(item);
    }

    startGioTransfer(preparedOperations, moveOperation);
}

void FileOperations::resetTransferState()
{
    m_pendingChangedPaths.clear();
}

void FileOperations::setProgressValue(double progress, const QString &speed, const QString &eta)
{
    const bool progressDiff = m_progress != progress;
    const bool speedDiff = m_speed != speed;
    const bool etaDiff = m_eta != eta;

    m_progress = progress;
    m_speed = speed;
    m_eta = eta;

    if (progressDiff) emit progressChanged();
    if (speedDiff) emit speedChanged();
    if (etaDiff) emit etaChanged();
}

void FileOperations::setPendingChangedPaths(const QStringList &paths)
{
    m_pendingChangedPaths = uniqueLocations(paths);
}

void FileOperations::emitPendingChangedPaths()
{
    emitChangedPaths(m_pendingChangedPaths);
    m_pendingChangedPaths.clear();
}

void FileOperations::emitChangedPaths(const QStringList &paths)
{
    const QStringList normalizedPaths = uniqueLocations(paths);
    if (!normalizedPaths.isEmpty())
        emit pathsChanged(normalizedPaths);
}

void FileOperations::pauseTransfer(int transferId)
{
    if (transferId < 0) {
        for (auto &t : m_activeTransfers) {
            if (!t.worker) continue;
            t.worker->pause();
            t.paused = true;
            t.statusText = QStringLiteral("Paused");
        }
    } else if (auto *t = findTransfer(transferId)) {
        if (t->worker) {
            t->worker->pause();
            t->paused = true;
            t->statusText = QStringLiteral("Paused");
        }
    }
    emitAggregatedState();
}

void FileOperations::resumeTransfer(int transferId)
{
    if (transferId < 0) {
        for (auto &t : m_activeTransfers) {
            if (!t.worker) continue;
            t.worker->resume();
            t.paused = false;
        }
    } else if (auto *t = findTransfer(transferId)) {
        if (t->worker) {
            t->worker->resume();
            t->paused = false;
        }
    }
    emitAggregatedState();
}

void FileOperations::cancelTransfer(int transferId)
{
    // Simple operations (compress/extract/trash) have no GioTransferWorker, so
    // their transfer entries carry a null worker — guard every dereference.
    if (transferId < 0) {
        for (auto &t : m_activeTransfers)
            if (t.worker) t.worker->cancel();
    } else if (auto *t = findTransfer(transferId)) {
        if (t->worker) t->worker->cancel();
    }
}

void FileOperations::cleanupTransfer(int transferId)
{
    for (int i = 0; i < m_activeTransfers.size(); ++i) {
        if (m_activeTransfers[i].id == transferId) {
            auto &t = m_activeTransfers[i];
            if (t.thread) {
                t.thread->quit();
                t.thread->wait();
                t.thread->deleteLater();
            }
            m_activeTransfers.removeAt(i);
            break;
        }
    }
    emitAggregatedState();
}

void FileOperations::startSimpleOperation(const QString &statusText, const QStringList &changedPaths,
                                           std::function<QString(ProgressReporter)> work)
{
    const int id = m_nextTransferId++;
    ActiveTransfer transfer;
    transfer.id = id;
    transfer.statusText = statusText;
    transfer.progress = -1.0;
    transfer.changedPaths = changedPaths;

    auto *thread = new QThread;
    transfer.thread = thread;
    transfer.worker = nullptr;
    m_activeTransfers.append(transfer);
    emitAggregatedState();

    auto reportProgress = [this, id](int current, int total, const QString &fileName) {
        QMetaObject::invokeMethod(this, [this, id, current, total, fileName]() {
            if (auto *t = findTransfer(id)) {
                t->progress = total > 0 ? static_cast<double>(current) / total : -1.0;
                t->currentFile = fileName;
                emitAggregatedState();
            }
        }, Qt::QueuedConnection);
    };

    auto *runner = new QObject;
    runner->moveToThread(thread);

    connect(thread, &QThread::started, runner, [runner, work, reportProgress, this, id]() {
        const QString error = work(reportProgress);
        const bool ok = error.isEmpty();
        QMetaObject::invokeMethod(this, [this, id, ok, error]() {
            if (auto *t = findTransfer(id)) {
                t->progress = 1.0;
                emitChangedPaths(t->changedPaths);
            }
            m_progress = 1.0;
            emit operationFinished(ok, error);
            cleanupTransfer(id);
        }, Qt::QueuedConnection);
        runner->deleteLater();
    });

    connect(thread, &QThread::finished, thread, &QObject::deleteLater);
    thread->start();
}

void FileOperations::startGioTransfer(const QVariantList &operations, bool moveOperation)
{
    QList<GioTransferWorker::TransferItem> items;
    int itemCount = 0;
    QStringList changedPaths;
    QStringList targetPaths;

    for (const QVariant &variant : operations) {
        const QVariantMap item = variant.toMap();
        const QString sourcePath = item.value("sourcePath").toString();
        const QString targetPath = item.value("targetPath").toString();
        const QString backupPath = item.value("backupPath").toString();
        const bool overwrite = item.value("overwrite").toBool();

        items.append({sourcePath, targetPath, backupPath, overwrite});
        ++itemCount;

        if (moveOperation)
            appendUniqueLocation(&changedPaths, sourcePath);
        appendUniqueLocation(&changedPaths, targetPath);
        appendUniqueLocation(&changedPaths, backupPath);
        appendUniqueLocation(&targetPaths, targetPath);
    }

    const int id = m_nextTransferId++;
    ActiveTransfer transfer;
    transfer.id = id;
    transfer.statusText = QString(moveOperation ? "Moving %1 item(s)..." : "Copying %1 item(s)...").arg(itemCount);
    transfer.progress = -1.0;
    transfer.changedPaths = changedPaths;
    transfer.targetPaths = targetPaths;

    auto *thread = new QThread;
    auto *worker = new GioTransferWorker;
    worker->moveToThread(thread);
    transfer.thread = thread;
    transfer.worker = worker;

    m_activeTransfers.append(transfer);

    connect(thread, &QThread::finished, worker, &QObject::deleteLater);

    connect(worker, &GioTransferWorker::progressUpdated, this,
            [this, id](double progress, const QString &speed, const QString &eta) {
        if (auto *t = findTransfer(id)) {
            t->progress = progress;
            t->speed = speed;
            t->eta = eta;
            emitAggregatedState();
        }
    });

    connect(worker, &GioTransferWorker::itemStarted, this,
            [this, id](const QString &sourcePath, const QString &targetPath) {
        Q_UNUSED(targetPath)
        if (auto *t = findTransfer(id)) {
            t->currentFile = sourcePath.mid(sourcePath.lastIndexOf('/') + 1);
            emitAggregatedState();
        }
    });

    connect(worker, &GioTransferWorker::finished, this,
            [this, id](bool success, const QString &error) {
        if (auto *t = findTransfer(id)) {
            emitChangedPaths(t->changedPaths);
            if (success)
                t->progress = 1.0;
        }
        if (success)
            m_progress = 1.0;
        emit operationFinished(success, error);
        cleanupTransfer(id);
    });

    emitAggregatedState();

    thread->start();
    QMetaObject::invokeMethod(worker, [worker, items, moveOperation]() {
        worker->execute(items, moveOperation);
    }, Qt::QueuedConnection);
}

QString FileOperations::conflictBackupPath(const QString &targetPath) const
{
    QString cacheRoot = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (cacheRoot.isEmpty())
        cacheRoot = QDir::homePath() + "/.cache/heimdall";

    QDir backupDir(cacheRoot + "/conflict-backups");
    backupDir.mkpath(".");

    const QString baseName = QFileInfo(targetPath).fileName();
    const QString uniqueName = QUuid::createUuid().toString(QUuid::WithoutBraces) + "-" + baseName;
    return backupDir.filePath(uniqueName);
}
