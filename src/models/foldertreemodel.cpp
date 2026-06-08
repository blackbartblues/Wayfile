#include "models/foldertreemodel.h"

#include <QDir>

FolderTreeModel::FolderTreeModel(QObject *parent)
    : QFileSystemModel(parent)
{
    // Directories only (no files): QDir::AllDirs lists directories and, with no
    // QDir::Files flag, files are omitted; QDir::NoDotAndDotDot drops "."/".."
    // and, with no QDir::Hidden, hidden folders are excluded.
    setFilter(QDir::AllDirs | QDir::NoDotAndDotDot);
    setReadOnly(true);
}

void FolderTreeModel::setRootDir(const QString &path)
{
    if (path == rootPath())
        return;
    QFileSystemModel::setRootPath(path);  // emits the base rootPathChanged()
}

QModelIndex FolderTreeModel::indexForPath(const QString &path) const
{
    return index(path);   // QFileSystemModel::index(const QString&)
}

QString FolderTreeModel::pathAt(const QModelIndex &idx) const
{
    return filePath(idx); // QFileSystemModel::filePath(const QModelIndex&)
}
