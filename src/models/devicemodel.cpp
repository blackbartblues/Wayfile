#include "models/devicemodel.h"

#include <QByteArray>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDebug>
#include <QHash>
#include <QMetaObject>
#include <QStringList>
#include <QVariant>

#undef signals
#include <gio/gio.h>
#define signals Q_SIGNALS

// Core DeviceModel: lifecycle, the UDisks2/GIO change monitors, the refresh
// dispatch, and the QAbstractListModel interface. The heavy refresh worker
// (applyManagedObjects) lives in devicemodel_enumerate.cpp and the mount/unmount
// operations in devicemodel_mount.cpp — both are methods of this same class.

static const QStringList kVirtualTypes = {
    "tmpfs", "devtmpfs", "proc", "sysfs",
    "cgroup", "cgroup2", "overlay", "squashfs",
    "devpts", "hugetlbfs", "mqueue", "pstore",
    "securityfs", "fusectl", "debugfs", "tracefs",
    "bpf", "autofs", "ramfs", "efivarfs",
};

DeviceModel::DeviceModel(QObject *parent, bool deferInitialRefresh, bool synchronousRefresh)
    : QAbstractListModel(parent)
    , m_synchronousRefresh(synchronousRefresh)
{
    m_refreshTimer.setSingleShot(true);
    m_refreshTimer.setInterval(600);
    connect(&m_refreshTimer, &QTimer::timeout, this, &DeviceModel::refresh);

    setupGioMonitor();
    setupUDisks2();
    if (deferInitialRefresh)
        scheduleRefresh();
    else
        refresh();
}

DeviceModel::~DeviceModel()
{
    clearDevices();
    if (m_volumeMonitor) {
        g_signal_handlers_disconnect_by_data(m_volumeMonitor, this);
        g_object_unref(m_volumeMonitor);
        m_volumeMonitor = nullptr;
    }
}

void DeviceModel::clearDevices()
{
    for (const DeviceEntry &device : std::as_const(m_devices)) {
        if (device.gioVolume)
            g_object_unref(device.gioVolume);
        if (device.gioMount)
            g_object_unref(device.gioMount);
    }
    m_devices.clear();
}

bool DeviceModel::isVirtual(const QString &fsType)
{
    return kVirtualTypes.contains(fsType.toLower());
}

void DeviceModel::setupUDisks2()
{
    QDBusConnection sys = QDBusConnection::systemBus();
    if (!sys.isConnected()) {
        qWarning() << "DeviceModel: cannot connect to system D-Bus; auto-refresh disabled";
        return;
    }

    sys.connect(
        "org.freedesktop.UDisks2",
        "/org/freedesktop/UDisks2",
        "org.freedesktop.DBus.ObjectManager",
        "InterfacesAdded",
        this, SLOT(scheduleRefresh())
    );

    sys.connect(
        "org.freedesktop.UDisks2",
        "/org/freedesktop/UDisks2",
        "org.freedesktop.DBus.ObjectManager",
        "InterfacesRemoved",
        this, SLOT(scheduleRefresh())
    );
}

namespace {

void onGioMonitorChanged(GVolumeMonitor *, gpointer, gpointer userData)
{
    auto *model = static_cast<DeviceModel *>(userData);
    if (!model)
        return;
    QMetaObject::invokeMethod(model, &DeviceModel::scheduleRefresh, Qt::QueuedConnection);
}

} // namespace

void DeviceModel::setupGioMonitor()
{
    m_volumeMonitor = g_volume_monitor_get();
    if (!m_volumeMonitor)
        return;

    g_signal_connect(m_volumeMonitor, "drive-connected",
                     G_CALLBACK(onGioMonitorChanged), this);
    g_signal_connect(m_volumeMonitor, "drive-disconnected",
                     G_CALLBACK(onGioMonitorChanged), this);
    g_signal_connect(m_volumeMonitor, "drive-changed",
                     G_CALLBACK(onGioMonitorChanged), this);
    g_signal_connect(m_volumeMonitor, "volume-added",
                     G_CALLBACK(onGioMonitorChanged), this);
    g_signal_connect(m_volumeMonitor, "volume-removed",
                     G_CALLBACK(onGioMonitorChanged), this);
    g_signal_connect(m_volumeMonitor, "volume-changed",
                     G_CALLBACK(onGioMonitorChanged), this);
    g_signal_connect(m_volumeMonitor, "mount-added",
                     G_CALLBACK(onGioMonitorChanged), this);
    g_signal_connect(m_volumeMonitor, "mount-removed",
                     G_CALLBACK(onGioMonitorChanged), this);
    g_signal_connect(m_volumeMonitor, "mount-changed",
                     G_CALLBACK(onGioMonitorChanged), this);
}

void DeviceModel::scheduleRefresh()
{
    m_refreshTimer.start();
}

void DeviceModel::refresh()
{
    m_refreshTimer.stop();

    // Ask UDisks2 for everything it knows about. Returns a{oa{sa{sv}}}:
    //   { object_path → { interface_name → { property_name → value } } }
    const QDBusMessage call = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.UDisks2"),
        QStringLiteral("/org/freedesktop/UDisks2"),
        QStringLiteral("org.freedesktop.DBus.ObjectManager"),
        QStringLiteral("GetManagedObjects"));

    // Test hook: block inline so tests observe a populated model without
    // spinning an event loop. Production takes the async path below so a slow
    // or unreachable UDisks2 cannot freeze the GUI thread (up to 3s) on every
    // device hotplug, mount, or unmount — the model keeps showing the previous
    // device list until the reply arrives.
    if (m_synchronousRefresh) {
        applyManagedObjects(QDBusConnection::systemBus().call(call, QDBus::Block, 3000));
        return;
    }

    const quint64 generation = ++m_refreshGeneration;
    QDBusPendingCall pending = QDBusConnection::systemBus().asyncCall(call, 3000);
    auto *watcher = new QDBusPendingCallWatcher(pending, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, generation](QDBusPendingCallWatcher *self) {
        self->deleteLater();
        // Discard a stale reply if a newer refresh() already superseded it.
        if (generation != m_refreshGeneration)
            return;
        applyManagedObjects(self->reply());
    });
}

int DeviceModel::rowCount(const QModelIndex &) const
{
    return m_devices.size();
}

QVariant DeviceModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_devices.size())
        return {};

    const auto &d = m_devices.at(index.row());
    switch (role) {
    case DeviceNameRole:   return d.deviceName;
    case DevicePathRole:   return d.devicePath;
    case MountPointRole:   return d.mountPoint;
    case TotalSizeRole:    return d.totalSize;
    case FreeSpaceRole:    return d.freeSpace;
    case UsagePercentRole: return d.usagePercent;
    case RemovableRole:    return d.removable;
    case MountedRole:      return d.mounted;
    case BackendRole:      return d.backend == DeviceBackend::Gio
                                ? QStringLiteral("gio")
                                : QStringLiteral("udisks2");
    }
    return {};
}

QHash<int, QByteArray> DeviceModel::roleNames() const
{
    return {
        {DeviceNameRole,   "deviceName"},
        {DevicePathRole,   "devicePath"},
        {MountPointRole,   "mountPoint"},
        {TotalSizeRole,    "totalSize"},
        {FreeSpaceRole,    "freeSpace"},
        {UsagePercentRole, "usagePercent"},
        {RemovableRole,    "removable"},
        {MountedRole,      "mounted"},
        {BackendRole,      "backend"},
    };
}
