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
    // A fresh tab is single-pane. Extra panes are grown only by addPane()
    // (merge / restore / the merge-button add-a-pane gesture), so a brand-new
    // tab never drags along a stale secondary pane into a later merge.
    PaneState primary;
    primary.currentPath = QDir::homePath();
    m_panes.append(primary);
}

// Public readers pull from m_panes[0], the primary pane.
QString TabModel::currentPath() const { return m_panes[0].currentPath; }

QString TabModel::title() const
{
    if (m_panes.isEmpty())
        return {};
    const QString name0 = displayNameForPath(m_panes[0].currentPath);

    // Merged supertab — every pane is live, join names with ' · ' per the
    // Wayfile design canvas. With the legacy split-view system gone, a
    // multi-pane tab is always a supertab (paneCount > 1 ⟺ isSupertab), so
    // this is the only multi-name case.
    if (m_isSupertab) {
        QStringList names;
        names.reserve(m_panes.size());
        for (const PaneState &p : m_panes)
            names.append(displayNameForPath(p.currentPath));
        return names.join(QStringLiteral(" · "));
    }

    // Single-pane tab: just the primary name.
    return name0;
}

QString TabModel::viewMode() const { return m_panes[0].viewMode; }
bool TabModel::canGoBack() const { return !m_panes[0].backStack.isEmpty(); }
bool TabModel::canGoForward() const { return !m_panes[0].forwardStack.isEmpty(); }
QString TabModel::sortBy() const { return m_panes[0].sortBy; }
bool TabModel::sortAscending() const { return m_panes[0].sortAscending; }

void TabModel::setViewMode(const QString &mode)
{
    if (m_panes[0].viewMode == mode)
        return;
    m_panes[0].viewMode = mode;
    // Mirror to every other pane if any exist; lazy-grown layouts may have
    // size 1 (single-pane tab) or any size up to kMaxPanes.
    for (int i = 1; i < m_panes.size(); ++i)
        m_panes[i].viewMode = mode;
    emit viewModeChanged();
}

void TabModel::setSortBy(const QString &column)
{
    if (m_panes[0].sortBy == column)
        return;
    m_panes[0].sortBy = column;
    for (int i = 1; i < m_panes.size(); ++i)
        m_panes[i].sortBy = column;
    emit sortChanged();
}

