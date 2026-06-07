#include "services/fileoperations.h"
#include "services/fileoperations_helpers.h"

#include <QDir>
#include <QFile>
#include <QSet>
#include <QUuid>

#undef signals
#include <gio/gio.h>
#define signals Q_SIGNALS

using namespace FileOperationsHelpers;

// Rename / create-folder / create-file cluster, split from fileoperations.cpp.
// The sync move/mkdir/create helpers and the rename-operation bookkeeping below
// are used only here; cross-cluster path helpers come from FileOperationsHelpers.
namespace {

bool moveLocationSync(const QString &sourcePath, const QString &targetPath, QString *error = nullptr)
{
    const QString normalizedSource = normalizeLocation(sourcePath);
    const QString normalizedTarget = normalizeLocation(targetPath);

    if (!isUriPath(normalizedSource) && !isUriPath(normalizedTarget)) {
        const bool ok = QFile::rename(normalizedSource, normalizedTarget);
        if (!ok && error)
            *error = QStringLiteral("Could not rename %1").arg(locationFileName(normalizedSource));
        return ok;
    }

    GFile *src = gFileForLocation(normalizedSource);
    GFile *dst = gFileForLocation(normalizedTarget);
    GError *gErr = nullptr;
    const bool ok = g_file_move(src, dst, G_FILE_COPY_NONE, nullptr, nullptr, nullptr, &gErr);
    if (!ok && error)
        *error = gErr ? QString::fromUtf8(gErr->message) : QStringLiteral("Move failed");
    if (gErr) g_error_free(gErr);
    g_object_unref(src);
    g_object_unref(dst);
    return ok;
}

bool makeDirectorySync(const QString &path, QString *error = nullptr)
{
    const QString normalized = normalizeLocation(path);
    if (!isUriPath(normalized)) {
        const bool ok = QDir().mkpath(normalized);
        if (!ok && error)
            *error = QStringLiteral("Could not create folder");
        return ok;
    }

    GFile *file = gFileForLocation(normalized);
    GError *gErr = nullptr;
    const bool ok = g_file_make_directory_with_parents(file, nullptr, &gErr);
    const bool alreadyExists = gErr && g_error_matches(gErr, G_IO_ERROR, G_IO_ERROR_EXISTS);
    if (!ok && !alreadyExists && error)
        *error = gErr ? QString::fromUtf8(gErr->message) : QStringLiteral("Could not create folder");
    if (gErr) g_error_free(gErr);
    g_object_unref(file);
    return ok || alreadyExists;
}

bool createEmptyFileSync(const QString &path, QString *error = nullptr)
{
    const QString normalized = normalizeLocation(path);
    if (!isUriPath(normalized)) {
        QFile file(normalized);
        const bool ok = file.open(QIODevice::WriteOnly);
        file.close();
        if (!ok && error)
            *error = QStringLiteral("Could not create file");
        return ok;
    }

    GFile *file = gFileForLocation(normalized);
    GError *gErr = nullptr;
    GFileOutputStream *stream = g_file_create(file, G_FILE_CREATE_NONE, nullptr, &gErr);
    if (stream) {
        g_output_stream_close(G_OUTPUT_STREAM(stream), nullptr, nullptr);
        g_object_unref(stream);
    } else {
        if (error)
            *error = gErr ? QString::fromUtf8(gErr->message) : QStringLiteral("Could not create file");
        if (gErr) g_error_free(gErr);
        g_object_unref(file);
        return false;
    }
    g_object_unref(file);
    return true;
}

struct RenameOperation {
    QString sourcePath;
    QString targetPath;
    QString tempPath;
};

QVariantMap renameResult(bool success, const QString &error = {}, const QStringList &changedPaths = {})
{
    QVariantMap result;
    result["success"] = success;
    result["error"] = error;
    result["changedPaths"] = changedPaths;
    return result;
}

QString temporaryRenamePathFor(const QString &sourcePath)
{
    QString tempPath;
    do {
        tempPath = joinLocation(parentLocation(sourcePath),
                                QStringLiteral(".wayfile-rename-%1.tmp")
                                    .arg(QUuid::createUuid().toString(QUuid::WithoutBraces)));
    } while (pathExistsSync(tempPath));

    return tempPath;
}

QString renameTargetError(const QString &targetPath)
{
    const QString fileName = locationFileName(targetPath);
    if (fileName.isEmpty() || fileName == "." || fileName == "..")
        return QStringLiteral("Enter a valid target name");

    const QString parentDir = parentLocation(targetPath);
    if (parentDir.isEmpty() || !pathExistsSync(parentDir))
        return QStringLiteral("Target folder does not exist");

    return {};
}

} // namespace

