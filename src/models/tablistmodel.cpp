#include "models/tablistmodel.h"
#include <QDir>
#include <QJsonObject>
#include <QFileInfo>
#include <QUrl>

namespace {

QString normalizedSessionPath(const QString &path)
{
    if (path.isEmpty())
        return QDir::homePath();

    const QUrl url(path);
    if (url.scheme() == QStringLiteral("trash"))
        return path;
    if (url.isValid() && !url.scheme().isEmpty() && url.scheme() != QStringLiteral("file"))
        return path;

    QFileInfo info(path);
    QString candidate = info.isDir() ? info.absoluteFilePath() : info.absolutePath();
    while (!candidate.isEmpty() && !QFileInfo::exists(candidate)) {
        const QString parent = QFileInfo(candidate).absolutePath();
        if (parent == candidate)
            break;
        candidate = parent;
    }

    return QFileInfo::exists(candidate) ? QDir(candidate).absolutePath() : QDir::homePath();
}

}

TabListModel::TabListModel(QObject *parent)
    : QAbstractListModel(parent)
{
    auto *tab = new TabModel(this);
    m_tabs.append(tab);
    connectTab(0, tab);
}

void TabListModel::connectTab(int row, TabModel *tab)
{
    connect(tab, &TabModel::currentPathChanged, this, [this, tab]() {
        int idx = m_tabs.indexOf(tab);
        if (idx >= 0) {
            QModelIndex mi = index(idx);
            emit dataChanged(mi, mi, {PathRole});
        }
        emit sessionChanged();
    });
    connect(tab, &TabModel::titleChanged, this, [this, tab]() {
        int idx = m_tabs.indexOf(tab);
        if (idx >= 0) {
            QModelIndex mi = index(idx);
            emit dataChanged(mi, mi, {TitleRole});
        }
    });
    connect(tab, &TabModel::secondaryCurrentPathChanged, this, &TabListModel::sessionChanged);
    connect(tab, &TabModel::viewModeChanged, this, &TabListModel::sessionChanged);
    connect(tab, &TabModel::splitViewEnabledChanged, this, &TabListModel::sessionChanged);
    connect(tab, &TabModel::sortChanged, this, &TabListModel::sessionChanged);
}

int TabListModel::rowCount(const QModelIndex &) const
{
    return m_tabs.size();
}

QVariant TabListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_tabs.size())
        return {};

    TabModel *tab = m_tabs.at(index.row());
    switch (role) {
    case TitleRole: return tab->title();
    case PathRole: return tab->currentPath();
    case TabObjectRole: return QVariant::fromValue(tab);
    case IsSelectedRole: return m_selectedIndices.contains(index.row());
    }
    return {};
}

QHash<int, QByteArray> TabListModel::roleNames() const
{
    return {
        {TitleRole, "title"},
        {PathRole, "path"},
        {TabObjectRole, "tabObject"},
        {IsSelectedRole, "isSelected"},
    };
}

int TabListModel::activeIndex() const { return m_activeIndex; }

void TabListModel::setActiveIndex(int index)
{
    if (index < 0 || index >= m_tabs.size())
        return;

    const bool activeChanged = (m_activeIndex != index);
    if (activeChanged) {
        m_activeIndex = index;
        emit activeIndexChanged();
        emit sessionChanged();
    }

    // Phase 2 P2-M1 unified model: the active tab is always part of the
    // selection set.  Inserting here keeps the invariant tight no matter
    // how setActiveIndex is reached (UI click, session restore, paneSwitch
    // shortcut, etc.) without each caller having to remember it.
    if (!m_selectedIndices.contains(index)) {
        m_selectedIndices.insert(index);
        emitIsSelectedChanged(index);
        emit selectionChanged();
    }
}

TabModel *TabListModel::activeTab() const
{
    if (m_activeIndex >= 0 && m_activeIndex < m_tabs.size())
        return m_tabs.at(m_activeIndex);
    return nullptr;
}

TabModel *TabListModel::tabAt(int index) const
{
    if (index >= 0 && index < m_tabs.size())
        return m_tabs.at(index);
    return nullptr;
}

