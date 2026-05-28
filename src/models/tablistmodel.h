#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QSet>
#include <QJsonArray>
#include "models/tabmodel.h"

class TabListModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int activeIndex READ activeIndex WRITE setActiveIndex NOTIFY activeIndexChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(TabModel* activeTab READ activeTab NOTIFY activeIndexChanged)
    // Phase 2 P2-M1: multi-tab selection set.  Ctrl-click on a tab toggles its
    // membership in this set; the merge button (P2-M5) becomes available
    // once the count is >= 2.
    Q_PROPERTY(int selectedCount READ selectedCount NOTIFY selectionChanged)

public:
    enum Roles {
        TitleRole = Qt::UserRole + 1,
        PathRole,
        TabObjectRole,
        IsSelectedRole,
    };

    explicit TabListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int activeIndex() const;
    void setActiveIndex(int index);

    TabModel *activeTab() const;
    TabModel *tabAt(int index) const;

    Q_INVOKABLE void addTab();
    Q_INVOKABLE void closeTab(int index);
    Q_INVOKABLE void reopenClosedTab();

    // Phase 2 P2-M1: multi-tab selection for the merge gesture.
    int selectedCount() const;
    Q_INVOKABLE bool isSelected(int index) const;
    Q_INVOKABLE void toggleSelected(int index);
    Q_INVOKABLE void clearSelection();
    Q_INVOKABLE QList<int> selectedIndices() const;
    // Atomic "the user plain-clicked this tab": collapse the selection to
    // exactly {index} and make it the active tab in one shot, so the
    // active ∈ selected invariant doesn't pass through a stale state when
    // the UI talks to the model.
    Q_INVOKABLE void activateAndCollapseSelection(int index);

    // Phase 2 P2-M4: collapse the current selection (>= 2 tabs) into one
    // supertab.  The lowest-indexed selected tab is the receiver: it keeps
    // its row, and each other selected tab donates its currentPath to a
    // new pane via receiver.addPane(...).  Donor tabs are removed.  No-op
    // when the selection has fewer than 2 entries.
    Q_INVOKABLE void mergeSelected();

    QJsonArray saveSession() const;
    void restoreSession(const QJsonArray &tabs, int activeIdx);

signals:
    void activeIndexChanged();
    void countChanged();
    void lastTabClosed();
    void sessionChanged();
    void selectionChanged();
    // Phase 2: fired when toggleSelected refused to add a tab because the
    // selection set already holds kMaxPanes entries.  QML hangs a toast off
    // it instead of leaving the user wondering why the outline didn't
    // appear.
    void selectionLimitReached(const QString &message);

private:
    void connectTab(int row, TabModel *tab);
    // Phase 2 P2-M1: emit dataChanged on IsSelectedRole for the rows whose
    // selected state changed.  Used by both toggleSelected and clearSelection.
    void emitIsSelectedChanged(int row);

    QList<TabModel *> m_tabs;
    int m_activeIndex = 0;
    QSet<int> m_selectedIndices;

    struct ClosedTabInfo {
        QString path;
        QString viewMode;
        QString secondaryPath;
        QString sortBy;
        bool sortAscending = true;
        bool splitViewEnabled = false;
    };
    QList<ClosedTabInfo> m_closedTabs;
};