void TabModel::setSortAscending(bool ascending)
{
    if (m_panes[0].sortAscending == ascending)
        return;
    m_panes[0].sortAscending = ascending;
    for (int i = 1; i < m_panes.size(); ++i)
        m_panes[i].sortAscending = ascending;
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

void TabModel::goUp()
{
    const QString parent = parentLocation(m_panes[0].currentPath);
    if (parent != m_panes[0].currentPath)
        navigateTo(parent);
}


// --- Phase 2 P2-M2: pane list growth -----------------------------------------

int TabModel::paneCount() const
{
    return m_panes.size();
}

int TabModel::addPane(const QString &path)
{
    // Phase 2: respect the same kMaxPanes ceiling the selection enforces, so
    // a runaway caller can't drift a tab into a paneCount the merge UI
    // refuses to create.
    if (m_panes.size() >= kMaxPanes)
        return -1;
    PaneState p;
    p.currentPath = path.isEmpty() ? QDir::homePath() : path;
    // Inherit the per-tab view + sort settings from pane 0 so a newly added
    // pane visually matches its siblings instead of dropping back to the
    // PaneState struct defaults.
    if (!m_panes.isEmpty()) {
        const PaneState &seed = m_panes.first();
        p.viewMode = seed.viewMode;
        p.sortBy = seed.sortBy;
        p.sortAscending = seed.sortAscending;
    }
    m_panes.append(p);
    emit panesChanged();
    emit titleChanged();
    return m_panes.size() - 1;
}

bool TabModel::removePane(int idx)
{
    // Phase 2 P2-M9: allow shrinking down to 1 pane.  When it does drop to
    // single-pane the tab demotes out of supertab mode so title() goes back
    // to just the primary name and Main.qml's Repeater collapses to one frame.
    if (idx < 0 || idx >= m_panes.size())
        return false;
    if (m_panes.size() <= 1)
        return false;
    m_panes.removeAt(idx);
    emit panesChanged();
    emit titleChanged();

    if (m_panes.size() == 1 && m_isSupertab) {
        m_isSupertab = false;
        emit supertabChanged();
        emit titleChanged();
    }
    return true;
}

void TabModel::navigateInPane(int idx, const QString &path)
{
    if (idx < 0 || idx >= m_panes.size() || path.isEmpty())
        return;
    // Pane 0 keeps the dedicated mutator so the primary Q_PROPERTYs
    // (currentPath / canGoBack / canGoForward, consumed by the tab bar,
    // toolbar and sidebar) keep emitting their fine-grained signals. Every
    // other pane is generic: push history on m_panes[idx] and let
    // panePathChanged(idx) drive the matching paneServices slot in QML.
    if (idx == 0) {
        navigateTo(path);
        emit panePathChanged(0);
        return;
    }
    PaneState &p = m_panes[idx];
    if (p.currentPath == path)
        return;
    p.backStack.append(p.currentPath);
    p.forwardStack.clear();
    p.currentPath = path;
    emit panePathChanged(idx);
    emit titleChanged();
}

// --- Phase 2 #9: generic per-pane history navigation -------------------------

void TabModel::paneGoBack(int idx)
{
    if (idx == 0) {
        goBack();
        return;
    }
    if (idx < 0 || idx >= m_panes.size())
        return;
    PaneState &p = m_panes[idx];
    if (p.backStack.isEmpty())
        return;
    p.forwardStack.append(p.currentPath);
    p.currentPath = p.backStack.takeLast();
    emit panePathChanged(idx);
    emit titleChanged();
}

void TabModel::paneGoForward(int idx)
{
    if (idx == 0) {
        goForward();
        return;
    }
    if (idx < 0 || idx >= m_panes.size())
        return;
    PaneState &p = m_panes[idx];
    if (p.forwardStack.isEmpty())
        return;
    p.backStack.append(p.currentPath);
    p.currentPath = p.forwardStack.takeLast();
    emit panePathChanged(idx);
    emit titleChanged();
}

void TabModel::paneGoUp(int idx)
{
    if (idx == 0) {
        goUp();
        return;
    }
    if (idx < 0 || idx >= m_panes.size())
        return;
    const QString parent = parentLocation(m_panes[idx].currentPath);
    if (parent != m_panes[idx].currentPath)
        navigateInPane(idx, parent);
}

bool TabModel::paneCanGoBack(int idx) const
{
    return idx >= 0 && idx < m_panes.size() && !m_panes[idx].backStack.isEmpty();
}

bool TabModel::paneCanGoForward(int idx) const
{
    return idx >= 0 && idx < m_panes.size() && !m_panes[idx].forwardStack.isEmpty();
}

void TabModel::setSupertab(bool on)
{
    if (m_isSupertab == on)
        return;
    m_isSupertab = on;
    emit supertabChanged();
    emit titleChanged();
}

void TabModel::compactToPrimary()
{
    bool changed = false;
    while (m_panes.size() > 1) {
        m_panes.removeLast();
        changed = true;
    }
    // The supertab marker is managed by the caller (mergeSelected sets it,
    // unmergeAt clears it), so compactToPrimary only collapses the pane list.
    if (changed) {
        emit panesChanged();
        emit titleChanged();
    }
}

QString TabModel::paneCurrentPath(int idx) const
{
    if (idx < 0 || idx >= m_panes.size())
        return {};
    return m_panes.at(idx).currentPath;
}

QString TabModel::paneViewMode(int idx) const
{
    if (idx < 0 || idx >= m_panes.size())
        return {};
    return m_panes.at(idx).viewMode;
}

QStringList TabModel::paneTitles() const
{
    QStringList names;
    names.reserve(m_panes.size());
    for (const PaneState &p : m_panes)
        names.append(displayNameForPath(p.currentPath));
    return names;
}

