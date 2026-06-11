#include "models/foldertreemodel.h"

#include <QDir>

FolderTreeModel::FolderTreeModel(QObject *parent)
    : QFileSystemModel(parent)
{
    setReadOnly(true);
    applyFilter();
}

void FolderTreeModel::setHiddenOnly(bool on)
{
    if (on == m_hiddenOnly)
        return;
    m_hiddenOnly = on;
    applyFilter();
    emit hiddenOnlyChanged();
}

void FolderTreeModel::applyFilter()
{
    if (m_hiddenOnly) {
        // Hidden directories ONLY. QDir::Dirs (not AllDirs) makes the name
        // filter apply to directory names; the ".*" glob keeps only dot-prefixed
        // entries, and QDir::Hidden is required to list them at all. With no
        // QDir::Files flag, files (incl. hidden ones) are omitted.
        // setNameFilterDisables(false) removes non-matching rows rather than
        // greying them out.
        setNameFilters(QStringList{QStringLiteral(".*")});
        setNameFilterDisables(false);
        setFilter(QDir::Dirs | QDir::NoDotAndDotDot | QDir::Hidden);
    } else {
        // Directories only (no files): QDir::AllDirs lists directories and, with
        // no QDir::Files flag, files are omitted; QDir::NoDotAndDotDot drops
        // "."/".." and, with no QDir::Hidden, hidden folders are excluded.
        setNameFilters(QStringList{});
        setFilter(QDir::AllDirs | QDir::NoDotAndDotDot);
    }
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
