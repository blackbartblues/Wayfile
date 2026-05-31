#include "models/filesystemmodel.h"
#include "models/filesystemmodel_helpers.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QLocale>
#include <QMimeDatabase>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QUrl>
#include <QStringList>
#include <QVariant>

using namespace FsmHelpers;

QVariantMap FileSystemModel::folderItemCounts(const QStringList &paths) const
{
    QVariantMap result;
    for (const QString &path : paths) {
        if (path.isEmpty())
            continue;
        QDir dir(path);
        if (!dir.exists())
            continue;
        const int count = dir.entryList(
            QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System).count();
        result.insert(path, count);
    }
    return result;
}

QVariantMap FileSystemModel::fileProperties(const QString &path) const
{
    const QString normalizedPath = normalizeLocation(path);
    if (isTrashUri(normalizedPath))
        return trashFileProperties(normalizedPath);

    if (isRemoteUri(normalizedPath))
        return remoteFileProperties(normalizedPath);

    QFileInfo info(normalizedPath);
    QVariantMap props;

    props["name"] = info.fileName();
    props["path"] = info.absoluteFilePath();
    props["parentDir"] = info.absolutePath();
    props["isDir"] = info.isDir();
    props["isSymlink"] = info.isSymLink();

    // Icon name (reuse the same mapping as data())
    props["iconName"] = iconNameForEntry(info.fileName(), info.isDir());
    if (info.isSymLink())
        props["symlinkTarget"] = info.symLinkTarget();

    // Size
    if (info.isDir()) {
        QDir dir(normalizedPath);
        auto allEntries = dir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden);
        int fileCount = 0, folderCount = 0;
        for (const auto &e : allEntries) {
            if (e.isDir()) ++folderCount;
            else ++fileCount;
        }
        props["containedItems"] = allEntries.count();
        props["containedFiles"] = fileCount;
        props["containedFolders"] = folderCount;
        props["contentText"] = QString("%1 items (%2 files, %3 folders)").arg(allEntries.count()).arg(fileCount).arg(folderCount);
        props["sizeText"] = QString("%1 items").arg(allEntries.count());
        props["size"] = QVariant(static_cast<qint64>(-1));
    } else {
        qint64 size = info.size();
        props["size"] = size;
        props["sizeText"] = formattedSize(size, true);
    }

    // Disk usage
    QStorageInfo storage(info.absoluteFilePath());
    if (storage.isValid()) {
        qint64 total = storage.bytesTotal();
        qint64 free = storage.bytesAvailable();
        qint64 used = total - free;
        double usedPct = total > 0 ? (double)used / total : 0;
        double freePct = total > 0 ? (double)free / total : 0;

        auto fmtSize = [](qint64 s) -> QString {
            if (s < 1024) return QString("%1 B").arg(s);
            if (s < 1024LL * 1024) return QString("%1 KB").arg(s / 1024.0, 0, 'f', 1);
            if (s < 1024LL * 1024 * 1024) return QString("%1 MB").arg(s / (1024.0 * 1024.0), 0, 'f', 1);
            return QString("%1 GB").arg(s / (1024.0 * 1024.0 * 1024.0), 0, 'f', 1);
        };
        props["diskTotal"] = fmtSize(total);
        props["diskUsed"] = fmtSize(used);
        props["diskFree"] = fmtSize(free);
        props["diskUsedPercent"] = usedPct;
        props["diskUsedPctText"] = QString("%1%").arg(qRound(usedPct * 100));
        props["diskFreePctText"] = QString("%1%").arg(qRound(freePct * 100));
    }

    // MIME type
    auto mime = mimeDb().mimeTypeForFile(info);
    props["mimeType"] = mime.name();
    props["mimeDescription"] = mime.comment();

    // Timestamps
    props["created"] = QLocale().toString(info.birthTime(), QLocale::LongFormat);
    props["modified"] = QLocale().toString(info.lastModified(), QLocale::LongFormat);
    props["accessed"] = QLocale().toString(info.lastRead(), QLocale::LongFormat);

    // Ownership
    props["owner"] = info.owner();
    props["group"] = info.group();

    // Permissions string
    auto p = info.permissions();
    QString permStr;
    permStr += (p & QFile::ReadOwner)  ? 'r' : '-';
    permStr += (p & QFile::WriteOwner) ? 'w' : '-';
    permStr += (p & QFile::ExeOwner)   ? 'x' : '-';
    permStr += (p & QFile::ReadGroup)  ? 'r' : '-';
    permStr += (p & QFile::WriteGroup) ? 'w' : '-';
    permStr += (p & QFile::ExeGroup)   ? 'x' : '-';
    permStr += (p & QFile::ReadOther)  ? 'r' : '-';
    permStr += (p & QFile::WriteOther) ? 'w' : '-';
    permStr += (p & QFile::ExeOther)   ? 'x' : '-';
    props["permissions"] = permStr;

    // Per-role access index: 0=None, 1=Read only, 2=Read & Write, 3=Read & Write & Execute
    // (for dropdown selectors)
    auto accessIndex = [](bool r, bool w, bool x) -> int {
        if (r && w && x) return 3;
        if (r && w)      return 2;
        if (r)           return 1;
        return 0;
    };
    props["ownerAccess"] = accessIndex(p & QFile::ReadOwner, p & QFile::WriteOwner, p & QFile::ExeOwner);
    props["groupAccess"] = accessIndex(p & QFile::ReadGroup, p & QFile::WriteGroup, p & QFile::ExeGroup);
    props["otherAccess"] = accessIndex(p & QFile::ReadOther, p & QFile::WriteOther, p & QFile::ExeOther);
    props["isExecutable"] = bool(p & QFile::ExeOwner);

    return props;
}

