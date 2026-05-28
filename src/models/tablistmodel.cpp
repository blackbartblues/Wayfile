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

void TabListModel::mergeSelected()
{
    if (m_selectedIndices.size() < 2)
        return;

    // Phase 2: pre-flight check.  Sum the panes the merge would actually
    // need to host — selected supertabs contribute their full paneCount
    // because we dissolve them before merging so their content survives.
    int totalPanes = 0;
    for (int idx : std::as_const(m_selectedIndices)) {
        if (idx >= 0 && idx < m_tabs.size())
            totalPanes += m_tabs[idx]->paneCount();
    }
    if (totalPanes > kMaxPanes) {
        emit selectionLimitReached(
            tr("Merge would exceed %1 panes").arg(kMaxPanes));
        return;
    }

    // Phase 2: if any selected tab is already a supertab, dissolve it
    // first so its panes participate in the new merge instead of being
    // silently dropped by the receiver's compactToPrimary.  unmergeAt
    // re-selects the spawned tabs, so the next iteration picks them up.
    bool unmergedAny = true;
    while (unmergedAny) {
        unmergedAny = false;
        const QList<int> sortedSelection = selectedIndices();
        for (int i = sortedSelection.size() - 1; i >= 0; --i) {
            const int idx = sortedSelection[i];
            if (idx >= 0 && idx < m_tabs.size() && m_tabs[idx]->isSupertab()) {
                unmergeAt(idx);
                unmergedAny = true;
                break;  // selection set changed; re-query
            }
        }
    }

    if (m_selectedIndices.size() < 2)
        return;

    const QList<int> sorted = selectedIndices();  // ascending
    const int receiverIdx = sorted.first();
    TabModel *receiver = m_tabs[receiverIdx];

    // Snapshot the donor paths before we touch anything else; once we
    // start removing rows the indices in `sorted` go stale.
    QStringList donorPaths;
    for (int i = 1; i < sorted.size(); ++i)
        donorPaths.append(m_tabs[sorted[i]]->currentPath());

    // Phase 2 P2-M4: reset the receiver to a clean single-pane state
    // before appending donors.  Any stored secondary (live split or
    // hidden after split-off) gets discarded — merge takes 'visible
    // now' state only.
    receiver->compactToPrimary();

    // Push donors into the receiver as new panes.  addPane refuses past
    // kMaxPanes so this is bounded automatically.
    for (const QString &path : donorPaths) {
        if (receiver->addPane(path) < 0)
            break;
    }

    // Mark the receiver as a supertab so title() joins every pane's name.
    receiver->setSupertab(true);

    // Remove donor rows from the high end down so earlier indices remain
    // valid while we work.
    QList<int> donorIndices = sorted.mid(1);
    std::sort(donorIndices.begin(), donorIndices.end(), std::greater<int>());
    for (int idx : donorIndices) {
        beginRemoveRows(QModelIndex(), idx, idx);
        TabModel *donor = m_tabs.takeAt(idx);
        donor->deleteLater();
        endRemoveRows();
    }

    // Selection collapses to {receiver}; receiver's row index didn't shift
    // because it was the lowest of the sorted set.
    m_selectedIndices.clear();
    m_selectedIndices.insert(receiverIdx);

    if (m_activeIndex != receiverIdx) {
        m_activeIndex = receiverIdx;
        emit activeIndexChanged();
    }

    // Receiver's TitleRole now reflects the joined supertab title; nudge
    // the view layer.
    const QModelIndex midx = createIndex(receiverIdx, 0);
    emit dataChanged(midx, midx, {TitleRole, PathRole, IsSelectedRole});

    emit countChanged();
    emit selectionChanged();
    emit sessionChanged();
}

void TabListModel::unmergeAt(int idx)
{
    if (idx < 0 || idx >= m_tabs.size())
        return;
    TabModel *supertab = m_tabs[idx];
    if (!supertab->isSupertab())
        return;
    if (supertab->paneCount() < 2)
        return;

    // Snapshot every pane's currentPath before we mutate anything.
    QStringList panePaths;
    panePaths.reserve(supertab->paneCount());
    for (int i = 0; i < supertab->paneCount(); ++i)
        panePaths.append(supertab->paneCurrentPath(i));

    // Shrink the supertab to just its primary pane and drop the supertab
    // marker; the receiver now looks like an ordinary single-pane tab
    // showing panePaths[0].
    supertab->compactToPrimary();
    supertab->setSupertab(false);

    // Spawn one new tab for each remaining pane path, inserted right after
    // the receiver so the unmerged tabs stay in their original order.
    for (int i = 1; i < panePaths.size(); ++i) {
        const int insertIdx = idx + i;
        beginInsertRows(QModelIndex(), insertIdx, insertIdx);
        auto *spawn = new TabModel(this);
        spawn->navigateTo(panePaths[i]);
        m_tabs.insert(insertIdx, spawn);
        connectTab(insertIdx, spawn);
        endInsertRows();
    }

    // Selection follows the unmerge: every tab spawned from the supertab
    // (idx..idx+spawned) lands selected so the user can re-merge them
    // immediately if the unmerge was a mis-click.  Earlier selections
    // past the supertab are preserved, shifted upward by `spawned`.
    const int spawned = panePaths.size() - 1;
    QSet<int> rebuilt;
    for (int sel : std::as_const(m_selectedIndices)) {
        if (sel == idx)
            continue;
        if (sel > idx)
            rebuilt.insert(sel + spawned);
        else
            rebuilt.insert(sel);
    }
    for (int i = 0; i <= spawned; ++i)
        rebuilt.insert(idx + i);
    m_selectedIndices = std::move(rebuilt);

    if (m_activeIndex != idx) {
        m_activeIndex = idx;
        emit activeIndexChanged();
    }

    // Nudge views: receiver lost its supertab title (now just primary),
    // and every spawned row gained the selection flag.
    const QModelIndex midx = createIndex(idx, 0);
    emit dataChanged(midx, midx, {TitleRole, PathRole, IsSelectedRole});
    for (int i = 1; i <= spawned; ++i)
        emitIsSelectedChanged(idx + i);

    emit countChanged();
    emit selectionChanged();
    emit sessionChanged();
}

