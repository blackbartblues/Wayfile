#include "services/fileoperations.h"
#include "services/fileoperations_helpers.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>

#undef signals
#include <gio/gio.h>
#define signals Q_SIGNALS

using namespace FileOperationsHelpers;

// Copy / move / delete / transfer-plan cluster, split from fileoperations.cpp.
// The recursive GIO delete and the source-metadata probes below are used only
// here; cross-cluster path helpers come from FileOperationsHelpers.
namespace {

bool deleteGFileRecursive(GFile *file, QString *error, GCancellable *cancellable = nullptr)
{
    const GFileType type = g_file_query_file_type(
        file, G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS, cancellable);
    if (type != G_FILE_TYPE_DIRECTORY) {
        GError *delErr = nullptr;
        const bool ok = g_file_delete(file, cancellable, &delErr);
        if (!ok && error)
            *error = delErr ? QString::fromUtf8(delErr->message)
                            : QStringLiteral("Failed to delete item");
        if (delErr)
            g_error_free(delErr);
        return ok;
    }

    GError *enumErr = nullptr;
    GFileEnumerator *enumerator = g_file_enumerate_children(
        file,
        G_FILE_ATTRIBUTE_STANDARD_NAME,
        G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS,
        cancellable,
        &enumErr);
    if (!enumerator) {
        if (error)
            *error = enumErr ? QString::fromUtf8(enumErr->message)
                             : QStringLiteral("Failed to enumerate directory");
        if (enumErr)
            g_error_free(enumErr);
        return false;
    }

    GFileInfo *childInfo = nullptr;
    while ((childInfo = g_file_enumerator_next_file(enumerator, cancellable, nullptr)) != nullptr) {
        GFile *child = g_file_get_child(file, g_file_info_get_name(childInfo));
        g_object_unref(childInfo);

        const bool ok = deleteGFileRecursive(child, error, cancellable);
        g_object_unref(child);
        if (!ok) {
            g_file_enumerator_close(enumerator, nullptr, nullptr);
            g_object_unref(enumerator);
            return false;
        }
    }

    g_file_enumerator_close(enumerator, nullptr, nullptr);
    g_object_unref(enumerator);

    GError *delErr = nullptr;
    const bool ok = g_file_delete(file, cancellable, &delErr);
    if (!ok && error)
        *error = delErr ? QString::fromUtf8(delErr->message)
                        : QStringLiteral("Failed to delete directory");
    if (delErr)
        g_error_free(delErr);
    return ok;
}

QVariantMap remotePathInfo(const QString &path)
{
    QVariantMap result;
    const QString normalized = normalizeLocation(path);

    GFile *file = gFileForLocation(normalized);
    GFileInfo *info = g_file_query_info(file,
        G_FILE_ATTRIBUTE_STANDARD_TYPE ","
        G_FILE_ATTRIBUTE_STANDARD_SIZE ","
        G_FILE_ATTRIBUTE_STANDARD_IS_SYMLINK,
        G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS, nullptr, nullptr);

    if (!info) {
        g_object_unref(file);
        return result;
    }

    result[QStringLiteral("exists")] = true;
    result[QStringLiteral("fileName")] = locationFileName(normalized);
    result[QStringLiteral("path")] = normalized;
    result[QStringLiteral("isDir")] = g_file_info_get_file_type(info) == G_FILE_TYPE_DIRECTORY;
    result[QStringLiteral("size")] = static_cast<qint64>(g_file_info_get_size(info));
    result[QStringLiteral("isSymlink")] = g_file_info_has_attribute(
        info, G_FILE_ATTRIBUTE_STANDARD_IS_SYMLINK)
        ? static_cast<bool>(g_file_info_get_is_symlink(info))
        : false;

    g_object_unref(info);
    g_object_unref(file);
    return result;
}

QVariantMap sourceInfoForPath(const QString &path)
{
    const QString normalized = normalizeLocation(path);
    if (isRemoteUriPath(normalized))
        return remotePathInfo(normalized);

    QVariantMap result;
    QFileInfo info(normalized);
    result[QStringLiteral("exists")] = info.exists();
    result[QStringLiteral("fileName")] = info.fileName();
    result[QStringLiteral("path")] = info.absoluteFilePath();
    result[QStringLiteral("isDir")] = info.isDir();
    result[QStringLiteral("size")] = info.size();
    result[QStringLiteral("isSymlink")] = info.isSymLink();
    return result;
}

QStringList nameParts(const QString &name)
{
    const int dotIndex = name.lastIndexOf('.');
    if (dotIndex > 0)
        return {name.left(dotIndex), name.mid(dotIndex)};
    return {name, QString()};
}

} // namespace

