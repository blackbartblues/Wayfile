#include "models/devicemodel.h"
#include "models/devicemodel_internal.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDebug>
#include <QFileInfo>
#include <QPointer>
#include <QProcess>
#include <QString>
#include <QUrl>

#include <memory>

// mount()/unmount() plus the GIO mount callbacks and UDisks2 polkit helpers,
// split out of devicemodel.cpp. Shares uriFromGFile with the enumerate TU via
// devicemodel_internal.h; every other helper here is TU-local.

using namespace devicemodel_detail;

namespace {

QString friendlyGioActionError(const QString &action, const QString &label,
                               const QString &err)
{
    const QString lower = err.toLower();
    if (action == QLatin1String("mount")
        && (lower.contains(QStringLiteral("pair"))
            || lower.contains(QStringLiteral("trust"))
            || lower.contains(QStringLiteral("lockdown")))) {
        return DeviceModel::tr(
            "Could not mount %1: unlock the iPhone or iPad, tap Trust on the device, and try again.")
            .arg(label);
    }
    return DeviceModel::tr("Could not %1 %2: %3").arg(action, label, err);
}

struct GioOperationContext {
    QPointer<DeviceModel> model;
    QString label;
};

void onGioVolumeMounted(GObject *sourceObject, GAsyncResult *result, gpointer userData)
{
    std::unique_ptr<GioOperationContext> context(
        static_cast<GioOperationContext *>(userData));
    if (!context || !context->model)
        return;

    auto *model = context->model.data();
    GError *error = nullptr;
    if (!g_volume_mount_finish(G_VOLUME(sourceObject), result, &error)) {
        const QString err = error ? QString::fromUtf8(error->message).trimmed()
                                  : DeviceModel::tr("Unknown error");
        if (error)
            g_error_free(error);
        emit model->mountError(friendlyGioActionError(QStringLiteral("mount"),
                                                      context->label, err));
        return;
    }

    QString mountPoint;
    GMount *mount = g_volume_get_mount(G_VOLUME(sourceObject));
    if (mount) {
        GFile *location = g_mount_get_default_location(mount);
        if (!location)
            location = g_mount_get_root(mount);
        mountPoint = uriFromGFile(location);
        if (location)
            g_object_unref(location);
        g_object_unref(mount);
    }

    if (mountPoint.isEmpty()) {
        GFile *activationRoot = g_volume_get_activation_root(G_VOLUME(sourceObject));
        mountPoint = uriFromGFile(activationRoot);
        if (activationRoot)
            g_object_unref(activationRoot);
    }

    model->refresh();
    emit model->deviceMounted(mountPoint);
}

void onGioMountUnmounted(GObject *sourceObject, GAsyncResult *result, gpointer userData)
{
    std::unique_ptr<GioOperationContext> context(
        static_cast<GioOperationContext *>(userData));
    if (!context || !context->model)
        return;

    auto *model = context->model.data();
    GError *error = nullptr;
    if (!g_mount_unmount_with_operation_finish(G_MOUNT(sourceObject), result, &error)) {
        const QString err = error ? QString::fromUtf8(error->message).trimmed()
                                  : DeviceModel::tr("Unknown error");
        if (error)
            g_error_free(error);
        emit model->mountError(friendlyGioActionError(QStringLiteral("unmount"),
                                                      context->label, err));
        return;
    }

    model->refresh();
}

} // namespace

// Map a /dev/<basename> path to its UDisks2 object path. This works for
// regular partitions (sdXY, nvmeXnYpZ, mmcblkXpY). Device-mapper / LUKS
// names use a different escaping scheme that we don't try to handle here;
// for those cases the call simply errors out and we log it.
static QString udisksObjectPathFor(const QString &devicePath)
{
    return QStringLiteral("/org/freedesktop/UDisks2/block_devices/")
        + QFileInfo(devicePath).fileName();
}

// UDisks2 returns "Not authorized to perform operation" when polkit refuses
// the call — in practice this is almost always because no polkit
// authentication agent is running in the user's session (polkitd itself is
// running, but it has no UI to prompt for the password). Fixed / internal
// partitions require admin auth, so mount/unmount on those fails silently.
static bool isPolkitAuthError(const QString &err)
{
    return err.contains(QStringLiteral("Not authorized"), Qt::CaseInsensitive);
}

static QString polkitAgentHint()
{
    return DeviceModel::tr(
        "No polkit authentication agent is running. Start one in your session "
        "(e.g. hyprpolkitagent, polkit-gnome, or polkit-kde-authentication-agent-1) "
        "and try again.");
}

void DeviceModel::unmount(int index)
{
    if (index < 0 || index >= m_devices.size())
        return;

    const DeviceEntry &dev = m_devices.at(index);
    if (!dev.mounted)
        return;

    const QString label = dev.deviceName;

    if (dev.backend == DeviceBackend::Gio) {
        if (!dev.gioMount) {
            refresh();
            return;
        }

        auto *context = new GioOperationContext{QPointer<DeviceModel>(this), label};
        g_mount_unmount_with_operation(dev.gioMount,
                                       G_MOUNT_UNMOUNT_NONE,
                                       nullptr,
                                       nullptr,
                                       onGioMountUnmounted,
                                       context);
        return;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.UDisks2"),
        udisksObjectPathFor(dev.devicePath),
        QStringLiteral("org.freedesktop.UDisks2.Filesystem"),
        QStringLiteral("Unmount"));
    msg << QVariant::fromValue(QVariantMap{});

    QDBusPendingCall pending = QDBusConnection::systemBus().asyncCall(msg);
    auto *watcher = new QDBusPendingCallWatcher(pending, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, watcher, label]() {
        QDBusPendingReply<> reply = *watcher;
        if (reply.isError()) {
            const QString err = reply.error().message();
            qWarning() << "UDisks2 Unmount failed:" << err;
            QString friendly = isPolkitAuthError(err)
                ? tr("Could not unmount %1: %2").arg(label, polkitAgentHint())
                : tr("Could not unmount %1: %2").arg(label, err);
            emit mountError(friendly);
        } else {
            refresh();
        }
        watcher->deleteLater();
    });
}

