#include "models/filesystemmodel.h"
#include "models/filesystemmodel_helpers.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QStringList>
#include <QTimer>
#include <QVariant>

using namespace FsmHelpers;

// Directories to scan for installed application .desktop files. Inside a
// Flatpak sandbox, QStandardPaths::ApplicationsLocation only sees the
// runtime + bundled apps, so we point at the host paths exposed via
// `--filesystem=host` (which mounts host /usr at /run/host/usr).
static QStringList applicationDataDirs()
{
    if (!runningInFlatpak())
        return QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);

    QStringList dirs;
    const QString home = QDir::homePath();
    dirs << home + QStringLiteral("/.local/share/applications")
         << home + QStringLiteral("/.local/share/flatpak/exports/share/applications")
         << QStringLiteral("/run/host/usr/local/share/applications")
         << QStringLiteral("/run/host/usr/share/applications")
         << QStringLiteral("/run/host/var/lib/flatpak/exports/share/applications");
    return dirs;
}


static QString desktopFileName(const QString &desktopId)
{
    // Search standard application dirs for a .desktop file
    for (const auto &dir : applicationDataDirs()) {
        QString path = dir + "/" + desktopId;
        if (QFile::exists(path))
            return path;
    }
    return {};
}

static QString readDesktopField(const QString &desktopPath, const QString &field)
{
    if (desktopPath.isEmpty())
        return {};
    QSettings desktop(desktopPath, QSettings::IniFormat);
    desktop.beginGroup("Desktop Entry");
    return desktop.value(field).toString();
}

// Parse `gio mime <type>` output into the app list. Shared by the sync and the
// async entry points so both produce byte-identical results — the only
// difference between them is how the process is run (blocking vs. non-blocking).
static QVariantList parseAvailableApps(const QString &output)
{
    QVariantList apps;

    // Registered apps appear after "Registered applications:".
    bool inRegistered = false;
    auto lines = output.split('\n');
    QSet<QString> seen;

    // Also grab the default
    QString defaultId;
    for (const auto &line : lines) {
        auto trimmed = line.trimmed();
        if (trimmed.startsWith("Default application")) {
            int colonIdx = trimmed.lastIndexOf(':');
            if (colonIdx >= 0)
                defaultId = trimmed.mid(colonIdx + 1).trimmed();
        }
        if (trimmed.startsWith("Registered applications:") || trimmed.startsWith("Recommended applications:")) {
            inRegistered = true;
            continue;
        }
        if (trimmed.isEmpty() || trimmed.startsWith("No ")) {
            inRegistered = false;
            continue;
        }
        if (inRegistered && trimmed.endsWith(".desktop") && !seen.contains(trimmed)) {
            seen.insert(trimmed);
            QString desktopId = trimmed;
            QString path = desktopFileName(desktopId);
            QString name = readDesktopField(path, "Name");
            if (name.isEmpty())
                name = desktopId.chopped(8);
            QString icon = readDesktopField(path, "Icon");

            QVariantMap app;
            app["desktopFile"] = desktopId;
            app["name"] = name;
            app["iconName"] = icon;
            app["isDefault"] = (desktopId == defaultId);
            apps.append(app);
        }
    }

    // Ensure the default app is in the list even if not registered/recommended
    if (!defaultId.isEmpty() && !seen.contains(defaultId)) {
        QString path = desktopFileName(defaultId);
        QString name = readDesktopField(path, "Name");
        if (name.isEmpty())
            name = defaultId.chopped(8);
        QString icon = readDesktopField(path, "Icon");

        QVariantMap app;
        app["desktopFile"] = defaultId;
        app["name"] = name;
        app["iconName"] = icon;
        app["isDefault"] = true;
        apps.prepend(app);
    }

    return apps;
}

QVariantList FileSystemModel::availableApps(const QString &mimeType) const
{
    if (mimeType.isEmpty())
        return {};

    // Inside a Flatpak this transparently runs `flatpak-spawn --host gio
    // mime <type>` so we see the host's MIME associations and host apps.
    const QString output = runHostTool(QStringLiteral("gio"),
                                       {QStringLiteral("mime"), mimeType});
    return parseAvailableApps(output);
}

