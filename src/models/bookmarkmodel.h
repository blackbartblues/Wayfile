#pragma once

#include <QAbstractListModel>
#include <QStringList>
#include <QVariantMap>
#include <QMap>

class BookmarkModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        PathRole,
        IconRole,
        ColorRole,
    };

    explicit BookmarkModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setBookmarks(const QStringList &paths);
    QStringList paths() const;

    // Seed the path → "#RRGGBB" star-color lookup (from ConfigManager). Must be
    // called BEFORE setBookmarks so makeBookmark can apply colors on first load;
    // re-applies to any existing rows otherwise.
    void setBookmarkColors(const QVariantMap &colors);

    Q_INVOKABLE void addBookmark(const QString &path);
    Q_INVOKABLE void insertBookmark(const QString &path, int index);
    Q_INVOKABLE void removeBookmark(int index);
    Q_INVOKABLE void moveBookmark(int from, int to);
    Q_INVOKABLE bool containsPath(const QString &path) const;
    // Set a bookmark's star color ("" = clear → default gold). Updates the row,
    // emits dataChanged(ColorRole), and emits bookmarkColorChanged so the host
    // can persist via ConfigManager (mirrors the bookmarksChanged → save wiring).
    Q_INVOKABLE void setBookmarkColor(int index, const QString &color);

signals:
    void countChanged();
    void bookmarksChanged();
    void bookmarkColorChanged(const QString &path, const QString &color);

private:
    struct Bookmark {
        QString name;
        QString path;
        QString icon;
        QString color;
    };

    QList<Bookmark> m_bookmarks;
    QMap<QString, QString> m_bookmarkColors;
    static QString expandPath(const QString &path);
    static QString iconForPath(const QString &name);
    Bookmark makeBookmark(const QString &path) const;
};