void DeviceModel::mount(int index)
{
    if (index < 0 || index >= m_devices.size())
        return;

    const DeviceEntry entry = m_devices.at(index);
    const QString fsType = entry.fsType;
    const QString label = entry.deviceName;

    if (entry.backend == DeviceBackend::Gio) {
        const QString mountUri = entry.mountPoint.isEmpty() ? entry.devicePath : entry.mountPoint;

        if (!entry.gioVolume) {
            if (QUrl(mountUri).scheme().isEmpty()) {
                refresh();
                return;
            }

            auto *primary = new QProcess(this);
            connect(primary,
                    qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
                    this,
                    [this, primary, mountUri, alternateUri = entry.alternateMountPoint, label]
                    (int exitCode, QProcess::ExitStatus) {
                const QString err = QString::fromUtf8(primary->readAllStandardError()).trimmed();
                primary->deleteLater();

                if (exitCode != 0) {
                    emit mountError(friendlyGioActionError(
                        QStringLiteral("mount"), label,
                        err.isEmpty() ? tr("gio mount failed") : err));
                    return;
                }

                if (!alternateUri.isEmpty() && alternateUri != mountUri) {
                    auto *secondary = new QProcess(this);
                    connect(secondary,
                            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
                            this, [this, secondary, mountUri](int, QProcess::ExitStatus) {
                        secondary->deleteLater();
                        refresh();
                        emit deviceMounted(mountUri);
                    });
                    connect(secondary, &QProcess::errorOccurred,
                            this, [this, secondary, mountUri](QProcess::ProcessError) {
                        secondary->deleteLater();
                        refresh();
                        emit deviceMounted(mountUri);
                    });
                    secondary->start(QStringLiteral("gio"),
                                     {QStringLiteral("mount"), alternateUri});
                    return;
                }

                refresh();
                emit deviceMounted(mountUri);
            });
            connect(primary, &QProcess::errorOccurred, this,
                    [this, primary, label](QProcess::ProcessError) {
                const QString err = primary->errorString();
                primary->deleteLater();
                emit mountError(friendlyGioActionError(
                    QStringLiteral("mount"), label,
                    err.isEmpty() ? tr("gio mount failed") : err));
            });
            primary->start(QStringLiteral("gio"),
                           {QStringLiteral("mount"), mountUri});
            return;
        }

        auto *context = new GioOperationContext{QPointer<DeviceModel>(this), label};
        g_volume_mount(entry.gioVolume,
                       G_MOUNT_MOUNT_NONE,
                       nullptr,
                       nullptr,
                       onGioVolumeMounted,
                       context);
        return;
    }

    const QString devicePath = entry.devicePath;

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.UDisks2"),
        udisksObjectPathFor(devicePath),
        QStringLiteral("org.freedesktop.UDisks2.Filesystem"),
        QStringLiteral("Mount"));
    msg << QVariant::fromValue(QVariantMap{});

    QDBusPendingCall pending = QDBusConnection::systemBus().asyncCall(msg);
    auto *watcher = new QDBusPendingCallWatcher(pending, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, watcher, fsType, label]() {
        QDBusPendingReply<QString> reply = *watcher;
        if (reply.isError()) {
            const QString err = reply.error().message();
            qWarning() << "UDisks2 Mount failed:" << err;

            QString friendly;
            const bool helperMissing = err.contains(
                QStringLiteral("missing codepage or helper"), Qt::CaseInsensitive)
                || err.contains(QStringLiteral("wrong fs type"), Qt::CaseInsensitive);
            const bool dirtyNtfs = err.contains(
                QStringLiteral("unsafe mount"), Qt::CaseInsensitive)
                || err.contains(QStringLiteral("hibernated"), Qt::CaseInsensitive)
                || err.contains(QStringLiteral("fast-restart"), Qt::CaseInsensitive);
            const bool isNtfs = fsType == QLatin1String("ntfs")
                || fsType == QLatin1String("ntfs3");

            if (isPolkitAuthError(err)) {
                friendly = tr("Could not mount %1: %2").arg(label, polkitAgentHint());
            } else if (isNtfs && dirtyNtfs) {
                friendly = tr("Could not mount %1: the NTFS volume is in an unsafe "
                              "state (Windows Fast Startup or hibernation). Boot into "
                              "Windows and fully shut down, or disable Fast Startup.")
                               .arg(label);
            } else if (isNtfs && helperMissing) {
                friendly = tr("Could not mount %1: the NTFS mount helper is missing. "
                              "Install it on the host with 'sudo apt install ntfs-3g' "
                              "(Debian/Ubuntu) or 'sudo pacman -S ntfs-3g' (Arch).")
                               .arg(label);
            } else if (helperMissing) {
                friendly = tr("Could not mount %1: the filesystem type (%2) is not "
                              "supported by the kernel or the mount helper is missing.")
                               .arg(label, fsType.isEmpty() ? tr("unknown") : fsType);
            } else {
                friendly = tr("Could not mount %1: %2").arg(label, err);
            }
            emit mountError(friendly);
        } else {
            const QString mountPath = reply.value();
            refresh();
            emit deviceMounted(mountPath);
        }
        watcher->deleteLater();
    });
}
