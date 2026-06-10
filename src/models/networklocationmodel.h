#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QTimer>

typedef struct _GVolumeMonitor GVolumeMonitor;

// Enumerates live GVFS network mounts (sftp/smb/ftp/nfs/dav/afp/…) as a flat
// list of {name, uri} rows for the sidebar's Network section. A GVolumeMonitor
// drives live refresh on mount add/remove/change. Local disks and mobile-device
// mounts (mtp/gphoto2/afc — those belong under Devices) are filtered out. When
// nothing network-y is mounted the model is empty and the sidebar hides the
// whole Network section (W8). A remote opened via RemoteConnect mounts through
// GVFS, so it shows up here automatically once connected.
class NetworkLocationModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        UriRole,
    };

    explicit NetworkLocationModel(QObject *parent = nullptr);
    ~NetworkLocationModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

public slots:
    void refresh();
    void scheduleRefresh();

signals:
    void countChanged();

private:
    void setupGioMonitor();

    struct NetEntry {
        QString name;
        QString uri;
    };

    QList<NetEntry> m_entries;
    GVolumeMonitor *m_volumeMonitor = nullptr;
    QTimer m_refreshTimer;
};
