#include "models/filesystemmodel.h"
#include "services/gitstatusservice.h"
#include <QLocale>
#include <QDateTime>
#include <QDebug>
#include <QFuture>
#include <QMimeDatabase>
#include <QStorageInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QDirIterator>
#include <QUrl>
#include <QtConcurrent>
#include <algorithm>

#include "models/filesystemmodel_helpers.h"

using namespace FsmHelpers;



FileSystemModel::FileSystemModel(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this]() {
        if (!m_rootPath.isEmpty())
            emit watchedDirectoryChanged(m_rootPath);
        refresh();
    });
}

FileSystemModel::~FileSystemModel()
{
    cancelRemoteReload();
    cancelLocalReload();
    cancelAppsProbes();
    cancelRemotePropsProbes();
}

void FileSystemModel::setGitStatusService(GitStatusService *service)
{
    if (m_gitService)
        disconnect(m_gitService, nullptr, this, nullptr);
    m_gitService = service;
    if (m_gitService) {
        connect(m_gitService, &GitStatusService::statusChanged, this, [this]() {
            if (rowCount() > 0)
                emit dataChanged(index(0), index(rowCount() - 1), {GitStatusRole, GitStatusIconRole});
        });
        m_gitService->setRootPath(m_rootPath);
    }
}

int FileSystemModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    if (isTrashRoot())
        return m_trashEntries.size();
    if (isRemoteRoot())
        return m_remoteEntries.size();
    return m_entries.size();
}