void TabListModel::addTab()
{
    beginInsertRows(QModelIndex(), m_tabs.size(), m_tabs.size());
    auto *tab = new TabModel(this);
    m_tabs.append(tab);
    connectTab(m_tabs.size() - 1, tab);
    endInsertRows();
    // Phase 2 P2-M1 unified model: a new tab takes over the active slot AND
    // collapses any outstanding selection, so the user doesn't get a fresh
    // tab that's been silently added to a half-remembered merge set.
    activateAndCollapseSelection(m_tabs.size() - 1);
    emit countChanged();
    emit sessionChanged();
}

void TabListModel::closeTab(int index)
{
    if (index < 0 || index >= m_tabs.size())
        return;

    if (m_tabs.size() <= 1) {
        emit lastTabClosed();
        return;
    }

    TabModel *tab = m_tabs.at(index);
    m_closedTabs.append({
        tab->currentPath(),
        tab->viewMode(),
        tab->secondaryCurrentPath(),
        tab->sortBy(),
        tab->sortAscending(),
        tab->splitViewEnabled(),
    });

    beginRemoveRows(QModelIndex(), index, index);
    m_tabs.removeAt(index);
    tab->deleteLater();
    endRemoveRows();

    // Phase 2 P2-M1: shift selection set down for indices past the removed
    // row, and drop the removed row's own membership if it was selected.
    QSet<int> rebuilt;
    bool selectionMutated = m_selectedIndices.contains(index);
    for (int sel : std::as_const(m_selectedIndices)) {
        if (sel == index)
            continue;
        if (sel > index) {
            rebuilt.insert(sel - 1);
            selectionMutated = true;
        } else {
            rebuilt.insert(sel);
        }
    }
    m_selectedIndices = std::move(rebuilt);

    if (m_activeIndex >= m_tabs.size())
        setActiveIndex(m_tabs.size() - 1);
    else if (m_activeIndex == index && m_activeIndex > 0)
        setActiveIndex(m_activeIndex - 1);
    else
        emit activeIndexChanged();

    emit countChanged();
    emit sessionChanged();
    if (selectionMutated)
        emit selectionChanged();
}

// --- Phase 2 P2-M1: selection set ------------------------------------------

int TabListModel::selectedCount() const
{
    return m_selectedIndices.size();
}

bool TabListModel::isSelected(int index) const
{
    return m_selectedIndices.contains(index);
}

void TabListModel::toggleSelected(int index)
{
    if (index < 0 || index >= m_tabs.size())
        return;

    if (m_selectedIndices.contains(index)) {
        // Phase 2 P2-M1 unified model: the active tab must always remain in
        // the selection set.  Refuse to un-select the active tab when it's
        // the only thing selected (the user has to plain-click a different
        // tab first).  Otherwise migrate active to a peer first, then
        // remove this row.
        if (index == m_activeIndex && m_selectedIndices.size() == 1)
            return;

        m_selectedIndices.remove(index);

        if (index == m_activeIndex) {
            int newActive = *std::min_element(m_selectedIndices.begin(),
                                              m_selectedIndices.end());
            m_activeIndex = newActive;
            emit activeIndexChanged();
            emit sessionChanged();
        }
    } else {
        // Phase 2: cap the merge selection at kMaxPanes.  Past 4 the
        // user can't merge them all into one supertab anyway, so the
        // outline + the merge button would just be lying.  Surface the
        // refusal through a signal so the QML side can fade in a toast
        // rather than leave the user staring at an un-changed tab.
        if (m_selectedIndices.size() >= kMaxPanes) {
            emit selectionLimitReached(
                tr("Maximum %1 tabs can be merged").arg(kMaxPanes));
            return;
        }
        m_selectedIndices.insert(index);
    }

    emitIsSelectedChanged(index);
    emit selectionChanged();
}

