#pragma once

#include <QSortFilterProxyModel>

// Filters a FileSystemModel down to folders-only or files-only (by IsDirRole)
// for the hybrid view's two stacked sections (Phase 8). The files variant
// carries its own independent sort via sortByColumn(), so sorting the file list
// never reorders the folder grid. roleNames() are inherited from the source
// model, so QML delegates see the same role set as the underlying model.
class DirFilterProxyModel : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(Mode mode READ mode WRITE setMode NOTIFY modeChanged)

public:
    enum Mode { FoldersOnly, FilesOnly };
    Q_ENUM(Mode)

    explicit DirFilterProxyModel(QObject *parent = nullptr);

    Mode mode() const { return m_mode; }
    void setMode(Mode mode);

    Q_INVOKABLE void switchSourceModel(QAbstractItemModel *model);
    // Sort by a FileSystemModel column: "name" / "size" / "modified" / "type".
    Q_INVOKABLE void sortByColumn(const QString &column, bool ascending);
    // Map between proxy rows and the underlying source rows (selection sync).
    Q_INVOKABLE int mapRowToSource(int proxyRow) const;
    Q_INVOKABLE int mapRowFromSource(int sourceRow) const;
    Q_INVOKABLE QString filePath(int row) const;
    Q_INVOKABLE bool isDir(int row) const;
    Q_INVOKABLE QString fileName(int row) const;

signals:
    void modeChanged();

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;

private:
    Mode m_mode = FilesOnly;
};
