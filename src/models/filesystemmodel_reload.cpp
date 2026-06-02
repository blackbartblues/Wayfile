#include "models/filesystemmodel.h"
#include "models/filesystemmodel_helpers.h"
#include "services/gitstatusservice.h"

#include <QByteArray>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QFuture>
#include <QProcess>
#include <QStorageInfo>
#include <QTimer>
#include <QUrl>
#include <QtConcurrent>
#include <algorithm>

using namespace FsmHelpers;

void FileSystemModel::reload()
{
    cancelRemoteReload();
    ++m_remoteReloadGeneration;

    if (isTrashRoot()) {
        if (m_synchronousReload) {
            // Test mode: keep it synchronous so rowCount() is populated at once.
            beginResetModel();
            m_entries.clear();
            m_remoteEntries.clear();
            m_trashEntries.clear();
            m_fileCount = 0;
            m_folderCount = 0;
            reloadTrash();
            endResetModel();
            emit countsChanged();
            return;
        }

        // GUI: clear rows now so the old dir disappears, then fetch the trash
        // listing asynchronously (reloadTrashAsync owns the reset around the
        // result) — navigating into Trash no longer freezes for up to 5s.
        beginResetModel();
        m_entries.clear();
        m_remoteEntries.clear();
        m_trashEntries.clear();
        m_fileCount = 0;
        m_folderCount = 0;
        endResetModel();
        emit countsChanged();
        reloadTrashAsync();
        return;
    }

    if (isRemoteRoot()) {
        // Remote: clear existing rows first so the old dir disappears,
        // then fire the async gio process. reloadRemote() / applyRemoteReload
        // own their own model-reset around the result.
        beginResetModel();
        m_entries.clear();
        m_remoteEntries.clear();
        m_trashEntries.clear();
        m_fileCount = 0;
        m_folderCount = 0;
        endResetModel();
        emit countsChanged();
        reloadRemote();
        return;
    }

    // Local: clear existing rows immediately so old directory's contents
    // vanish the moment the user navigates; the async scan will repopulate
    // via applyLocalReload() which runs its own begin/endResetModel.
    beginResetModel();
    m_entries.clear();
    m_remoteEntries.clear();
    m_trashEntries.clear();
    m_fileCount = 0;
    m_folderCount = 0;
    endResetModel();
    emit countsChanged();

    reloadLocal();
}

void FileSystemModel::reloadLocal()
{
    scheduleLocalReload(/*tryDiff=*/false);
}

FileSystemModel::LocalReloadResult FileSystemModel::scanLocalEntries(
    quint64 generation, const QString &rootPath, bool showHidden,
    bool hiddenOnly, QDir::SortFlags sortFlags)
{
    LocalReloadResult result;
    result.generation = generation;
    if (rootPath.isEmpty())
        return result;

    QDir dir(rootPath);
    QDir::Filters filters = QDir::AllEntries | QDir::NoDotAndDotDot;
    // hiddenOnly forces the Hidden flag on even when showHidden is false: the
    // dedicated "Hidden" view always scans dotfiles, then keeps only those.
    if (showHidden || hiddenOnly)
        filters |= QDir::Hidden;

    const QFileInfoList infos = dir.entryInfoList(filters, sortFlags);
    result.entries.reserve(infos.size());
    for (const QFileInfo &info : infos) {
        if (hiddenOnly && !info.fileName().startsWith(QLatin1Char('.')))
            continue;
        Entry e;
        e.info = info;
        result.entries.append(std::move(e));
    }
    return result;
}

void FileSystemModel::scheduleLocalReload(bool tryDiff)
{
    const quint64 gen = ++m_localReloadGeneration;
    m_localReloadTryDiff = tryDiff;

    if (m_synchronousReload) {
        // Test mode: run scan inline so rowCount is correct before the
        // caller moves on.
        applyLocalReload(scanLocalEntries(gen, m_rootPath, m_showHidden, m_hiddenOnly, m_sortFlags),
                         tryDiff);
        return;
    }

    if (!m_localReloadWatcher) {
        m_localReloadWatcher = new QFutureWatcher<LocalReloadResult>(this);
        connect(m_localReloadWatcher, &QFutureWatcherBase::finished, this, [this]() {
            if (!m_localReloadWatcher)
                return;
            applyLocalReload(m_localReloadWatcher->result(), m_localReloadTryDiff);
        });
    }

    auto future = QtConcurrent::run(&FileSystemModel::scanLocalEntries,
                                    gen, m_rootPath, m_showHidden, m_hiddenOnly, m_sortFlags);
    m_localReloadWatcher->setFuture(future);
}