QVariant FileSystemModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount())
        return {};

    if (isTrashRoot()) {
        const QVariantMap &entry = m_trashEntries.at(index.row());

        switch (role) {
        case FileNameRole:
            return entry.value("fileName");
        case FilePathRole:
            return entry.value("filePath");
        case FileSizeRole:
            return entry.value("fileSize");
        case FileSizeTextRole:
            return entry.value("fileSizeText");
        case FileTypeRole:
            return entry.value("fileType");
        case FileModifiedRole:
            return entry.value("fileModified");
        case FileModifiedTextRole:
            return entry.value("fileModifiedText");
        case FilePermissionsRole:
            return entry.value("filePermissions");
        case IsDirRole:
            return entry.value("isDir");
        case IsSymlinkRole:
            return entry.value("isSymlink");
        case FileIconNameRole:
            return entry.value("fileIconName");
        case FileCategoryRole:
            return entry.value("fileCategory");
        case FileExtensionRole:
            return entry.value("fileExtension");
        case FolderTypeRole:
            // Trashed folders carry no typed-folder emblem.
            return QString();
        case GitStatusRole:
        case GitStatusIconRole:
            // Trashed files aren't git-tracked, but the view delegates
            // declare these as required properties.
            return QString();
        case HasImagePreviewRole: {
            const PreviewKind kind = previewKindForEntry(
                entry.value(QStringLiteral("fileName")).toString(),
                entry.value(QStringLiteral("isDir")).toBool(),
                entry.value(QStringLiteral("mimeType")).toString());
            return kind == PreviewKind::Image;
        }
        case HasVideoPreviewRole: {
            const PreviewKind kind = previewKindForEntry(
                entry.value(QStringLiteral("fileName")).toString(),
                entry.value(QStringLiteral("isDir")).toBool(),
                entry.value(QStringLiteral("mimeType")).toString());
            return kind == PreviewKind::Video;
        }
        default:
            return {};
        }
    }

    if (isRemoteRoot()) {
        const QVariantMap &entry = m_remoteEntries.at(index.row());

        switch (role) {
        case FileNameRole:
            return entry.value(QStringLiteral("fileName"));
        case FilePathRole:
            return entry.value(QStringLiteral("filePath"));
        case FileSizeRole:
            return entry.value(QStringLiteral("fileSize"));
        case FileSizeTextRole:
            return entry.value(QStringLiteral("fileSizeText"));
        case FileTypeRole:
            return entry.value(QStringLiteral("fileType"));
        case FileModifiedRole:
            return entry.value(QStringLiteral("fileModified"));
        case FileModifiedTextRole:
            return entry.value(QStringLiteral("fileModifiedText"));
        case FilePermissionsRole:
            return entry.value(QStringLiteral("filePermissions"));
        case IsDirRole:
            return entry.value(QStringLiteral("isDir"));
        case IsSymlinkRole:
            return entry.value(QStringLiteral("isSymlink"));
        case FileIconNameRole:
            return entry.value(QStringLiteral("fileIconName"));
        case FileCategoryRole:
            return entry.value(QStringLiteral("fileCategory"));
        case FileExtensionRole:
            return entry.value(QStringLiteral("fileExtension"));
        case FolderTypeRole:
            // Remote folders carry no typed-folder emblem.
            return QString();
        case GitStatusRole:
        case GitStatusIconRole:
            // Remote files (sftp/smb/dav) aren't git-tracked, but the view
            // delegates declare these as required properties.
            return QString();
        case HasImagePreviewRole:
        case HasVideoPreviewRole:
            // No thumbnails for remote files (the thumbnailer needs local
            // file access).
            return false;
        default:
            return {};
        }
    }

    const Entry &entry = m_entries.at(index.row());
    const QFileInfo &info = entry.info;

    switch (role) {
    // Path / filename / size / dir / symlink / modified come straight from
    // QFileInfo's own stat cache, so they don't need the lazy populate path.
    case FileNameRole:
        return info.fileName();
    case FilePathRole:
        return info.absoluteFilePath();
    case FileSizeRole:
        return info.isDir() ? QVariant(-1) : QVariant(info.size());
    case FileModifiedRole:
        return info.lastModified();
    case IsDirRole:
        return info.isDir();
    case IsSymlinkRole:
        return info.isSymLink();
    case FileSizeTextRole:
        ensurePopulated(entry);
        return entry.sizeText;
    case FileTypeRole:
        ensurePopulated(entry);
        return entry.fileType;
    case FileModifiedTextRole:
        ensurePopulated(entry);
        return entry.modifiedText;
    case FilePermissionsRole:
        ensurePopulated(entry);
        return entry.permissionsText;
    case FileIconNameRole:
        ensurePopulated(entry);
        return entry.iconName;
    case HasImagePreviewRole:
        ensurePopulated(entry);
        return entry.hasImagePreview;
    case HasVideoPreviewRole:
        ensurePopulated(entry);
        return entry.hasVideoPreview;
    case FileCategoryRole:
        ensurePopulated(entry);
        return entry.fileCategory;
    case FileExtensionRole:
        ensurePopulated(entry);
        return entry.fileExtension;
    case FolderTypeRole:
        // Path-only — no populate needed (mirrors GitStatusRole below).
        return info.isDir() ? folderTypeForPath(info.absoluteFilePath()) : QString();
    case GitStatusRole:
        return m_gitService ? m_gitService->statusForPath(info.absoluteFilePath()) : QString();
    case GitStatusIconRole: {
        if (!m_gitService)
            return QString();
        const QString st = m_gitService->statusForPath(info.absoluteFilePath());
        if (st == "modified")   return QStringLiteral("git-modified");
        if (st == "staged")     return QStringLiteral("git-staged");
        if (st == "untracked")  return QStringLiteral("git-untracked");
        if (st == "deleted")    return QStringLiteral("git-deleted");
        if (st == "renamed")    return QStringLiteral("git-renamed");
        if (st == "conflicted") return QStringLiteral("git-conflicted");
        if (st == "ignored")    return QStringLiteral("git-ignored");
        if (st == "dirty")      return QStringLiteral("git-dirty");
        return QString();
    }
    default:
        return {};
    }
}

QHash<int, QByteArray> FileSystemModel::roleNames() const
{
    return {
        {FileNameRole,         "fileName"},
        {FilePathRole,         "filePath"},
        {FileSizeRole,         "fileSize"},
        {FileSizeTextRole,     "fileSizeText"},
        {FileTypeRole,         "fileType"},
        {FileModifiedRole,     "fileModified"},
        {FileModifiedTextRole, "fileModifiedText"},
        {FilePermissionsRole,  "filePermissions"},
        {IsDirRole,            "isDir"},
        {IsSymlinkRole,        "isSymlink"},
        {FileIconNameRole,     "fileIconName"},
        {GitStatusRole,        "gitStatus"},
        {GitStatusIconRole,    "gitStatusIcon"},
        {HasImagePreviewRole,  "hasImagePreview"},
        {HasVideoPreviewRole,  "hasVideoPreview"},
        {FileCategoryRole,     "fileCategory"},
        {FileExtensionRole,    "fileExtension"},
        {FolderTypeRole,       "folderType"},
    };
}

