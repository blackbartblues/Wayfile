#include "services/previewservice.h"
#include "services/previewservice_internal.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

// Core PreviewService: lifecycle, the async-process watchdog, support probing,
// the low-level read/list primitives, and binary/text classification. The
// process-based loaders live in previewservice_text.cpp (ANSI/bat + text/trash/
// dir) and previewservice_binary.cpp (archive/font/pdf) — all methods of this
// same class. encodedUri/startGioCat are defined here and shared via
// previewservice_internal.h.

namespace {

bool runningInFlatpak()
{
    static const bool inSandbox = QFile::exists(QStringLiteral("/.flatpak-info"));
    return inSandbox;
}

} // namespace

namespace previewservice_detail {

QString encodedUri(const QString &path)
{
    return QUrl(path).toString(QUrl::FullyEncoded);
}

void startGioCat(QProcess &proc, const QString &uri)
{
    if (runningInFlatpak()) {
        proc.start(QStringLiteral("flatpak-spawn"),
                   {QStringLiteral("--host"), QStringLiteral("gio"),
                    QStringLiteral("cat"), uri});
    } else {
        proc.start(QStringLiteral("gio"), {QStringLiteral("cat"), uri});
    }
}

} // namespace previewservice_detail

using namespace previewservice_detail;

PreviewService::PreviewService(QObject *parent)
    : QObject(parent)
{
}

PreviewService::~PreviewService()
{
    // Stop any in-flight async processes (archive listings, pdfinfo, bat
    // highlights) so QProcess doesn't warn ("Destroyed while process is still
    // running") or block during teardown. Disconnect first so the
    // finished/errorOccurred lambdas — which touch members — can't fire while
    // the object is being destroyed.
    const auto stopAll = [this](QHash<QString, QProcess *> &procMap) {
        const QList<QProcess *> procs = procMap.values();
        procMap.clear();
        for (QProcess *proc : procs) {
            proc->disconnect(this);
            proc->kill();
            proc->waitForFinished(100);
        }
    };
    stopAll(m_archiveProcs);
    stopAll(m_pdfProcs);
    stopAll(m_textProcs);
    stopAll(m_dirProcs);
}

void PreviewService::armProcessTimeout(QProcess *proc, int ms)
{
    // Single-shot watchdog parented to the process. On expiry, kill it if it's
    // still running; the kill drives the proc's finished/errorOccurred handler,
    // which emits the fallback result and frees its per-path dedup slot. The
    // timer dies with the process (proc->deleteLater() takes its child timer),
    // so a process that finishes first never gets killed.
    auto *timer = new QTimer(proc);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, proc, [proc]() {
        if (proc->state() != QProcess::NotRunning)
            proc->kill();
    });
    timer->start(ms);
}

bool PreviewService::pdfPreviewAvailable() const
{
    return !QStandardPaths::findExecutable(QStringLiteral("pdftoppm")).isEmpty()
        && !QStandardPaths::findExecutable(QStringLiteral("pdfinfo")).isEmpty();
}

void PreviewService::refreshSupport()
{
    emit supportChanged();
}

QVariantMap PreviewService::loadDirectoryPreview(const QString &path, int maxEntries) const
{
    QVariantMap result;
    bool truncated = false;
    QString error;
    const QStringList entries = listDirectoryEntries(path, maxEntries, &truncated, &error);

    result["entries"] = entries;
    result["truncated"] = truncated;
    result["error"] = error;
    result["count"] = entries.size();
    return result;
}

QByteArray PreviewService::readPathBytes(const QString &path, qint64 maxBytes, bool *truncated,
                                         QString *error) const
{
    if (truncated)
        *truncated = false;
    if (error)
        error->clear();

    if (path.isEmpty()) {
        if (error)
            *error = QStringLiteral("No file selected");
        return {};
    }

    const qint64 readLimit = qMax<qint64>(1, maxBytes) + 1;

    if (isTrashUri(path)) {
        QProcess proc;
        startGioCat(proc, encodedUri(path));
        if (!proc.waitForStarted(2000)) {
            if (error)
                *error = QStringLiteral("Failed to start preview reader");
            return {};
        }

        QByteArray data;
        while (proc.state() != QProcess::NotRunning) {
            if (!proc.waitForReadyRead(100))
                proc.waitForFinished(100);
            data += proc.readAllStandardOutput();
            if (data.size() >= readLimit) {
                proc.kill();
                proc.waitForFinished(1000);
                break;
            }
        }
        data += proc.readAllStandardOutput();

        if (proc.exitStatus() != QProcess::NormalExit && data.isEmpty()) {
            if (error)
                *error = QStringLiteral("Failed to read preview data");
            return {};
        }

        if (data.size() > maxBytes) {
            if (truncated)
                *truncated = true;
            data.truncate(maxBytes);
        }
        return data;
    }

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        if (error)
            *error = file.errorString();
        return {};
    }

    QByteArray data = file.read(readLimit);
    if (data.size() > maxBytes) {
        if (truncated)
            *truncated = true;
        data.truncate(maxBytes);
    }
    return data;
}

QStringList PreviewService::listDirectoryEntries(const QString &path, int maxEntries, bool *truncated,
                                                QString *error) const
{
    if (truncated)
        *truncated = false;
    if (error)
        error->clear();

    if (path.isEmpty()) {
        if (error)
            *error = QStringLiteral("No folder selected");
        return {};
    }

    if (isTrashUri(path)) {
        QProcess proc;
        proc.start("gio", {"list", "-h", encodedUri(path)});
        if (!proc.waitForFinished(5000) || proc.exitCode() != 0) {
            if (error)
                *error = QString::fromUtf8(proc.readAllStandardError()).trimmed();
            return {};
        }

        const QStringList allEntries = QString::fromUtf8(proc.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts);
        if (truncated)
            *truncated = maxEntries > 0 && allEntries.size() > maxEntries;
        return maxEntries > 0 ? allEntries.mid(0, maxEntries) : allEntries;
    }

    QDir dir(path);
    if (!dir.exists()) {
        if (error)
            *error = QStringLiteral("Folder does not exist");
        return {};
    }

    const QFileInfoList allEntries = dir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden,
                                                       QDir::DirsFirst | QDir::IgnoreCase | QDir::Name);
    QStringList names;
    const int count = maxEntries > 0 ? qMin(maxEntries, allEntries.size()) : allEntries.size();
    for (int i = 0; i < count; ++i) {
        const QFileInfo &info = allEntries.at(i);
        names.append(info.isDir() ? info.fileName() + "/" : info.fileName());
    }

    if (truncated)
        *truncated = maxEntries > 0 && allEntries.size() > maxEntries;
    return names;
}

bool PreviewService::isTrashUri(const QString &path)
{
    return QUrl(path).scheme() == QStringLiteral("trash");
}

bool PreviewService::looksBinary(const QByteArray &data)
{
    if (data.contains('\0'))
        return true;

    const int sampleSize = qMin(data.size(), 4096);
    if (sampleSize <= 0)
        return false;

    int suspicious = 0;
    for (int i = 0; i < sampleSize; ++i) {
        const unsigned char ch = static_cast<unsigned char>(data.at(i));
        const bool isWhitespace = ch == '\n' || ch == '\r' || ch == '\t' || ch == '\f';
        if (!isWhitespace && ch < 0x20)
            ++suspicious;
    }

    return suspicious * 10 > sampleSize;
}

QString PreviewService::decodeText(const QByteArray &data)
{
    const QString utf8 = QString::fromUtf8(data);
    if (!utf8.contains(QChar::ReplacementCharacter))
        return utf8;
    return QString::fromLocal8Bit(data);
}