void FileSystemModel::cancelLocalReload()
{
    if (!m_localReloadWatcher)
        return;
    m_localReloadWatcher->disconnect(this);
    m_localReloadWatcher->waitForFinished();
}

void FileSystemModel::applyLocalReload(LocalReloadResult result, bool tryDiff)
{
    // Drop stale results — the user already navigated elsewhere and a newer
    // scan has been dispatched; whatever came back is for a path we no
    // longer care about.
    if (result.generation != m_localReloadGeneration)
        return;

    if (tryDiff && applyLocalDiff(result.entries))
        return;

    beginResetModel();
    m_entries = std::move(result.entries);
    m_trashEntries.clear();
    updateLocalCounts();
    endResetModel();
    emit countsChanged();
}

void FileSystemModel::reloadRemote()
{
    if (m_rootPath.isEmpty()) {
        m_fileCount = 0;
        m_folderCount = 0;
        return;
    }

    QStringList args = {
        QStringLiteral("list"),
        QStringLiteral("-l"),
        QStringLiteral("-u"),
        QStringLiteral("-a"),
        QStringLiteral("standard::display-name,standard::content-type,time::modified,unix::mode,standard::is-symlink,standard::symlink-target")
    };
    if (m_showHidden)
        args.append(QStringLiteral("-h"));
    args.append(gioLocationArg(m_rootPath));

    const int generation = m_remoteReloadGeneration;
    const QString rootPath = m_rootPath;
    auto *process = new QProcess(this);
    m_remoteReloadProcess = process;

    connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, process, generation, rootPath](int exitCode, QProcess::ExitStatus) {
        if (process != m_remoteReloadProcess || generation != m_remoteReloadGeneration) {
            process->deleteLater();
            return;
        }

        const QByteArray output = exitCode == 0 ? process->readAllStandardOutput() : QByteArray();
        m_remoteReloadProcess = nullptr;
        process->deleteLater();

        if (output.isEmpty() && exitCode != 0)
            return;

        applyRemoteReload(rootPath, output);
    });

    startHostToolProcess(process, QStringLiteral("gio"), args);
    QTimer::singleShot(8000, process, [this, process, generation]() {
        if (process == m_remoteReloadProcess
            && generation == m_remoteReloadGeneration
            && process->state() != QProcess::NotRunning) {
            process->kill();
        }
    });
}

void FileSystemModel::cancelRemoteReload()
{
    if (!m_remoteReloadProcess)
        return;

    m_remoteReloadProcess->disconnect();
    if (m_remoteReloadProcess->state() != QProcess::NotRunning) {
        m_remoteReloadProcess->kill();
        m_remoteReloadProcess->waitForFinished(100);
    }
    m_remoteReloadProcess->deleteLater();
    m_remoteReloadProcess = nullptr;
}

