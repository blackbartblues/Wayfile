import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Window
import Wayfile
import "components" as Components
import Quill as Q

ApplicationWindow {
    id: root
    width: 1024
    height: 768
    minimumWidth: 760
    minimumHeight: 520
    visibility: Window.Windowed
    title: "Wayfile"
    color: "transparent"
    // Wayfile fork: always frameless on Linux. Compositor (Hyprland) handles
    // close/minimize/maximize via keybinds; in-app controls are intentionally
    // dropped (see Toolbar.qml — showWindowControls is hardcoded false below).
    flags: Qt.platform.os === "linux"
        ? (Qt.Window | Qt.FramelessWindowHint) : Qt.Window

    readonly property bool useIntegratedWindowControls: false

    // Per-pane view-state flags, indexed by pane (0..paneServicesProvider.count-1).
    // These replace the old primary*/secondary* boolean pairs whose getters
    // treated every index other than 1 as "primary" — so panes 2 and 3 of a
    // merged supertab aliased pane 0's recents/search/filter state, and
    // navigating one of them flipped the others (#9 follow-up bug).  The arrays
    // are reassigned wholesale on every change (never mutated in place) so the
    // QML bindings that read them re-evaluate; sparse holes read as undefined,
    // which paneIsRecents()/paneSearchMode()/paneFilterPanelOpen() treat as false.
    property var paneRecents: []
    // Per-pane "Hidden" view flag (#8 pkt5) — mirrors paneRecents. When set,
    // paneModel(pane) returns the dedicated hiddenEntries model (Home's
    // top-level dotfiles/dotfolders) instead of the pane's real folder.
    property var paneHidden: []
    property var paneSearchModes: []
    property var paneFilterPanels: []
    readonly property bool isRecentsView: root.paneIsRecents(activePaneIndex)
    readonly property bool isHiddenView: root.paneIsHidden(activePaneIndex)
    property var deleteConfirmPaths: []
    property var transferConflictItems: []
    property var transferResolvedItems: []
    property int transferConflictIndex: -1
    property bool transferMoveOperation: false
    property bool transferClearClipboardOnSuccess: false
    property string transferDestinationPath: ""
    property var transferReservedTargets: ({})
    property bool paneFocusScheduled: false
    readonly property string unifiedTrashPath: "trash:///"
    // Bind to the activePanePath reactive mirror, not panePath(activePaneIndex)
    // directly: panePath() reads the untracked Q_INVOKABLE paneCurrentPath(),
    // so a raw binding never re-fires on in-pane navigation and these flags
    // freeze (toolbar keeps showing trash/remote chrome after navigating away).
    readonly property bool isTrashView: fileOps.isTrashPath(activePanePath)
    readonly property bool isRemoteView: fileOps.isRemotePath(activePanePath)

    // ── Click-anywhere-clears: any plain LMB press anywhere in the window
    // collapses a >1 tab selection down to just the active tab.  Sits on
    // top of all content with mouse.accepted=false so it observes the
    // press then lets it propagate normally to the actual click target.
    // Shift/Ctrl are skipped so multi-select gestures (Ctrl-click,
    // Shift-click range) still work on the tab strip.
    MouseArea {
        id: clickClearsTabSelection
        anchors.fill: parent
        z: 9999
        acceptedButtons: Qt.LeftButton
        hoverEnabled: false
        propagateComposedEvents: true
        // A press on the (armed) merge button must NOT collapse the selection:
        // this observer fires before the button's onClicked, so collapsing here
        // would disarm the merge the user is in the middle of triggering.
        function pressOnMergeButton(x, y) {
            const btn = toolbar.mergeButton
            if (!btn || !btn.visible || !btn.enabled)
                return false
            const p = btn.mapFromItem(clickClearsTabSelection, x, y)
            return p.x >= 0 && p.y >= 0 && p.x < btn.width && p.y < btn.height
        }
        onPressed: (mouse) => {
            if (mouse.modifiers === Qt.NoModifier
                && tabModel.selectedCount > 1
                && !pressOnMergeButton(mouse.x, mouse.y)) {
                tabModel.activateAndCollapseSelection(tabModel.activeIndex)
            }
            mouse.accepted = false
        }
    }

    // ── Sync fsModel when active tab changes; quit on last tab closed ───────
    Connections {
        target: tabModel
        function onActiveIndexChanged() {
            if (tabModel.activeTab) {
                root.activePaneIndex = 0
                // Reset per-pane recents/search/filter state for every pane
                // slot, not just 0/1 — a supertab we're leaving may have had
                // recents or an active search on panes 2/3.
                root.paneRecents = []
                root.paneHidden = []
                for (var p = 0; p < paneServicesProvider.count; ++p)
                    root.clearPaneSearch(p)
                fsModel.setRootPath(tabModel.activeTab.currentPath)
                root.syncMillerParentModel(tabModel.activeTab.currentPath)
                // Supertab tabs carry up to kMaxPanes panes; seed every fsModel
                // slot so each PaneFrame in the Repeater shows the right content
                // on the first paint.
                for (var i = 0; i < tabModel.activeTab.paneCount; ++i) {
                    var mdl = paneServicesProvider.fsModelAt(i)
                    if (mdl)
                        mdl.setRootPath(tabModel.activeTab.paneCurrentPath(i))
                }
                root.applyActiveTabSort()
                root.scheduleActivePaneFocus()
                root.refreshActivePanePath()
            }
        }
        function onLastTabClosed() {
            Qt.quit()
        }
        // Phase 2: tabs.selectionLimitReached fires when Ctrl-click tries
        // to push the merge selection past the cap; fade in a brief toast
        // so the user understands why the outline didn't appear.
        function onSelectionLimitReached(message) {
            toast.show(message, "info")
        }
    }

    Connections {
        target: tabModel.activeTab ?? null
        ignoreUnknownSignals: true
        function onCurrentPathChanged() {
            if (tabModel.activeTab) {
                fsModel.setRootPath(tabModel.activeTab.currentPath)
                root.syncMillerParentModel(tabModel.activeTab.currentPath)
                root.setPaneRecents(0, false)
                root.setPaneHidden(0, false)
                root.clearPaneSearch(0)
                root.scheduleActivePaneFocus()
                root.refreshActivePanePath()
            }
        }
        // Navigation inside any non-primary pane (idx >= 1) pushes only
        // panePathChanged(idx) — wire each pane's fsModel slot to follow.
        function onPanePathChanged(idx) {
            if (!tabModel.activeTab)
                return
            var model = paneServicesProvider.fsModelAt(idx)
            if (model)
                model.setRootPath(tabModel.activeTab.paneCurrentPath(idx))
            root.setPaneRecents(idx, false)
            root.setPaneHidden(idx, false)
            root.clearPaneSearch(idx)
            root.scheduleActivePaneFocus()
            root.refreshActivePanePath()
        }
        // Phase 2 P2-M6: merge / unmerge / compactToPrimary keeps the
        // active tab the same but restructures its m_panes list; sync the
        // fsModel slots for every pane the new layout exposes.
        function onPanesChanged() {
            if (!tabModel.activeTab)
                return
            for (var i = 0; i < tabModel.activeTab.paneCount; ++i) {
                var mdl = paneServicesProvider.fsModelAt(i)
                if (mdl)
                    mdl.setRootPath(tabModel.activeTab.paneCurrentPath(i))
            }
            root.refreshActivePanePath()
        }
        function onSortChanged() {
            root.applyActiveTabSort()
        }
        function onViewModeChanged() {
            if (tabModel.activeTab)
                root.syncMillerParentModel(tabModel.activeTab.currentPath)
            root.scheduleActivePaneFocus()
        }
    }

    Connections {
        target: config

        function onConfigChanged() {
            root.sidebarVisible = config.sidebarVisible
            root.sidebarWidth = config.sidebarWidth
            root.sidebarCompact = config.sidebarCompact
        }
    }

    // Connect each pane slot's search-finished + directory-watch signals once.
    // The PaneServices backends are allocated for the app's lifetime in
    // main.cpp, so a single imperative connect (rather than static slot-0/1
    // Connections) reaches panes 2/3 too and never needs tearing down.
    function wirePaneServiceSignals() {
        for (var i = 0; i < paneServicesProvider.count; ++i) {
            (function(idx) {
                var svc = paneServicesProvider.searchServiceAt(idx)
                if (svc)
                    svc.searchFinished.connect(function() { root.selectFirstSearchResult(idx) })
                var mdl = paneServicesProvider.fsModelAt(idx)
                if (mdl)
                    mdl.watchedDirectoryChanged.connect(function(path) { diskUsageService.invalidatePath(path) })
            })(i)
        }
    }

    // Force initial load after QML is fully set up
    Component.onCompleted: {
        root.wirePaneServiceSignals()
        // W7: load the persisted Full/Compact sidebar mode on startup.
        root.sidebarCompact = config.sidebarCompact
        if (tabModel.activeTab) {
            fsModel.setRootPath(tabModel.activeTab.currentPath)
            // Seed every pane of a (possibly session-restored) supertab, not
            // just slot 0 — other panes otherwise start with no root path.
            for (var i = 0; i < tabModel.activeTab.paneCount; ++i) {
                var mdl = paneServicesProvider.fsModelAt(i)
                if (mdl)
                    mdl.setRootPath(tabModel.activeTab.paneCurrentPath(i))
            }
            root.syncMillerParentModel(tabModel.activeTab.currentPath)
            root.applyActiveTabSort()
        }
        root.refreshActivePanePath()

        // Bridge Wayfile theme into Quill theme singleton
        Q.Theme.background = Qt.binding(() => Theme.base)
        Q.Theme.backgroundAlt = Qt.binding(() => Theme.mantle)
        Q.Theme.backgroundDeep = Qt.binding(() => Theme.crust)
        Q.Theme.surface0 = Qt.binding(() => Theme.surface)
        // surface1/surface2 back Quill components that need an opaque fill
        // (Tooltip, Popup, etc.), so pre-composite the 10%/15% text tint onto
        // the base background instead of emitting a translucent color.
        Q.Theme.surface1 = Qt.binding(() => Qt.rgba(
            Theme.base.r * 0.9 + Theme.text.r * 0.1,
            Theme.base.g * 0.9 + Theme.text.g * 0.1,
            Theme.base.b * 0.9 + Theme.text.b * 0.1,
            1.0))
        Q.Theme.surface2 = Qt.binding(() => Qt.rgba(
            Theme.base.r * 0.85 + Theme.text.r * 0.15,
            Theme.base.g * 0.85 + Theme.text.g * 0.15,
            Theme.base.b * 0.85 + Theme.text.b * 0.15,
            1.0))
        Q.Theme.textPrimary = Qt.binding(() => Theme.text)
        Q.Theme.textSecondary = Qt.binding(() => Theme.subtext)
        Q.Theme.textTertiary = Qt.binding(() => Theme.muted)
        Q.Theme.primary = Qt.binding(() => Theme.accent)
        Q.Theme.success = Qt.binding(() => Theme.success)
        Q.Theme.warning = Qt.binding(() => Theme.warning)
        Q.Theme.error = Qt.binding(() => Theme.error)
        Q.Theme.radiusSm = Qt.binding(() => Theme.radiusSmall)
        Q.Theme.radius = Qt.binding(() => Theme.radiusMedium)
        Q.Theme.radiusLg = Qt.binding(() => Theme.radiusLarge)
        Q.Theme.fontFamily = Qt.binding(() => Qt.application.font.family)
        Q.Theme.fontSizeSmall = Qt.binding(() => Theme.fontSmall)
        Q.Theme.fontSize = Qt.binding(() => Theme.fontNormal)
        Q.Theme.fontSizeLarge = Qt.binding(() => Theme.fontLarge)
        Q.Theme.animDurationFast = Qt.binding(() => Theme.animDurationFast)
        Q.Theme.animDuration = Qt.binding(() => Theme.animDuration)
        Q.Theme.animDurationSlow = Qt.binding(() => Theme.animDurationSlow)
        Q.Theme.transparencyEnabled = Qt.binding(() => Theme.transparencyEnabled)
        Q.Theme.transparencyLevel = Qt.binding(() => Theme.transparencyLevel)
        // Wayfile obsidian+gold accent layer -> the gold-skinned Quill controls.
        Q.Theme.gold = Qt.binding(() => Theme.gold)
        Q.Theme.goldMid = Qt.binding(() => Theme.goldMid)
        Q.Theme.goldLight = Qt.binding(() => Theme.goldLight)
        Q.Theme.knob = Qt.binding(() => Theme.knob)
        // overlay0/overlay1 are rendered (settings-nav inactive icons) but were
        // never bridged -> stuck Catppuccin grey under any theme. Route them and
        // the remaining stale Quill semantic tokens onto Wayfile equivalents.
        Q.Theme.overlay0 = Qt.binding(() => Theme.muted)
        Q.Theme.overlay1 = Qt.binding(() => Theme.subtext)
        Q.Theme.secondary = Qt.binding(() => Theme.subtext)
        Q.Theme.accent = Qt.binding(() => Theme.accent)
        Q.Theme.info = Qt.binding(() => Theme.accent)

        root.scheduleActivePaneFocus()
        // Wayfile: dependency check is opt-in via Settings -> "Check Optional
        // Dependencies", not a startup popup. The dialog is still present, but
        // we don't auto-open it.
    }

    onActiveChanged: {
        if (active)
            root.scheduleActivePaneFocus()
    }

    // ── Sidebar visibility (local property; config.sidebarVisible is read-only) ─
    property bool sidebarVisible: config.sidebarVisible

    // W7: Full ↔ Compact (56px icon rail) mode. Local mirror of the read-only
    // config.sidebarCompact; the toolbar toggle flips this + persists it. Seeded
    // from config in Component.onCompleted and kept in sync via onConfigChanged.
    property bool sidebarCompact: config.sidebarCompact

    property int sidebarWidth: config.sidebarWidth
    readonly property int minSidebarWidth: 160
    readonly property int maxSidebarWidth: 480
    property bool sidebarResizeActive: false
    property real sidebarResizeStartGlobalX: 0
    property int sidebarResizeStartWidth: 0

    // ── Search state ──────────────────────────────────────────────────────────
    property var debounceTimer: null
    // Phase 1 M7: panes are addressed by integer index throughout the
    // dispatch path now.  0 == the primary pane, 1 == the secondary; Phase 2
    // generalises to arbitrary N when merged supertabs land.
    property int debouncePane: 0
    property int activePaneIndex: 0
    // Reactive mirror of panePath(activePaneIndex). panePath() reads
    // paneCurrentPath(), a Q_INVOKABLE method QML's binding engine cannot
    // track, so a plain `panePath(activePaneIndex)` binding never re-fires on
    // navigation. Consumers that must follow the active pane's path (sidebar
    // highlight, status bar) bind to this property instead; it is refreshed
    // from the path-change signals in the Connections blocks above and on
    // activePaneIndex changes.
    property string activePanePath: ""
    // Bumped on every pane navigation. The per-pane currentPath binding in the
    // PaneFrame Repeater delegate references this so it re-evaluates
    // panePath(index) — which reads an untracked Q_INVOKABLE and would
    // otherwise stay stale, sending drops/operations to the previously-viewed
    // folder.
    property int paneNavTick: 0
    function refreshActivePanePath() {
        paneNavTick++
        activePanePath = panePath(activePaneIndex)
    }
    onActivePaneIndexChanged: refreshActivePanePath()
    readonly property bool searchMode: paneSearchMode(activePaneIndex)

    // ── Selection state for StatusBar ────────────────────────────────────────
    property int currentSelectedCount: 0
    property string currentSelectedSize: ""
    property bool currentSelectedSizePending: false
    property int currentSelectedSizeRequestId: -1

    // Phase 2 P2-M6: indexed lookups so the N-pane Repeater can address
    // pane 2 and 3 the same way the hand-wired primary / secondary panes
    // used 0 and 1.  paneServicesProvider is the C++ context property
    // exposing the kMaxPanes-sized list main.cpp built at startup.
    function paneBaseModel(pane) {
        return paneServicesProvider.fsModelAt(pane) || fsModel
    }

    // #9 follow-up: per-pane fan-out helpers.  A merged supertab renders up to
    // paneServicesProvider.count panes, each backed by its own fsModelAt(i).
    // Operations that historically touched only fsModel (slot 0) + splitFsModel
    // (slot 1) must reach every live pane, or panes 2/3 go stale (wrong sort,
    // no refresh after a file op, etc.).
    function forEachLivePaneModel(fn) {
        var n = tabModel.activeTab ? tabModel.activeTab.paneCount : 1
        for (var i = 0; i < n; ++i) {
            var mdl = paneServicesProvider.fsModelAt(i)
            if (mdl)
                fn(mdl, i)
        }
    }

    function refreshAllPanes() {
        forEachLivePaneModel(function(mdl) { mdl.refresh() })
    }

    // Sort is tab-level: TabModel mirrors sortBy/sortAscending across every
    // pane, so a UI sort request (context menu or column header) updates the
    // tab metadata and re-sorts all live panes through applyActiveTabSort().
    function applySortFromUi(column, ascending) {
        if (!tabModel.activeTab)
            return
        // Setting sortBy/sortAscending fires sortChanged, whose handler runs
        // applyActiveTabSort() across all panes. Only sort explicitly when the
        // metadata is unchanged (no signal would fire) so we don't sort twice.
        var changed = tabModel.activeTab.sortBy !== column
            || tabModel.activeTab.sortAscending !== ascending
        tabModel.activeTab.sortBy = column
        tabModel.activeTab.sortAscending = ascending
        if (!changed)
            root.applyActiveTabSort()
    }

    function clampedSidebarWidth(width) {
        return Math.max(minSidebarWidth, Math.min(maxSidebarWidth, Math.round(width)))
    }

    // Flip Full ↔ Compact and persist. Used by the sidebar's collapse button
    // and the drag-to-collapse/expand splitter (R3/R4).
    function setSidebarCompact(compact) {
        if (sidebarCompact === compact)
            return
        sidebarCompact = compact
        config.saveSidebarCompact(compact)
    }

    function panePath(pane) {
        if (!tabModel.activeTab)
            return fsModel.homePath()
        var path = tabModel.activeTab.paneCurrentPath(pane)
        return path !== "" ? path : tabModel.activeTab.currentPath
    }

    // SplitPaneHeader moved to components/SplitPaneHeader.qml so PaneFrame
    // (which also lives in the Wayfile module) can reach it via plain
    // `import Wayfile` rather than depending on this inline-component scope.

    function parentDirForPath(path) {
        var slashIndex = path.lastIndexOf("/")
        return slashIndex > 0 ? path.substring(0, slashIndex) : "/"
    }

    function syncMillerParentModel(path) {
        if (!tabModel.activeTab || tabModel.activeTab.viewMode !== "miller") {
            millerParentModel.setRootPath("")
            return
        }

        var parent = path ? fileOps.parentPath(path) : ""
        millerParentModel.setRootPath(parent && parent !== path ? parent : "")
    }

    function isLocalPath(path) {
        return !!path && !fileOps.isRemotePath(path) && path.indexOf("://") < 0
    }

    function openRemoteConnectDialog() {
        mainOverlays.remoteConnectDialog.resetForm()
        mainOverlays.remoteConnectDialog.open()
    }

    function openSettingsPanel() {
        if (mainOverlays.settingsPanel.visible)
            mainOverlays.settingsPanel.closePanel()
        else
            mainOverlays.settingsPanel.openPanel()
    }

    function openKeyboardShortcutsDialog() {
        mainOverlays.shortcutsDialog.openDialog()
    }

    function paneIsRecents(pane) {
        return paneRecents[pane] === true
    }

    function setPaneRecents(pane, enabled) {
        if (pane < 0)
            return
        var next = paneRecents.slice()
        next[pane] = enabled
        paneRecents = next
        // Recents and Hidden are mutually exclusive special views — entering
        // one leaves the other (guarded by `enabled` to avoid recursion).
        if (enabled)
            setPaneHidden(pane, false)
    }

    function paneIsHidden(pane) {
        return paneHidden[pane] === true
    }

    function setPaneHidden(pane, enabled) {
        if (pane < 0)
            return
        var next = paneHidden.slice()
        next[pane] = enabled
        paneHidden = next
        if (enabled)
            setPaneRecents(pane, false)
    }

    function searchProxyForPane(pane) {
        return paneServicesProvider.searchProxyAt(pane) || searchProxy
    }

    function searchResultsForPane(pane) {
        return paneServicesProvider.searchResultsAt(pane) || searchResults
    }

    function searchServiceForPane(pane) {
        return paneServicesProvider.searchServiceAt(pane) || searchService
    }

    function paneSearchMode(pane) {
        return paneSearchModes[pane] === true
    }

    function setPaneSearchMode(pane, enabled) {
        if (pane < 0)
            return
        var next = paneSearchModes.slice()
        next[pane] = enabled
        paneSearchModes = next
    }

    function paneFilterPanelOpen(pane) {
        return paneFilterPanels[pane] === true
    }

    function setPaneFilterPanelOpen(pane, enabled) {
        if (pane < 0)
            return
        var next = paneFilterPanels.slice()
        next[pane] = enabled
        paneFilterPanels = next
    }

    function clearPaneDebounce(pane) {
        if (debounceTimer && debouncePane === pane) {
            debounceTimer.destroy()
            debounceTimer = null
        }
    }

    function clearPaneSearch(pane) {
        clearPaneDebounce(pane)
        setPaneSearchMode(pane, false)
        setPaneFilterPanelOpen(pane, false)
        searchServiceForPane(pane).cancelSearch()
        searchResultsForPane(pane).clear()
        searchProxyForPane(pane).clearSearch()
    }

    function paneModel(pane) {
        if (root.paneIsRecents(pane))
            return recentFiles

        if (root.paneIsHidden(pane))
            return hiddenEntries

        if (root.paneSearchMode(pane))
            return searchProxyForPane(pane)

        return paneBaseModel(pane)
    }

    function filePathFromModel(model, row) {
        if (!model || row < 0)
            return ""

        if (model.filePath)
            return model.filePath(row)

        return model.data(model.index(row, 0), 258 /* FilePathRole */) || ""
    }

    function isDirectoryFromModel(model, row) {
        if (!model || row < 0)
            return false

        if (model.isDir)
            return model.isDir(row)

        return model.data(model.index(row, 0), 265 /* IsDirRole */) || false
    }

    function fileViewForPane(pane) {
        // Phase 2 P2-M6: paneRow is a Repeater now; itemAt(idx) gives the
        // PaneFrame for that index, and its 'fileView' alias is the
        // FileViewContainer the keyboard / drag focus code needs.
        if (!paneRepeater || pane < 0 || pane >= paneRepeater.count)
            return null
        var frame = paneRepeater.itemAt(pane)
        return frame ? frame.fileView : null
    }

    function activeFileView() {
        return fileViewForPane(activePaneIndex)
    }

    function focusPathInPane(pane, path, reveal) {
        var view = fileViewForPane(pane)
        if (view && view.focusPath)
            view.focusPath(path, reveal)
    }

    function subViewFor(view) {
        if (!view)
            return null

        var vm = tabModel.activeTab ? tabModel.activeTab.viewMode : "hybrid"
        if (vm === "hybrid") return view.hybridViewItem
        if (vm === "grid") return view.gridViewItem
        if (vm === "miller") return view.millerViewItem
        if (vm === "gallery") return view.galleryViewItem
        return view.detailedViewItem
    }

    function activeSubView() {
        return subViewFor(activeFileView())
    }

    function reservedTargetNames() {
        return namesFromReserved(transferReservedTargets)
    }

    // Extract the basenames of the truthy keys of a {targetPath: bool} map, so a
    // batch transfer can block names already claimed within the same batch when
    // generating the next unique "(copy)" name.
    function namesFromReserved(reservedMap) {
        var names = []
        for (var path in reservedMap) {
            if (!reservedMap[path])
                continue
            var slashIndex = path.lastIndexOf("/")
            names.push(slashIndex >= 0 ? path.substring(slashIndex + 1) : path)
        }
        return names
    }

    function shouldFocusActivePane() {
        return root.active
            && !root.searchMode
            && !mainOverlays.bulkRenameDialog.visible
            && !mainOverlays.remoteConnectDialog.visible
            && !mainOverlays.settingsPanel.visible
            && !mainOverlays.shortcutsDialog.visible
            && !mainOverlays.renameDialog.visible
            && !mainOverlays.newFolderDialog.visible
            && !mainOverlays.newFileDialog.visible
            && !mainOverlays.conflictDialog.visible
            && !mainOverlays.deleteConfirmDialog.visible
            && !mainOverlays.emptyTrashConfirmDialog.visible
            && !quickPreview.active
    }

    function scheduleActivePaneFocus() {
        if (paneFocusScheduled)
            return

        paneFocusScheduled = true
        Qt.callLater(function() {
            paneFocusScheduled = false
            if (!root.shouldFocusActivePane())
                return

            var subView = root.activeSubView()
            if (subView)
                subView.forceActiveFocus()
        })
    }

    function setActivePane(pane) {
        // Phase 2 P2-M6: any pane index inside the current tab's pane list
        // is fair game.  Reject out-of-range requests (clamp to primary) so
        // a stale binding doesn't pin the active onto a slot that hasn't
        // been merged into existence yet.
        var nextPane = pane
        var count = tabModel.activeTab ? tabModel.activeTab.paneCount : 1
        if (nextPane < 0 || nextPane >= count)
            nextPane = 0

        if (activePaneIndex === nextPane)
            return

        activePaneIndex = nextPane
        root.updateSelectionStatus()
        root.scheduleActivePaneFocus()
    }

    function focusNextPane() {
        var count = tabModel.activeTab ? tabModel.activeTab.paneCount : 1
        if (count <= 1)
            return
        root.setActivePane((activePaneIndex + 1) % count)
    }

    function focusPreviousPane() {
        var count = tabModel.activeTab ? tabModel.activeTab.paneCount : 1
        if (count <= 1)
            return
        root.setActivePane((activePaneIndex - 1 + count) % count)
    }

    // Phase 2 P2-M9: close the pane at idx.  If the tab is single-pane
    // after this we let the underlying TabModel demote it out of supertab
    // / split-view mode automatically; if it was already single-pane
    // (the keyboard shortcut path on a non-supertab tab) we route the
    // close through TabListModel so the whole tab goes instead.
    function closePaneAt(idx) {
        if (!tabModel.activeTab)
            return
        if (tabModel.activeTab.paneCount > 1) {
            // The per-pane search/filter backends are bound to fixed slot
            // indices, so they can't follow a pane that shifts down when idx
            // is removed.  Clear search on every pane to avoid leaving stale
            // results wired to the wrong pane, then shift the recents flags so
            // they keep tracking the surviving panes.
            for (var p = 0; p < paneServicesProvider.count; ++p)
                root.clearPaneSearch(p)
            root.removePaneRecents(idx)
            root.removePaneHidden(idx)
            // Keep the active marker pointing at the same pane it referenced
            // before the removal collapsed the indices.
            if (root.activePaneIndex === idx)
                root.activePaneIndex = 0
            else if (root.activePaneIndex > idx)
                root.activePaneIndex = root.activePaneIndex - 1
            tabModel.activeTab.removePane(idx)
        } else if (tabModel.count > 1) {
            tabModel.closeTab(tabModel.activeIndex)
        }
    }

    // Splice the recents flag for the pane being removed so flags for panes
    // above idx shift down to match TabModel's m_panes.removeAt(idx).
    function removePaneRecents(idx) {
        if (idx < 0 || idx >= paneRecents.length)
            return
        var next = paneRecents.slice()
        next.splice(idx, 1)
        paneRecents = next
    }

    // Splice the hidden-view flag for the pane being removed (mirrors
    // removePaneRecents) so flags above idx shift down to match m_panes.
    function removePaneHidden(idx) {
        if (idx < 0 || idx >= paneHidden.length)
            return
        var next = paneHidden.slice()
        next.splice(idx, 1)
        paneHidden = next
    }

    function navigatePaneTo(pane, path) {
        if (!tabModel.activeTab || !path)
            return

        root.setPaneRecents(pane, false)
        root.setPaneHidden(pane, false)
        root.clearPaneSearch(pane)
        // Pane 0 keeps the dedicated navigateTo so the primary currentPath
        // Q_PROPERTY signals fire for the tab bar / sidebar; every other pane
        // goes through navigateInPane, which updates m_panes[pane] and emits
        // panePathChanged(pane) to drive the matching paneServices slot.
        if (pane === 0)
            tabModel.activeTab.navigateTo(path)
        else
            tabModel.activeTab.navigateInPane(pane, path)
        root.scheduleActivePaneFocus()
    }

    function navigateActivePaneTo(path) {
        navigatePaneTo(activePaneIndex, path)
    }

    // Spawn a new tab and seed its view/sort from the configured defaults.
    // TabModel's own defaults are hardcoded (grid / name / ascending); this
    // is the single point where config.defaultView/sortBy/sortAscending
    // actually take effect. Session restore does NOT go through here, so
    // restored tabs keep their saved view/sort.
    function createTabWithDefaults() {
        tabModel.addTab()
        if (tabModel.activeTab) {
            tabModel.activeTab.viewMode = config.defaultView
            tabModel.activeTab.sortBy = config.sortBy
            tabModel.activeTab.sortAscending = config.sortAscending
        }
    }

    function openPathInNewTab(path) {
        if (!path)
            return

        root.setPaneRecents(root.activePaneIndex, false)
        root.setPaneHidden(root.activePaneIndex, false)
        root.createTabWithDefaults()
        if (tabModel.activeTab)
            tabModel.activeTab.navigateTo(path)
        root.scheduleActivePaneFocus()
    }

    function resetTransferConflictState() {
        transferConflictItems = []
        transferResolvedItems = []
        transferConflictIndex = -1
        transferMoveOperation = false
        transferClearClipboardOnSuccess = false
        transferDestinationPath = ""
        transferReservedTargets = ({})
    }

    function executeTransferOperation(items, moveOperation, clearClipboardOnSuccess) {
        if (!items || items.length === 0)
            return

        var usesRemotePath = false
        for (var i = 0; i < items.length; ++i) {
            if (fileOps.isRemotePath(items[i].sourcePath) || fileOps.isRemotePath(items[i].targetPath)) {
                usesRemotePath = true
                break
            }
        }

        if (clearClipboardOnSuccess) {
            // Named one-shot rather than arguments.callee (which breaks under
            // JS strict mode and is hard to debug): disconnect by reference.
            var onClipboardTransferFinished = function(success) {
                fileOps.operationFinished.disconnect(onClipboardTransferFinished)
                if (success)
                    clipboard.clear()
            }
            fileOps.operationFinished.connect(onClipboardTransferFinished)
        }

        if (usesRemotePath) {
            if (moveOperation)
                fileOps.moveResolvedItems(items)
            else
                fileOps.copyResolvedItems(items)
            return
        }

        if (moveOperation)
            undoManager.moveResolvedItems(items)
        else
            undoManager.copyResolvedItems(items)
    }

    function openTransferConflict(index) {
        if (index < 0 || index >= transferConflictItems.length) {
            var items = transferResolvedItems.slice()
            var moveOperation = transferMoveOperation
            var clearClipboard = transferClearClipboardOnSuccess
            resetTransferConflictState()
            mainOverlays.conflictDialog.close()
            executeTransferOperation(items, moveOperation, clearClipboard)
            return
        }

        transferConflictIndex = index
        var item = transferConflictItems[index]
        mainOverlays.conflictDialog.renameText = fileOps.uniqueNameForDestination(
            transferDestinationPath,
            item.sourceName,
            reservedTargetNames()
        )
        mainOverlays.conflictDialog.errorText = ""
        mainOverlays.conflictDialog.currentItem = item
        mainOverlays.conflictDialog.open()
    }

    function beginTransfer(paths, destinationPath, moveOperation, clearClipboardOnSuccess) {
        if (!paths || paths.length === 0 || !destinationPath)
            return

        var plan = fileOps.transferPlan(paths, destinationPath)
        if (!plan || plan.length === 0)
            return

        var resolved = []
        var conflicts = []
        var reserved = ({})

        for (var i = 0; i < plan.length; ++i) {
            var item = plan[i]
            if (item.samePath) {
                // A move onto an item's own location is meaningless — skip it.
                // It must never reach the overwrite/backup path, which would
                // move the file to a backup then fail to copy the now-missing
                // source, destroying it. (Also guards drag into source's dir.)
                if (moveOperation)
                    continue
                // A COPY into the source's own folder becomes "name (copy).ext"
                // (Windows/Nautilus behaviour) rather than a no-op. Reserve the
                // generated name so a multi-file batch doesn't collide.
                var copyName = fileOps.uniqueNameForDestination(
                    destinationPath, item.sourceName, namesFromReserved(reserved))
                var copyTarget = destinationPath + "/" + copyName
                reserved[copyTarget] = true
                resolved.push({
                    sourcePath: item.sourcePath,
                    targetPath: copyTarget,
                    overwrite: false
                })
                continue
            }
            var targetPath = item.targetPath
            var hasReservedConflict = reserved[targetPath] === true
            if (item.targetExists || hasReservedConflict) {
                conflicts.push(item)
                continue
            }

            reserved[targetPath] = true
            resolved.push({
                sourcePath: item.sourcePath,
                targetPath: item.targetPath,
                overwrite: false
            })
        }

        // Everything was a self-drop (or nothing actionable): do nothing.
        if (resolved.length === 0 && conflicts.length === 0)
            return

        if (conflicts.length === 0) {
            executeTransferOperation(resolved, moveOperation, clearClipboardOnSuccess)
            return
        }

        transferResolvedItems = resolved
        transferConflictItems = conflicts
        transferConflictIndex = -1
        transferMoveOperation = moveOperation
        transferClearClipboardOnSuccess = clearClipboardOnSuccess
        transferDestinationPath = destinationPath
        transferReservedTargets = reserved
        openTransferConflict(0)
    }

    function resolveTransferConflict(action) {
        if (transferConflictIndex < 0 || transferConflictIndex >= transferConflictItems.length)
            return

        var item = transferConflictItems[transferConflictIndex]
        if (action === "overwrite") {
            if (item.samePath) {
                mainOverlays.conflictDialog.errorText = "Cannot overwrite an item with itself"
                return
            }

            transferReservedTargets[item.targetPath] = true
            transferResolvedItems = transferResolvedItems.concat([{ sourcePath: item.sourcePath, targetPath: item.targetPath, overwrite: true }])
        } else if (action === "rename") {
            var name = mainOverlays.conflictDialog.renameText.trim()
            if (name === "" || name === "." || name === ".." || name.indexOf("/") >= 0) {
                mainOverlays.conflictDialog.errorText = "Enter a valid file name"
                return
            }

            var targetPath = transferDestinationPath + "/" + name
            if (transferReservedTargets[targetPath] || fileOps.pathExists(targetPath) || targetPath === item.sourcePath) {
                mainOverlays.conflictDialog.errorText = "That name already exists"
                return
            }

            transferReservedTargets[targetPath] = true
            transferResolvedItems = transferResolvedItems.concat([{ sourcePath: item.sourcePath, targetPath: targetPath, overwrite: false }])
        }

        var nextIndex = transferConflictIndex + 1
        if (nextIndex >= transferConflictItems.length) {
            openTransferConflict(nextIndex)
            return
        }

        transferConflictIndex = nextIndex
        var nextItem = transferConflictItems[nextIndex]
        mainOverlays.conflictDialog.currentItem = nextItem
        mainOverlays.conflictDialog.renameText = fileOps.uniqueNameForDestination(
            transferDestinationPath,
            nextItem.sourceName,
            reservedTargetNames()
        )
        mainOverlays.conflictDialog.errorText = ""
        mainOverlays.conflictDialog.focusRenameField()
    }

    function cancelTransferConflicts() {
        if (mainOverlays.conflictDialog.visible)
            mainOverlays.conflictDialog.close()
        else {
            resetTransferConflictState()
            scheduleActivePaneFocus()
        }
    }

    // #9: every pane's history navigation goes through the indexed
    // paneGoBack/Forward/Up entry points, dispatched by activePaneIndex.
    // TabModel routes slots 0/1 to the legacy mutators and slots >= 2 to the
    // generic per-pane path, so this no longer has to know which pane is
    // "secondary" — the old activeIsSecondaryPane() fork (which silently fell
    // through to pane 0) is gone.
    function goActivePaneBack() {
        if (tabModel.activeTab)
            tabModel.activeTab.paneGoBack(activePaneIndex)
    }

    function goActivePaneForward() {
        if (tabModel.activeTab)
            tabModel.activeTab.paneGoForward(activePaneIndex)
    }

    function goActivePaneUp() {
        if (!tabModel.activeTab || root.paneIsRecents(activePaneIndex) || root.paneIsHidden(activePaneIndex))
            return

        var currentPath = panePath(activePaneIndex)
        if (fileOps.isRemotePath(currentPath)) {
            var parentRemotePath = fileOps.parentPath(currentPath)
            if (parentRemotePath && parentRemotePath !== currentPath)
                root.navigateActivePaneTo(parentRemotePath)
            return
        }

        if (currentPath.startsWith("trash:///")) {
            var normalized = currentPath.length > 9 && currentPath.endsWith("/")
                ? currentPath.slice(0, -1)
                : currentPath
            if (normalized === unifiedTrashPath.slice(0, -1) || normalized === unifiedTrashPath)
                return

            var slashIndex = normalized.lastIndexOf("/")
            var parentPath = slashIndex <= 8 ? unifiedTrashPath : normalized.substring(0, slashIndex)
            root.navigateActivePaneTo(parentPath)
            return
        }

        tabModel.activeTab.paneGoUp(activePaneIndex)
    }

    // The toolbar merge button + F3 dispatch through this single function.
    // Behaviour:
    //   * active tab is a supertab  -> unmerge it back into separate tabs
    //   * 2+ tabs selected          -> merge the explicit selection into one
    //                                  supertab
    //   * otherwise (only active)   -> merge the active tab with an adjacent
    //                                  one (defaulting to the tab on the right,
    //                                  falling back to the left), or spawn a
    //                                  fresh tab and merge it in when the active
    //                                  tab is the only tab.  See
    //                                  TabListModel::mergeActiveWithAdjacent.
    function toggleMergeOrUnmerge() {
        if (!tabModel.activeTab)
            return
        if (tabModel.activeTab.isSupertab) {
            tabModel.unmergeActive()
            return
        }

        if (tabModel.selectedCount >= 2) {
            tabModel.mergeSelected()
            return
        }

        tabModel.mergeActiveWithAdjacent()
    }

    // P2-M5: predicates feeding the toolbar merge button's icon + tooltip.
    // Read straight off the same state machine as toggleMergeOrUnmerge so
    // the button can never advertise an action it wouldn't actually fire.
    // - mergeButtonWillUnmerge: true iff the next click would dissolve the
    //   active supertab back into separate tabs.  Drives the IconLink vs
    //   IconUnlink swap.
    // - mergeButtonTooltip: human-readable description of the next action,
    //   including the cap-reached case where the click would no-op with a
    //   toast.  Bindings re-evaluate on selectionChanged / supertabChanged
    //   / countChanged because every term references one of them.
    function mergeButtonWillUnmerge() {
        return !!(tabModel.activeTab && tabModel.activeTab.isSupertab)
    }

    // mergeButtonOn drives the ARMED highlight only — the toolbar button is
    // always clickable (a plain click merges the active tab with its right
    // neighbour via toggleMergeOrUnmerge). It brightens when an explicit
    // ≥2-tab merge or a supertab unmerge is pending.
    function mergeButtonOn() {
        return !!(tabModel.activeTab
                  && (tabModel.activeTab.isSupertab || tabModel.selectedCount >= 2))
    }

    function mergeButtonTooltip() {
        if (!tabModel.activeTab)
            return ""
        if (tabModel.activeTab.isSupertab)
            return "Unmerge supertab"
        if (tabModel.selectedCount >= 2) {
            var total = tabModel.selectedPaneCountTotal()
            if (total > 4)
                return "Tab limit reached (max 4 panes)"
            return "Merge " + tabModel.selectedCount + " tabs"
        }
        // Only the active tab: the click merges it with an adjacent tab, or
        // spawns a fresh pane when it's the only tab.
        return tabModel.count >= 2 ? "Merge with adjacent tab" : "Split into a new pane"
    }

    // paneCanGoBack/Forward are Q_INVOKABLEs (not bindable Q_PROPERTYs), so
    // touch paneNavTick — bumped on every pane navigation via
    // refreshActivePanePath — to give the toolbar's enabled bindings a
    // reactive dependency that re-fires when any pane's history changes.
    function activePaneCanGoBack() {
        root.paneNavTick
        return tabModel.activeTab
            ? tabModel.activeTab.paneCanGoBack(activePaneIndex)
            : false
    }

    function activePaneCanGoForward() {
        root.paneNavTick
        return tabModel.activeTab
            ? tabModel.activeTab.paneCanGoForward(activePaneIndex)
            : false
    }

    function activeItemCount() {
        if (root.paneIsRecents(activePaneIndex))
            return recentFiles.count
        if (root.paneIsHidden(activePaneIndex))
            return hiddenEntries.fileCount + hiddenEntries.folderCount
        if (root.paneSearchMode(activePaneIndex))
            return searchProxyForPane(activePaneIndex).rowCount()

        var model = paneBaseModel(activePaneIndex)
        return model.fileCount + model.folderCount
    }

    function activeFolderCount() {
        if (root.paneIsHidden(activePaneIndex))
            return hiddenEntries.folderCount
        if (root.paneIsRecents(activePaneIndex) || root.paneSearchMode(activePaneIndex))
            return 0

        return paneBaseModel(activePaneIndex).folderCount
    }

    function applyActiveTabSort() {
        if (!tabModel.activeTab)
            return

        var sortBy = tabModel.activeTab.sortBy
        var ascending = tabModel.activeTab.sortAscending
        forEachLivePaneModel(function(mdl) { mdl.sortByColumn(sortBy, ascending) })
    }

    function updateSelectionStatus() {
        var subView = activeSubView()

        if (!subView || !subView.selectedIndices) {
            cancelSelectedSizeRequest()
            currentSelectedCount = 0
            currentSelectedSize = ""
            currentSelectedSizePending = false
            return
        }

        var indices = subView.selectedIndices
        currentSelectedCount = indices.length

        if (indices.length === 0) {
            cancelSelectedSizeRequest()
            currentSelectedSize = ""
            currentSelectedSizePending = false
            return
        }

        var paths = []
        var model = paneModel(activePaneIndex)
        for (var i = 0; i < indices.length; ++i) {
            var selectedPath = filePathFromModel(model, indices[i])
            if (isLocalPath(selectedPath))
                paths.push(selectedPath)
        }

        if (paths.length === 0) {
            cancelSelectedSizeRequest()
            currentSelectedSize = ""
            currentSelectedSizePending = false
            return
        }

        cancelSelectedSizeRequest()
        currentSelectedSizePending = true
        currentSelectedSize = "Calculating size..."
        currentSelectedSizeRequestId = diskUsageService.requestSize(paths)
    }

    function cancelSelectedSizeRequest() {
        if (currentSelectedSizeRequestId >= 0)
            diskUsageService.cancelRequest(currentSelectedSizeRequestId)
        currentSelectedSizeRequestId = -1
    }

    // ── Helper: collect selected file paths from active view ─────────────────
    function getSelectedPaths(pane) {
        var paths = []
        var targetPane = pane || activePaneIndex
        var view = fileViewForPane(targetPane)
        if (!view) return paths

        var subView = subViewFor(view)
        var model = paneModel(targetPane)

        if (!subView || !subView.selectedIndices || !model) return paths

        var indices = subView.selectedIndices
        for (var i = 0; i < indices.length; i++) {
            var fp = filePathFromModel(model, indices[i])
            if (fp !== "") paths.push(fp)
        }
        return paths
    }

    function getSelectedItems(pane) {
        var items = []
        var targetPane = pane || activePaneIndex
        var view = fileViewForPane(targetPane)
        if (!view) return items

        var subView = subViewFor(view)
        var model = paneModel(targetPane)

        if (!subView || !subView.selectedIndices || !model) return items

        var indices = subView.selectedIndices
        for (var i = 0; i < indices.length; i++) {
            var row = indices[i]
            var fp = filePathFromModel(model, row)
            if (fp !== "")
                items.push({ path: fp, isDir: isDirectoryFromModel(model, row) })
        }
        return items
    }

    function currentOrSelectedDirectoryPath() {
        var items = root.getSelectedItems(root.activePaneIndex)
        if (items.length === 1 && items[0].isDir)
            return items[0].path

        if (!root.paneIsRecents(root.activePaneIndex) && !root.paneIsHidden(root.activePaneIndex) && !root.paneSearchMode(root.activePaneIndex))
            return root.panePath(root.activePaneIndex)

        return ""
    }

    function selectedOrCurrentPropertiesPath() {
        var items = root.getSelectedItems(root.activePaneIndex)
        if (items.length === 1)
            return items[0].path

        if (!root.paneIsRecents(root.activePaneIndex) && !root.paneIsHidden(root.activePaneIndex) && !root.paneSearchMode(root.activePaneIndex))
            return root.panePath(root.activePaneIndex)

        return ""
    }

    function selectedOrCurrentTerminalPath() {
        var items = root.getSelectedItems(root.activePaneIndex)
        if (items.length === 1)
            return items[0].isDir ? items[0].path : fileOps.parentPath(items[0].path)

        if (!root.paneIsRecents(root.activePaneIndex) && !root.paneIsHidden(root.activePaneIndex) && !root.paneSearchMode(root.activePaneIndex))
            return root.panePath(root.activePaneIndex)

        return ""
    }

    function showContextMenuForActiveSelection() {
        var positionSource = root.activeFileView() || contentArea
        var mapped = positionSource.mapToItem(null, positionSource.width / 2, positionSource.height / 2)
        var items = root.getSelectedItems(root.activePaneIndex)
        if (items.length > 0) {
            root.showContextMenuForPane(root.activePaneIndex, items[0].path, items[0].isDir, Qt.point(mapped.x, mapped.y))
            return
        }

        root.showContextMenuForPane(root.activePaneIndex, "", true, Qt.point(mapped.x, mapped.y))
    }

    function openRenameDialogForPath(path) {
        if (!path)
            return

        root.renameTargetPath = path
        mainOverlays.renameDialog.openDialog(path.substring(path.lastIndexOf("/") + 1))
    }

    function openBulkRenameDialog(paths) {
        if (!paths || paths.length < 2)
            return

        mainOverlays.bulkRenameDialog.openForPaths(paths)
    }

    function toggleRenameWorkflow(paths) {
        if (mainOverlays.renameDialog.visible) {
            mainOverlays.renameDialog.closeDialog()
            return
        }

        if (mainOverlays.bulkRenameDialog.visible) {
            mainOverlays.bulkRenameDialog.reject()
            return
        }

        if (mainOverlays.newFolderDialog.visible || mainOverlays.newFileDialog.visible)
            return

        openRenameWorkflow(paths)
    }

    function showNewFolderDialog(parentPath) {
        if (!parentPath)
            return

        root.newItemParentPath = parentPath
        mainOverlays.newFolderDialog.openDialog()
    }

    function toggleNewFolderDialog(parentPath) {
        if (mainOverlays.newFolderDialog.visible) {
            mainOverlays.newFolderDialog.closeDialog()
            return
        }

        if (mainOverlays.renameDialog.visible || mainOverlays.bulkRenameDialog.visible || mainOverlays.newFileDialog.visible)
            return

        showNewFolderDialog(parentPath)
    }

    function showNewFileDialog(parentPath) {
        if (!parentPath)
            return

        root.newItemParentPath = parentPath
        mainOverlays.newFileDialog.openDialog()
    }

    function toggleNewFileDialog(parentPath) {
        if (mainOverlays.newFileDialog.visible) {
            mainOverlays.newFileDialog.closeDialog()
            return
        }

        if (mainOverlays.renameDialog.visible || mainOverlays.bulkRenameDialog.visible || mainOverlays.newFolderDialog.visible)
            return

        showNewFileDialog(parentPath)
    }

    function openRenameWorkflow(paths) {
        if (!paths || paths.length === 0)
            return

        if (paths.length === 1)
            openRenameDialogForPath(paths[0])
        else
            openBulkRenameDialog(paths)
    }

    function handleBulkRenameApplied(paths) {
        if (!paths || paths.length === 0) {
            root.scheduleActivePaneFocus()
            return
        }

        if (!root.paneIsRecents(root.activePaneIndex) && !root.paneIsHidden(root.activePaneIndex) && !root.paneSearchMode(root.activePaneIndex)) {
            var firstPath = paths[0]
            if (root.parentDirForPath(firstPath) === panePath(root.activePaneIndex)) {
                Qt.callLater(function() {
                    root.focusPathInPane(root.activePaneIndex, firstPath, true)
                })
            }
        }

        root.scheduleActivePaneFocus()
    }

    // ── Helper: list of all file paths in current directory (for preview cycling)
    function getDirectoryFiles() {
        var files = []
        var activeModel = paneModel(activePaneIndex)
        var count = activeModel.rowCount()
        for (var i = 0; i < count; i++) {
            var fp = filePathFromModel(activeModel, i)
            if (fp !== "")
                files.push(fp)
        }
        return files
    }

    // ── Search helpers ────────────────────────────────────────────────────────
    function openSearch() {
        if (fileOps.isRemotePath(panePath(activePaneIndex)))
            return
        setPaneRecents(activePaneIndex, false)
        setPaneHidden(activePaneIndex, false)
        setPaneSearchMode(activePaneIndex, true)
    }

    function closeSearch(pane) {
        clearPaneSearch(pane || activePaneIndex)
    }

    function handleSearchQuery(query) {
        var pane = activePaneIndex
        var proxy = searchProxyForPane(pane)
        var results = searchResultsForPane(pane)
        var service = searchServiceForPane(pane)

        proxy.searchQuery = query
        if (debounceTimer) debounceTimer.destroy()
        debounceTimer = null

        if (query === "") {
            service.cancelSearch()
            results.clear()
            return
        }

        debouncePane = pane
        var timer = Qt.createQmlObject(
            'import QtQuick; Timer { interval: 500; running: true; repeat: false }',
            root
        )
        debounceTimer = timer
        timer.triggered.connect(function() {
            root.triggerRecursiveSearch(pane, query)
            // Only clear the property if it still points at THIS timer (a newer
            // query may have replaced it), then destroy the fired instance so
            // it doesn't leak — the old code nulled the property and leaked it.
            if (debounceTimer === timer)
                debounceTimer = null
            timer.destroy()
        })
    }

    function triggerRecursiveSearch(pane, query) {
        var targetPane = pane || activePaneIndex
        var targetQuery = query !== undefined ? query : searchProxyForPane(targetPane).searchQuery
        if (targetQuery === "") return
        searchServiceForPane(targetPane).startSearch(
            panePath(targetPane),
            targetQuery,
            fsModel.showHidden
        )
    }

    function handleSearchEnter() {
        var query = searchProxyForPane(activePaneIndex).searchQuery
        if (query === "") return
        clearPaneDebounce(activePaneIndex)
        searchServiceForPane(activePaneIndex).startSearch(
            panePath(activePaneIndex),
            query,
            fsModel.showHidden
        )
    }

    function selectFirstSearchResult(pane) {
        // Nullish (not ||) so pane 0 isn't treated as "unspecified" and
        // silently redirected to the active pane.
        var targetPane = pane ?? activePaneIndex
        if (!paneSearchMode(targetPane) || searchProxyForPane(targetPane).rowCount() === 0)
            return

        var subView = subViewFor(fileViewForPane(targetPane))
        if (subView && subView.selectedIndices !== undefined) {
            subView.selectedIndices = [0]
            if (targetPane === activePaneIndex)
                subView.forceActiveFocus()
        }
    }

    // Per-pane search-finished + directory-watch connections are wired
    // imperatively for every pane slot in Component.onCompleted (see
    // wirePaneServiceSignals) — the pane backends are app-lifetime objects, so
    // a one-time connect reaches panes 2/3 without static slot-0/1 Connections.

    Connections {
        target: diskUsageService

        function onRequestFinished(requestId, result) {
            if (requestId === root.currentSelectedSizeRequestId) {
                root.currentSelectedSizeRequestId = -1
                root.currentSelectedSizePending = false
                root.currentSelectedSize = result.sizeText || ""
            }

            if (requestId === mainOverlays.propertiesDialog.folderDiskUsageRequestId) {
                mainOverlays.propertiesDialog.folderDiskUsageRequestId = -1
                mainOverlays.propertiesDialog.folderDiskUsagePending = false
                mainOverlays.propertiesDialog.folderDiskUsageText = result.sizeTextVerbose || result.sizeText || ""
            }
        }
    }

    // ── Rename / New-item target paths ───────────────────────────────────────
    // Kept on root (not moved into MainOverlays): the rename / new-folder /
    // new-file setters below write these, and MainOverlays' dialog handlers read
    // them back via host.renameTargetPath / host.newItemParentPath.
    property string renameTargetPath: ""
    property string newItemParentPath: ""

    // ── Modal overlays (dialogs + context menus) ─────────────────────────────
    MainOverlays {
        id: mainOverlays
        host: root
        blurTarget: mainContent
        toast: toast
        sidebarVisible: root.sidebarVisible
        sidebarWidth: root.sidebarWidth
        activePaneIndex: root.activePaneIndex
        transferMoveOperation: root.transferMoveOperation
        deleteConfirmPaths: root.deleteConfirmPaths
        isTrashView: root.isTrashView
    }

    // ── Keyboard Shortcuts ───────────────────────────────────────────────────────────────────────────
    AppShortcuts {
        host: root
        toolbar: toolbar
        quickPreview: quickPreview
        propertiesDialog: mainOverlays.propertiesDialog
        deleteConfirmDialog: mainOverlays.deleteConfirmDialog
        emptyTrashConfirmDialog: mainOverlays.emptyTrashConfirmDialog
        contextMenu: mainOverlays.contextMenu
        sidebarContextMenu: mainOverlays.sidebarContextMenu
        bulkRenameDialog: mainOverlays.bulkRenameDialog
        settingsPanel: mainOverlays.settingsPanel
        shortcutsDialog: mainOverlays.shortcutsDialog
        renameDialog: mainOverlays.renameDialog
        newFolderDialog: mainOverlays.newFolderDialog
        newFileDialog: mainOverlays.newFileDialog
    }

    function handlePaneFileActivated(pane, filePath, isDirectory) {
        root.setActivePane(pane)

        if (isDirectory) {
            root.navigatePaneTo(pane, filePath)
        } else if (fileOps.isArchive(filePath)) {
            var dir = filePath.substring(0, filePath.lastIndexOf("/"))
            // The root-folder listing and the extraction both run async now, so
            // neither blocks the GUI thread on activation. Navigate into the
            // extracted root only once BOTH have reported — otherwise a quick
            // extraction could finish before the listing and drop us at the
            // parent dir instead of inside the archive's root folder.
            var nav = { root: "", rootResolved: false, extractDone: false, success: false }
            // Declared together up front so each closure can reference the
            // others without tripping QML's use-before-declaration warning.
            var finishArchive, onArchiveRoot, onArchiveExtracted
            finishArchive = function() {
                if (!nav.rootResolved || !nav.extractDone)
                    return
                fileOps.archiveRootFolderReady.disconnect(onArchiveRoot)
                fileOps.operationFinished.disconnect(onArchiveExtracted)
                if (nav.success)
                    root.navigatePaneTo(pane, nav.root ? dir + "/" + nav.root : dir)
            }
            onArchiveRoot = function(archivePath, rootFolder) {
                if (archivePath !== filePath)
                    return
                nav.root = rootFolder
                nav.rootResolved = true
                finishArchive()
            }
            onArchiveExtracted = function(success) {
                nav.extractDone = true
                nav.success = success
                finishArchive()
            }
            fileOps.archiveRootFolderReady.connect(onArchiveRoot)
            fileOps.operationFinished.connect(onArchiveExtracted)
            fileOps.requestArchiveRootFolder(filePath)
            fileOps.extractArchive(filePath, dir)
        } else {
            fileOps.openFile(filePath)
            recentFiles.addRecent(filePath)
        }
    }

    function showContextMenuForPane(pane, filePath, isDirectory, position) {
        root.setActivePane(pane)

        var currentDir = panePath(pane)
        mainOverlays.contextMenu.targetPath = filePath !== "" ? filePath : currentDir
        mainOverlays.contextMenu.targetIsDir = filePath !== "" ? isDirectory : true
        mainOverlays.contextMenu.isEmptySpace = (filePath === "")
        var sel = getSelectedPaths(pane)
        mainOverlays.contextMenu.selectedPaths = (sel.length > 1) ? sel : (filePath !== "" ? [filePath] : [])
        mainOverlays.contextMenu.popup(position.x, position.y)
    }

    function pasteIntoDirectory(destPath) {
        if (!destPath)
            return

        if (clipboard.hasContent) {
            var wasCut = clipboard.isCut
            var items = clipboard.paths
            if (!items || items.length === 0) return
            beginTransfer(items, destPath, wasCut, wasCut)
            return
        }

        if (fileOps.isRemotePath(destPath))
            return

        if (fileOps.hasClipboardImage)
            fileOps.pasteClipboardImage(destPath)
    }

    // ── Layout ──────────────────────────────────────────────────────────────
    // Browser-style: TabBar runs full window width above everything, then a
    // RowLayout splits Sidebar | (Toolbar over Content over StatusBar).
    ColumnLayout {
        id: mainContent
        anchors.fill: parent
        spacing: 0

        TabBar {
            id: tabBar
            Layout.fillWidth: true
            // P2-M7: mirror window-level active sub-pane so the supertab's
            // mini folder icons can highlight which pane currently has
            // keyboard focus.
            activePaneIndex: root.activePaneIndex
            onNewTabRequested: root.createTabWithDefaults()
            onTransferRequested: (paths, destinationPath, moveOperation) =>
                root.beginTransfer(paths, destinationPath, moveOperation, false)
            // P2-M7: clicking a mini folder icon inside a merged supertab
            // activates the tab and snaps active pane focus to that sub-pane
            // in one gesture — same intent as clicking the pane in the
            // viewport, just shorter travel for mouse users.
            onSubPaneClicked: (tabIdx, paneIdx) => {
                tabModel.activateAndCollapseSelection(tabIdx)
                if (paneIdx >= 0)
                    root.activePaneIndex = paneIdx
            }
        }

        // Toolbar + breadcrumb — full-width row between the tab bar and the
        // [Sidebar | Content] row (#8). Living here (rather than inside the
        // content column) puts the action cluster at the far left, above the
        // sidebar, and keeps every icon visible when the sidebar is collapsed.
        Toolbar {
            id: toolbar
            z: 5
            Layout.fillWidth: true
            window: root
            activeTab: tabModel.activeTab
            // #9: bind to the activePanePath reactive mirror. panePath()
            // reads the untracked Q_INVOKABLE paneCurrentPath() (whose value
            // is always non-empty, so the tracked currentPath fallback branch
            // is never taken), so a raw panePath(activePaneIndex) binding only
            // re-fires on tab/pane switches — never on in-pane navigation —
            // which froze the breadcrumb on a stale path.
            navigationPath: activePanePath
            canGoBack: activePaneCanGoBack()
            canGoForward: activePaneCanGoForward()
            mergeWillUnmerge: root.mergeButtonWillUnmerge()
            mergeOn: root.mergeButtonOn()
            mergeTooltip: root.mergeButtonTooltip()
            isRecentsView: root.isRecentsView
            isHiddenView: root.isHiddenView
            isTrashView: root.isTrashView
            isRemoteView: root.isRemoteView
            searchMode: root.searchMode
            showWindowControls: false
            windowButtonLayout: config.windowButtonLayout
            currentSearchQuery: root.searchProxyForPane(activePaneIndex).searchQuery
            searchTypeFilter: root.searchProxyForPane(activePaneIndex).fileTypeFilter
            searchDateFilter: root.searchProxyForPane(activePaneIndex).dateFilter
            searchSizeFilter: root.searchProxyForPane(activePaneIndex).sizeFilter
            filterPanelOpen: root.paneFilterPanelOpen(activePaneIndex)
            onBackRequested: root.goActivePaneBack()
            onForwardRequested: root.goActivePaneForward()
            onUpRequested: root.goActivePaneUp()
            onRefreshRequested: {
                // Refresh the active model when it can (FileSystemModel —
                // normal + hidden views); otherwise fall back to the pane's
                // base model. Recents has no meaningful rescan (it's a derived
                // list, not a directory) so skip it silently rather than
                // pointlessly rescanning the base dir; search proxies refresh
                // via their base model.
                var mdl = root.paneModel(activePaneIndex)
                if (mdl && typeof mdl.refresh === "function")
                    mdl.refresh()
                else if (!root.paneIsRecents(activePaneIndex))
                    root.paneBaseModel(activePaneIndex).refresh()
            }
            onNavigateRequested: (targetPath) => root.navigateActivePaneTo(targetPath)
            onConnectRemoteRequested: root.openRemoteConnectDialog()
            onSettingsRequested: root.openSettingsPanel()
            onNewFolderRequested: root.showNewFolderDialog(activePanePath)
            onKeyboardShortcutsRequested: root.openKeyboardShortcutsDialog()
            onCloseRequested: root.close()
            onMinimizeRequested: root.showMinimized()
            onMaximizeRequested: root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
            onRestoreTrashRequested: {
                var paths = getSelectedPaths()
                if (paths.length > 0)
                    fileOps.restoreFromTrash(paths)
            }
            onEmptyTrashRequested: mainOverlays.emptyTrashConfirmDialog.open()
            onSplitViewToggled: root.toggleMergeOrUnmerge()
            onHomeClicked: {
                root.navigateActivePaneTo(fsModel.homePath())
            }
            onSearchClicked: root.openSearch()
            onSearchClosed: root.closeSearch()
            onSearchQueryChanged: (query) => root.handleSearchQuery(query)
            onSearchEnterPressed: root.handleSearchEnter()
            onSearchNavigateDown: {
                var subView = root.activeSubView()
                if (subView) subView.forceActiveFocus()
            }
            onSearchFilterToggled: root.setPaneFilterPanelOpen(activePaneIndex, !root.paneFilterPanelOpen(activePaneIndex))
            onTransferRequested: (paths, destinationPath, moveOperation) => root.beginTransfer(paths, destinationPath, moveOperation, false)
            onTypeFilterChanged: (filter) => root.searchProxyForPane(activePaneIndex).fileTypeFilter = filter
            onDateFilterChanged: (filter) => root.searchProxyForPane(activePaneIndex).dateFilter = filter
            onSizeFilterChanged: (filter) => root.searchProxyForPane(activePaneIndex).sizeFilter = filter
            onClearAllFilters: {
                root.searchProxyForPane(activePaneIndex).fileTypeFilter = ""
                root.searchProxyForPane(activePaneIndex).dateFilter = ""
                root.searchProxyForPane(activePaneIndex).sizeFilter = ""
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            // Sidebar "right" reverses ONLY this row's direct child order
            // (SidebarPane vs the content Item) so the sidebar renders against
            // the window's right edge. childrenInherit is FALSE so the mirroring
            // does NOT cascade into the children's internals — the toolbar,
            // breadcrumb, buttons and file views are never RTL-reversed.
            LayoutMirroring.enabled: config.sidebarPosition === "right"
            LayoutMirroring.childrenInherit: false

        // Sidebar (full height, animated)
        SidebarPane {
            host: root
            coordSpace: mainContent
            sidebarContextMenu: mainOverlays.sidebarContextMenu
            sidebarTooltipLayer: sidebarTooltipLayer
            toast: toast
        }

        // Right panel: toolbar + content
        Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                // The parent RowLayout reverses child order (childrenInherit:false)
                // so this Item lands on the correct side without inheriting any
                // mirroring — nothing to reset here.

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

            // File view (semi-transparent — Hyprland compositor blurs behind this)
            Rectangle {
                id: contentArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.containerColor(Theme.base, 0.65)

                // Curved mantle fills for inverse rounded corners
                Shape {
                    z: 1; width: Theme.radiusMedium; height: Theme.radiusMedium
                    anchors.top: parent.top; anchors.left: parent.left
                    ShapePath {
                        fillColor: Theme.mantle; strokeColor: "transparent"
                        startX: 0; startY: 0
                        PathLine { x: Theme.radiusMedium; y: 0 }
                        PathArc {
                            x: 0; y: Theme.radiusMedium
                            radiusX: Theme.radiusMedium; radiusY: Theme.radiusMedium
                            direction: PathArc.Counterclockwise
                        }
                        PathLine { x: 0; y: 0 }
                    }
                }
                Shape {
                    z: 1; width: Theme.radiusMedium; height: Theme.radiusMedium
                    anchors.top: parent.top; anchors.right: parent.right
                    ShapePath {
                        fillColor: Theme.mantle; strokeColor: "transparent"
                        startX: Theme.radiusMedium; startY: 0
                        PathLine { x: 0; y: 0 }
                        PathArc {
                            x: Theme.radiusMedium; y: Theme.radiusMedium
                            radiusX: Theme.radiusMedium; radiusY: Theme.radiusMedium
                            direction: PathArc.Clockwise
                        }
                        PathLine { x: Theme.radiusMedium; y: 0 }
                    }
                }

                // Phase 2 P2-M6: paneRow is now a Repeater over the active
                // tab's paneCount.  Single-pane tab => one PaneFrame fills
                // the area.  Split view or merged supertab => 2..4 frames
                // distributed equally via Layout.fillWidth.  Spacing keeps
                // a visible gutter between frames; PaneFrame's own border
                // overlay handles the active-pane highlight.
                RowLayout {
                    id: paneRow
                    anchors.fill: parent
                    readonly property bool multiPane: tabModel.activeTab && tabModel.activeTab.paneCount > 1
                    anchors.margins: multiPane ? 8 : 0
                    spacing: multiPane ? 8 : 0

                    Repeater {
                        id: paneRepeater
                        // Re-derive the model whenever the active tab or its
                        // paneCount changes so merge / unmerge / split toggle
                        // all rebuild the row.
                        model: tabModel.activeTab ? tabModel.activeTab.paneCount : 1

                        delegate: PaneFrame {
                            id: paneCell
                            required property int index
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            paneIndex: index
                            active: root.activePaneIndex === index
                            // splitViewPresented is reused as 'pane chrome
                            // visible' — the SplitPaneHeader appears whenever
                            // the row hosts more than one frame.
                            splitViewPresented: paneRow.multiPane
                            splitTransitionProgress: paneRow.multiPane ? 1 : 0
                            paneFileModel: root.paneModel(index)
                            // (paneTitle removed in Phase 7 — SplitPaneHeader
                            // now shows the pane's path + item count instead.)
                            // panePath() reads an untracked Q_INVOKABLE; depend
                            // on paneNavTick (bumped on every navigation) and
                            // the active tab so this re-evaluates instead of
                            // staying on the previously-viewed folder.
                            paneCurrentPath: {
                                root.paneNavTick
                                var _t = tabModel.activeTab
                                return root.panePath(index)
                            }
                            paneViewMode: tabModel.activeTab ? tabModel.activeTab.viewMode : "hybrid"

                            onInteractionStarted: root.setActivePane(index)
                            onFileActivated: (filePath, isDirectory) =>
                                root.handlePaneFileActivated(index, filePath, isDirectory)
                            onSelectionChanged: {
                                root.setActivePane(index)
                                root.updateSelectionStatus()
                            }
                            onTransferRequested: (paths, destinationPath, moveOperation) => {
                                root.setActivePane(index)
                                root.beginTransfer(paths, destinationPath, moveOperation, false)
                            }
                            onContextMenuRequested: (filePath, isDirectory, position) =>
                                root.showContextMenuForPane(index, filePath, isDirectory, position)
                            onSortRequested: (column, ascending) => {
                                root.setActivePane(index)
                                root.applySortFromUi(column, ascending)
                            }
                            // Empty-state New folder / New file → open the matching
                            // create dialog rooted at this pane's directory.
                            onCreateItemRequested: (kind, parentPath) => {
                                root.setActivePane(index)
                                if (kind === "folder")
                                    root.showNewFolderDialog(parentPath)
                                else
                                    root.showNewFileDialog(parentPath)
                            }
                            onCloseRequested: root.closePaneAt(index)
                        }
                    }
                }
                }

                StatusBar {
                    Layout.fillWidth: true
                    itemCount: root.activeItemCount()
                    folderCount: root.activeFolderCount()
                    // Wayfile design-canvas: active-pane absolute path in mono.
                    // Hidden during search (the result-count message replaces it)
                    // and for virtual views (recents) where there's no real path.
                    activePath: (root.searchMode || root.isRecentsView || root.isHiddenView)
                        ? ""
                        : root.activePanePath
                    searchStatus: root.searchMode && root.searchServiceForPane(activePaneIndex).isSearching
                        ? "Searching... " + root.searchServiceForPane(activePaneIndex).resultCount + " results"
                        : (root.searchMode && root.searchProxyForPane(activePaneIndex).searchActive
                            ? root.searchProxyForPane(activePaneIndex).rowCount() + " results"
                            : "")
                    selectedCount: root.currentSelectedCount
                    selectedSize: root.currentSelectedSize
                    selectedSizePending: root.currentSelectedSizePending
                    // View-switch cluster (#8 pkt 7): reflect and drive the
                    // active tab's per-tab viewMode.
                    viewMode: tabModel.activeTab ? tabModel.activeTab.viewMode : "hybrid"
                    onViewModeRequested: (m) => {
                        if (tabModel.activeTab) tabModel.activeTab.viewMode = m
                    }
                }
            }
        }
        }
    }

    Item {
        id: sidebarTooltipLayer
        anchors.fill: parent
        z: 900
    }

    // ── Mouse back/forward button support ────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        z: -100
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        propagateComposedEvents: true
        onClicked: (mouse) => {
            if (mouse.button === Qt.BackButton)
                root.goActivePaneBack()
            else if (mouse.button === Qt.ForwardButton)
                root.goActivePaneForward()
        }
    }

    // ── Quick Preview overlay (on top of everything) ─────────────────────────
    QuickPreview {
        id: quickPreview
        anchors.fill: parent
        z: 100
        onOpenRequested: (path, isDirectory) => {
            if (isDirectory) {
                root.navigateActivePaneTo(path)
            } else {
                fileOps.openFile(path)
                recentFiles.addRecent(path)
            }
        }
        onClosed: {
            quickPreview.active = false
            root.scheduleActivePaneFocus()
        }
    }

    // ── Toast notifications ──────────────────────────────────────────────────
    Toast {
        id: toast
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
    }

    Connections {
        target: fileOps
        function onPathsChanged(paths) {
            diskUsageService.invalidatePaths(paths)
            if (mainOverlays.propertiesDialog.visible && mainOverlays.propertiesDialog.props.path)
                mainOverlays.propertiesDialog.refreshFolderDiskUsage()
        }

        function onOperationFinished(success, error) {
            root.refreshAllPanes()
            root.updateSelectionStatus()
            if (mainOverlays.propertiesDialog.visible && mainOverlays.propertiesDialog.props.path) {
                mainOverlays.propertiesDialog.props = mainOverlays.propertiesDialog.fileModelRef.fileProperties(mainOverlays.propertiesDialog.props.path)
                mainOverlays.propertiesDialog.refreshFolderDiskUsage()
            }
            if (success)
                toast.show("Operation completed successfully", "success")
            else
                toast.show(error || "Operation failed", "error")
        }
    }

    Connections {
        target: devices
        function onMountError(message) {
            toast.show(message, "error")
        }
    }

    // fsModel / splitFsModel directory-watch was wired per-slot here; it is now
    // connected for every pane in wirePaneServiceSignals() (Component.onCompleted)
    // so panes 2/3 invalidate disk-usage cache on directory changes too.
}