QString FileSystemModel::rootPath() const { return m_rootPath; }
bool FileSystemModel::showHidden() const { return m_showHidden; }
int FileSystemModel::fileCount() const { return m_fileCount; }
int FileSystemModel::folderCount() const { return m_folderCount; }
int FileSystemModel::trashEntryCount() const { return m_trashEntries.size(); }

bool FileSystemModel::isTrashRoot() const
{
    return isTrashUri(m_rootPath);
}

bool FileSystemModel::isRemoteRoot() const
{
    return isRemoteUri(m_rootPath);
}

void FileSystemModel::setRootPath(const QString &path)
{
    const QString normalizedPath = normalizeLocation(path);
    if (m_rootPath == normalizedPath)
        return;

    // Stop watching old directory
    if (!m_rootPath.isEmpty() && !isTrashRoot() && !isRemoteRoot())
        m_watcher.removePath(m_rootPath);

    m_rootPath = normalizedPath;

    // Watch new directory
    if (!m_rootPath.isEmpty() && !isTrashRoot() && !isRemoteRoot())
        m_watcher.addPath(m_rootPath);

    reload();
    if (m_gitService)
        m_gitService->setRootPath(m_rootPath);
    emit rootPathChanged();
}

void FileSystemModel::setShowHidden(bool show)
{
    if (m_showHidden == show)
        return;
    m_showHidden = show;
    if (!m_rootPath.isEmpty())
        reload();
    emit showHiddenChanged();
}

void FileSystemModel::setHiddenOnly(bool on)
{
    if (m_hiddenOnly == on)
        return;
    m_hiddenOnly = on;
    if (!m_rootPath.isEmpty())
        reload();
}

void FileSystemModel::sortByColumn(const QString &column, bool ascending)
{
    if (m_sortColumn == column && m_sortAscending == ascending)
        return;

    m_sortColumn = column;
    m_sortAscending = ascending;

    QDir::SortFlags flags = QDir::DirsFirst | QDir::IgnoreCase;
    if (column == "name")
        flags |= QDir::Name;
    else if (column == "size")
        flags |= QDir::Size;
    else if (column == "modified")
        flags |= QDir::Time;
    else if (column == "type")
        flags |= QDir::Type;
    else
        flags |= QDir::Name;

    if (!ascending)
        flags |= QDir::Reversed;

    m_sortFlags = flags;
    reload();
}

void FileSystemModel::refresh()
{
    if (isTrashRoot()) {
        reload();
        return;
    }

    if (isRemoteRoot()) {
        reload();
        return;
    }

    // Local refresh triggered by QFileSystemWatcher or user action: keep
    // existing rows visible and diff the new scan against them so small
    // edits don't force a full reset.
    scheduleLocalReload(/*tryDiff=*/true);
}

QString FileSystemModel::filePath(int row) const
{
    if (row < 0 || row >= rowCount())
        return {};

    if (isTrashRoot())
        return m_trashEntries.at(row).value("filePath").toString();

    if (isRemoteRoot())
        return m_remoteEntries.at(row).value(QStringLiteral("filePath")).toString();

    return m_entries.at(row).info.absoluteFilePath();
}

bool FileSystemModel::isDir(int row) const
{
    if (row < 0 || row >= rowCount())
        return false;

    if (isTrashRoot())
        return m_trashEntries.at(row).value("isDir").toBool();

    if (isRemoteRoot())
        return m_remoteEntries.at(row).value(QStringLiteral("isDir")).toBool();

    return m_entries.at(row).info.isDir();
}

QString FileSystemModel::fileName(int row) const
{
    if (row < 0 || row >= rowCount())
        return {};

    if (isTrashRoot())
        return m_trashEntries.at(row).value("fileName").toString();

    if (isRemoteRoot())
        return m_remoteEntries.at(row).value(QStringLiteral("fileName")).toString();

    return m_entries.at(row).info.fileName();
}

QString FileSystemModel::homePath() const
{
    return QDir::homePath();
}