void FileSystemModel::applyRemoteReload(const QString &rootPath, const QByteArray &output)
{
    if (rootPath != m_rootPath || !isRemoteRoot())
        return;

    QList<QVariantMap> entries;
    const QStringList lines = QString::fromUtf8(output).split('\n', Qt::SkipEmptyParts);
    for (const QString &line : lines) {
        const QVariantMap entry = buildRemoteEntryFromLine(line);
        if (!entry.isEmpty())
            entries.append(entry);
    }

    const QString afcDocumentsUri = afcDocumentsUriFor(m_rootPath);
    if (!afcDocumentsUri.isEmpty()) {
        bool alreadyPresent = false;
        for (const QVariantMap &entry : std::as_const(entries)) {
            if (entry.value(QStringLiteral("filePath")).toString() == afcDocumentsUri) {
                alreadyPresent = true;
                break;
            }
        }

        if (!alreadyPresent) {
            QVariantMap entry;
            entry[QStringLiteral("fileName")] = QStringLiteral("Apps");
            entry[QStringLiteral("filePath")] = afcDocumentsUri;
            entry[QStringLiteral("fileSize")] = QVariant(qint64(-1));
            entry[QStringLiteral("fileSizeText")] = QString();
            entry[QStringLiteral("fileType")] = QStringLiteral("folder");
            entry[QStringLiteral("fileModified")] = QDateTime();
            entry[QStringLiteral("fileModifiedText")] = QString();
            entry[QStringLiteral("filePermissions")] = QString();
            entry[QStringLiteral("isDir")] = true;
            entry[QStringLiteral("isSymlink")] = false;
            entry[QStringLiteral("fileIconName")] = QStringLiteral("folder");
            entry[QStringLiteral("mimeType")] = QStringLiteral("inode/directory");
            entry[QStringLiteral("symlinkTarget")] = QString();
            entries.prepend(entry);
        }
    }

    std::sort(entries.begin(), entries.end(), [this](const QVariantMap &lhs, const QVariantMap &rhs) {
        const bool lhsDir = lhs.value(QStringLiteral("isDir")).toBool();
        const bool rhsDir = rhs.value(QStringLiteral("isDir")).toBool();
        if (lhsDir != rhsDir)
            return lhsDir > rhsDir;

        int comparison = 0;
        if (m_sortColumn == QStringLiteral("size")) {
            const qint64 leftSize = lhs.value(QStringLiteral("fileSize")).toLongLong();
            const qint64 rightSize = rhs.value(QStringLiteral("fileSize")).toLongLong();
            comparison = (leftSize < rightSize) ? -1 : (leftSize > rightSize ? 1 : 0);
        } else if (m_sortColumn == QStringLiteral("modified")) {
            const QDateTime leftModified = lhs.value(QStringLiteral("fileModified")).toDateTime();
            const QDateTime rightModified = rhs.value(QStringLiteral("fileModified")).toDateTime();
            comparison = (leftModified < rightModified) ? -1 : (leftModified > rightModified ? 1 : 0);
        } else if (m_sortColumn == QStringLiteral("type")) {
            comparison = QString::compare(lhs.value(QStringLiteral("fileType")).toString(),
                                          rhs.value(QStringLiteral("fileType")).toString(),
                                          Qt::CaseInsensitive);
        } else {
            comparison = QString::compare(lhs.value(QStringLiteral("fileName")).toString(),
                                          rhs.value(QStringLiteral("fileName")).toString(),
                                          Qt::CaseInsensitive);
        }

        return m_sortAscending ? comparison < 0 : comparison > 0;
    });

    int files = 0;
    int folders = 0;
    for (const auto &entry : std::as_const(entries)) {
        if (entry.value(QStringLiteral("isDir")).toBool())
            ++folders;
        else
            ++files;
    }

    beginResetModel();
    m_remoteEntries = std::move(entries);
    m_fileCount = files;
    m_folderCount = folders;
    endResetModel();
    emit countsChanged();
}

QList<FileSystemModel::Entry> FileSystemModel::currentLocalEntries() const
{
    if (m_rootPath.isEmpty())
        return {};

    QDir dir(m_rootPath);
    QDir::Filters filters = QDir::AllEntries | QDir::NoDotAndDotDot;
    if (m_showHidden || m_hiddenOnly)
        filters |= QDir::Hidden;

    // Fast path: only the syscall + QFileInfo construction. Derived fields
    // (icon name, mime-backed type, locale-formatted date, permission text)
    // populate lazily on first data() request for each row.
    const QFileInfoList infos = dir.entryInfoList(filters, m_sortFlags);
    QList<Entry> entries;
    entries.reserve(infos.size());
    for (const QFileInfo &info : infos) {
        if (m_hiddenOnly && !info.fileName().startsWith(QLatin1Char('.')))
            continue;
        Entry e;
        e.info = info;
        entries.append(std::move(e));
    }
    return entries;
}