void TabListModel::moveTab(int from, int to)
{
    if (from < 0 || from >= m_tabs.size() || to < 0 || to >= m_tabs.size())
        return;
    if (from == to)
        return;

    // beginMoveRows wants the dest row in pre-removal coordinates: if we're
    // moving forward, the destination is one past the target slot.
    const int dest = (to > from) ? to + 1 : to;
    if (!beginMoveRows(QModelIndex(), from, from, QModelIndex(), dest))
        return;

    m_tabs.move(from, to);

    auto shiftIndex = [from, to](int sel) {
        if (sel == from)
            return to;
        if (from < to && sel > from && sel <= to)
            return sel - 1;
        if (from > to && sel >= to && sel < from)
            return sel + 1;
        return sel;
    };

    QSet<int> rebuilt;
    for (int sel : std::as_const(m_selectedIndices))
        rebuilt.insert(shiftIndex(sel));
    m_selectedIndices = std::move(rebuilt);

    const int newActive = shiftIndex(m_activeIndex);
    const bool activeMoved = (newActive != m_activeIndex);
    m_activeIndex = newActive;

    endMoveRows();
    if (activeMoved)
        emit activeIndexChanged();
    emit selectionChanged();
    emit sessionChanged();
}

void TabListModel::selectRangeTo(int idx)
{
    if (idx < 0 || idx >= m_tabs.size())
        return;
    const int anchor = m_activeIndex >= 0 ? m_activeIndex : 0;
    int lo = qMin(anchor, idx);
    int hi = qMax(anchor, idx);

    // Phase 2: cap-aware trim — keep the anchor end fixed so the user
    // sees the selection grow from where they were.
    if (hi - lo + 1 > kMaxPanes) {
        emit selectionLimitReached(
            tr("Maximum %1 tabs can be merged").arg(kMaxPanes));
        if (idx >= anchor)
            hi = anchor + kMaxPanes - 1;
        else
            lo = anchor - kMaxPanes + 1;
    }

    QSet<int> rebuilt;
    for (int i = lo; i <= hi; ++i)
        rebuilt.insert(i);

    const QSet<int> previous = m_selectedIndices;
    m_selectedIndices = rebuilt;

    // Invariant: active ∈ selected.  If the trim pushed the active out
    // of range, snap it to the clamped clicked end.
    if (!m_selectedIndices.contains(m_activeIndex)) {
        const int newActive = (idx >= anchor) ? hi : lo;
        m_activeIndex = newActive;
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
    for (int row : std::as_const(m_selectedIndices)) {
        if (!previous.contains(row)) {
            emitIsSelectedChanged(row);
            selectionMutated = true;
        }
    }
    if (selectionMutated)
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
    // Phase 2 P2-M4: only grow the secondary pane if the closed tab actually
    // had split view on.  A non-split tab stays at paneCount == 1 so a later
    // merge gesture doesn't pull along a stale secondary path.
    if (info.splitViewEnabled && !info.secondaryPath.isEmpty())
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
        const bool splitEnabled = obj.value("splitViewEnabled").toBool(false);
        tab->setSplitViewEnabled(splitEnabled);
        // Phase 2 P2-M4: skip secondary restore for non-split tabs so they
        // come back at paneCount == 1 (matches the lazy-grow constructor).
        if (splitEnabled) {
            const QString secondaryPath = normalizedSessionPath(
                obj.value("secondaryPath").toString(tab->currentPath()));
            tab->setSecondaryCurrentPath(secondaryPath);
        }
        tab->setSortBy(obj.value("sortBy").toString("name"));
        tab->setSortAscending(obj.value("sortAscending").toBool(true));
        m_tabs.append(tab);
        connectTab(m_tabs.size() - 1, tab);
    }
    endResetModel();

    // Phase 2 P2-M1: route through setActiveIndex so the active ∈ selected
    // invariant is established for the restored layout — otherwise the
    // outline doesn't appear on the active tab until the user clicks it.
    const int restoredActive = qBound(0, activeIdx, m_tabs.size() - 1);
    m_activeIndex = -1;  // force the setter to take the change-path
    setActiveIndex(restoredActive);
    emit countChanged();
    emit sessionChanged();
}
