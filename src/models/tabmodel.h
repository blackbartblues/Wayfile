#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QDir>
#include <QList>

#include "models/panestate.h"

class TabModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString currentPath READ currentPath NOTIFY currentPathChanged)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(QString viewMode READ viewMode WRITE setViewMode NOTIFY viewModeChanged)
    Q_PROPERTY(bool canGoBack READ canGoBack NOTIFY historyChanged)
    Q_PROPERTY(bool canGoForward READ canGoForward NOTIFY historyChanged)
    Q_PROPERTY(QString sortBy READ sortBy WRITE setSortBy NOTIFY sortChanged)
    Q_PROPERTY(bool sortAscending READ sortAscending WRITE setSortAscending NOTIFY sortChanged)
    // Phase 2 P2-M2: pane list size, exposed so the future N-pane paneRow
    // (P2-M6) can use Repeater { model: tabModel.activeTab.paneCount }.
    Q_PROPERTY(int paneCount READ paneCount NOTIFY panesChanged)
    // Phase 2 P2-M4: lets QML bind merge / unmerge button state to the
    // current tab's supertab flag without round-tripping through a
    // Q_INVOKABLE call (toggleMergeOrUnmerge needs it on every press).
    Q_PROPERTY(bool isSupertab READ isSupertab NOTIFY supertabChanged)

public:
    explicit TabModel(QObject *parent = nullptr);

    QString currentPath() const;
    QString title() const;
    QString viewMode() const;
    bool canGoBack() const;
    bool canGoForward() const;
    QString sortBy() const;
    bool sortAscending() const;

    void setViewMode(const QString &mode);
    void setSortBy(const QString &column);
    void setSortAscending(bool ascending);

    Q_INVOKABLE void navigateTo(const QString &path);
    Q_INVOKABLE void goBack();
    Q_INVOKABLE void goForward();
    Q_INVOKABLE void goUp();

    // Navigate the pane at idx to a new path.  idx == 0 delegates to
    // navigateTo so the primary currentPath Q_PROPERTY signals fire; every
    // other pane pushes m_panes[idx].currentPath + history stacks directly and
    // emits panePathChanged(idx) so Main.qml can re-setRootPath the matching
    // paneServices slot.
    Q_INVOKABLE void navigateInPane(int idx, const QString &path);

    // #9 (split -> N-pane unification): generic per-pane history navigation.
    // These are the single entry points Main.qml routes the active pane's
    // back / forward / up through, indexed by activePaneIndex.  idx == 0
    // delegates to goBack/goForward/goUp so the primary currentPath /
    // canGoBack / canGoForward Q_PROPERTYs keep emitting; every other pane
    // operates on m_panes[idx] directly and emits panePathChanged(idx).  The
    // CanGo readers are uniform across every index (each pane carries its own
    // back/forward
    // stack in PaneState), so they work for 0 / 1 too.
    Q_INVOKABLE void paneGoBack(int idx);
    Q_INVOKABLE void paneGoForward(int idx);
    Q_INVOKABLE void paneGoUp(int idx);
    Q_INVOKABLE bool paneCanGoBack(int idx) const;
    Q_INVOKABLE bool paneCanGoForward(int idx) const;

    // Phase 2 P2-M2: grow / shrink the pane list past the original N=2.
    int paneCount() const;
    Q_INVOKABLE int addPane(const QString &path);
    Q_INVOKABLE bool removePane(int idx);
    // Per-pane getters for the future N-pane Repeater (P2-M6).  primaryX /
    // secondaryX Q_PROPERTYs stay alive while paneRow is still hand-wired.
    Q_INVOKABLE QString paneCurrentPath(int idx) const;
    Q_INVOKABLE QString paneViewMode(int idx) const;
    // Set one pane's view mode without touching its siblings. idx 0 also emits
    // viewModeChanged() so tab-level consumers (session save, miller sync for
    // the primary pane) keep firing.
    Q_INVOKABLE void setPaneViewMode(int idx, const QString &mode);
    // Phase 2 P2-M7: batched basename list for every live pane.  Mirrors
    // the join used by title() so the TabBar delegate can render the same
    // names as N discrete chips without re-parsing the joined string.
    Q_INVOKABLE QStringList paneTitles() const;

    // Phase 2 P2-M4: supertab marker.  Set by TabListModel::mergeSelected
    // on the receiver tab; cleared when the supertab dissolves back to a
    // single pane (P2-M9 close-pane-in-supertab).  Lets title() distinguish
    // '2-pane merged supertab' (show 'A · B') from '2-pane that used to be
    // split but isn't right now' (show just primary).
    bool isSupertab() const { return m_isSupertab; }
    Q_INVOKABLE void setSupertab(bool on);
    // Drop every pane past index 0 and turn split view off, so a merge
    // action starts with a clean primary pane regardless of the tab's
    // prior split state.
    void compactToPrimary();

signals:
    void currentPathChanged();
    void titleChanged();
    void viewModeChanged();
    void historyChanged();
    void sortChanged();
    // Phase 2 P2-M2: emitted whenever m_panes grows or shrinks.  Per-pane
    // currentPath / viewMode mutations still emit the existing fine-grained
    // signals (currentPathChanged, viewModeChanged, etc.) — only the
    // structural list shape change uses this.
    void panesChanged();
    // Phase 2 P2-M4: fires when the supertab marker is set / cleared by
    // mergeSelected / unmergeAt / compactToPrimary.
    void supertabChanged();
    // Emitted whenever a pane's currentPath changes. For pane 0 this fires
    // alongside currentPathChanged; for every other pane it's the only path
    // signal QML gets. Carries the pane index so the handler can re-seed the
    // matching paneServices slot's fsModel.
    void panePathChanged(int idx);
    // Emitted when a single pane's view mode changes via setPaneViewMode.
    // Carries the pane index so Main.qml refreshes that pane's binding.
    void paneViewModeChanged(int idx);

private:
    // m_panes is the single source of truth for every per-pane field
    // (currentPath, viewMode, sortBy, sortAscending, backStack, forwardStack).
    // Index 0 is the primary pane; merged supertabs grow indices 1..N-1.
    QList<PaneState> m_panes;

    // Tab-level state that isn't per-pane: set when this tab is the receiver
    // of a merge gesture (paneCount > 1 ⟺ isSupertab now that split-view is
    // gone).
    bool m_isSupertab = false;
};