void FileSystemModel::ensurePopulated(const Entry &entry) const
{
    if (entry.populated)
        return;
    const bool isDir = entry.info.isDir();
    const QString absPath = entry.info.absoluteFilePath();
    entry.iconName = iconNameForEntry(absPath, isDir);
    entry.fileType = fileTypeForEntry(entry.info.fileName(), isDir);
    entry.fileCategory = fileCategoryForEntry(entry.info.fileName(), isDir);
    entry.fileExtension = isDir ? QString() : entry.info.completeSuffix();
    entry.sizeText = isDir ? QString() : formattedSize(entry.info.size());
    entry.modifiedText = QLocale().toString(entry.info.lastModified(), QLocale::ShortFormat);
    entry.permissionsText = permissionsString(entry.info);
    const PreviewKind kind = previewKindForEntry(absPath, isDir);
    entry.hasImagePreview = kind == PreviewKind::Image;
    entry.hasVideoPreview = kind == PreviewKind::Video;
    entry.populated = true;
}

void FileSystemModel::updateLocalCounts()
{
    int files = 0;
    int folders = 0;
    for (const Entry &entry : m_entries) {
        if (entry.info.isDir())
            ++folders;
        else
            ++files;
    }
    m_fileCount = files;
    m_folderCount = folders;
}

bool FileSystemModel::applyLocalDiff(const QList<Entry> &newEntries)
{
    const int oldCount = m_entries.size();
    const int newCount = newEntries.size();

    auto pathAt = [](const QList<Entry> &list, int row) {
        return list.at(row).info.absoluteFilePath();
    };

    if (newCount == oldCount + 1) {
        int insertRow = 0;
        while (insertRow < oldCount
               && pathAt(m_entries, insertRow) == pathAt(newEntries, insertRow)) {
            ++insertRow;
        }

        bool matches = true;
        for (int oldRow = insertRow, newRow = insertRow + 1; oldRow < oldCount; ++oldRow, ++newRow) {
            if (pathAt(m_entries, oldRow) != pathAt(newEntries, newRow)) {
                matches = false;
                break;
            }
        }

        if (matches) {
            beginInsertRows({}, insertRow, insertRow);
            m_entries.insert(insertRow, newEntries.at(insertRow));
            endInsertRows();
            updateLocalCounts();
            emit countsChanged();
            return true;
        }
    }

    if (newCount + 1 == oldCount) {
        int removeRow = 0;
        while (removeRow < newCount
               && pathAt(m_entries, removeRow) == pathAt(newEntries, removeRow)) {
            ++removeRow;
        }

        bool matches = true;
        for (int oldRow = removeRow + 1, newRow = removeRow; newRow < newCount; ++oldRow, ++newRow) {
            if (pathAt(m_entries, oldRow) != pathAt(newEntries, newRow)) {
                matches = false;
                break;
            }
        }

        if (matches) {
            beginRemoveRows({}, removeRow, removeRow);
            m_entries.removeAt(removeRow);
            endRemoveRows();
            updateLocalCounts();
            emit countsChanged();
            return true;
        }
    }

    if (newCount == oldCount) {
        bool sameOrder = true;
        for (int row = 0; row < newCount; ++row) {
            if (pathAt(m_entries, row) != pathAt(newEntries, row)) {
                sameOrder = false;
                break;
            }
        }

        if (sameOrder) {
            m_entries = newEntries;
            updateLocalCounts();
            if (newCount > 0) {
                static const QVector<int> changedRoles = {
                    FileSizeRole, FileSizeTextRole,
                    FileModifiedRole, FileModifiedTextRole,
                    FilePermissionsRole,
                    HasImagePreviewRole, HasVideoPreviewRole,
                };
                emit dataChanged(index(0, 0), index(newCount - 1, 0), changedRoles);
            }
            emit countsChanged();
            return true;
        }
    }

    return false;
}

// Argument list for `gio list` against the trash root (shared by the sync and
// async reload paths). Inside a Flatpak the call is transparently wrapped with
// `flatpak-spawn --host` by runHostTool/startHostToolProcess so it queries the
// host's real ~/.local/share/Trash rather than the sandbox-local one.
static QStringList trashGioListArgs(const QString &rootPath)
{
    return {
        QStringLiteral("list"),
        QStringLiteral("-l"),
        QStringLiteral("-u"),
        QStringLiteral("-a"),
        QStringLiteral("standard::display-name,standard::name,standard::content-type,time::modified,trash::orig-path,trash::deletion-date"),
        QUrl(rootPath).toString(QUrl::FullyEncoded)
    };
}

