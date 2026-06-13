#pragma once

#include <QObject>
#include <QString>
#include <QList>

// Path-keyed store of a folder's last user-chosen view mode. Mirrors the
// RecentFilesModel idiom: load() on construct, save() on every mutation, and an
// LRU cap so the file can't grow without bound. Plain QObject (never displayed);
// exposed to QML as the `folderViewStore` context property.
class FolderViewStore : public QObject
{
    Q_OBJECT

public:
    explicit FolderViewStore(const QString &storagePath, QObject *parent = nullptr);

    // "" when the folder has no remembered view (caller leaves the pane as-is).
    // Pure lookup: never reorders and never writes to disk.
    Q_INVOKABLE QString viewForFolder(const QString &path) const;
    // Records path -> mode, moving it to the front (LRU). A blank path or mode
    // is ignored.
    Q_INVOKABLE void rememberView(const QString &path, const QString &mode);
    Q_INVOKABLE void forget(const QString &path);
    Q_INVOKABLE void clear();

private:
    void load();
    void save() const;
    static QString normalize(const QString &path);

    struct Entry {
        QString path;
        QString viewMode;
    };

    QList<Entry> m_entries;   // most-recently-written at front
    QString m_storagePath;
    int m_maxEntries = 500;
};
