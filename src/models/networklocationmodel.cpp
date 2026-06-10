#include "models/networklocationmodel.h"

#include <QHash>
#include <QMetaObject>
#include <QSet>
#include <QUrl>

#include <gio/gio.h>

namespace {

// GVFS schemes that represent NETWORK locations. Local (file), mobile devices
// (mtp/gphoto2/afc — shown under Devices), and virtual roots (trash/recent/
// computer/network/burn/cdda/archive) are intentionally excluded.
const QSet<QString> kNetworkSchemes = {
    QStringLiteral("sftp"), QStringLiteral("ssh"), QStringLiteral("smb"),
    QStringLiteral("cifs"), QStringLiteral("ftp"), QStringLiteral("ftps"),
    QStringLiteral("nfs"), QStringLiteral("dav"), QStringLiteral("davs"),
    QStringLiteral("afp"), QStringLiteral("webdav"),
};

QString netQStringFromGChar(gchar *s)
{
    if (!s)
        return QString();
    const QString out = QString::fromUtf8(s);
    g_free(s);
    return out;
}

// One callback for all monitor signals; the middle GMount*/GVolume* arg is
// ignored. Hops back onto the Qt thread (queued) to coalesce via the timer.
void onNetworkMonitorChanged(GVolumeMonitor *, gpointer, gpointer userData)
{
    auto *model = static_cast<NetworkLocationModel *>(userData);
    if (!model)
        return;
    QMetaObject::invokeMethod(model, &NetworkLocationModel::scheduleRefresh, Qt::QueuedConnection);
}

} // namespace

NetworkLocationModel::NetworkLocationModel(QObject *parent)
    : QAbstractListModel(parent)
{
    m_refreshTimer.setSingleShot(true);
    m_refreshTimer.setInterval(200);
    connect(&m_refreshTimer, &QTimer::timeout, this, &NetworkLocationModel::refresh);

    setupGioMonitor();
    refresh();
}

NetworkLocationModel::~NetworkLocationModel()
{
    if (m_volumeMonitor) {
        g_signal_handlers_disconnect_by_data(m_volumeMonitor, this);
        g_object_unref(m_volumeMonitor);
        m_volumeMonitor = nullptr;
    }
}

void NetworkLocationModel::setupGioMonitor()
{
    m_volumeMonitor = g_volume_monitor_get();
    if (!m_volumeMonitor)
        return;
    g_signal_connect(m_volumeMonitor, "mount-added",
                     G_CALLBACK(onNetworkMonitorChanged), this);
    g_signal_connect(m_volumeMonitor, "mount-removed",
                     G_CALLBACK(onNetworkMonitorChanged), this);
    g_signal_connect(m_volumeMonitor, "mount-changed",
                     G_CALLBACK(onNetworkMonitorChanged), this);
}

void NetworkLocationModel::scheduleRefresh()
{
    m_refreshTimer.start();
}

void NetworkLocationModel::refresh()
{
    QList<NetEntry> next;
    QSet<QString> seen;

    if (m_volumeMonitor) {
        GList *mounts = g_volume_monitor_get_mounts(m_volumeMonitor);
        for (GList *it = mounts; it; it = it->next) {
            GMount *mount = G_MOUNT(it->data);
            if (!mount || g_mount_is_shadowed(mount))
                continue;

            GFile *location = g_mount_get_default_location(mount);
            if (!location)
                location = g_mount_get_root(mount);
            const QString uri =
                netQStringFromGChar(location ? g_file_get_uri(location) : nullptr);
            if (location)
                g_object_unref(location);

            if (uri.isEmpty())
                continue;
            const QString scheme = QUrl(uri).scheme().toLower();
            if (!kNetworkSchemes.contains(scheme))
                continue;
            if (seen.contains(uri))
                continue;
            seen.insert(uri);

            QString name = netQStringFromGChar(g_mount_get_name(mount));
            if (name.isEmpty())
                name = uri;
            next.append({name, uri});
        }
        g_list_free_full(mounts, g_object_unref);
    }

    beginResetModel();
    m_entries = next;
    endResetModel();
    emit countChanged();
}

int NetworkLocationModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_entries.size();
}

QVariant NetworkLocationModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return QVariant();
    const NetEntry &e = m_entries.at(index.row());
    switch (role) {
    case NameRole:
        return e.name;
    case UriRole:
        return e.uri;
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> NetworkLocationModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {UriRole, "uri"},
    };
}
