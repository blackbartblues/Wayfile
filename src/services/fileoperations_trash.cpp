#include "services/fileoperations.h"
#include "services/fileoperations_helpers.h"

#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QStorageInfo>
#include <QUrl>
#include <unistd.h>

#undef signals
#include <gio/gio.h>
#define signals Q_SIGNALS

using namespace FileOperationsHelpers;

// Trash / restore / empty cluster, split from fileoperations.cpp. The trash
// root-discovery helpers below are used only here, so they stay local to this
// translation unit; cross-cluster path helpers come from FileOperationsHelpers.
namespace {

QString currentUidString()
{
    return QString::number(geteuid());
}

QString trashUriRootPath()
{
    return QStringLiteral("trash:///");
}

QString homeTrashRootPath()
{
    return QDir::cleanPath(QDir::homePath() + "/.local/share/Trash");
}

QString homeTrashFilesPath()
{
    return homeTrashRootPath() + "/files";
}

QString existingLookupPathFor(const QString &path)
{
    QString candidate = QDir::cleanPath(path);
    if (candidate.isEmpty())
        return QDir::homePath();

    const QFileInfo info(candidate);
    candidate = info.isDir() ? info.absoluteFilePath() : info.absolutePath();

    while (!candidate.isEmpty() && !QFileInfo::exists(candidate)) {
        const QString parent = QFileInfo(candidate).absolutePath();
        if (parent == candidate)
            break;
        candidate = parent;
    }

    return QFileInfo::exists(candidate) ? candidate : QDir::homePath();
}

QStringList trashRootCandidatesForPath(const QString &path)
{
    QStringList roots;

    const QString cleanPath = QDir::cleanPath(path);
    if (!cleanPath.isEmpty()) {
        const QString lookupPath = existingLookupPathFor(cleanPath);
        const QString storageRoot = QDir::cleanPath(QStorageInfo(lookupPath).rootPath());
        if (!storageRoot.isEmpty() && storageRoot != "/") {
            const QString uid = currentUidString();
            roots.append(QDir(storageRoot).filePath(".Trash-" + uid));
            roots.append(QDir(storageRoot).filePath(".Trash/" + uid));
        }
    }

    roots.append(homeTrashRootPath());
    roots.removeDuplicates();
    return roots;
}

QString matchingTrashFilesRoot(const QString &path)
{
    if (isTrashUriPath(path))
        return trashUriRootPath();

    const QString cleanPath = QDir::cleanPath(path);
    if (cleanPath.isEmpty())
        return {};

    for (const QString &trashRoot : trashRootCandidatesForPath(cleanPath)) {
        const QString filesRoot = QDir(trashRoot).filePath("files");
        if (cleanPath == filesRoot || cleanPath.startsWith(filesRoot + "/"))
            return filesRoot;
    }

    return {};
}

QString trashUriForPath(const QString &path)
{
    const QUrl url(path);
    if (url.scheme() == "trash")
        return url.toString(QUrl::FullyEncoded);

    const QString filesRoot = matchingTrashFilesRoot(path);
    if (filesRoot.isEmpty())
        return {};

    const QString relativePath = QDir::cleanPath(QDir(filesRoot).relativeFilePath(QDir::cleanPath(path)));
    if (relativePath.isEmpty() || relativePath == "." || relativePath.startsWith("../"))
        return {};

    QUrl trashUrl;
    trashUrl.setScheme("trash");
    trashUrl.setPath("/" + QDir::fromNativeSeparators(relativePath));
    return trashUrl.toString(QUrl::FullyEncoded);
}

} // namespace

void FileOperations::trashFiles(const QStringList &paths)
{
    startSimpleOperation(
        QString("Trashing %1 item(s)...").arg(paths.size()), paths,
        [paths](ProgressReporter report) -> QString {
            QString lastError;
            const int total = paths.size();

            // Inside a Flatpak, GLib's g_file_trash() puts files in the
            // *sandbox's* trash (~/.var/app/<app-id>/data/Trash) because
            // XDG_DATA_HOME is overridden. Shell out to host gio so files land
            // in the user's real ~/.local/share/Trash — and do it in ONE call
            // for all paths rather than spawning flatpak-spawn per file.
            if (runningInFlatpak()) {
                report(0, total, {});
                QStringList args = {QStringLiteral("--host"), QStringLiteral("gio"),
                                    QStringLiteral("trash")};
                for (const QString &p : paths)
                    args << normalizeLocation(p);
                QProcess proc;
                proc.start(QStringLiteral("flatpak-spawn"), args);
                proc.waitForFinished(30000);
                report(total, total, {});
                if (proc.exitCode() != 0)
                    return QString::fromUtf8(proc.readAllStandardError()).trimmed();
                return {};
            }

            // Native: g_file_trash per file is fast and in-process, so keep the
            // per-file loop (it also reports progress for large batches).
            for (int i = 0; i < total; ++i) {
                const QString normalized = normalizeLocation(paths[i]);
                report(i, total, locationFileName(normalized));

                GFile *file = gFileForLocation(normalized);
                GError *gErr = nullptr;
                if (!g_file_trash(file, nullptr, &gErr)) {
                    if (gErr) {
                        lastError = QString::fromUtf8(gErr->message);
                        g_error_free(gErr);
                    }
                }
                g_object_unref(file);
            }
            return lastError;
        });
}

