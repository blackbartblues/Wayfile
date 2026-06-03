#include "models/filesystemmodel_helpers.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLocale>
#include <QMimeDatabase>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QUrl>
#include <algorithm>

namespace FsmHelpers {


// Shared MIME database: construction is cheap but keeping one instance
// avoids repeating the same static-init dance across every helper below.
QMimeDatabase &mimeDb()
{
    static QMimeDatabase db;
    return db;
}

bool isTrashUri(const QString &path)
{
    return QUrl(path).scheme() == "trash";
}

bool shouldSpawnHostTool()
{
    static const bool inSandbox = QFile::exists(QStringLiteral("/.flatpak-info"));
    return inSandbox;
}

void startHostToolProcess(QProcess *process, const QString &program, const QStringList &arguments)
{
    if (shouldSpawnHostTool()) {
        QStringList args;
        args << QStringLiteral("--host") << program << arguments;
        process->start(QStringLiteral("flatpak-spawn"), args);
        return;
    }

    process->start(program, arguments);
}

bool isRemoteUri(const QString &path)
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

    const QString encodedPath = [&normalizedUrl]() {
        QString value = normalizedUrl.path(QUrl::FullyEncoded);
        if (value.isEmpty())
            value = QStringLiteral("/");
        if (value.size() > 1 && value.endsWith(QLatin1Char('/')))
            value.chop(1);
        return value;
    }();

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

QString gioLocationArg(const QString &path)
{
    const QString normalized = normalizeLocation(path);
    if (QUrl(normalized).scheme().isEmpty())
        return normalized;
    return normalized;
}

QString locationFileName(const QString &path)
{
    const QString normalized = normalizeLocation(path);
    if (isRemoteUri(normalized)) {
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
    if (isRemoteUri(normalized)) {
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

    return QFileInfo(normalized).absolutePath();
}

QString afcDocumentsUriFor(const QString &path)
{
    const QString normalized = normalizeLocation(path);
    const QUrl url(normalized);
    if (url.scheme() != QLatin1String("afc"))
        return {};

    const QString authority = remoteAuthority(normalized);
    if (authority.isEmpty() || authority.contains(QLatin1String(":3")))
        return {};

    return QStringLiteral("afc://%1:3/").arg(authority);
}

QString expandUserPath(const QString &path)
{
    if (path == QStringLiteral("~"))
        return QDir::homePath();
    if (path.startsWith(QStringLiteral("~/")))
        return QDir::cleanPath(QDir::homePath() + path.mid(1));
    return path;
}

QString displayPathForSuggestion(const QString &path)
{
    const QString cleanPath = QDir::cleanPath(path);
    const QString homePath = QDir::homePath();
    if (cleanPath == homePath)
        return QStringLiteral("~");
    if (cleanPath.startsWith(homePath + QLatin1Char('/')))
        return QStringLiteral("~") + cleanPath.mid(homePath.size());
    return cleanPath;
}

QDateTime dateTimeFromSeconds(const QString &value)
{
    return value.isEmpty() ? QDateTime() : QDateTime::fromSecsSinceEpoch(value.toLongLong());
}

QString permissionsStringFromMode(int mode)
{
    if (mode <= 0)
        return {};

    QString s;
    s += (mode & 0400) ? 'r' : '-';
    s += (mode & 0200) ? 'w' : '-';
    s += (mode & 0100) ? 'x' : '-';
    s += (mode & 0040) ? 'r' : '-';
    s += (mode & 0020) ? 'w' : '-';
    s += (mode & 0010) ? 'x' : '-';
    s += (mode & 0004) ? 'r' : '-';
    s += (mode & 0002) ? 'w' : '-';
    s += (mode & 0001) ? 'x' : '-';
    return s;
}

int accessIndexFromMode(int mode, int readMask, int writeMask, int execMask)
{
    const bool canRead = mode & readMask;
    const bool canWrite = mode & writeMask;
    const bool canExecute = mode & execMask;
    if (canRead && canWrite && canExecute)
        return 3;
    if (canRead && canWrite)
        return 2;
    if (canRead)
        return 1;
    return 0;
}

QString formattedSize(qint64 size, bool verbose)
{
    if (size < 0)
        return {};
    if (size < 1024)
        return verbose ? QString("%1 B (%2 bytes)").arg(size).arg(QLocale().toString(size))
                       : QString("%1 B").arg(size);
    if (size < 1024 * 1024)
        return verbose ? QString("%1 KB (%2 bytes)").arg(size / 1024.0, 0, 'f', 1).arg(QLocale().toString(size))
                       : QString("%1 KB").arg(size / 1024.0, 0, 'f', 1);
    if (size < 1024LL * 1024 * 1024)
        return verbose ? QString("%1 MB (%2 bytes)").arg(size / (1024.0 * 1024.0), 0, 'f', 1).arg(QLocale().toString(size))
                       : QString("%1 MB").arg(size / (1024.0 * 1024.0), 0, 'f', 1);
    return verbose ? QString("%1 GB (%2 bytes)").arg(size / (1024.0 * 1024.0 * 1024.0), 0, 'f', 2).arg(QLocale().toString(size))
                   : QString("%1 GB").arg(size / (1024.0 * 1024.0 * 1024.0), 0, 'f', 1);
}

// Resolve a MIME type name (e.g. "text/x-typescript", "video/mp2t") to a
// freedesktop icon theme name. Falls back to the type's generic icon, then
// to a plain text icon as last resort.
QString iconNameForMimeName(const QString &mimeName)
{
    if (mimeName.isEmpty())
        return QStringLiteral("text-x-generic");
    const QMimeType mime = mimeDb().mimeTypeForName(mimeName);
    if (!mime.isValid())
        return QStringLiteral("text-x-generic");
    QString icon = mime.iconName();
    if (icon.isEmpty())
        icon = mime.genericIconName();
    return icon.isEmpty() ? QStringLiteral("text-x-generic") : icon;
}

// Resolve an icon for a file from its name (and optional precomputed
// content type, e.g. from `gio list -a standard::content-type` for trash
// entries). When no content type is given, ask QMimeDatabase based on the
// name; for ambiguous extensions like .ts (TypeScript vs MPEG-TS) the
// MIME database picks based on glob priority and content sniffing rather
// than a hand-maintained suffix table.
QString iconNameForEntry(const QString &name, bool isDir, const QString &contentType)
{
    if (isDir)
        return QStringLiteral("folder");

    if (!contentType.isEmpty())
        return iconNameForMimeName(contentType);

    // mimeTypeForFile with just a name uses extension/glob lookup. If the
    // path is a real local file, MatchDefault will additionally sniff the
    // content when the glob is ambiguous, which is what disambiguates
    // .ts files between TypeScript and MPEG-TS video.
    const QMimeType mime = mimeDb().mimeTypeForFile(name);
    return iconNameForMimeName(mime.name());
}

QString fileTypeForEntry(const QString &name, bool isDir, const QString &contentType)
{
    if (isDir)
        return QStringLiteral("folder");

    if (!contentType.isEmpty()) {
        const QMimeType mime = mimeDb().mimeTypeForName(contentType);
        if (mime.isValid())
            return mime.comment();
        return contentType;
    }

    const QMimeType mime = mimeDb().mimeTypeForFile(name);
    return mime.isValid() ? mime.comment() : QFileInfo(name).suffix();
}

QString fileCategoryForEntry(const QString &name, bool isDir, const QString &contentType)
{
    if (isDir)
        return QStringLiteral("folder");

    QString mimeName = contentType;
    if (mimeName.isEmpty()) {
        const QMimeType mime = mimeDb().mimeTypeForFile(name);
        if (mime.isValid())
            mimeName = mime.name();
    }

    if (mimeName.startsWith(QLatin1String("image/")))
        return QStringLiteral("image");
    if (mimeName.startsWith(QLatin1String("video/")))
        return QStringLiteral("video");
    if (mimeName.startsWith(QLatin1String("audio/")))
        return QStringLiteral("audio");

    // Archives — explicit MIME names (covers tar/gzip/xz/bzip2/zstd/7z/rar/zip
    // and their compound *-compressed-tar variants).
    static const QStringList archiveMimes = {
        QStringLiteral("application/zip"), QStringLiteral("application/gzip"),
        QStringLiteral("application/x-tar"), QStringLiteral("application/x-7z-compressed"),
        QStringLiteral("application/x-xz"), QStringLiteral("application/x-bzip"),
        QStringLiteral("application/x-bzip2"), QStringLiteral("application/zstd"),
        QStringLiteral("application/vnd.rar"), QStringLiteral("application/x-rar-compressed"),
        QStringLiteral("application/x-compressed-tar"), QStringLiteral("application/x-bzip-compressed-tar"),
        QStringLiteral("application/x-xz-compressed-tar"), QStringLiteral("application/x-7z-compressed-tar"),
        QStringLiteral("application/x-archive"), QStringLiteral("application/vnd.android.package-archive"),
    };
    if (archiveMimes.contains(mimeName))
        return QStringLiteral("archive");

    // Code — source/markup/data formats. text/x-* covers most languages; the
    // rest are common application/* and text/* code formats.
    if (mimeName.startsWith(QLatin1String("text/x-")))
        return QStringLiteral("code");
    static const QStringList codeMimes = {
        QStringLiteral("application/json"), QStringLiteral("application/xml"),
        QStringLiteral("text/xml"), QStringLiteral("application/javascript"),
        QStringLiteral("text/javascript"), QStringLiteral("application/x-shellscript"),
        QStringLiteral("application/x-yaml"), QStringLiteral("text/yaml"),
        QStringLiteral("application/toml"), QStringLiteral("text/html"),
        QStringLiteral("text/css"), QStringLiteral("application/x-php"),
        QStringLiteral("application/sql"),
    };
    if (codeMimes.contains(mimeName))
        return QStringLiteral("code");

    // Documents — PDFs, office formats, and plain/rich text.
    if (mimeName == QLatin1String("application/pdf"))
        return QStringLiteral("document");
    if (mimeName.startsWith(QLatin1String("application/vnd.oasis"))
        || mimeName.startsWith(QLatin1String("application/vnd.openxmlformats"))
        || mimeName.startsWith(QLatin1String("application/msword"))
        || mimeName.startsWith(QLatin1String("application/vnd.ms-")))
        return QStringLiteral("document");
    if (mimeName.startsWith(QLatin1String("text/")))
        return QStringLiteral("document");

    return QStringLiteral("other");
}

QString folderTypeForPath(const QString &absolutePath)
{
    if (absolutePath.isEmpty())
        return QString();

    const QDir target(absolutePath);
    auto matches = [&target](QStandardPaths::StandardLocation loc) {
        const QString dir = QStandardPaths::writableLocation(loc);
        return !dir.isEmpty() && target == QDir(dir);
    };

    // XDG user-dirs (QStandardPaths). HomeLocation is always defined; the
    // rest fall back to ~/Subdir when unset, which is exactly what we want.
    if (matches(QStandardPaths::HomeLocation))      return QStringLiteral("home");
    if (matches(QStandardPaths::DocumentsLocation)) return QStringLiteral("documents");
    if (matches(QStandardPaths::DownloadLocation))  return QStringLiteral("downloads");
    if (matches(QStandardPaths::PicturesLocation))  return QStringLiteral("pictures");
    if (matches(QStandardPaths::MusicLocation))     return QStringLiteral("music");
    if (matches(QStandardPaths::MoviesLocation))    return QStringLiteral("videos");
    if (matches(QStandardPaths::DesktopLocation))   return QStringLiteral("desktop");

    // "Projects" has no XDG entry — match the handoff convention of a dev
    // directory living directly under $HOME.
    const QString home = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    if (!home.isEmpty()) {
        static const QStringList devNames = {
            QStringLiteral("Projects"), QStringLiteral("Code"),
            QStringLiteral("Developer"), QStringLiteral("dev"),
            QStringLiteral("Development"),
        };
        for (const QString &name : devNames) {
            if (target == QDir(home + QLatin1Char('/') + name))
                return QStringLiteral("projects");
        }
    }

    return QString();
}

// Classify a file as image/video for thumbnail purposes. Prefers an
// already-known content type (e.g. from `gio list -a standard::content-type`
// for trash entries) and otherwise asks QMimeDatabase. For local files
// QMimeDatabase content-sniffs ambiguous extensions like .ts.

PreviewKind previewKindForEntry(const QString &localPath, bool isDir,
                                const QString &contentType)
{
    if (isDir)
        return PreviewKind::None;

    QString mimeName = contentType;
    if (mimeName.isEmpty()) {
        const QMimeType mime = mimeDb().mimeTypeForFile(localPath);
        if (mime.isValid())
            mimeName = mime.name();
    }
    if (mimeName.isEmpty())
        return PreviewKind::None;

    if (mimeName.startsWith(QLatin1String("image/")))
        return PreviewKind::Image;
    if (mimeName.startsWith(QLatin1String("video/")))
        return PreviewKind::Video;
    return PreviewKind::None;
}

// Build a cached permission string (e.g. "rwxr-xr-x") from QFileInfo.
QString permissionsString(const QFileInfo &info)
{
    const auto p = info.permissions();
    QString s;
    s += (p & QFile::ReadOwner)  ? 'r' : '-';
    s += (p & QFile::WriteOwner) ? 'w' : '-';
    s += (p & QFile::ExeOwner)   ? 'x' : '-';
    s += (p & QFile::ReadGroup)  ? 'r' : '-';
    s += (p & QFile::WriteGroup) ? 'w' : '-';
    s += (p & QFile::ExeGroup)   ? 'x' : '-';
    s += (p & QFile::ReadOther)  ? 'r' : '-';
    s += (p & QFile::WriteOther) ? 'w' : '-';
    s += (p & QFile::ExeOther)   ? 'x' : '-';
    return s;
}

QHash<QString, QString> parseGioAttributes(const QString &attributeText)
{
    QHash<QString, QString> attrs;
    static const QRegularExpression attrRe(R"(([A-Za-z0-9:-]+)=(.*?)(?= [A-Za-z0-9:-]+=|$))");

    auto it = attrRe.globalMatch(attributeText.trimmed());
    while (it.hasNext()) {
        const auto match = it.next();
        attrs.insert(match.captured(1), match.captured(2));
    }

    return attrs;
}

QVariantMap buildRemoteEntryFromLine(const QString &line)
{
    static const QRegularExpression lineRe(QStringLiteral("^([^\\t]+)\\t([0-9-]+)\\t\\(([^)]*)\\)(?:\\t(.*))?$"));
    const auto match = lineRe.match(line.trimmed());
    if (!match.hasMatch())
        return {};

    const QString uri = normalizeLocation(match.captured(1).trimmed());
    const qint64 size = match.captured(2).trimmed().toLongLong();
    const QString typeToken = match.captured(3).trimmed().toLower();
    const auto attrs = parseGioAttributes(match.captured(4));

    const bool isDir = typeToken.contains(QStringLiteral("directory"));
    const QString displayName = attrs.value(QStringLiteral("standard::display-name"), locationFileName(uri));
    const QString contentType = attrs.value(QStringLiteral("standard::content-type"));
    const int unixMode = attrs.value(QStringLiteral("unix::mode")).toInt();
    const QDateTime modified = dateTimeFromSeconds(attrs.value(QStringLiteral("time::modified")));

    QVariantMap entry;
    entry[QStringLiteral("fileName")] = displayName;
    entry[QStringLiteral("filePath")] = uri;
    entry[QStringLiteral("fileSize")] = isDir ? QVariant(qint64(-1)) : QVariant(size);
    entry[QStringLiteral("fileSizeText")] = isDir ? QString() : formattedSize(size);
    entry[QStringLiteral("fileType")] = fileTypeForEntry(displayName, isDir, contentType);
    entry[QStringLiteral("fileCategory")] = fileCategoryForEntry(displayName, isDir, contentType);
    entry[QStringLiteral("fileExtension")] = isDir ? QString() : QFileInfo(displayName).completeSuffix();
    entry[QStringLiteral("fileModified")] = modified;
    entry[QStringLiteral("fileModifiedText")] = modified.isValid() ? QLocale().toString(modified, QLocale::ShortFormat) : QString();
    entry[QStringLiteral("filePermissions")] = permissionsStringFromMode(unixMode);
    entry[QStringLiteral("isDir")] = isDir;
    entry[QStringLiteral("isSymlink")] = attrs.value(QStringLiteral("standard::is-symlink")) == QStringLiteral("TRUE");
    entry[QStringLiteral("fileIconName")] = iconNameForEntry(displayName, isDir, contentType);
    entry[QStringLiteral("mimeType")] = contentType;
    entry[QStringLiteral("symlinkTarget")] = attrs.value(QStringLiteral("standard::symlink-target"));
    return entry;
}

QVariantMap buildFallbackRemoteProperties(const QString &path)
{
    QVariantMap props;
    props[QStringLiteral("name")] = locationFileName(path);
    props[QStringLiteral("path")] = path;
    props[QStringLiteral("parentDir")] = parentLocation(path);
    props[QStringLiteral("isDir")] = false;
    props[QStringLiteral("isSymlink")] = false;
    props[QStringLiteral("iconName")] = iconNameForEntry(props.value(QStringLiteral("name")).toString(), false);
    props[QStringLiteral("size")] = qint64(-1);
    props[QStringLiteral("sizeText")] = QString();
    props[QStringLiteral("permissions")] = QString();
    props[QStringLiteral("ownerAccess")] = 0;
    props[QStringLiteral("groupAccess")] = 0;
    props[QStringLiteral("otherAccess")] = 0;
    props[QStringLiteral("isExecutable")] = false;
    props[QStringLiteral("canEditPermissions")] = false;
    return props;
}

QVariantMap buildRemotePropertiesFromEntry(const QVariantMap &entry)
{
    QVariantMap props;
    const QString displayName = entry.value(QStringLiteral("fileName")).toString();
    const QString path = entry.value(QStringLiteral("filePath")).toString();
    const bool isDir = entry.value(QStringLiteral("isDir")).toBool();
    const QString mimeType = entry.value(QStringLiteral("mimeType")).toString();
    const QDateTime modified = entry.value(QStringLiteral("fileModified")).toDateTime();
    const qint64 size = entry.value(QStringLiteral("fileSize")).toLongLong();

    props[QStringLiteral("name")] = displayName;
    props[QStringLiteral("path")] = path;
    props[QStringLiteral("parentDir")] = parentLocation(path);
    props[QStringLiteral("isDir")] = isDir;
    props[QStringLiteral("isSymlink")] = entry.value(QStringLiteral("isSymlink")).toBool();
    props[QStringLiteral("symlinkTarget")] = entry.value(QStringLiteral("symlinkTarget")).toString();
    props[QStringLiteral("iconName")] = entry.value(QStringLiteral("fileIconName")).toString();
    props[QStringLiteral("mimeType")] = mimeType;
    props[QStringLiteral("mimeDescription")] = mimeType.isEmpty() ? QString() : mimeDb().mimeTypeForName(mimeType).comment();
    props[QStringLiteral("created")] = QString();
    props[QStringLiteral("modified")] = modified.isValid() ? QLocale().toString(modified, QLocale::LongFormat) : QString();
    props[QStringLiteral("accessed")] = QString();
    props[QStringLiteral("owner")] = QString();
    props[QStringLiteral("group")] = QString();
    props[QStringLiteral("permissions")] = entry.value(QStringLiteral("filePermissions")).toString();
    props[QStringLiteral("ownerAccess")] = 0;
    props[QStringLiteral("groupAccess")] = 0;
    props[QStringLiteral("otherAccess")] = 0;
    props[QStringLiteral("isExecutable")] = false;
    props[QStringLiteral("canEditPermissions")] = false;

    if (isDir) {
        props[QStringLiteral("size")] = qint64(-1);
        props[QStringLiteral("sizeText")] = QString();
        props[QStringLiteral("contentText")] = QString();
    } else {
        props[QStringLiteral("size")] = size;
        props[QStringLiteral("sizeText")] = size >= 0 ? formattedSize(size, true) : QString();
    }

    return props;
}

QVariantMap buildTrashEntryFromLine(const QString &line)
{
    static const QRegularExpression lineRe(R"(^([^\t]+)\t(\d+)\t\(([^)]*)\)(?:\t(.*))?$)");
    const auto match = lineRe.match(line.trimmed());
    if (!match.hasMatch())
        return {};

    const QString uri = match.captured(1).trimmed();
    const qint64 size = match.captured(2).toLongLong();
    const QString typeToken = match.captured(3).trimmed().toLower();
    const auto attrs = parseGioAttributes(match.captured(4));

    const bool isDir = typeToken.contains("directory");
    QString displayName = attrs.value("standard::display-name");
    if (displayName.isEmpty()) {
        const QUrl url(uri);
        displayName = url.fileName();
        if (displayName.isEmpty())
            displayName = attrs.value("standard::name");
    }

    QDateTime modified;
    const QString modifiedSeconds = attrs.value("time::modified");
    if (!modifiedSeconds.isEmpty())
        modified = QDateTime::fromSecsSinceEpoch(modifiedSeconds.toLongLong());

    QDateTime deletedAt;
    const QString deletionDate = attrs.value("trash::deletion-date");
    if (!deletionDate.isEmpty()) {
        deletedAt = QDateTime::fromString(deletionDate, Qt::ISODate);
        if (!deletedAt.isValid())
            deletedAt = QDateTime::fromString(deletionDate, Qt::ISODateWithMs);
    }

    const QString contentType = attrs.value("standard::content-type");
    const QString mimeDescription = contentType.isEmpty()
        ? QString()
        : mimeDb().mimeTypeForName(contentType).comment();

    QVariantMap entry;
    entry["fileName"] = displayName;
    entry["filePath"] = uri;
    entry["fileSize"] = isDir ? QVariant(-1) : QVariant(size);
    entry["fileSizeText"] = isDir ? QString() : formattedSize(size);
    entry["fileType"] = fileTypeForEntry(displayName, isDir, contentType);
    entry["fileCategory"] = fileCategoryForEntry(displayName, isDir, contentType);
    entry["fileExtension"] = isDir ? QString() : QFileInfo(displayName).completeSuffix();
    entry["fileModified"] = modified;
    entry["fileModifiedText"] = modified.isValid() ? QLocale().toString(modified, QLocale::ShortFormat) : QString();
    entry["filePermissions"] = QString();
    entry["isDir"] = isDir;
    entry["isSymlink"] = typeToken.contains("symbolic");
    entry["fileIconName"] = iconNameForEntry(displayName, isDir, contentType);
    entry["originalPath"] = attrs.value("trash::orig-path");
    entry["deletedAt"] = deletedAt;
    entry["deletedAtText"] = deletedAt.isValid() ? QLocale().toString(deletedAt, QLocale::LongFormat) : QString();
    entry["mimeType"] = contentType;
    entry["mimeDescription"] = mimeDescription;
    return entry;
}

QVariantMap buildTrashProperties(const QVariantMap &entry)
{
    QVariantMap props;
    const QString originalPath = entry.value("originalPath").toString();
    const QFileInfo originalInfo(originalPath);

    props["name"] = entry.value("fileName").toString();
    props["path"] = entry.value("filePath").toString();
    props["parentDir"] = originalPath.isEmpty() ? QString() : originalInfo.absolutePath();
    props["originalPath"] = originalPath;
    props["isDir"] = entry.value("isDir").toBool();
    props["isSymlink"] = false;
    props["iconName"] = entry.value("fileIconName").toString();
    props["size"] = entry.value("fileSize");
    props["sizeText"] = entry.value("fileSizeText").toString();
    props["mimeType"] = entry.value("mimeType").toString();
    props["mimeDescription"] = entry.value("mimeDescription").toString();
    props["created"] = QString();
    props["modified"] = entry.value("fileModified").toDateTime().isValid()
        ? QLocale().toString(entry.value("fileModified").toDateTime(), QLocale::LongFormat)
        : QString();
    props["accessed"] = QString();
    props["owner"] = QString();
    props["group"] = QString();
    props["permissions"] = QString();
    props["ownerAccess"] = 0;
    props["groupAccess"] = 0;
    props["otherAccess"] = 0;
    props["isExecutable"] = false;
    props["canEditPermissions"] = false;
    props["isTrashItem"] = true;
    props["deleted"] = entry.value("deletedAtText").toString();
    return props;
}


// True when this binary is running inside a Flatpak sandbox.
bool runningInFlatpak()
{
    static const bool inSandbox = QFile::exists(QStringLiteral("/.flatpak-info"));
    return inSandbox;
}

// Run a host CLI tool, transparently wrapping it in `flatpak-spawn --host`
// when we're inside a Flatpak sandbox. Returns trimmed stdout. (Default
// for timeoutMs is on the forward declaration at the top of the file.)
QString runHostTool(const QString &program, const QStringList &arguments,
                           int timeoutMs)
{
    QProcess proc;
    if (runningInFlatpak()) {
        QStringList args;
        args << QStringLiteral("--host") << program << arguments;
        proc.start(QStringLiteral("flatpak-spawn"), args);
    } else {
        proc.start(program, arguments);
    }
    proc.waitForFinished(timeoutMs);
    return QString::fromUtf8(proc.readAllStandardOutput());
}

} // namespace FsmHelpers