QVariantMap FileSystemModel::remoteFileProperties(const QString &path) const
{
    const QString normalizedPath = normalizeLocation(path);
    for (const auto &entry : m_remoteEntries) {
        if (entry.value(QStringLiteral("filePath")).toString() == normalizedPath)
            return buildRemotePropertiesFromEntry(entry);
    }

    QVariantMap props;
    QProcess proc;
    proc.start(QStringLiteral("gio"), {
        QStringLiteral("info"),
        QStringLiteral("-a"),
        QStringLiteral("standard::name,standard::display-name,standard::content-type,standard::size,standard::is-symlink,standard::symlink-target,time::created,time::modified,time::access,owner::user,owner::group,unix::mode,access::can-read,access::can-write,access::can-execute"),
        gioLocationArg(normalizedPath)
    });

    if (!proc.waitForFinished(8000) || proc.exitCode() != 0) {
        return buildFallbackRemoteProperties(normalizedPath);
    }

    const QString output = QString::fromUtf8(proc.readAllStandardOutput());
    QHash<QString, QString> fields;
    bool inAttributes = false;
    for (const QString &line : output.split('\n', Qt::SkipEmptyParts)) {
        const QString trimmed = line.trimmed();
        if (trimmed == QStringLiteral("attributes:")) {
            inAttributes = true;
            continue;
        }

        const int separator = trimmed.indexOf(':');
        if (separator < 0)
            continue;

        const QString key = trimmed.left(separator).trimmed();
        const QString value = trimmed.mid(separator + 1).trimmed();
        if (inAttributes)
            fields.insert(key, value);
        else
            fields.insert(key, value);
    }

    const QString typeText = fields.value(QStringLiteral("type")).toLower();
    const bool isDir = typeText.contains(QStringLiteral("directory"));
    const QString displayName = fields.value(QStringLiteral("display name"), locationFileName(normalizedPath));
    const QString mimeType = fields.value(QStringLiteral("standard::content-type"));
    const qint64 size = fields.value(QStringLiteral("standard::size")).toLongLong();
    const int unixMode = fields.value(QStringLiteral("unix::mode")).toInt();

    props["name"] = displayName;
    props["path"] = normalizedPath;
    props["parentDir"] = parentLocation(normalizedPath);
    props["isDir"] = isDir;
    props["isSymlink"] = fields.value(QStringLiteral("standard::is-symlink")) == QStringLiteral("TRUE");
    props["symlinkTarget"] = fields.value(QStringLiteral("standard::symlink-target"));
    props["iconName"] = iconNameForEntry(displayName, isDir, mimeType);
    props["mimeType"] = mimeType;
    props["mimeDescription"] = mimeType.isEmpty() ? QString() : mimeDb().mimeTypeForName(mimeType).comment();
    props["created"] = QLocale().toString(dateTimeFromSeconds(fields.value(QStringLiteral("time::created"))), QLocale::LongFormat);
    props["modified"] = QLocale().toString(dateTimeFromSeconds(fields.value(QStringLiteral("time::modified"))), QLocale::LongFormat);
    props["accessed"] = QLocale().toString(dateTimeFromSeconds(fields.value(QStringLiteral("time::access"))), QLocale::LongFormat);
    props["owner"] = fields.value(QStringLiteral("owner::user"));
    props["group"] = fields.value(QStringLiteral("owner::group"));
    props["permissions"] = permissionsStringFromMode(unixMode);
    props["ownerAccess"] = accessIndexFromMode(unixMode, 0400, 0200, 0100);
    props["groupAccess"] = accessIndexFromMode(unixMode, 0040, 0020, 0010);
    props["otherAccess"] = accessIndexFromMode(unixMode, 0004, 0002, 0001);
    props["isExecutable"] = bool(unixMode & 0100) || fields.value(QStringLiteral("access::can-execute")) == QStringLiteral("TRUE");
    props["canEditPermissions"] = false;

    if (isDir) {
        props["contentText"] = QString();
        props["sizeText"] = QString();
        props["size"] = qint64(-1);
    } else {
        props["size"] = size;
        props["sizeText"] = formattedSize(size, true);
    }

    return props;
}