void FileSystemModel::requestAvailableApps(const QString &mimeType)
{
    if (mimeType.isEmpty()) {
        emit availableAppsReady(mimeType, QVariantList());
        return;
    }

    // Supersede any in-flight probe for the same MIME type (dedup).
    if (QProcess *stale = m_appsProcs.take(mimeType)) {
        stale->disconnect(this);
        stale->kill();
        stale->deleteLater();
    }

    auto *proc = new QProcess(this);
    m_appsProcs.insert(mimeType, proc);

    connect(proc, &QProcess::finished, this,
            [this, proc, mimeType](int, QProcess::ExitStatus) {
                if (m_appsProcs.value(mimeType) != proc) {
                    proc->deleteLater();
                    return;
                }
                m_appsProcs.remove(mimeType);
                // Match the sync path, which reads stdout regardless of exit
                // code (runHostTool ignores it): `gio mime` prints its result
                // on stdout even when it returns non-zero.
                const QString output = QString::fromUtf8(proc->readAllStandardOutput());
                emit availableAppsReady(mimeType, parseAvailableApps(output));
                proc->deleteLater();
            });
    connect(proc, &QProcess::errorOccurred, this,
            [this, proc, mimeType](QProcess::ProcessError) {
                if (m_appsProcs.value(mimeType) != proc) {
                    proc->deleteLater();
                    return;
                }
                m_appsProcs.remove(mimeType);
                emit availableAppsReady(mimeType, QVariantList());
                proc->deleteLater();
            });

    // Watchdog mirrors runHostTool's default 3s cap: kill a hung probe so it
    // cannot leak. The kill triggers finished/errorOccurred, which emits.
    QTimer::singleShot(3000, proc, [this, proc, mimeType]() {
        if (m_appsProcs.value(mimeType) == proc && proc->state() != QProcess::NotRunning)
            proc->kill();
    });

    startHostToolProcess(proc, QStringLiteral("gio"),
                         {QStringLiteral("mime"), mimeType});
}

void FileSystemModel::cancelAppsProbes()
{
    const QList<QProcess *> procs = m_appsProcs.values();
    m_appsProcs.clear();
    for (QProcess *proc : procs) {
        proc->disconnect(this);
        proc->kill();
        proc->waitForFinished(100);
        delete proc;
    }
}

QString FileSystemModel::defaultApp(const QString &mimeType) const
{
    return runHostTool(QStringLiteral("xdg-mime"),
                       {QStringLiteral("query"), QStringLiteral("default"), mimeType},
                       2000).trimmed();
}

void FileSystemModel::setDefaultApp(const QString &mimeType, const QString &desktopFile)
{
    runHostTool(QStringLiteral("xdg-mime"),
                {QStringLiteral("default"), desktopFile, mimeType}, 2000);
}

QVariantList FileSystemModel::allInstalledApps() const
{
    QVariantList apps;
    QSet<QString> seen;

    const auto dataDirs = applicationDataDirs();
    for (const auto &dir : dataDirs) {
        QDirIterator it(dir, {"*.desktop"}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            it.next();
            // Use relative path as desktop ID (e.g. "org.kde.dolphin.desktop")
            QString desktopId = QDir(dir).relativeFilePath(it.filePath());
            if (seen.contains(desktopId))
                continue;
            seen.insert(desktopId);

            QString name = readDesktopField(it.filePath(), "Name");
            if (name.isEmpty())
                continue;
            QString icon = readDesktopField(it.filePath(), "Icon");
            QString noDisplay = readDesktopField(it.filePath(), "NoDisplay");
            if (noDisplay.compare("true", Qt::CaseInsensitive) == 0)
                continue;

            QVariantMap app;
            app["desktopFile"] = desktopId;
            app["name"] = name;
            app["iconName"] = icon;
            apps.append(app);
        }
    }

    // Sort by name
    std::sort(apps.begin(), apps.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap()["name"].toString().compare(b.toMap()["name"].toString(), Qt::CaseInsensitive) < 0;
    });

    return apps;
}
