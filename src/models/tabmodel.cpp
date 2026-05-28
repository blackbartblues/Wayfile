#include "models/tabmodel.h"
#include <QFileInfo>
#include <QUrl>

namespace {

bool isRemoteUri(const QString &path)
{
    const QUrl url(path);
    return url.isValid() && !url.scheme().isEmpty()
        && url.scheme() != QStringLiteral("file")
        && url.scheme() != QStringLiteral("trash");
}

QString displayNameForPath(const QString &path)
{
    const QUrl url(path);
    if (url.scheme() == QStringLiteral("trash")) {
        const QString fileName = url.fileName();
        return fileName.isEmpty() ? QStringLiteral("Trash") : fileName;
    }

    if (isRemoteUri(path)) {
        const QString fileName = QUrl::fromPercentEncoding(url.fileName().toUtf8());
        if (!fileName.isEmpty())
            return fileName;
        if (!url.host().isEmpty())
            return url.host();
        return url.scheme().toUpper();
    }

    if (path == QStringLiteral("/"))
        return QStringLiteral("/");

    const QDir dir(path);
    return dir.dirName();
}

QString parentLocation(const QString &path)
{
    const QUrl url(path);
    if (url.scheme() == QStringLiteral("trash")) {
        QString current = path;
        if (current.size() > 9 && current.endsWith('/'))
            current.chop(1);
        if (current == QStringLiteral("trash:///") || current == QStringLiteral("trash://"))
            return QStringLiteral("trash:///");
        const int slashIndex = current.lastIndexOf('/');
        return slashIndex <= 8 ? QStringLiteral("trash:///") : current.left(slashIndex);
    }

    if (isRemoteUri(path)) {
        QUrl parentUrl(url);
        QString urlPath = parentUrl.path();
        if (urlPath.isEmpty() || urlPath == QStringLiteral("/"))
            return path;
        if (urlPath.endsWith('/'))
            urlPath.chop(1);
        const int slashIndex = urlPath.lastIndexOf('/');
        parentUrl.setPath(slashIndex <= 0 ? QStringLiteral("/") : urlPath.left(slashIndex));
        return parentUrl.toString(QUrl::FullyEncoded);
    }

    QDir dir(path);
    if (dir.cdUp())
        return dir.absolutePath();
    return path;
}

}

TabModel::TabModel(QObject *parent)
    : QObject(parent)
{
    // Phase 1 M4: pane storage is the only state today.  Default-construct
    // two entries (one per pane) and seed currentPath to the user's home;
    // viewMode / sortBy / sortAscending pick up their PaneState defaults.
    PaneState primary;
    primary.currentPath = QDir::homePath();
    m_panes.append(primary);

    PaneState secondary;
    secondary.currentPath = QDir::homePath();
    m_panes.append(secondary);
}

// Phase 1 M3: public readers pull from m_panes.  Mirror fields still exist
// (and are still written via syncPaneFromMirror in mutators) but external
// behaviour is now driven by the pane storage.  If any M2 write-through
// site was missed, this is where it shows up as stale state.
QString TabModel::currentPath() const { return m_panes[0].currentPath; }

QString TabModel::title() const
{
    const QString primaryTitle = displayNameForPath(m_panes[0].currentPath);
    if (!m_splitViewEnabled)
        return primaryTitle;

    return primaryTitle + QStringLiteral(" / ") + displayNameForPath(m_panes[1].currentPath);
}

QString TabModel::viewMode() const { return m_panes[0].viewMode; }
bool TabModel::canGoBack() const { return !m_panes[0].backStack.isEmpty(); }
bool TabModel::canGoForward() const { return !m_panes[0].forwardStack.isEmpty(); }
bool TabModel::splitViewEnabled() const { return m_splitViewEnabled; }
QString TabModel::secondaryCurrentPath() const { return m_panes[1].currentPath; }
bool TabModel::secondaryCanGoBack() const { return !m_panes[1].backStack.isEmpty(); }
bool TabModel::secondaryCanGoForward() const { return !m_panes[1].forwardStack.isEmpty(); }
QString TabModel::sortBy() const { return m_panes[0].sortBy; }
bool TabModel::sortAscending() const { return m_panes[0].sortAscending; }

void TabModel::setViewMode(const QString &mode)
{
    if (m_panes[0].viewMode == mode)
        return;
    m_panes[0].viewMode = mode;
    m_panes[1].viewMode = mode;
    emit viewModeChanged();
}

