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
    Q_PROPERTY(bool splitViewEnabled READ splitViewEnabled WRITE setSplitViewEnabled NOTIFY splitViewEnabledChanged)
    Q_PROPERTY(QString secondaryCurrentPath READ secondaryCurrentPath WRITE setSecondaryCurrentPath NOTIFY secondaryCurrentPathChanged)
    Q_PROPERTY(bool secondaryCanGoBack READ secondaryCanGoBack NOTIFY secondaryHistoryChanged)
    Q_PROPERTY(bool secondaryCanGoForward READ secondaryCanGoForward NOTIFY secondaryHistoryChanged)
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
    bool splitViewEnabled() const;
    QString secondaryCurrentPath() const;
    bool secondaryCanGoBack() const;
    bool secondaryCanGoForward() const;
    QString sortBy() const;
    bool sortAscending() const;

    void setViewMode(const QString &mode);
    void setSplitViewEnabled(bool enabled);
    void setSecondaryCurrentPath(const QString &path);
    void setSortBy(const QString &column);
    void setSortAscending(bool ascending);

    Q_INVOKABLE void navigateTo(const QString &path);
    Q_INVOKABLE void navigateSecondaryTo(const QString &path);
    Q_INVOKABLE void goBack();
    Q_INVOKABLE void goForward();
    Q_INVOKABLE void goUp();
    Q_INVOKABLE void secondaryGoBack();
    Q_INVOKABLE void secondaryGoForward();
    Q_INVOKABLE void secondaryGoUp();
    Q_INVOKABLE void resetSecondaryTo(const QString &path);

    // Phase 2 P2-M6: navigate the pane at idx to a new path.  Dispatches to
    // navigateTo (idx == 0) / navigateSecondaryTo (idx == 1) when those
    // legacy mutators apply; for supertab panes idx >= 2 it pushes
    // m_panes[idx].currentPath + history stacks directly and emits
    // panePathChanged(idx) so Main.qml can re-setRootPath the matching
    // paneServices slot.
    Q_INVOKABLE void navigateInPane(int idx, const QString &path);

    // Phase 2 P2-M2: grow / shrink the pane list past the original N=2.
    int paneCount() const;
    Q_INVOKABLE int addPane(const QString &path);
    Q_INVOKABLE bool removePane(int idx);
    // Per-pane getters for the future N-pane Repeater (P2-M6).  primaryX /
    // secondaryX Q_PROPERTYs stay alive while paneRow is still hand-wired.
    Q_INVOKABLE QString paneCurrentPath(int idx) const;
    Q_INVOKABLE QString paneViewMode(int idx) const;

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
    void splitViewEnabledChanged();
    void secondaryCurrentPathChanged();
    void secondaryHistoryChanged();
    void sortChanged();
    // Phase 2 P2-M2: emitted whenever m_panes grows or shrinks.  Per-pane
    // currentPath / viewMode mutations still emit the existing fine-grained
    // signals (currentPathChanged, viewModeChanged, etc.) — only the
    // structural list shape change uses this.
    void panesChanged();
    // Phase 2 P2-M4: fires when the supertab marker is set / cleared by
    // mergeSelected / unmergeAt / compactToPrimary.
    void supertabChanged();
    // Phase 2 P2-M6: emitted whenever a pane's currentPath changes (for
    // the legacy slots 0 / 1 this fires alongside currentPathChanged /
    // secondaryCurrentPathChanged; for slot >= 2 it's the only signal
    // QML gets).  Carries the pane index so the handler can re-seed the
    // matching paneServices slot's fsModel.
    void panePathChanged(int idx);

private:
    // Phase 2 P2-M4: secondary pane is grown lazily the first time anything
    // reaches for it.  Keeps a fresh tab at paneCount == 1 so merge actions
    // don't pull along a stale home-dir constructor leftover.
    void ensureSecondaryPane();

    // Phase 1 M4: m_panes is the single source of truth for every per-pane
    // field (currentPath, viewMode, sortBy, sortAscending, backStack,
    // forwardStack).  Index 0 == primary, index 1 == secondary today; later
    // milestones generalise to arbitrary N panes per tab.
    QList<PaneState> m_panes;

    // Tab-level state that isn't per-pane.  splitViewEnabled toggles whether
    // the secondary pane is rendered; secondaryInitialized tracks whether
    // the secondary pane has ever been navigated (used to seed it from the
    // primary path the first time split view is enabled).  isSupertab is
    // set when this tab is the receiver of a merge gesture.
    bool m_splitViewEnabled = false;
    bool m_secondaryInitialized = false;
    bool m_isSupertab = false;
};
