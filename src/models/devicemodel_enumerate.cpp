#include "models/devicemodel.h"
#include "models/devicemodel_internal.h"

#include <QDBusArgument>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDebug>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QRegularExpression>
#include <QSet>
#include <QStorageInfo>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariant>

#include <algorithm>

// applyManagedObjects() — the refresh worker that rebuilds m_devices from a
// UDisks2 GetManagedObjects reply plus a GIO volume/mount enumeration. Split
// out of devicemodel.cpp with the DBus-parse and GIO-enumeration helpers it
// consumes. Only uriFromGFile is shared (with the mount TU) and lives in
// devicemodel_detail; everything else is TU-local.

namespace {

// Strip the trailing NUL that UDisks2 includes in `ay` byte arrays
// (Device, Symlinks, MountPoints elements).
QString cstrFromBytes(const QByteArray &bytes)
{
    QByteArray copy = bytes;
    if (copy.endsWith('\0'))
        copy.chop(1);
    return QString::fromUtf8(copy);
}

QStringList parseMountPoints(const QVariant &value)
{
    QStringList out;
    // MountPoints is `aay` — a list of NUL-terminated byte arrays.
    const QDBusArgument arg = value.value<QDBusArgument>();
    if (arg.currentType() == QDBusArgument::ArrayType) {
        arg.beginArray();
        while (!arg.atEnd()) {
            QByteArray mp;
            arg >> mp;
            out << cstrFromBytes(mp);
        }
        arg.endArray();
    }
    return out;
}

QString qStringFromGChar(gchar *value)
{
    const QString out = value ? QString::fromUtf8(value) : QString();
    g_free(value);
    return out;
}

QString schemeFromUri(const QString &uri)
{
    return QUrl(uri).scheme().toLower();
}

QString authorityFromUri(const QString &uri)
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

QString hostFromAuthority(const QString &authority)
{
    const int atIndex = authority.lastIndexOf(QLatin1Char('@'));
    const QString hostAndPort = atIndex >= 0 ? authority.mid(atIndex + 1) : authority;
    const int colonIndex = hostAndPort.indexOf(QLatin1Char(':'));
    return colonIndex >= 0 ? hostAndPort.left(colonIndex) : hostAndPort;
}

QString buildAfcUri(const QString &udid, int port = -1)
{
    if (udid.isEmpty())
        return {};
    return port > 0
        ? QStringLiteral("afc://%1:%2/").arg(udid, QString::number(port))
        : QStringLiteral("afc://%1/").arg(udid);
}

QString hyphenateUdid(const QString &condensed)
{
    if (condensed.size() <= 8)
        return condensed;
    return condensed.left(8) + QLatin1Char('-') + condensed.mid(8);
}

bool afcBackendAvailable()
{
    return QFileInfo::exists(QStringLiteral("/usr/share/gvfs/mounts/afc.mount"))
        || QFileInfo::exists(QStringLiteral("/usr/lib/gvfs/gvfsd-afc"))
        || QFileInfo::exists(QStringLiteral("/usr/libexec/gvfsd-afc"))
        || QFileInfo::exists(QStringLiteral("/run/host/usr/share/gvfs/mounts/afc.mount"))
        || QFileInfo::exists(QStringLiteral("/run/host/usr/lib/gvfs/gvfsd-afc"))
        || QFileInfo::exists(QStringLiteral("/run/host/usr/libexec/gvfsd-afc"));
}

QString mobileUdidFromUri(const QString &uri)
{
    const QString scheme = schemeFromUri(uri);
    if (scheme == QLatin1String("afc"))
        return hostFromAuthority(authorityFromUri(uri));

    if (scheme != QLatin1String("gphoto2"))
        return {};

    static const QRegularExpression suffixRe(QStringLiteral("([0-9A-Fa-f]{12,})$"));
    const auto match = suffixRe.match(authorityFromUri(uri));
    if (!match.hasMatch())
        return {};
    return hyphenateUdid(match.captured(1).toUpper());
}

bool isMobileDeviceScheme(const QString &scheme)
{
    static const QSet<QString> schemes = {
        QStringLiteral("afc"),
        QStringLiteral("gphoto2"),
    };
    return schemes.contains(scheme);
}

bool isRemovableDrive(GDrive *drive)
{
    return drive && (g_drive_is_removable(drive) || g_drive_is_media_removable(drive));
}

QString fallbackGioDeviceKey(const QString &prefix, const QString &name,
                             const QString &uuid, quintptr pointerValue)
{
    QString key = prefix;
    if (!uuid.isEmpty())
        key += QStringLiteral(":") + uuid;
    else if (!name.isEmpty())
        key += QStringLiteral(":") + name;
    else
        key += QStringLiteral(":0x") + QString::number(pointerValue, 16);
    return key;
}

struct DriveInfo {
    bool removable = false;
    QString connectionBus;
};

struct BlockInfo {
    QString device;          // /dev/sdXY
    QString idLabel;
    QString idType;          // filesystem type, e.g. "ext4"
    bool hintIgnore = false;
    QString drivePath;       // object path of parent drive
    qint64 size = 0;
    bool hasFilesystem = false;
    QStringList mountPoints;
    QString partitionType;   // GPT GUID / MBR type, lowercased
};

} // namespace