void FileSystemModel::reloadTrash()
{
    if (m_rootPath.isEmpty()) {
        m_fileCount = 0;
        m_folderCount = 0;
        return;
    }

    // Synchronous gio query. Only used in test mode (setSynchronousReload); the
    // GUI uses reloadTrashAsync() so navigating into Trash never blocks for the
    // up-to-5s gio call.
    const QString output = runHostTool(QStringLiteral("gio"), trashGioListArgs(m_rootPath), 5000);
    applyTrashReload(output);
}

void FileSystemModel::reloadTrashAsync()
{
    if (m_rootPath.isEmpty()) {
        m_fileCount = 0;
        m_folderCount = 0;
        return;
    }

    const int generation = m_remoteReloadGeneration;
    const QString rootPath = m_rootPath;
    auto *process = new QProcess(this);
    m_remoteReloadProcess = process;

    connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, process, generation, rootPath](int exitCode, QProcess::ExitStatus) {
        if (process != m_remoteReloadProcess || generation != m_remoteReloadGeneration) {
            process->deleteLater();
            return;
        }

        const QByteArray output = exitCode == 0 ? process->readAllStandardOutput() : QByteArray();
        m_remoteReloadProcess = nullptr;
        process->deleteLater();

        // Discard if the user navigated away while the query was in flight.
        if (rootPath != m_rootPath || !isTrashRoot())
            return;

        beginResetModel();
        m_trashEntries.clear();
        applyTrashReload(QString::fromUtf8(output));
        endResetModel();
        emit countsChanged();
    });

    startHostToolProcess(process, QStringLiteral("gio"), trashGioListArgs(m_rootPath));
    QTimer::singleShot(8000, process, [this, process, generation]() {
        if (process == m_remoteReloadProcess
            && generation == m_remoteReloadGeneration
            && process->state() != QProcess::NotRunning) {
            process->kill();
        }
    });
}

void FileSystemModel::applyTrashReload(const QString &output)
{
    const QStringList lines = output.split('\n', Qt::SkipEmptyParts);
    for (const QString &line : lines) {
        const QVariantMap entry = buildTrashEntryFromLine(line);
        if (!entry.isEmpty())
            m_trashEntries.append(entry);
    }

    std::sort(m_trashEntries.begin(), m_trashEntries.end(), [this](const QVariantMap &lhs, const QVariantMap &rhs) {
        const bool lhsDir = lhs.value("isDir").toBool();
        const bool rhsDir = rhs.value("isDir").toBool();
        if (lhsDir != rhsDir)
            return lhsDir > rhsDir;

        int comparison = 0;
        if (m_sortColumn == "size") {
            const qint64 leftSize = lhs.value("fileSize").toLongLong();
            const qint64 rightSize = rhs.value("fileSize").toLongLong();
            comparison = (leftSize < rightSize) ? -1 : (leftSize > rightSize ? 1 : 0);
        } else if (m_sortColumn == "modified") {
            const QDateTime leftModified = lhs.value("fileModified").toDateTime();
            const QDateTime rightModified = rhs.value("fileModified").toDateTime();
            comparison = (leftModified < rightModified) ? -1 : (leftModified > rightModified ? 1 : 0);
        } else if (m_sortColumn == "type") {
            comparison = QString::compare(lhs.value("fileType").toString(), rhs.value("fileType").toString(), Qt::CaseInsensitive);
        } else {
            comparison = QString::compare(lhs.value("fileName").toString(), rhs.value("fileName").toString(), Qt::CaseInsensitive);
        }

        return m_sortAscending ? comparison < 0 : comparison > 0;
    });

    int files = 0;
    int folders = 0;
    for (const auto &entry : std::as_const(m_trashEntries)) {
        if (entry.value("isDir").toBool())
            ++folders;
        else
            ++files;
    }

    m_fileCount = files;
    m_folderCount = folders;
}