void FileOperations::restoreFromTrash(const QStringList &paths)
{
    startSimpleOperation(
        QString("Restoring %1 item(s)...").arg(paths.size()), paths,
        [paths](ProgressReporter report) -> QString {
            QString lastError;
            const int total = paths.size();
            // Same XDG_DATA_HOME issue as trashFiles: under Flatpak the
            // GLib trash:// URIs resolve to the sandbox trash, not the
            // host's. Shell out to host gio for restore.
            const bool inFlatpak = runningInFlatpak();
            for (int i = 0; i < total; ++i) {
                const QString uri = trashUriForPath(paths[i]);
                if (uri.isEmpty()) {
                    // Don't silently drop the item: record it so the operation
                    // reports failure instead of a false success.
                    lastError = QStringLiteral("Could not locate \"%1\" in trash")
                                    .arg(locationFileName(paths[i]));
                    continue;
                }

                report(i, total, locationFileName(paths[i]));

                if (inFlatpak) {
                    QProcess proc;
                    proc.start(QStringLiteral("flatpak-spawn"),
                               {QStringLiteral("--host"), QStringLiteral("gio"),
                                QStringLiteral("trash"), QStringLiteral("--restore"), uri});
                    proc.waitForFinished(10000);
                    if (proc.exitCode() != 0) {
                        const QString err = QString::fromUtf8(proc.readAllStandardError()).trimmed();
                        if (!err.isEmpty())
                            lastError = err;
                    }
                    continue;
                }

                GFile *trashFile = g_file_new_for_uri(uri.toUtf8().constData());
                GError *gErr = nullptr;
                GFileInfo *info = g_file_query_info(trashFile,
                    G_FILE_ATTRIBUTE_TRASH_ORIG_PATH,
                    G_FILE_QUERY_INFO_NONE, nullptr, &gErr);

                if (!info) {
                    if (gErr) { lastError = QString::fromUtf8(gErr->message); g_error_free(gErr); }
                    g_object_unref(trashFile);
                    continue;
                }

                const char *origPath = g_file_info_get_attribute_byte_string(info, G_FILE_ATTRIBUTE_TRASH_ORIG_PATH);
                if (!origPath) {
                    lastError = QStringLiteral("Could not determine original path");
                    g_object_unref(info);
                    g_object_unref(trashFile);
                    continue;
                }

                GFile *destFile = g_file_new_for_path(origPath);
                GFile *parent = g_file_get_parent(destFile);
                if (parent) {
                    GError *mkErr = nullptr;
                    g_file_make_directory_with_parents(parent, nullptr, &mkErr);
                    if (mkErr) g_error_free(mkErr);
                    g_object_unref(parent);
                }

                GError *mvErr = nullptr;
                if (!g_file_move(trashFile, destFile, G_FILE_COPY_NONE, nullptr, nullptr, nullptr, &mvErr)) {
                    if (mvErr) { lastError = QString::fromUtf8(mvErr->message); g_error_free(mvErr); }
                }

                g_object_unref(info);
                g_object_unref(destFile);
                g_object_unref(trashFile);
            }
            return lastError;
        });
}

bool FileOperations::isTrashPath(const QString &path) const
{
    const QString normalized = normalizeLocation(path);
    if (isTrashUriPath(normalized))
        return true;
    if (isRemoteUriPath(normalized))
        return false;
    return !matchingTrashFilesRoot(normalized).isEmpty();
}

QString FileOperations::trashFilesPathFor(const QString &path) const
{
    const QString normalized = normalizeLocation(path);
    if (isTrashUriPath(normalized))
        return trashUriRootPath();
    if (isRemoteUriPath(normalized))
        return homeTrashFilesPath();

    const QString matchedRoot = matchingTrashFilesRoot(normalized);
    if (!matchedRoot.isEmpty())
        return matchedRoot;

    const QStringList roots = trashRootCandidatesForPath(normalized);
    if (!roots.isEmpty())
        return QDir(roots.first()).filePath("files");

    return homeTrashFilesPath();
}

void FileOperations::emptyTrash()
{
    startSimpleOperation(
        QStringLiteral("Emptying trash..."), {},
        [](ProgressReporter report) -> QString {
            // Empty via the `gio` CLI rather than g_file_delete() on individual
            // trash:/// URIs. GVFS refuses per-item deletion in uid-named
            // top-level trash dirs — e.g. /home/.Trash-1000 when /home is its
            // own mount/subvolume — with "Items in the wastebasket may not be
            // modified", so the old per-item loop failed on every item there.
            // `gio trash --empty` is the reference implementation and clears
            // every trash dir the user owns (home + per-volume). We trade
            // per-file progress for correctness (one shot), matching the
            // Flatpak path which already did this.
            report(0, 1, QStringLiteral("Emptying trash..."));
            QProcess proc;
            if (runningInFlatpak()) {
                // GLib's trash:// inside a sandbox is the sandbox's trash; shell
                // out to the host gio so we empty the user's real trash.
                proc.start(QStringLiteral("flatpak-spawn"),
                           {QStringLiteral("--host"), QStringLiteral("gio"),
                            QStringLiteral("trash"), QStringLiteral("--empty")});
            } else {
                proc.start(QStringLiteral("gio"),
                           {QStringLiteral("trash"), QStringLiteral("--empty")});
            }
            if (!proc.waitForStarted(5000))
                return QStringLiteral("Could not start gio to empty trash");
            proc.waitForFinished(60000);
            if (proc.exitCode() != 0) {
                const QString err = QString::fromUtf8(proc.readAllStandardError()).trimmed();
                return err.isEmpty() ? QStringLiteral("gio trash --empty failed") : err;
            }
            return QString();
        });
}
