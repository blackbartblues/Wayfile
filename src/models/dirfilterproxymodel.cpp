#include "models/dirfilterproxymodel.h"
#include "models/filesystemmodel.h"

DirFilterProxyModel::DirFilterProxyModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
    setDynamicSortFilter(true);
    // Text columns (name/type) sort case-insensitively and locale-aware; the
    // default lessThan handles numeric/date roles correctly on its own.
    setSortCaseSensitivity(Qt::CaseInsensitive);
    setSortLocaleAware(true);
    setSortRole(FileSystemModel::FileNameRole);

    // Keep the `count` property reactive: any structural change to the filtered
    // row set re-emits countChanged so the hybrid section headers update.
    connect(this, &QAbstractItemModel::rowsInserted, this, &DirFilterProxyModel::countChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &DirFilterProxyModel::countChanged);
    connect(this, &QAbstractItemModel::modelReset, this, &DirFilterProxyModel::countChanged);
    connect(this, &QAbstractItemModel::layoutChanged, this, &DirFilterProxyModel::countChanged);
}

void DirFilterProxyModel::setMode(Mode mode)
{
    if (m_mode == mode)
        return;
    m_mode = mode;
    invalidateFilter();
    emit modeChanged();
}

void DirFilterProxyModel::switchSourceModel(QAbstractItemModel *model)
{
    setSourceModel(model);
}

void DirFilterProxyModel::sortByColumn(const QString &column, bool ascending)
{
    int role = FileSystemModel::FileNameRole;
    if (column == QLatin1String("size"))
        role = FileSystemModel::FileSizeRole;
    else if (column == QLatin1String("modified"))
        role = FileSystemModel::FileModifiedRole;
    else if (column == QLatin1String("type"))
        role = FileSystemModel::FileTypeRole;
    setSortRole(role);
    sort(0, ascending ? Qt::AscendingOrder : Qt::DescendingOrder);
}

int DirFilterProxyModel::mapRowToSource(int proxyRow) const
{
    const QModelIndex src = mapToSource(index(proxyRow, 0));
    return src.isValid() ? src.row() : -1;
}

int DirFilterProxyModel::mapRowFromSource(int sourceRow) const
{
    if (!sourceModel())
        return -1;
    const QModelIndex proxy = mapFromSource(sourceModel()->index(sourceRow, 0));
    return proxy.isValid() ? proxy.row() : -1;
}

QString DirFilterProxyModel::filePath(int row) const
{
    if (!sourceModel())
        return {};
    const QModelIndex idx = mapToSource(index(row, 0));
    return idx.isValid() ? sourceModel()->data(idx, FileSystemModel::FilePathRole).toString()
                         : QString();
}

bool DirFilterProxyModel::isDir(int row) const
{
    if (!sourceModel())
        return false;
    const QModelIndex idx = mapToSource(index(row, 0));
    return idx.isValid() && sourceModel()->data(idx, FileSystemModel::IsDirRole).toBool();
}

QString DirFilterProxyModel::fileName(int row) const
{
    if (!sourceModel())
        return {};
    const QModelIndex idx = mapToSource(index(row, 0));
    return idx.isValid() ? sourceModel()->data(idx, FileSystemModel::FileNameRole).toString()
                         : QString();
}

bool DirFilterProxyModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    if (!sourceModel())
        return false;
    const QModelIndex idx = sourceModel()->index(sourceRow, 0, sourceParent);
    const bool isDirectory = sourceModel()->data(idx, FileSystemModel::IsDirRole).toBool();
    switch (m_mode) {
    case FoldersOnly:
        return isDirectory;
    case FilesOnly:
        return !isDirectory;
    case Media: {
        if (isDirectory)
            return false;
        const QString cat =
            sourceModel()->data(idx, FileSystemModel::FileCategoryRole).toString();
        if (cat == QLatin1String("image") || cat == QLatin1String("video")
            || cat == QLatin1String("audio"))
            return true;
        // PDFs are categorised as "document"; match them by extension instead.
        const QString ext =
            sourceModel()->data(idx, FileSystemModel::FileExtensionRole).toString();
        return ext.compare(QLatin1String("pdf"), Qt::CaseInsensitive) == 0;
    }
    }
    return false;
}
