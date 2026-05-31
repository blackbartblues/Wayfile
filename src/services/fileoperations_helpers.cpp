#include "services/fileoperations_helpers.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QUrl>
#include <algorithm>

#undef signals
#include <gio/gio.h>
#define signals Q_SIGNALS

namespace FileOperationsHelpers {

bool runningInFlatpak()
{
    static const bool inSandbox = QFile::exists(QStringLiteral("/.flatpak-info"));
    return inSandbox;
}

bool isTrashUriPath(const QString &path)
{
    return QUrl(path).scheme() == "trash";
}

bool isUriPath(const QString &path)
{
    const QUrl url(path);
    return url.isValid() && !url.scheme().isEmpty();
}

bool isRemoteUriPath(const QString &path)
{
    const QUrl url(path);
    return url.isValid() && !url.scheme().isEmpty()
        && url.scheme() != QStringLiteral("file")
        && url.scheme() != QStringLiteral("trash");
}

QString remoteAuthority(const QString &uri)
{
    const int schemeSep = uri.indexOf(QStringLiteral("://"));
    if (schemeSep < 0)
        return {};

    const int authorityStart = schemeSep + 3;
    int authorityEnd = uri.size();
    const int pathStart = uri.indexOf(QLatin1Char('/'), authorityStart);
    const int queryStart = uri.indexOf(QLatin1Char('?'), authorityStart);
    const int fragmentStart = uri.indexOf(QLatin1Char('#'), authorityStart);
    for (const int marker : {pathStart, queryStart, fragmentStart}) {
        if (marker >= 0)
            authorityEnd = std::min(authorityEnd, marker);
    }

    return uri.mid(authorityStart, authorityEnd - authorityStart);
}

QString normalizeRemoteUri(const QString &path)
{
    const QUrl url(path);
    if (!url.isValid() || url.scheme().isEmpty())
        return path;

    const QUrl normalizedUrl = url.adjusted(QUrl::NormalizePathSegments);
    QString encodedPath = normalizedUrl.path(QUrl::FullyEncoded);
    if (encodedPath.isEmpty())
        encodedPath = QStringLiteral("/");
    if (encodedPath.size() > 1 && encodedPath.endsWith(QLatin1Char('/')))
        encodedPath.chop(1);

    QString normalized = url.scheme().toLower() + QStringLiteral("://")
        + remoteAuthority(path)
        + encodedPath;

    const QString query = normalizedUrl.query(QUrl::FullyEncoded);
    if (!query.isEmpty())
        normalized += QLatin1Char('?') + query;

    const QString fragment = normalizedUrl.fragment(QUrl::FullyEncoded);
    if (!fragment.isEmpty())
        normalized += QLatin1Char('#') + fragment;

    return normalized;
}

QString normalizeLocation(const QString &path)
{
    if (path.isEmpty())
        return {};

    const QUrl url(path);
    if (url.isValid() && url.scheme() == QStringLiteral("file"))
        return QDir::cleanPath(url.toLocalFile());

    if (url.isValid() && !url.scheme().isEmpty())
        return normalizeRemoteUri(path);

    return QDir::cleanPath(path);
}

QString locationFileName(const QString &path)
{
    const QString normalized = normalizeLocation(path);
    if (isUriPath(normalized)) {
        const QUrl url(normalized);
        QString fileName = QUrl::fromPercentEncoding(url.fileName().toUtf8());
        if (!fileName.isEmpty())
            return fileName;
        const QString authority = remoteAuthority(normalized);
        if (!authority.isEmpty())
            return QUrl::fromPercentEncoding(authority.toUtf8());
        return url.scheme().toUpper();
    }

    if (normalized == QStringLiteral("/"))
        return normalized;

    const QFileInfo info(normalized);
    return info.fileName().isEmpty() ? normalized : info.fileName();
}

QString parentLocation(const QString &path)
{
    const QString normalized = normalizeLocation(path);

    if (isTrashUriPath(normalized)) {
        QString current = normalized;
        if (current.size() > 9 && current.endsWith('/'))
            current.chop(1);
        if (current == QStringLiteral("trash://"))
            current = QStringLiteral("trash:///");
        if (current == QStringLiteral("trash:///") || current == QStringLiteral("trash://"))
            return QStringLiteral("trash:///");

        const int slashIndex = current.lastIndexOf('/');
        return slashIndex <= 8 ? QStringLiteral("trash:///") : current.left(slashIndex);
    }

    if (isRemoteUriPath(normalized)) {
        QUrl url(normalized);
        QString urlPath = url.path(QUrl::FullyEncoded);
        const QString base = url.scheme().toLower() + QStringLiteral("://")
            + remoteAuthority(normalized);
        if (urlPath.isEmpty() || urlPath == QStringLiteral("/"))
            return base + QStringLiteral("/");

        if (urlPath.endsWith('/'))
            urlPath.chop(1);

        const int slashIndex = urlPath.lastIndexOf('/');
        return base + (slashIndex <= 0 ? QStringLiteral("/") : urlPath.left(slashIndex));
    }

    const QFileInfo info(normalized);
    return info.absolutePath();
}

QString joinLocation(const QString &parentPath, const QString &name)
{
    const QString normalizedParent = normalizeLocation(parentPath);
    if (isUriPath(normalizedParent)) {
        const QUrl url(normalizedParent);
        QString urlPath = url.path(QUrl::FullyEncoded);
        if (!urlPath.endsWith('/'))
            urlPath += '/';

        QString joined = url.scheme().toLower() + QStringLiteral("://")
            + remoteAuthority(normalizedParent)
            + urlPath
            + QString::fromUtf8(QUrl::toPercentEncoding(name, "/"));

        const QString query = url.query(QUrl::FullyEncoded);
        if (!query.isEmpty())
            joined += QLatin1Char('?') + query;

        const QString fragment = url.fragment(QUrl::FullyEncoded);
        if (!fragment.isEmpty())
            joined += QLatin1Char('#') + fragment;

        return normalizeLocation(joined);
    }

    return QDir(normalizedParent).filePath(name);
}

GFile *gFileForLocation(const QString &path)
{
    const QByteArray utf8 = path.toUtf8();
    if (isUriPath(path))
        return g_file_new_for_uri(utf8.constData());
    return g_file_new_for_path(utf8.constData());
}

bool gioPathExists(const QString &path)
{
    GFile *file = gFileForLocation(path);
    GFileInfo *info = g_file_query_info(file, G_FILE_ATTRIBUTE_STANDARD_TYPE,
                                        G_FILE_QUERY_INFO_NONE, nullptr, nullptr);
    const bool exists = info != nullptr;
    if (info) g_object_unref(info);
    g_object_unref(file);
    return exists;
}

bool pathExistsSync(const QString &path)
{
    const QString normalized = normalizeLocation(path);
    if (isUriPath(normalized))
        return gioPathExists(normalized);
    return QFileInfo::exists(normalized);
}

} // namespace FileOperationsHelpers
