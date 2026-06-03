#pragma once

#include <QSortFilterProxyModel>

// Filters a FileSystemModel down to folders-only or files-only (by IsDirRole)
// for the hybrid view's two stacked sections (Phase 8). The files variant
// carries its own independent sort via sortByColumn(), so sorting the file list
// never reorders the folder grid. roleNames() are inherited from the source
// model, so QML delegates see the same role set as the underlying model.
//
// Registered as a creatable QML type in main.cpp (qmlRegisterType into the
// "Heimdall" module) so each HybridView can create its own folders/files proxy
// pair over the pane's source model. (Kept QtQml-free here so the unit test
// targets, which don't link Qt6::Qml, still compile against this header.)
class DirFilterProxyModel : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(Mode mode READ mode WRITE setMode NOTIFY modeChanged)
    // Reactive row count for the hybrid view's section header ("Folders 8").
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Mode { FoldersOnly, FilesOnly };
    Q_ENUM(Mode)

    explicit DirFilterProxyModel(QObject *parent = nullptr);

    Mode mode() const { return m_mode; }
    void setMode(Mode mode);

    int count() const { return rowCount(); }

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
    void countChanged();

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;

private:
    Mode m_mode = FilesOnly;
};