namespace devicemodel_detail {

QString uriFromGFile(GFile *file)
{
    if (!file)
        return {};
    return qStringFromGChar(g_file_get_uri(file));
}

} // namespace devicemodel_detail

using namespace devicemodel_detail;

void DeviceModel::applyManagedObjects(const QDBusMessage &reply)
{
    beginResetModel();
    clearDevices();

    QHash<QString, DriveInfo> drives;
    QHash<QString, BlockInfo> blocks;

    if (reply.type() != QDBusMessage::ReplyMessage) {
        qWarning() << "DeviceModel: UDisks2 GetManagedObjects failed:"
                   << reply.errorMessage();
    } else {
        const QDBusArgument outer = reply.arguments().constFirst().value<QDBusArgument>();
        outer.beginMap();
        while (!outer.atEnd()) {
            outer.beginMapEntry();
            QDBusObjectPath objectPath;
            outer >> objectPath;

            // Inner map: { interface_name → { property_name → value } }
            outer.beginMap();
            while (!outer.atEnd()) {
                outer.beginMapEntry();
                QString interfaceName;
                QVariantMap properties;
                outer >> interfaceName >> properties;
                outer.endMapEntry();

                const QString path = objectPath.path();

                if (interfaceName == QLatin1String("org.freedesktop.UDisks2.Drive")) {
                    DriveInfo &d = drives[path];
                    d.removable = properties.value(QStringLiteral("Removable")).toBool();
                    d.connectionBus = properties.value(QStringLiteral("ConnectionBus")).toString();
                } else if (interfaceName == QLatin1String("org.freedesktop.UDisks2.Block")) {
                    BlockInfo &b = blocks[path];
                    b.device = cstrFromBytes(properties.value(QStringLiteral("Device")).toByteArray());
                    b.idLabel = properties.value(QStringLiteral("IdLabel")).toString();
                    b.idType = properties.value(QStringLiteral("IdType")).toString();
                    b.hintIgnore = properties.value(QStringLiteral("HintIgnore")).toBool();
                    b.size = properties.value(QStringLiteral("Size")).toLongLong();
                    b.drivePath = properties.value(QStringLiteral("Drive"))
                                      .value<QDBusObjectPath>().path();
                } else if (interfaceName == QLatin1String("org.freedesktop.UDisks2.Filesystem")) {
                    BlockInfo &b = blocks[path];
                    b.hasFilesystem = true;
                    b.mountPoints = parseMountPoints(
                        properties.value(QStringLiteral("MountPoints")));
                } else if (interfaceName == QLatin1String("org.freedesktop.UDisks2.Partition")) {
                    BlockInfo &b = blocks[path];
                    b.partitionType = properties.value(QStringLiteral("Type"))
                                          .toString().toLower();
                }
            }
            outer.endMap();
            outer.endMapEntry();
        }
        outer.endMap();
    }

    static const QString kEfiGuid = QStringLiteral("c12a7328-f81f-11d2-ba4b-00a098cb80e7");

    for (auto it = blocks.constBegin(); it != blocks.constEnd(); ++it) {
        const BlockInfo &b = it.value();

        if (b.hintIgnore)
            continue;
        if (b.idType.isEmpty() || b.idType == QLatin1String("swap"))
            continue;
        if (isVirtual(b.idType))
            continue;
        if (b.device.startsWith(QLatin1String("/dev/loop")) ||
            b.device.startsWith(QLatin1String("/dev/zram")))
            continue;
        if (b.partitionType == kEfiGuid)
            continue;

        const bool mounted = !b.mountPoints.isEmpty();
        const QString mountPoint = mounted ? b.mountPoints.constFirst() : QString();

        if (mounted && (mountPoint.startsWith(QLatin1String("/boot")) ||
                        mountPoint.startsWith(QLatin1String("/snap")) ||
                        mountPoint.startsWith(QLatin1String("/nix")) ||
                        mountPoint.startsWith(QLatin1String("/efi"))))
            continue;

        const DriveInfo drive = drives.value(b.drivePath);
        const bool removable = drive.removable
            || drive.connectionBus == QLatin1String("usb")
            || drive.connectionBus == QLatin1String("sdio");

        QString name;
        if (!b.idLabel.isEmpty())
            name = b.idLabel;
        else if (mounted && mountPoint == QLatin1String("/"))
            name = QStringLiteral("/");
        else if (mounted)
            name = mountPoint.section(QLatin1Char('/'), -1);
        else
            name = b.device.section(QLatin1Char('/'), -1);

        qint64 total = 0;
        qint64 free = 0;
        int usage = 0;
        if (mounted) {
            // Inside a Flatpak the sandbox's `/` is a tmpfs runtime
            // overlay, not the host root. With --filesystem=host the host
            // file system is exposed under /run/host as individual bind
            // mounts (/run/host/usr, /run/host/etc, /run/host/var, etc.).
            // Note: /run/host itself is the tmpfs, so we cannot just stat
            // it — we have to stat one of the sub-mounts that lives on
            // the host root partition.
            //
            // Strategy: try the mount point directly first (works for
            // /home, /tmp, /opt, /media, /mnt, /run/media which are bind
            // mounted at the same path). If that fails or gives bogus
            // numbers and we're in Flatpak, fall back to a host-side
            // probe. For "/" specifically, /run/host/usr is the safest
            // bet — every distro has /usr on the root partition.
            const bool inFlatpak = QFile::exists(QStringLiteral("/.flatpak-info"));
            QStorageInfo storage(mountPoint);
            if (inFlatpak && (!storage.isValid() || storage.bytesTotal() == 0
                              || storage.device() == QByteArrayLiteral("tmpfs"))) {
                QStringList probes;
                if (mountPoint == QLatin1String("/")) {
                    probes << QStringLiteral("/run/host/usr")
                           << QStringLiteral("/run/host/etc");
                } else {
                    probes << QStringLiteral("/run/host") + mountPoint;
                }
                for (const QString &probe : std::as_const(probes)) {
                    if (!QFileInfo(probe).exists())
                        continue;
                    QStorageInfo s(probe);
                    if (s.isValid() && s.bytesTotal() > 0
                        && s.device() != QByteArrayLiteral("tmpfs")) {
                        storage = s;
                        break;
                    }
                }
            }
            if (storage.isValid()) {
                total = storage.bytesTotal();
                free = storage.bytesAvailable();
                if (total > 0)
                    usage = static_cast<int>((total - free) * 100 / total);
            }
        } else {
            total = b.size;
        }

        m_devices.append({name, b.device, mountPoint, b.idType.toLower(),
                          total, free, usage, removable, mounted,
                          QString(), DeviceBackend::UDisks2, nullptr, nullptr});
    }

    GVolumeMonitor *volumeMonitor = m_volumeMonitor ? m_volumeMonitor : g_volume_monitor_get();
    if (volumeMonitor) {
        QList<DeviceEntry> gioDevices;
        QSet<QString> seenMobileDevices;
        QSet<QString> afcRootUris;
        QHash<QString, QString> preferredNamesByUdid;
        const bool canUseAfc = afcBackendAvailable();

        GList *mounts = g_volume_monitor_get_mounts(volumeMonitor);
        for (GList *it = mounts; it; it = it->next) {
            GMount *mount = G_MOUNT(it->data);
            if (!mount || g_mount_is_shadowed(mount))
                continue;

            GFile *location = g_mount_get_default_location(mount);
            if (!location)
                location = g_mount_get_root(mount);

            const QString uri = uriFromGFile(location);
            const QString scheme = schemeFromUri(uri);
            if (!isMobileDeviceScheme(scheme)) {
                if (location)
                    g_object_unref(location);
                continue;
            }

            QString name = qStringFromGChar(g_mount_get_name(mount));
            const QString udid = mobileUdidFromUri(uri);
            if (!udid.isEmpty() && !name.isEmpty())
                preferredNamesByUdid.insert(udid, name);

            if (scheme == QLatin1String("afc") && !udid.isEmpty()
                && !authorityFromUri(uri).contains(QLatin1String(":3"))) {
                afcRootUris.insert(buildAfcUri(udid));
            }

            const QString key = !uri.isEmpty()
                ? uri
                : fallbackGioDeviceKey(QStringLiteral("gio-mount"), name,
                                       qStringFromGChar(g_mount_get_uuid(mount)),
                                       reinterpret_cast<quintptr>(mount));
            if (seenMobileDevices.contains(key)) {
                if (location)
                    g_object_unref(location);
                continue;
            }
            seenMobileDevices.insert(key);

            qint64 total = 0;
            qint64 free = 0;
            int usage = 0;

            GDrive *drive = g_mount_get_drive(mount);
            const bool removable = isRemovableDrive(drive) || uri.startsWith(QLatin1String("afc://"));
            if (drive)
                g_object_unref(drive);

            if (location)
                g_object_unref(location);

            if (name.isEmpty())
                name = QStringLiteral("Mobile Device");

            gioDevices.append({name, key, uri, scheme,
                               total, free, usage, removable, true,
                               QString(), DeviceBackend::Gio, nullptr,
                               G_MOUNT(g_object_ref(mount))});
        }
        g_list_free_full(mounts, g_object_unref);

        GList *volumes = g_volume_monitor_get_volumes(volumeMonitor);
        for (GList *it = volumes; it; it = it->next) {
            GVolume *volume = G_VOLUME(it->data);
            if (!volume)
                continue;

            GMount *mounted = g_volume_get_mount(volume);
            if (mounted) {
                g_object_unref(mounted);
                continue;
            }

            GFile *activationRoot = g_volume_get_activation_root(volume);
            const QString uri = uriFromGFile(activationRoot);
            const QString scheme = schemeFromUri(uri);
            const QString udid = mobileUdidFromUri(uri);
            const QString volumeClass = qStringFromGChar(
                g_volume_get_identifier(volume, G_VOLUME_IDENTIFIER_KIND_CLASS));
            const QString unixDevice = qStringFromGChar(
                g_volume_get_identifier(volume, G_VOLUME_IDENTIFIER_KIND_UNIX_DEVICE));

            const bool looksLikeRemoteMobileDevice = isMobileDeviceScheme(scheme)
                || (unixDevice.isEmpty() && volumeClass == QLatin1String("device"));
            if (!looksLikeRemoteMobileDevice) {
                if (activationRoot)
                    g_object_unref(activationRoot);
                continue;
            }

            QString name = qStringFromGChar(g_volume_get_name(volume));
            if (!udid.isEmpty() && !name.isEmpty())
                preferredNamesByUdid.insert(udid, name);

            const QString key = !uri.isEmpty()
                ? uri
                : fallbackGioDeviceKey(QStringLiteral("gio-volume"), name,
                                       qStringFromGChar(g_volume_get_uuid(volume)),
                                       reinterpret_cast<quintptr>(volume));
            if (seenMobileDevices.contains(key)) {
                if (activationRoot)
                    g_object_unref(activationRoot);
                continue;
            }
            seenMobileDevices.insert(key);

            if (activationRoot)
                g_object_unref(activationRoot);

            if (name.isEmpty())
                name = QStringLiteral("Mobile Device");

            gioDevices.append({name, key, QString(), scheme,
                               0, 0, 0, true, false,
                               QString(), DeviceBackend::Gio,
                               G_VOLUME(g_object_ref(volume)), nullptr});
        }
        g_list_free_full(volumes, g_object_unref);

        for (auto it = preferredNamesByUdid.constBegin(); canUseAfc && it != preferredNamesByUdid.constEnd(); ++it) {
            const QString udid = it.key();
            const QString rootUri = buildAfcUri(udid);
            if (rootUri.isEmpty() || seenMobileDevices.contains(rootUri))
                continue;

            seenMobileDevices.insert(rootUri);
            afcRootUris.insert(rootUri);

            QString name = it.value().trimmed();
            if (name.isEmpty())
                name = QStringLiteral("iPhone");

            gioDevices.append({name, rootUri, QString(), QStringLiteral("afc"),
                               0, 0, 0, true, false,
                               buildAfcUri(udid, 3), DeviceBackend::Gio, nullptr, nullptr});
        }

        for (const DeviceEntry &device : std::as_const(gioDevices)) {
            const QString mobileUri = device.mountPoint.isEmpty() ? device.devicePath : device.mountPoint;
            const QString udid = mobileUdidFromUri(mobileUri);
            if (schemeFromUri(mobileUri) == QLatin1String("afc")
                && authorityFromUri(mobileUri).contains(QLatin1String(":3"))
                && !udid.isEmpty() && afcRootUris.contains(buildAfcUri(udid))) {
                continue;
            }
            if (schemeFromUri(mobileUri) == QLatin1String("gphoto2")
                && canUseAfc && !udid.isEmpty() && afcRootUris.contains(buildAfcUri(udid))) {
                continue;
            }
            m_devices.append(device);
        }

        if (volumeMonitor != m_volumeMonitor)
            g_object_unref(volumeMonitor);
    }

    std::sort(m_devices.begin(), m_devices.end(),
              [](const DeviceEntry &a, const DeviceEntry &b) {
                  if (a.removable != b.removable)
                      return a.removable;
                  return a.devicePath < b.devicePath;
              });

    endResetModel();
}