void FileOperations::copyFiles(const QStringList &sources, const QString &destination)
{
    transferResolvedItems(transferPlan(sources, destination), false);
}

void FileOperations::copyResolvedItems(const QVariantList &operations)
{
    transferResolvedItems(operations, false);
}

void FileOperations::moveFiles(const QStringList &sources, const QString &destination)
{
    transferResolvedItems(transferPlan(sources, destination), true);
}

void FileOperations::moveResolvedItems(const QVariantList &operations)
{
    transferResolvedItems(operations, true);
}

QVariantList FileOperations::transferPlan(const QStringList &sources, const QString &destination) const
{
    QVariantList plan;
    const QString normalizedDestination = normalizeLocation(destination);

    for (const QString &sourcePath : sources) {
        const QVariantMap sourceInfo = sourceInfoForPath(sourcePath);
        if (!sourceInfo.value(QStringLiteral("exists")).toBool())
            continue;

        const QString sourceName = sourceInfo.value(QStringLiteral("fileName")).toString();
        const QString normalizedSourcePath = sourceInfo.value(QStringLiteral("path")).toString();
        const QString targetPath = normalizeLocation(joinLocation(normalizedDestination, sourceName));

        QVariantMap item;
        item["sourcePath"] = normalizedSourcePath;
        item["sourceName"] = sourceName;
        item["targetPath"] = targetPath;
        item["targetName"] = sourceName;
        item["targetExists"] = pathExistsSync(targetPath);
        item["samePath"] = (normalizedSourcePath == targetPath);
        item["isDir"] = sourceInfo.value(QStringLiteral("isDir")).toBool();
        plan.append(item);
    }

    return plan;
}

QString FileOperations::uniqueNameForDestination(const QString &destinationDir, const QString &desiredName,
                                                 const QStringList &blockedNames) const
{
    if (desiredName.isEmpty())
        return {};

    const auto parts = nameParts(desiredName);
    const QString stem = parts.at(0);
    const QString suffix = parts.at(1);
    const QString normalizedDestination = normalizeLocation(destinationDir);

    auto isBlocked = [&](const QString &candidate) {
        return blockedNames.contains(candidate) || pathExistsSync(joinLocation(normalizedDestination, candidate));
    };

    if (!isBlocked(desiredName))
        return desiredName;

    const QString copyStem = stem + " (copy)";
    const QString firstCandidate = copyStem + suffix;
    if (!isBlocked(firstCandidate))
        return firstCandidate;

    for (int i = 2; i < 10000; ++i) {
        const QString candidate = QString("%1 (copy %2)%3").arg(stem).arg(i).arg(suffix);
        if (!isBlocked(candidate))
            return candidate;
    }

    return {};
}

void FileOperations::deleteFiles(const QStringList &paths)
{
    startSimpleOperation(
        QString("Deleting %1 item(s)...").arg(paths.size()), paths,
        [paths](ProgressReporter report) -> QString {
            QString lastError;
            const int total = paths.size();
            for (int i = 0; i < total; ++i) {
                const QString normalized = normalizeLocation(paths[i]);
                report(i, total, locationFileName(normalized));

                if (isUriPath(normalized)) {
                    GFile *file = gFileForLocation(normalized);
                    QString err;
                    if (!deleteGFileRecursive(file, &err) && !err.isEmpty())
                        lastError = err;
                    g_object_unref(file);
                } else {
                    QFileInfo info(normalized);
                    if (info.isDir()) {
                        if (!QDir(normalized).removeRecursively())
                            lastError = QStringLiteral("Failed to delete one or more items");
                    } else {
                        if (!QFile::remove(normalized))
                            lastError = QStringLiteral("Failed to delete one or more items");
                    }
                }
            }
            return lastError;
        });
}