QVariantMap FileSystemModel::trashFileProperties(const QString &path) const
{
    for (const auto &entry : m_trashEntries) {
        if (entry.value("filePath").toString() == path)
            return buildTrashProperties(entry);
    }

    QVariantMap props;
    props["name"] = QUrl(path).fileName();
    props["path"] = path;
    props["parentDir"] = QString();
    props["isDir"] = false;
    props["isSymlink"] = false;
    props["iconName"] = iconNameForEntry(props.value("name").toString(), false);
    props["size"] = qint64(-1);
    props["sizeText"] = QString();
    props["mimeType"] = QString();
    props["mimeDescription"] = QString();
    props["created"] = QString();
    props["modified"] = QString();
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
    props["deleted"] = QString();
    return props;
}

bool FileSystemModel::setFilePermissions(const QString &path, int ownerAccess, int groupAccess, int otherAccess)
{
    if (isTrashUri(path) || isRemoteUri(path))
        return false;

    // accessIndex: 0=None, 1=Read only, 2=Read & Write, 3=Read & Write & Execute
    QFile::Permissions perms;

    auto applyAccess = [](int access, QFile::Permission r, QFile::Permission w, QFile::Permission x) -> QFile::Permissions {
        QFile::Permissions p;
        if (access >= 1) p |= r;
        if (access >= 2) p |= w;
        if (access >= 3) p |= x;
        return p;
    };

    perms |= applyAccess(ownerAccess, QFile::ReadOwner, QFile::WriteOwner, QFile::ExeOwner);
    perms |= applyAccess(groupAccess, QFile::ReadGroup, QFile::WriteGroup, QFile::ExeGroup);
    perms |= applyAccess(otherAccess, QFile::ReadOther, QFile::WriteOther, QFile::ExeOther);

    // Also set the User variants (Qt uses both)
    perms |= applyAccess(ownerAccess, QFile::ReadUser, QFile::WriteUser, QFile::ExeUser);

    return QFile::setPermissions(path, perms);
}


QVariantList FileSystemModel::pathSuggestions(const QString &input, int limit) const
{
    QVariantList suggestions;

    const QString trimmed = input.trimmed();
    if (trimmed.isEmpty() || limit <= 0)
        return suggestions;

    const bool preferTildeDisplay = trimmed == QStringLiteral("~")
        || trimmed.startsWith(QStringLiteral("~/"));

    const QString expanded = expandUserPath(trimmed);
    if (isRemoteUri(expanded) || isTrashUri(expanded))
        return suggestions;

    QString parentPath;
    QString fragment;

    if (expanded == QStringLiteral("/")) {
        parentPath = QStringLiteral("/");
    } else if (expanded.endsWith(QLatin1Char('/'))) {
        parentPath = QDir::cleanPath(expanded);
    } else {
        const int slashIndex = expanded.lastIndexOf(QLatin1Char('/'));
        if (slashIndex < 0)
            return suggestions;

        parentPath = slashIndex == 0 ? QStringLiteral("/") : expanded.left(slashIndex);
        fragment = expanded.mid(slashIndex + 1);
    }

    const QDir dir(parentPath);
    if (!dir.exists())
        return suggestions;

    QDir::Filters filters = QDir::Dirs | QDir::NoDotAndDotDot;
    if (m_showHidden || fragment.startsWith(QLatin1Char('.')))
        filters |= QDir::Hidden;

    const QFileInfoList entries = dir.entryInfoList(filters, QDir::Name | QDir::IgnoreCase);
    for (const QFileInfo &entry : entries) {
        const QString name = entry.fileName();
        if (!fragment.isEmpty() && !name.startsWith(fragment, Qt::CaseInsensitive))
            continue;

        QVariantMap suggestion;
        const QString absolutePath = QDir::cleanPath(entry.absoluteFilePath());
        suggestion.insert(QStringLiteral("path"), absolutePath);
        suggestion.insert(QStringLiteral("displayPath"), preferTildeDisplay ? displayPathForSuggestion(absolutePath) : absolutePath);
        suggestion.insert(QStringLiteral("name"), name);
        suggestions.append(suggestion);

        if (suggestions.size() >= limit)
            break;
    }

    return suggestions;
}
