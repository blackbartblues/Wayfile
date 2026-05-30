import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Window
import Heimdall
import "components" as Components
import Quill as Q

ApplicationWindow {
    id: root
    width: 1024
    height: 768
    minimumWidth: 760
    minimumHeight: 520
    visibility: Window.Windowed
    title: "Heimdall"
    color: "transparent"
    // Heimdall fork: always frameless on Linux. Compositor (Hyprland) handles
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
    property var paneSearchModes: []
    property var paneFilterPanels: []
    readonly property bool isRecentsView: root.paneIsRecents(activePaneIndex)
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
    readonly property bool isTrashView: fileOps.isTrashPath(panePath(activePaneIndex))
    readonly property bool isRemoteView: fileOps.isRemotePath(panePath(activePaneIndex))

    // ── Click-anywhere-clears: any plain LMB press anywhere in the window
    // collapses a >1 tab selection down to just the active tab.  Sits on
    // top of all content with mouse.accepted=false so it observes the
    // press then lets it propagate normally to the actual click target.
    // Shift/Ctrl are skipped so multi-select gestures (Ctrl-click,
    // Shift-click range) still work on the tab strip.
    MouseArea {
        anchors.fill: parent
        z: 9999
        acceptedButtons: Qt.LeftButton
        hoverEnabled: false
        propagateComposedEvents: true
        onPressed: (mouse) => {
            if (mouse.modifiers === Qt.NoModifier
                && tabModel.selectedCount > 1) {
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

        // Bridge Heimdall theme into Quill theme singleton
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

        root.scheduleActivePaneFocus()
        // Heimdall: dependency check is opt-in via Settings -> "Check Optional
        // Dependencies", not a startup popup. The dialog is still present, but
        // we don't auto-open it.
    }

    onActiveChanged: {
        if (active)
            root.scheduleActivePaneFocus()
    }

    // ── Sidebar visibility (local property; config.sidebarVisible is read-only) ─
    property bool sidebarVisible: config.sidebarVisible
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

    function panePath(pane) {
        if (!tabModel.activeTab)
            return fsModel.homePath()
        var path = tabModel.activeTab.paneCurrentPath(pane)
        return path !== "" ? path : tabModel.activeTab.currentPath
    }

    function pathDisplayName(path) {
        if (!path)
            return ""

        if (fileOps.isTrashPath(path)) {
            var trashPath = path.length > 9 && path.endsWith("/") ? path.slice(0, -1) : path
            if (trashPath === unifiedTrashPath || trashPath === unifiedTrashPath.slice(0, -1))
                return "Trash"
            var trashIndex = trashPath.lastIndexOf("/")
            return decodeURIComponent(trashIndex >= 0 ? trashPath.substring(trashIndex + 1) : trashPath)
        }

        if (fileOps.isRemotePath(path)) {
            var remotePath = path.split("?")[0]
            if (remotePath.length > 1 && remotePath.endsWith("/"))
                remotePath = remotePath.slice(0, -1)
            var remoteIndex = remotePath.lastIndexOf("/")
            var remoteName = remoteIndex >= 0 ? remotePath.substring(remoteIndex + 1) : ""
            if (remoteName !== "")
                return decodeURIComponent(remoteName)
            var hostMatch = path.match(/^[^:]+:\/\/([^/]+)/)
            return hostMatch && hostMatch.length > 1 ? hostMatch[1] : path
        }

        if (path === "/")
            return "/"

        var localPath = path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path
        var slashIndex = localPath.lastIndexOf("/")
        return slashIndex >= 0 ? (localPath.substring(slashIndex + 1) || "/") : localPath
    }

    function paneDisplayName(pane) {
        if (root.paneIsRecents(pane))
            return "Recents"

        return root.pathDisplayName(root.panePath(pane))
    }

    // SplitPaneHeader moved to components/SplitPaneHeader.qml so PaneFrame
    // (which also lives in the Heimdall module) can reach it via plain
    // `import Heimdall` rather than depending on this inline-component scope.

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
        remoteConnectDialog.resetForm()
        remoteConnectDialog.open()
    }

    function openSettingsPanel() {
        if (settingsPanel.visible)
            settingsPanel.closePanel()
        else
            settingsPanel.openPanel()
    }

    function openKeyboardShortcutsDialog() {
        shortcutsDialog.openDialog()
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

        var vm = tabModel.activeTab ? tabModel.activeTab.viewMode : "grid"
        if (vm === "grid") return view.gridViewItem
        if (vm === "miller") return view.millerViewItem
        return view.detailedViewItem
    }

    function activeSubView() {
        return subViewFor(activeFileView())
    }

    function reservedTargetNames() {
        var names = []
        for (var path in transferReservedTargets) {
            if (!transferReservedTargets[path])
                continue
            var slashIndex = path.lastIndexOf("/")
            names.push(slashIndex >= 0 ? path.substring(slashIndex + 1) : path)
        }
        return names
    }

    function shouldFocusActivePane() {
        return root.active
            && !root.searchMode
            && !bulkRenameDialog.visible
            && !remoteConnectDialog.visible
            && !settingsPanel.visible
            && !shortcutsDialog.visible
            && !renameDialog.visible
            && !newFolderDialog.visible
            && !newFileDialog.visible
            && !conflictDialog.visible
            && !deleteConfirmDialog.visible
            && !emptyTrashConfirmDialog.visible
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

    function navigatePaneTo(pane, path) {
        if (!tabModel.activeTab || !path)
            return

        root.setPaneRecents(pane, false)
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
            conflictDialog.close()
            executeTransferOperation(items, moveOperation, clearClipboard)
            return
        }

        transferConflictIndex = index
        var item = transferConflictItems[index]
        conflictDialog.renameText = fileOps.uniqueNameForDestination(
            transferDestinationPath,
            item.sourceName,
            reservedTargetNames()
        )
        conflictDialog.errorText = ""
        conflictDialog.currentItem = item
        conflictDialog.open()
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
            // Dropping an item onto its own location is a no-op: skip it
            // entirely. It must never reach the overwrite/backup path, which
            // would move the file to a backup and then fail to copy the now
            // missing source — destroying it. (Guards drag into source's dir.)
            if (item.samePath)
                continue
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
                conflictDialog.errorText = "Cannot overwrite an item with itself"
                return
            }

            transferReservedTargets[item.targetPath] = true
            transferResolvedItems = transferResolvedItems.concat([{ sourcePath: item.sourcePath, targetPath: item.targetPath, overwrite: true }])
        } else if (action === "rename") {
            var name = conflictDialog.renameText.trim()
            if (name === "" || name === "." || name === ".." || name.indexOf("/") >= 0) {
                conflictDialog.errorText = "Enter a valid file name"
                return
            }

            var targetPath = transferDestinationPath + "/" + name
            if (transferReservedTargets[targetPath] || fileOps.pathExists(targetPath) || targetPath === item.sourcePath) {
                conflictDialog.errorText = "That name already exists"
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
        conflictDialog.currentItem = nextItem
        conflictDialog.renameText = fileOps.uniqueNameForDestination(
            transferDestinationPath,
            nextItem.sourceName,
            reservedTargetNames()
        )
        conflictDialog.errorText = ""
        conflictDialog.focusRenameField()
    }

    function cancelTransferConflicts() {
        if (conflictDialog.visible)
            conflictDialog.close()
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
        if (!tabModel.activeTab || root.paneIsRecents(activePaneIndex))
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
    //   * 2+ tabs selected          -> merge the selection into one supertab
    //   * otherwise (only active)   -> spawn a fresh tab and merge it in as a
    //                                  new pane, so the button doubles as
    //                                  "add a pane to this tab" (this replaced
    //                                  the old "Open in split view" action)
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

        // Only the active tab is in the selection: spawn a fresh tab and merge
        // it against the active one. addTab makes the new tab the only-selected
        // active, so re-arm the original (its index is unchanged — addTab
        // appends) then merge {original, new}; mergeSelected picks the lower
        // index (the original) as the receiver.
        var active = tabModel.activeIndex
        tabModel.addTab()
        tabModel.toggleSelected(active)
        tabModel.mergeSelected()
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
        return "Add a new pane"
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
        if (root.paneSearchMode(activePaneIndex))
            return searchProxyForPane(activePaneIndex).rowCount()

        var model = paneBaseModel(activePaneIndex)
        return model.fileCount + model.folderCount
    }

    function activeFolderCount() {
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

        if (!root.paneIsRecents(root.activePaneIndex) && !root.paneSearchMode(root.activePaneIndex))
            return root.panePath(root.activePaneIndex)

        return ""
    }

    function selectedOrCurrentPropertiesPath() {
        var items = root.getSelectedItems(root.activePaneIndex)
        if (items.length === 1)
            return items[0].path

        if (!root.paneIsRecents(root.activePaneIndex) && !root.paneSearchMode(root.activePaneIndex))
            return root.panePath(root.activePaneIndex)

        return ""
    }

    function selectedOrCurrentTerminalPath() {
        var items = root.getSelectedItems(root.activePaneIndex)
        if (items.length === 1)
            return items[0].isDir ? items[0].path : fileOps.parentPath(items[0].path)

        if (!root.paneIsRecents(root.activePaneIndex) && !root.paneSearchMode(root.activePaneIndex))
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
        renameDialog.openDialog(path.substring(path.lastIndexOf("/") + 1))
    }

    function openBulkRenameDialog(paths) {
        if (!paths || paths.length < 2)
            return

        bulkRenameDialog.openForPaths(paths)
    }

    function toggleRenameWorkflow(paths) {
        if (renameDialog.visible) {
            renameDialog.closeDialog()
            return
        }

        if (bulkRenameDialog.visible) {
            bulkRenameDialog.reject()
            return
        }

        if (newFolderDialog.visible || newFileDialog.visible)
            return

        openRenameWorkflow(paths)
    }

    function showNewFolderDialog(parentPath) {
        if (!parentPath)
            return

        root.newItemParentPath = parentPath
        newFolderDialog.openDialog()
    }

    function toggleNewFolderDialog(parentPath) {
        if (newFolderDialog.visible) {
            newFolderDialog.closeDialog()
            return
        }

        if (renameDialog.visible || bulkRenameDialog.visible || newFileDialog.visible)
            return

        showNewFolderDialog(parentPath)
    }

    function showNewFileDialog(parentPath) {
        if (!parentPath)
            return

        root.newItemParentPath = parentPath
        newFileDialog.openDialog()
    }

    function toggleNewFileDialog(parentPath) {
        if (newFileDialog.visible) {
            newFileDialog.closeDialog()
            return
        }

        if (renameDialog.visible || bulkRenameDialog.visible || newFolderDialog.visible)
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

        if (!root.paneIsRecents(root.activePaneIndex) && !root.paneSearchMode(root.activePaneIndex)) {
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

            if (requestId === propertiesDialog.folderDiskUsageRequestId) {
                propertiesDialog.folderDiskUsageRequestId = -1
                propertiesDialog.folderDiskUsagePending = false
                propertiesDialog.folderDiskUsageText = result.sizeTextVerbose || result.sizeText || ""
            }
        }
    }

    BulkRenameDialog {
        id: bulkRenameDialog
        onRenameApplied: (paths) => root.handleBulkRenameApplied(paths)
    }

    RemoteConnectDialog {
        id: remoteConnectDialog
        onConnected: (uri) => root.navigateActivePaneTo(uri)
    }

    Components.SettingsPanel {
        id: settingsPanel
        transientParent: root
        currentShowHidden: fsModel.showHidden
        currentSidebarVisible: root.sidebarVisible
        currentSidebarWidth: root.sidebarWidth
        onRemoteConnectRequested: root.openRemoteConnectDialog()
        onKeyboardShortcutsRequested: root.openKeyboardShortcutsDialog()
        onDependencyCheckRequested: missingDependenciesDialog.openDialog()
        onClosed: root.scheduleActivePaneFocus()
    }

    Components.KeyboardShortcutsDialog {
        id: shortcutsDialog
        onClosed: root.scheduleActivePaneFocus()
    }

    Components.MissingDependenciesDialog {
        id: missingDependenciesDialog
        onClosed: root.scheduleActivePaneFocus()
    }

    // (Heimdall: the startup auto-popup was removed. Trigger via Settings ->
    // "Check Optional Dependencies" instead.)

    // ── Rename dialog ───────────────────────────────────────────────────────
    property string renameTargetPath: ""

    AnimatedInputDialog {
        id: renameDialog
        title: "Rename"
        placeholder: "Enter new name"
        confirmText: "Rename"
        selectAllOnOpen: true
        onSubmitted: (name) => {
            if (root.renameTargetPath === "")
                return
            var parentDir = fileOps.parentPath(root.renameTargetPath)
            var targetPath = parentDir + "/" + name
            if (fileOps.pathExists(targetPath)) {
                showError("\"" + name + "\" already exists")
                return
            }
            if (fileOps.isRemotePath(root.renameTargetPath)) {
                var result = fileOps.renameResolvedItems([{ sourcePath: root.renameTargetPath, targetPath: targetPath }])
                if (!result.success) {
                    showError(result.error || "Rename failed")
                    return
                }
                root.refreshAllPanes()
            } else {
                undoManager.rename(root.renameTargetPath, name)
            }
            closeDialog()
        }
    }

    // ── New Folder / New File dialogs ───────────────────────────────────────
    property string newItemParentPath: ""

    AnimatedInputDialog {
        id: newFolderDialog
        title: "New Folder"
        placeholder: "Folder name"
        confirmText: "Create"
        onSubmitted: (name) => {
            if (root.newItemParentPath === "")
                return
            var createdPath = root.newItemParentPath + "/" + name
            if (fileOps.pathExists(createdPath)) {
                showError("\"" + name + "\" already exists")
                return
            }
            if (fileOps.isRemotePath(root.newItemParentPath)) {
                fileOps.createFolder(root.newItemParentPath, name)
                root.refreshAllPanes()
            } else {
                undoManager.createFolder(root.newItemParentPath, name)
            }
            if (fileOps.pathExists(createdPath))
                root.focusPathInPane(root.activePaneIndex, createdPath, true)
            closeDialog()
        }
    }

    AnimatedInputDialog {
        id: newFileDialog
        title: "New File"
        placeholder: "File name"
        confirmText: "Create"
        onSubmitted: (name) => {
            if (root.newItemParentPath === "")
                return
            var createdPath = root.newItemParentPath + "/" + name
            if (fileOps.pathExists(createdPath)) {
                showError("\"" + name + "\" already exists")
                return
            }
            if (fileOps.isRemotePath(root.newItemParentPath)) {
                fileOps.createFile(root.newItemParentPath, name)
                root.refreshAllPanes()
            } else {
                undoManager.createFile(root.newItemParentPath, name)
            }
            if (fileOps.pathExists(createdPath))
                root.focusPathInPane(root.activePaneIndex, createdPath, true)
            closeDialog()
        }
    }


    // ── App Chooser dialog ──────────────────────────
    Components.AppChooserDialog {
        id: appChooserDialog
        fileModel: root.paneBaseModel(root.activePaneIndex)
        onUsedAndClosed: {
            if (propertiesDialog.visible && propertiesDialog.props.mimeType)
                propertiesDialog.apps = propertiesDialog.fileModelRef.availableApps(propertiesDialog.props.mimeType)
        }
    }

    // ── Properties dialog ──────────────────────────────────────────────────
    Components.PropertiesDialog {
        id: propertiesDialog
        host: root
        onChooseAppRequested: (path, mimeType) => {
            appChooserDialog.filePath = path
            appChooserDialog.mimeType = mimeType
            appChooserDialog.open()
        }
    }

    TransferConflictDialog {
        id: conflictDialog
        isMoveOperation: root.transferMoveOperation
        onResolveRequested: (action) => root.resolveTransferConflict(action)
        onRejected: {
            root.resetTransferConflictState()
            root.scheduleActivePaneFocus()
        }
    }

    // ── Permanent Delete Confirmation Dialog ───────────────────────────────
    ConfirmActionDialog {
        id: deleteConfirmDialog
        title: "Permanently Delete?"
        confirmLabel: "Delete"
        bodyText: root.deleteConfirmPaths.length === 1
            ? "\"" + root.deleteConfirmPaths[0].substring(root.deleteConfirmPaths[0].lastIndexOf("/") + 1) + "\" will be permanently deleted. This cannot be undone."
            : root.deleteConfirmPaths.length + " items will be permanently deleted. This cannot be undone."
        onConfirmed: fileOps.deleteFiles(root.deleteConfirmPaths)
    }

    // ── Empty Trash Confirmation Dialog ──────────────────────────────────────
    ConfirmActionDialog {
        id: emptyTrashConfirmDialog
        title: "Empty Trash?"
        confirmLabel: "Empty Trash"
        bodyText: "All items in the Trash will be permanently deleted. This cannot be undone."
        onConfirmed: fileOps.emptyTrash()
    }

    // ── Context Menu ────────────────────────────────────────────────────────
    ContextMenu {
        id: contextMenu
        blurSource: mainContent

        fileModel: root.paneBaseModel(root.activePaneIndex)
        isTrashView: root.isTrashView
        currentViewMode: tabModel.activeTab ? tabModel.activeTab.viewMode : "grid"
        currentSortBy: tabModel.activeTab ? tabModel.activeTab.sortBy : "name"
        currentSortAscending: tabModel.activeTab ? tabModel.activeTab.sortAscending : true

        onOpenRequested: (path, isDir) => {
            if (isDir)
                root.navigateActivePaneTo(path)
            else
                fileOps.openFile(path)
        }
        onOpenInNewTabRequested: (path) => root.openPathInNewTab(path)
        onOpenWithRequested: (path, desktopFile) => fileOps.openFileWith(path, desktopFile)
        onSetDefaultAppRequested: (mimeType, desktopFile) => {
            root.paneBaseModel(root.activePaneIndex).setDefaultApp(mimeType, desktopFile)
        }
        onChooseAppRequested: (path, mimeType) => {
            appChooserDialog.filePath = path
            appChooserDialog.mimeType = mimeType
            appChooserDialog.open()
        }

        onCutRequested: (paths) => clipboard.cut(paths)

        onCopyRequested: (paths) => clipboard.copy(paths)

        onPasteRequested: (destPath) => {
            root.pasteIntoDirectory(destPath)
        }

        onCopyPathRequested: (path) => fileOps.copyPathToClipboard(path)

        onRenameRequested: (path) => root.openRenameDialogForPath(path)
        onBulkRenameRequested: (paths) => root.openBulkRenameDialog(paths)

        onTrashRequested: (paths) => {
            var hasRemotePath = false
            for (var i = 0; i < paths.length; ++i) {
                if (fileOps.isRemotePath(paths[i])) {
                    hasRemotePath = true
                    break
                }
            }

            if (hasRemotePath)
                fileOps.trashFiles(paths)
            else
                undoManager.trashFiles(paths)
        }
        onRestoreRequested: (paths) => fileOps.restoreFromTrash(paths)
        onEmptyTrashRequested: emptyTrashConfirmDialog.open()

        onDeleteRequested: (paths) => {
            deleteConfirmPaths = paths
            deleteConfirmDialog.open()
        }

        onOpenInTerminalRequested: (path) => {
            fileOps.openInTerminal(path)
        }

        onNewFolderRequested: (parentPath) => {
            root.showNewFolderDialog(parentPath)
        }

        onNewFileRequested: (parentPath) => {
            root.showNewFileDialog(parentPath)
        }

        onSelectAllRequested: {
            var view = root.activeFileView()
            if (view) view.selectAll()
        }

        onPropertiesRequested: (path) => {
            propertiesDialog.showProperties(path)
        }

        onViewModeRequested: (mode) => {
            if (tabModel.activeTab) tabModel.activeTab.viewMode = mode
        }

        onSortRequested: (column, ascending) => root.applySortFromUi(column, ascending)
    }

    ContextMenu {
        id: sidebarContextMenu
        menuWidth: 220

        property var sidebarItem: ({})

        onOpenRequested: (path) => {
            if (sidebarItem.isRecents) {
                root.setPaneRecents(root.activePaneIndex, true)
                return
            }

            root.navigateActivePaneTo(path)
        }

        onOpenInNewTabRequested: (path) => {
            if (path)
                root.openPathInNewTab(path)
        }

        onPropertiesRequested: (path) => {
            if (path)
                propertiesDialog.showProperties(path)
        }

        onOpenInTerminalRequested: (path) => {
            if (path)
                fileOps.openInTerminal(path)
        }

        onCustomActionRequested: (action) => {
            if (action === "emptytrash") {
                emptyTrashConfirmDialog.open()
            } else if (action === "removebookmark") {
                if (sidebarItem.kind === "bookmark" && sidebarItem.index >= 0)
                    bookmarks.removeBookmark(sidebarItem.index)
            } else if (action === "mountdevice") {
                if (sidebarItem.backend === "udisks2" && !runtimeFeatures.udisksctlAvailable) {
                    toast.show(runtimeFeatures.installHint("deviceMount"), "info")
                } else if (sidebarItem.kind === "device" && sidebarItem.index >= 0) {
                    devices.mount(sidebarItem.index)
                }
            } else if (action === "unmountdevice") {
                if (sidebarItem.backend === "udisks2" && !runtimeFeatures.udisksctlAvailable) {
                    toast.show(runtimeFeatures.installHint("deviceMount"), "info")
                } else if (sidebarItem.kind === "device" && sidebarItem.index >= 0) {
                    devices.unmount(sidebarItem.index)
                }
            }
        }

        onVisibleChanged: {
            if (!visible)
                sidebarItem = ({})
        }
    }

    // ── Keyboard Shortcuts ───────────────────────────────────────────────────────────────────────────
    AppShortcuts {
        host: root
        toolbar: toolbar
        quickPreview: quickPreview
        propertiesDialog: propertiesDialog
        deleteConfirmDialog: deleteConfirmDialog
        emptyTrashConfirmDialog: emptyTrashConfirmDialog
        contextMenu: contextMenu
        sidebarContextMenu: sidebarContextMenu
        bulkRenameDialog: bulkRenameDialog
        settingsPanel: settingsPanel
        shortcutsDialog: shortcutsDialog
        renameDialog: renameDialog
        newFolderDialog: newFolderDialog
        newFileDialog: newFileDialog
    }

    function sidebarMenuItems(item) {
        if (!item)
            return []

        if (item.kind === "quickAccess") {
            if (item.isRecents)
                return [
                    { text: "Open", shortcut: "", action: "open" }
                ]

            if (fileOps.isTrashPath(item.path))
                return [
                    { text: "Open", shortcut: "Return", action: "open" },
                    { text: "Open in New Tab", shortcut: "", action: "opennewtab" },
                    { text: "Open in Split View", shortcut: "", action: "split_open", icon: "SquareSplitHorizontal" },
                    { separator: true },
                    { text: "Empty Trash", shortcut: "", action: "emptytrash", destructive: true }
                ]

            return [
                { text: "Open", shortcut: "Return", action: "open" },
                { text: "Open in New Tab", shortcut: "", action: "opennewtab" },
                { text: "Open in Split View", shortcut: "", action: "split_open", icon: "SquareSplitHorizontal" },
                { separator: true },
                { text: "Open in Terminal", shortcut: "", action: "terminal" },
                { text: "Properties", shortcut: "", action: "properties" }
            ]
        }

        if (item.kind === "bookmark") {
            return [
                { text: "Open", shortcut: "Return", action: "open" },
                { text: "Open in New Tab", shortcut: "", action: "opennewtab" },
                { text: "Open in Split View", shortcut: "", action: "split_open", icon: "SquareSplitHorizontal" },
                { separator: true },
                { text: "Open in Terminal", shortcut: "", action: "terminal" },
                { text: "Properties", shortcut: "", action: "properties" },
                { separator: true },
                { text: "Remove from Bookmarks", shortcut: "", action: "removebookmark", destructive: true }
            ]
        }

        if (item.kind === "device") {
            if (!item.mounted)
                return [
                    { text: "Mount", shortcut: "", action: "mountdevice" }
                ]

            return [
                { text: "Open", shortcut: "Return", action: "open" },
                { text: "Open in New Tab", shortcut: "", action: "opennewtab" },
                { text: "Open in Split View", shortcut: "", action: "split_open", icon: "SquareSplitHorizontal" },
                { separator: true },
                { text: "Open in Terminal", shortcut: "", action: "terminal" },
                { text: "Properties", shortcut: "", action: "properties" },
                { separator: true },
                { text: "Unmount", shortcut: "", action: "unmountdevice" }
            ]
        }

        return []
    }

    function handlePaneFileActivated(pane, filePath, isDirectory) {
        root.setActivePane(pane)

        if (isDirectory) {
            root.navigatePaneTo(pane, filePath)
        } else if (fileOps.isArchive(filePath)) {
            var dir = filePath.substring(0, filePath.lastIndexOf("/"))
            var rootFolder = fileOps.archiveRootFolder(filePath)
            fileOps.extractArchive(filePath, dir)
            // Named one-shot rather than arguments.callee (see above).
            var onArchiveExtracted = function(success) {
                fileOps.operationFinished.disconnect(onArchiveExtracted)
                if (success) {
                    root.navigatePaneTo(pane, rootFolder ? dir + "/" + rootFolder : dir)
                }
            }
            fileOps.operationFinished.connect(onArchiveExtracted)
        } else {
            fileOps.openFile(filePath)
            recentFiles.addRecent(filePath)
        }
    }

    function showContextMenuForPane(pane, filePath, isDirectory, position) {
        root.setActivePane(pane)

        var currentDir = panePath(pane)
        contextMenu.targetPath = filePath !== "" ? filePath : currentDir
        contextMenu.targetIsDir = filePath !== "" ? isDirectory : true
        contextMenu.isEmptySpace = (filePath === "")
        var sel = getSelectedPaths(pane)
        contextMenu.selectedPaths = (sel.length > 1) ? sel : (filePath !== "" ? [filePath] : [])
        contextMenu.popup(position.x, position.y)
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

        if (fileOps.hasClipboardImage())
            fileOps.pasteClipboardImage(destPath)
    }

    // ── Layout ──────────────────────────────────────────────────────────────
    // Browser-style: TabBar runs full window width above everything, then a
    // RowLayout splits Sidebar | (Toolbar over Content over StatusBar).
    ColumnLayout {
        id: mainContent
        anchors.fill: parent
        spacing: 0
        LayoutMirroring.enabled: config.sidebarPosition === "right"
        LayoutMirroring.childrenInherit: false

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

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

        // Sidebar (full height, animated)
        Item {
                id: sidebarHost
                Layout.preferredWidth: root.sidebarVisible ? root.sidebarWidth : 0
                Layout.fillHeight: true
                clip: true

                Behavior on Layout.preferredWidth {
                    enabled: !root.sidebarResizeActive
                    NumberAnimation { duration: Theme.animDuration; easing.type: Theme.animEasingTransition; easing.bezierCurve: Theme.animBezierCurve }
                }

                Sidebar {
                    width: root.sidebarWidth
                    height: parent.height
                    tooltipLayer: sidebarTooltipLayer
                    currentPath: root.activePanePath
                    trashPath: root.unifiedTrashPath
                    isRecentsView: root.isRecentsView
                    onBookmarkClicked: (path) => {
                        root.navigateActivePaneTo(path)
                    }
                    onSidebarContextMenuRequested: (item, position) => {
                        sidebarContextMenu.sidebarItem = item
                        sidebarContextMenu.contextData = item
                        sidebarContextMenu.customItems = root.sidebarMenuItems(item)
                        sidebarContextMenu.targetPath = item.path || ""
                        sidebarContextMenu.targetIsDir = !!item.path
                        sidebarContextMenu.isEmptySpace = false
                        sidebarContextMenu.selectedPaths = item.path ? [item.path] : []
                        sidebarContextMenu.popup(position.x, position.y)
                    }
                    onRecentsClicked: {
                        root.setPaneRecents(root.activePaneIndex, true)
                    }
                    onCollapseClicked: root.sidebarVisible = !root.sidebarVisible
                    onFeatureHintRequested: (message) => toast.show(message, "info")
                }

                MouseArea {
                    id: sidebarResizeHandle
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: config.sidebarPosition === "right" ? undefined : parent.right
                    anchors.left: config.sidebarPosition === "right" ? parent.left : undefined
                    width: 10
                    hoverEnabled: true
                    enabled: root.sidebarVisible
                    cursorShape: Qt.SizeHorCursor
                    z: 10

                    onPressed: (mouse) => {
                        root.sidebarResizeActive = true
                        root.sidebarResizeStartGlobalX = sidebarResizeHandle.mapToItem(mainContent, mouse.x, mouse.y).x
                        root.sidebarResizeStartWidth = root.sidebarWidth
                        mouse.accepted = true
                    }

                    onPositionChanged: (mouse) => {
                        if (!pressed)
                            return
                        var globalX = sidebarResizeHandle.mapToItem(mainContent, mouse.x, mouse.y).x
                        var delta = globalX - root.sidebarResizeStartGlobalX
                        if (config.sidebarPosition === "right") delta = -delta
                        root.sidebarWidth = root.clampedSidebarWidth(root.sidebarResizeStartWidth + delta)
                        mouse.accepted = true
                    }

                    onReleased: {
                        root.sidebarResizeActive = false
                        config.saveSidebarWidth(root.sidebarWidth)
                    }

                    onCanceled: {
                        root.sidebarResizeActive = false
                        config.saveSidebarWidth(root.sidebarWidth)
                    }

                    preventStealing: true
                }
        }

        // Right panel: toolbar + content
        Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    visible: root.sidebarVisible
                    x: config.sidebarPosition === "right" ? parent.width - 1 : -1
                    y: 0
                    width: 2
                    height: toolbar.height
                    color: Theme.mantle
                    z: 2
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

            // Toolbar with integrated tabs
            Toolbar {
                id: toolbar
                z: 5
                Layout.fillWidth: true
                window: root
                activeTab: tabModel.activeTab
                navigationPath: panePath(activePaneIndex)
                canGoBack: activePaneCanGoBack()
                canGoForward: activePaneCanGoForward()
                mergeWillUnmerge: root.mergeButtonWillUnmerge()
                mergeTooltip: root.mergeButtonTooltip()
                isRecentsView: root.isRecentsView
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
                onNavigateRequested: (targetPath) => root.navigateActivePaneTo(targetPath)
                onConnectRemoteRequested: root.openRemoteConnectDialog()
                onSettingsRequested: root.openSettingsPanel()
                onKeyboardShortcutsRequested: root.openKeyboardShortcutsDialog()
                onCloseRequested: root.close()
                onMinimizeRequested: root.showMinimized()
                onMaximizeRequested: root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
                onRestoreTrashRequested: {
                    var paths = getSelectedPaths()
                    if (paths.length > 0)
                        fileOps.restoreFromTrash(paths)
                }
                onEmptyTrashRequested: emptyTrashConfirmDialog.open()
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
                            paneTitle: root.paneDisplayName(index)
                            paneFileModel: root.paneModel(index)
                            // panePath() reads an untracked Q_INVOKABLE; depend
                            // on paneNavTick (bumped on every navigation) and
                            // the active tab so this re-evaluates instead of
                            // staying on the previously-viewed folder.
                            paneCurrentPath: {
                                root.paneNavTick
                                var _t = tabModel.activeTab
                                return root.panePath(index)
                            }
                            paneViewMode: tabModel.activeTab ? tabModel.activeTab.viewMode : "grid"

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
                            onCloseRequested: root.closePaneAt(index)
                        }
                    }
                }
                }

                StatusBar {
                    Layout.fillWidth: true
                    itemCount: root.activeItemCount()
                    folderCount: root.activeFolderCount()
                    // Heimdall design-canvas: active-pane absolute path in mono.
                    // Hidden during search (the result-count message replaces it)
                    // and for virtual views (recents) where there's no real path.
                    activePath: (root.searchMode || root.isRecentsView)
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
            if (propertiesDialog.visible && propertiesDialog.props.path)
                propertiesDialog.refreshFolderDiskUsage()
        }

        function onOperationFinished(success, error) {
            root.refreshAllPanes()
            root.updateSelectionStatus()
            if (propertiesDialog.visible && propertiesDialog.props.path) {
                propertiesDialog.props = propertiesDialog.fileModelRef.fileProperties(propertiesDialog.props.path)
                propertiesDialog.refreshFolderDiskUsage()
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
