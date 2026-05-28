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

signals:
    void currentPathChanged();
    void titleChanged();
    void viewModeChanged();
    void historyChanged();
    void splitViewEnabledChanged();
    void secondaryCurrentPathChanged();
    void secondaryHistoryChanged();
    void sortChanged();

private:
    // Phase 1 M4: m_panes is the single source of truth for every per-pane
    // field (currentPath, viewMode, sortBy, sortAscending, backStack,
    // forwardStack).  Index 0 == primary, index 1 == secondary today; later
    // milestones generalise to arbitrary N panes per tab.
    QList<PaneState> m_panes;

    // Tab-level state that isn't per-pane.  splitViewEnabled toggles whether
    // the secondary pane is rendered; secondaryInitialized tracks whether
    // the secondary pane has ever been navigated (used to seed it from the
    // primary path the first time split view is enabled).
    bool m_splitViewEnabled = false;
    bool m_secondaryInitialized = false;
};
