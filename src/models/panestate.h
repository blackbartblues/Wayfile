#pragma once

#include <QString>
#include <QStringList>

// Phase 2: hard cap on how many panes a single tab can hold (and therefore on
// the selection-set size for the merge gesture).  Lives here so TabListModel
// (selection limit), TabModel (addPane refusal), and main.cpp (paneServices
// pre-allocation) all share one source of truth.  4 covers the realistic
// UX ceiling — 3 panes is already tight in a 1024 px window — without
// dragging in dynamic-growth complexity.
inline constexpr int kMaxPanes = 4;

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
