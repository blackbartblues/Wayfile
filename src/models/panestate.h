#pragma once

#include <QString>
#include <QStringList>

// Per-pane navigation + view state.
//
// Phase 1 of the primary/secondary -> panes[N] cleanup.  This struct is the
// future single source of truth for everything that's currently mirrored
// twice on TabModel (m_currentPath / m_secondaryCurrentPath, etc.).  For now
// it lives alongside the mirrored fields as parallel storage; subsequent
// milestones flip readers, drop the mirror fields, and switch QML to access
// panes by index.
//
// Per Heimdall design canvas: path, viewMode, sortBy, sortAscending are all
// per-pane concepts.  Selection / focused row / scrollTop already live in the
// QML FileViewContainer (per-pane by virtue of instance separation), so they
// are not duplicated here.
struct PaneState {
    QString currentPath;
    QString viewMode = QStringLiteral("grid");
    QString sortBy = QStringLiteral("name");
    bool sortAscending = true;
    QStringList backStack;
    QStringList forwardStack;
};
