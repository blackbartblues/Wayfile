#include "models/folderviewstore.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

FolderViewStore::FolderViewStore(const QString &storagePath, QObject *parent)
    : QObject(parent), m_storagePath(storagePath)
{
    load();
}

QString FolderViewStore::normalize(const QString &path)
{
    if (path.size() > 1 && path.endsWith('/'))
        return path.left(path.size() - 1);
    return path;
}

QString FolderViewStore::viewForFolder(const QString &path) const
{
    const QString key = normalize(path);
    for (const Entry &e : m_entries) {
        if (e.path == key)
            return e.viewMode;
    }
    return QString();
}

void FolderViewStore::rememberView(const QString &path, const QString &mode)
{
    const QString key = normalize(path);
    if (key.isEmpty() || mode.isEmpty())
        return;

    for (int i = 0; i < m_entries.size(); ++i) {
        if (m_entries[i].path == key) {
            if (i == 0 && m_entries[i].viewMode == mode)
                return;                 // already front + unchanged: skip write
            m_entries.removeAt(i);
            break;
        }
    }
    m_entries.prepend({key, mode});

    if (m_entries.size() > m_maxEntries)
        m_entries.resize(m_maxEntries);

    save();
}

void FolderViewStore::forget(const QString &path)
{
    const QString key = normalize(path);
    for (int i = 0; i < m_entries.size(); ++i) {
        if (m_entries[i].path == key) {
            m_entries.removeAt(i);
            save();
            return;
        }
    }
}

void FolderViewStore::clear()
{
    if (m_entries.isEmpty())
        return;
    m_entries.clear();
    save();
}

void FolderViewStore::load()
{
    QFile file(m_storagePath);
    if (!file.open(QIODevice::ReadOnly))
        return;

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isArray())
        return;

    for (const auto &val : doc.array()) {
        const QJsonObject obj = val.toObject();
        const QString path = obj.value("path").toString();
        const QString mode = obj.value("viewMode").toString();
        if (!path.isEmpty() && !mode.isEmpty())
            m_entries.append({path, mode});
    }
    if (m_entries.size() > m_maxEntries)
        m_entries.resize(m_maxEntries);
}

void FolderViewStore::save() const
{
    QFile file(m_storagePath);
    if (!file.open(QIODevice::WriteOnly))
        return;

    QJsonArray arr;
    for (const Entry &e : m_entries) {
        arr.append(QJsonObject{
            {"path", e.path},
            {"viewMode", e.viewMode},
        });
    }
    file.write(QJsonDocument(arr).toJson(QJsonDocument::Compact));
}