bool FileOperations::rename(const QString &path, const QString &newName)
{
    const QString normalizedPath = normalizeLocation(path);
    const QString targetPath = joinLocation(parentLocation(normalizedPath), newName);
    const QVariantMap result = renameResolvedItems({QVariantMap {
        {"sourcePath", normalizedPath},
        {"targetPath", targetPath}
    }});
    return result.value("success").toBool();
}

QVariantMap FileOperations::renameResolvedItems(const QVariantList &operations)
{
    QList<RenameOperation> renameOperations;
    QSet<QString> sourcePaths;
    QSet<QString> changedSourcePaths;
    QSet<QString> finalTargetPaths;

    for (const QVariant &variant : operations) {
        const QVariantMap item = variant.toMap();
        const QString sourcePath = normalizeLocation(item.value("sourcePath").toString());
        const QString targetPath = normalizeLocation(item.value("targetPath").toString());

        if (sourcePath.isEmpty() || targetPath.isEmpty())
            return renameResult(false, QStringLiteral("Rename operation is missing a path"));

        if (sourcePaths.contains(sourcePath))
            return renameResult(false, QStringLiteral("Cannot rename the same item twice in one batch"));

        sourcePaths.insert(sourcePath);

        const QString targetError = renameTargetError(targetPath);
        if (!targetError.isEmpty())
            return renameResult(false, targetError);

        if (finalTargetPaths.contains(targetPath))
            return renameResult(false, QStringLiteral("Two items cannot end with the same name"));

        finalTargetPaths.insert(targetPath);

        if (!pathExistsSync(sourcePath)) {
            return renameResult(false, QStringLiteral("%1 no longer exists")
                .arg(locationFileName(sourcePath)));
        }

        if (sourcePath == targetPath)
            continue;

        changedSourcePaths.insert(sourcePath);
        renameOperations.append({sourcePath, targetPath, temporaryRenamePathFor(sourcePath)});
    }

    for (const RenameOperation &op : renameOperations) {
        if (pathExistsSync(op.targetPath) && !changedSourcePaths.contains(op.targetPath)) {
            return renameResult(false, QStringLiteral("%1 already exists")
                .arg(locationFileName(op.targetPath)));
        }
    }

    if (renameOperations.isEmpty())
        return renameResult(true, {}, {});

    QList<int> stagedIndices;
    QList<int> finalizedIndices;
    auto rollback = [&renameOperations, &stagedIndices, &finalizedIndices]() {
        for (int i = finalizedIndices.size() - 1; i >= 0; --i) {
            const RenameOperation &op = renameOperations.at(finalizedIndices.at(i));
            if (pathExistsSync(op.targetPath))
                moveLocationSync(op.targetPath, op.sourcePath);
        }

        for (int i = stagedIndices.size() - 1; i >= 0; --i) {
            const RenameOperation &op = renameOperations.at(stagedIndices.at(i));
            if (pathExistsSync(op.tempPath))
                moveLocationSync(op.tempPath, op.sourcePath);
        }
    };

    for (int i = 0; i < renameOperations.size(); ++i) {
        const RenameOperation &op = renameOperations.at(i);
        QString error;
        if (!moveLocationSync(op.sourcePath, op.tempPath, &error)) {
            rollback();
            return renameResult(false, QStringLiteral("Could not prepare %1 for renaming")
                .arg(locationFileName(op.sourcePath)));
        }

        stagedIndices.append(i);
    }

    for (int i = 0; i < renameOperations.size(); ++i) {
        const RenameOperation &op = renameOperations.at(i);
        QString error;
        if (!moveLocationSync(op.tempPath, op.targetPath, &error)) {
            rollback();
            return renameResult(false, QStringLiteral("Could not rename %1")
                .arg(locationFileName(op.sourcePath)));
        }

        finalizedIndices.append(i);
    }

    QStringList changedPaths;
    QStringList invalidatedPaths;
    for (const RenameOperation &op : renameOperations) {
        changedPaths.append(op.targetPath);
        invalidatedPaths << op.sourcePath << op.targetPath;
    }

    emitChangedPaths(invalidatedPaths);

    return renameResult(true, {}, changedPaths);
}

void FileOperations::createFolder(const QString &parentPath, const QString &name)
{
    const QString targetPath = joinLocation(parentPath, name);
    QString error;
    if (makeDirectorySync(targetPath, &error) || error.isEmpty()) {
        emitChangedPaths({targetPath});
        return;
    }
    emit operationFinished(false, error);
}

void FileOperations::createFile(const QString &parentPath, const QString &name)
{
    const QString targetPath = joinLocation(parentPath, name);
    QString error;
    if (createEmptyFileSync(targetPath, &error) || error.isEmpty()) {
        emitChangedPaths({targetPath});
        return;
    }
    emit operationFinished(false, error);
}