void TabListModel::activateAndCollapseSelection(int index)
{
    if (index < 0 || index >= m_tabs.size())
        return;

    const QSet<int> previous = m_selectedIndices;
    m_selectedIndices = QSet<int>{index};

    const bool activeChanged = (m_activeIndex != index);
    if (activeChanged) {
        m_activeIndex = index;
        emit activeIndexChanged();
        emit sessionChanged();
    }

    bool selectionMutated = false;
    for (int row : previous) {
        if (!m_selectedIndices.contains(row)) {
            emitIsSelectedChanged(row);
            selectionMutated = true;
        }
    }
    if (!previous.contains(index)) {
        emitIsSelectedChanged(index);
        selectionMutated = true;
    }
    if (selectionMutated)
        emit selectionChanged();
}

void TabListModel::clearSelection()
{
    // Phase 2 P2-M1 unified model: active is always in the selection set, so
    // "clear" really means "collapse to {activeIndex}".  Nothing visible
    // disappears from the active tab.
    if (m_selectedIndices.size() <= 1
        && (m_selectedIndices.isEmpty() || m_selectedIndices.contains(m_activeIndex)))
        return;

    const QSet<int> previous = m_selectedIndices;
    m_selectedIndices.clear();
    if (m_activeIndex >= 0 && m_activeIndex < m_tabs.size())
        m_selectedIndices.insert(m_activeIndex);

    for (int row : previous) {
        if (!m_selectedIndices.contains(row))
            emitIsSelectedChanged(row);
    }
    emit selectionChanged();
}

QList<int> TabListModel::selectedIndices() const
{
    QList<int> result = m_selectedIndices.values();
    std::sort(result.begin(), result.end());
    return result;
}

void TabListModel::emitIsSelectedChanged(int row)
{
    if (row < 0 || row >= m_tabs.size())
        return;
    const QModelIndex idx = createIndex(row, 0);
    emit dataChanged(idx, idx, {IsSelectedRole});
}

void TabListModel::reopenClosedTab()
{
    if (m_closedTabs.isEmpty())
        return;

    auto info = m_closedTabs.takeLast();

    beginInsertRows(QModelIndex(), m_tabs.size(), m_tabs.size());
    auto *tab = new TabModel(this);
    tab->navigateTo(info.path);
    tab->setViewMode(info.viewMode);
    tab->setSecondaryCurrentPath(info.secondaryPath);
    tab->setSortBy(info.sortBy);
    tab->setSortAscending(info.sortAscending);
    tab->setSplitViewEnabled(info.splitViewEnabled);
    m_tabs.append(tab);
    connectTab(m_tabs.size() - 1, tab);
    endInsertRows();
    setActiveIndex(m_tabs.size() - 1);
    emit countChanged();
    emit sessionChanged();
}

QJsonArray TabListModel::saveSession() const
{
    QJsonArray arr;
    for (const auto *tab : m_tabs) {
        arr.append(QJsonObject{
            {"path", tab->currentPath()},
            {"viewMode", tab->viewMode()},
            {"splitViewEnabled", tab->splitViewEnabled()},
            {"secondaryPath", tab->secondaryCurrentPath()},
            {"sortBy", tab->sortBy()},
            {"sortAscending", tab->sortAscending()},
        });
    }
    return arr;
}

void TabListModel::restoreSession(const QJsonArray &tabs, int activeIdx)
{
    if (tabs.isEmpty())
        return;

    beginResetModel();
    qDeleteAll(m_tabs);
    m_tabs.clear();

    for (const auto &val : tabs) {
        QJsonObject obj = val.toObject();
        auto *tab = new TabModel(this);
        tab->navigateTo(normalizedSessionPath(obj.value("path").toString()));
        tab->setViewMode(obj.value("viewMode").toString("grid"));
        tab->setSplitViewEnabled(obj.value("splitViewEnabled").toBool(false));
        tab->setSecondaryCurrentPath(normalizedSessionPath(obj.value("secondaryPath").toString(tab->currentPath())));
        tab->setSortBy(obj.value("sortBy").toString("name"));
        tab->setSortAscending(obj.value("sortAscending").toBool(true));
        m_tabs.append(tab);
        connectTab(m_tabs.size() - 1, tab);
    }
    endResetModel();

    m_activeIndex = qBound(0, activeIdx, m_tabs.size() - 1);
    emit activeIndexChanged();
    emit countChanged();
    emit sessionChanged();
}
