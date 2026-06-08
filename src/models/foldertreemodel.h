#pragma once

#include <QFileSystemModel>

// Folders-only filesystem tree model for the Gallery sidebar's folder tree.
// Subclasses QFileSystemModel (Qt's built-in, lazily-populated FS tree) and:
//   - filters to directories only, excluding hidden ones,
//   - exposes rootPath as a QML-writable property (the base setRootPath()
//     returns a QModelIndex, so a void wrapper `setRootDir` backs the WRITE),
//   - adds indexForPath()/pathAt() invokables to bridge QML <-> QModelIndex,
//     used to root the TreeView at Home and to auto-reveal the active folder.
//
// Registered as a creatable QML type in main.cpp (qmlRegisterType into the
// "Wayfile" module). Kept Qt6::Qml-free so the unit test can link it alone.
class FolderTreeModel : public QFileSystemModel
{
    Q_OBJECT
    Q_PROPERTY(QString rootPath READ rootPath WRITE setRootDir NOTIFY rootPathChanged)

public:
    explicit FolderTreeModel(QObject *parent = nullptr);

    // QML-writable wrapper around the base setRootPath() (which returns an index).
    void setRootDir(const QString &path);

    Q_INVOKABLE QModelIndex indexForPath(const QString &path) const;
    Q_INVOKABLE QString pathAt(const QModelIndex &idx) const;
};