void TabModel::setSplitViewEnabled(bool enabled)
{
    if (m_splitViewEnabled == enabled)
        return;

    if (enabled && !m_secondaryInitialized) {
        m_panes[1].currentPath = m_panes[0].currentPath;
        m_secondaryInitialized = true;
        emit secondaryCurrentPathChanged();
    }

    m_splitViewEnabled = enabled;
    emit splitViewEnabledChanged();
    emit titleChanged();
}

void TabModel::setSecondaryCurrentPath(const QString &path)
{
    if (path.isEmpty() || m_panes[1].currentPath == path)
        return;

    m_panes[1].currentPath = path;
    m_secondaryInitialized = true;
    emit secondaryCurrentPathChanged();
    emit titleChanged();
}

void TabModel::setSortBy(const QString &column)
{
    if (m_panes[0].sortBy == column)
        return;
    m_panes[0].sortBy = column;
    m_panes[1].sortBy = column;
    emit sortChanged();
}

void TabModel::setSortAscending(bool ascending)
{
    if (m_panes[0].sortAscending == ascending)
        return;
    m_panes[0].sortAscending = ascending;
    m_panes[1].sortAscending = ascending;
    emit sortChanged();
}

void TabModel::navigateTo(const QString &path)
{
    PaneState &p = m_panes[0];
    if (path == p.currentPath)
        return;
    p.backStack.append(p.currentPath);
    p.forwardStack.clear();
    p.currentPath = path;
    emit currentPathChanged();
    emit titleChanged();
    emit historyChanged();
}

void TabModel::navigateSecondaryTo(const QString &path)
{
    PaneState &p = m_panes[1];
    if (path == p.currentPath || path.isEmpty())
        return;

    p.backStack.append(p.currentPath);
    p.forwardStack.clear();
    p.currentPath = path;
    m_secondaryInitialized = true;
    emit secondaryCurrentPathChanged();
    emit titleChanged();
    emit secondaryHistoryChanged();
}

void TabModel::goBack()
{
    PaneState &p = m_panes[0];
    if (p.backStack.isEmpty())
        return;
    p.forwardStack.append(p.currentPath);
    p.currentPath = p.backStack.takeLast();
    emit currentPathChanged();
    emit titleChanged();
    emit historyChanged();
}

void TabModel::secondaryGoBack()
{
    PaneState &p = m_panes[1];
    if (p.backStack.isEmpty())
        return;

    p.forwardStack.append(p.currentPath);
    p.currentPath = p.backStack.takeLast();
    emit secondaryCurrentPathChanged();
    emit titleChanged();
    emit secondaryHistoryChanged();
}

void TabModel::goForward()
{
    PaneState &p = m_panes[0];
    if (p.forwardStack.isEmpty())
        return;
    p.backStack.append(p.currentPath);
    p.currentPath = p.forwardStack.takeLast();
    emit currentPathChanged();
    emit titleChanged();
    emit historyChanged();
}

void TabModel::secondaryGoForward()
{
    PaneState &p = m_panes[1];
    if (p.forwardStack.isEmpty())
        return;

    p.backStack.append(p.currentPath);
    p.currentPath = p.forwardStack.takeLast();
    emit secondaryCurrentPathChanged();
    emit titleChanged();
    emit secondaryHistoryChanged();
}

void TabModel::goUp()
{
    const QString parent = parentLocation(m_panes[0].currentPath);
    if (parent != m_panes[0].currentPath)
        navigateTo(parent);
}

void TabModel::secondaryGoUp()
{
    const QString parent = parentLocation(m_panes[1].currentPath);
    if (parent != m_panes[1].currentPath)
        navigateSecondaryTo(parent);
}

void TabModel::resetSecondaryTo(const QString &path)
{
    if (path.isEmpty())
        return;

    PaneState &p = m_panes[1];
    const bool pathChanged = p.currentPath != path;
    const bool historyChanged = !p.backStack.isEmpty() || !p.forwardStack.isEmpty();

    p.backStack.clear();
    p.forwardStack.clear();
    p.currentPath = path;
    m_secondaryInitialized = true;

    if (pathChanged) {
        emit secondaryCurrentPathChanged();
        emit titleChanged();
    }
    if (historyChanged)
        emit secondaryHistoryChanged();
}
