import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import Wayfile
import Quill as Q

Rectangle {
    id: root
    Accessible.role: Accessible.ToolBar
    Accessible.name: "Navigation toolbar"

    property var activeTab: null
    property string navigationPath: ""
    property bool canGoBack: false
    property bool canGoForward: false
    // P2-M5 / W4: dynamic merge/unmerge button state.  mergeOn is the ARMED
    // highlight (an explicit ≥2-tab merge or a supertab unmerge is pending) —
    // the button stays clickable when off and falls back to merge-with-right-
    // neighbour; mergeWillUnmerge picks the
    // broken-link IconUnlink (unmerge) vs the inlined chain-link Shape (merge);
    // mergeTooltip rotates between four messages (merge N / merge with
    // neighbour / unmerge / cap reached) so the button never feels ambiguous.
    // Main.qml computes all three off the same predicates as
    // toggleMergeOrUnmerge — see mergeButtonOn/mergeButtonTooltip there.
    property bool mergeWillUnmerge: false
    property bool mergeOn: false
    property string mergeTooltip: ""
    // Exposed so Main.qml's click-anywhere-clears overlay can exempt presses
    // on this button — collapsing the tab selection on the very press that
    // is about to merge it would disarm the merge before onClicked fires.
    readonly property Item mergeButton: mergeBtn
    property bool isRecentsView: false
    property bool isHiddenView: false
    property bool isTrashView: false
    property bool isRemoteView: false
    property bool searchMode: false
    property bool showWindowControls: false
    property string windowButtonLayout: ":minimize,maximize,close"
    property var window: null
    property string currentSearchQuery: ""
    property string searchTypeFilter: ""
    property string searchDateFilter: ""
    property string searchSizeFilter: ""
    property bool filterPanelOpen: false
    property alias searchBar: searchBarLoader.item
    property alias filterPanel: filterPanelLoader.item

    function startEditing() {
        if (!searchMode) breadcrumb.startEditing()
    }

    function syncSearchBarState() {
        if (searchBarLoader.item)
            searchBarLoader.item.applyQuery(currentSearchQuery)
    }

    function syncFilterPanelState() {
        if (!filterPanelLoader.item)
            return

        filterPanelLoader.item.visible = filterPanelOpen
        filterPanelLoader.item.applyState(searchTypeFilter, searchDateFilter, searchSizeFilter)
    }

    onCurrentSearchQueryChanged: syncSearchBarState()
    onSearchTypeFilterChanged: syncFilterPanelState()
    onSearchDateFilterChanged: syncFilterPanelState()
    onSearchSizeFilterChanged: syncFilterPanelState()
    onFilterPanelOpenChanged: syncFilterPanelState()

    signal searchClicked()
    signal connectRemoteRequested()
    signal homeClicked()
    signal searchQueryChanged(string query)
    signal searchFilterToggled()
    signal searchClosed()
    signal searchEnterPressed()
    signal searchNavigateDown()
    signal backRequested()
    signal forwardRequested()
    signal upRequested()
    signal navigateRequested(string targetPath)
    signal splitViewToggled()
    signal typeFilterChanged(string filter)
    signal dateFilterChanged(string filter)
    signal sizeFilterChanged(string filter)
    signal clearAllFilters()
    signal restoreTrashRequested()
    signal emptyTrashRequested()
    signal settingsRequested()
    signal newFolderRequested()
    signal keyboardShortcutsRequested()
    signal closeRequested()
    signal minimizeRequested()
    signal maximizeRequested()
    signal transferRequested(var paths, string destinationPath, bool moveOperation)

    // Parse "buttons_left:buttons_right" layout string
    readonly property var _parsedLayout: {
        var layout = windowButtonLayout || ":minimize,maximize,close"
        var parts = layout.split(":")
        var leftStr = parts[0] || ""
        var rightStr = parts.length > 1 ? parts[1] : ""
        return {
            left: leftStr ? leftStr.split(",").filter(function(s) { return s.trim() !== "" }) : [],
            right: rightStr ? rightStr.split(",").filter(function(s) { return s.trim() !== "" }) : []
        }
    }

    implicitHeight: toolbarColumn.implicitHeight
    // Obsidian toolbar gradient (handoff .toolbar).
    gradient: Gradient {
        GradientStop { position: 0.0; color: Theme.panel2 }
        GradientStop { position: 1.0; color: Theme.bgA }
    }

    // 1px bottom border line separating the toolbar from the content below.
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.divider
        z: 5
    }

    // Wayfile fork: window is always frameless on Linux, so the toolbar is
    // the only drag region. Enable the handler whenever a window is present
    // rather than gating it on the now-removed in-app window controls.
    DragHandler {
        enabled: root.window !== null
        target: null
        acceptedButtons: Qt.LeftButton
        onActiveChanged: {
            if (active && root.window && root.window.startSystemMove)
                root.window.startSystemMove()
        }
    }

    ColumnLayout {
        id: toolbarColumn
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        // ── Row 1: Navigation + Breadcrumb + Search ──
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.toolbarRowHeight

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacing
                anchors.rightMargin: Theme.spacing
                spacing: 4

                // Left-side window controls
                Repeater {
                    model: root.showWindowControls ? root._parsedLayout.left : []
                    delegate: HoverRect {
                        required property string modelData
                        width: Theme.controlSize; height: Theme.controlSize
                        color: modelData === "close" && hovered
                            ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.9)
                            : (hovered ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : "transparent")
                        onClicked: {
                            if (modelData === "close") root.closeRequested()
                            else if (modelData === "minimize") root.minimizeRequested()
                            else if (modelData === "maximize") root.maximizeRequested()
                        }
                        IconX { anchors.centerIn: parent; size: 14; color: parent.modelData === "close" && parent.hovered ? Theme.base : Theme.text; visible: parent.modelData === "close" }
                        IconMinus { anchors.centerIn: parent; size: 14; color: Theme.text; visible: parent.modelData === "minimize" }
                        IconSquare { anchors.centerIn: parent; size: 12; color: Theme.text; visible: parent.modelData === "maximize" }
                    }
                }

                Item {
                    visible: root.showWindowControls && root._parsedLayout.left.length > 0
                    width: visible ? 4 : 0
                    height: 1
                }

                // ── Action cluster (left of the breadcrumb, #8) ──
                // Merge/unmerge, sidebar toggle, search, settings, new folder.
                // Relocated here from the toolbar's right edge so they sit on
                // the left side of the breadcrumb. Always visible — they do not
                // disappear when the sidebar (a separate panel) is collapsed.
                // Signature merge action. Idle = gold-wash + goldLine border +
                // gold link glyph (handoff .iconbtn--gold). Armed (the active
                // tab is a supertab / a merge is pending) = solid gold gradient
                // + dark glyph + gold glow (handoff .iconbtn--armed).
                HoverRect {
                    id: mergeBtn
                    width: Theme.controlSize; height: Theme.controlSize
                    visible: !root.searchMode
                    // ALWAYS clickable: with no extra selection a click merges
                    // the active tab with its right neighbour (left fallback /
                    // split when it's the only tab). `mergeOn` is the ARMED
                    // highlight — an explicit ≥2-tab merge or a supertab unmerge
                    // — and only brightens the recipe; it never gates the click.
                    border.width: 1
                    border.color: root.mergeOn ? Theme.gold : Theme.goldLine
                    gradient: root.mergeOn ? mergeArmedGrad : null
                    color: root.mergeOn
                        ? "transparent"
                        : (hovered ? Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.12)
                                   : Theme.goldWash)
                    layer.enabled: root.mergeOn
                    layer.effect: MultiEffect {
                        autoPaddingEnabled: true
                        shadowEnabled: true
                        shadowColor: Theme.goldGlow
                        shadowBlur: 0.7
                    }
                    onClicked: root.splitViewToggled()

                    Gradient {
                        id: mergeArmedGrad
                        GradientStop { position: 0.0; color: Theme.goldLight }
                        GradientStop { position: 0.6; color: Theme.gold }
                        GradientStop { position: 1.0; color: Theme.goldMid }
                    }

                    // chain-link to MERGE the selection (inlined Shape per CLAUDE.md
                    // — the icons dir is a no-push submodule). Broken-link to
                    // UNMERGE a supertab reuses the existing IconUnlink.
                    Shape {
                        anchors.centerIn: parent
                        width: 18; height: 18
                        visible: !root.mergeWillUnmerge
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            // dark glyph on the bright armed gradient; gold glyph
                            // on the subtle idle gold-wash (matches handoff).
                            strokeColor: root.mergeOn ? Theme.goldInk : Theme.gold
                            strokeWidth: Math.max(1, 18 / 12)
                            fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                            scale: Qt.size(18 / 24, 18 / 24)
                            PathSvg { path: "M10.4 13.6a4 4 0 0 0 6 .43l2.2-2.2a4 4 0 0 0-5.66-5.66l-1.26 1.25" }
                        }
                        ShapePath {
                            // dark glyph on the bright armed gradient; gold glyph
                            // on the subtle idle gold-wash (matches handoff).
                            strokeColor: root.mergeOn ? Theme.goldInk : Theme.gold
                            strokeWidth: Math.max(1, 18 / 12)
                            fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                            scale: Qt.size(18 / 24, 18 / 24)
                            PathSvg { path: "M13.6 10.4a4 4 0 0 0-6-.43l-2.2 2.2a4 4 0 0 0 5.66 5.66l1.25-1.25" }
                        }
                    }
                    IconUnlink { anchors.centerIn: parent; size: 18; color: Theme.goldInk; visible:  root.mergeWillUnmerge }
                    Q.Tooltip { text: root.mergeTooltip; visible: mergeBtn.hovered && root.mergeTooltip.length > 0 }
                }

                // Gold-highlighted when the sidebar is HIDDEN (signals "click to
                // bring it back"); plain when it's already showing.
                HoverRect {
                    id: sidebarToggleBtn
                    width: Theme.controlSize; height: Theme.controlSize
                    visible: !root.searchMode && root.window !== null
                    readonly property bool sbHidden: root.window !== null && !root.window.sidebarVisible
                    border.width: sbHidden ? 1 : 0
                    border.color: Theme.goldLine
                    color: sbHidden
                        ? (hovered ? Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.12) : Theme.goldWash)
                        : (hovered ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : "transparent")
                    onClicked: {
                        if (root.window)
                            root.window.sidebarVisible = !root.window.sidebarVisible
                    }
                    IconPanelLeft {
                        anchors.centerIn: parent
                        size: 18
                        color: sidebarToggleBtn.sbHidden ? Theme.gold : Theme.text
                    }
                    Q.Tooltip {
                        text: (root.window && root.window.sidebarVisible) ? "Hide sidebar" : "Show sidebar"
                        visible: sidebarToggleBtn.hovered
                    }
                }

                HoverRect {
                    id: searchBtn
                    width: Theme.controlSize; height: Theme.controlSize
                    visible: !root.searchMode && !root.isTrashView && !root.isRemoteView
                    onClicked: root.searchClicked()
                    IconSearch { anchors.centerIn: parent; size: 18; color: Theme.text }
                    Q.Tooltip { text: "Search"; visible: searchBtn.hovered }
                }

                HoverRect {
                    id: settingsBtn
                    width: Theme.controlSize; height: Theme.controlSize
                    visible: !root.searchMode
                    onClicked: root.settingsRequested()
                    IconSettings { anchors.centerIn: parent; size: 18; color: Theme.text }
                    Q.Tooltip { text: "Settings"; visible: settingsBtn.hovered }
                }

                // Separator between settings and the new-folder action.
                Rectangle {
                    visible: !root.searchMode
                    Layout.alignment: Qt.AlignVCenter
                    width: 1
                    height: Math.round(Theme.controlSize * 0.55)
                    color: Theme.line
                }

                HoverRect {
                    id: newFolderBtn
                    width: Theme.controlSize; height: Theme.controlSize
                    visible: !root.searchMode && !root.isTrashView
                    onClicked: root.newFolderRequested()
                    IconFolder { anchors.centerIn: parent; size: 18; color: Theme.text }
                    IconPlus {
                        anchors.right: parent.right; anchors.bottom: parent.bottom
                        anchors.rightMargin: 8; anchors.bottomMargin: 8
                        size: 12; color: Theme.accent
                    }
                    Q.Tooltip { text: "New folder"; visible: newFolderBtn.hovered }
                }

                // Divider between the new-folder action and the navigation buttons
                Rectangle {
                    visible: !root.searchMode
                    Layout.alignment: Qt.AlignVCenter
                    width: 1
                    height: Math.round(Theme.controlSize * 0.55)
                    color: Theme.line
                }

                // Back button
                HoverRect {
                    width: Theme.controlSize; height: Theme.controlSize
                    hoverEnabled: root.canGoBack
                    opacity: hoverEnabled ? 1.0 : 0.4
                    onClicked: root.backRequested()
                    IconChevronLeft { anchors.centerIn: parent; size: 18; color: Theme.text }
                }

                // Forward button
                HoverRect {
                    width: Theme.controlSize; height: Theme.controlSize
                    hoverEnabled: root.canGoForward
                    opacity: hoverEnabled ? 1.0 : 0.4
                    onClicked: root.forwardRequested()
                    IconChevronRight { anchors.centerIn: parent; size: 18; color: Theme.text }
                }

                // Up button
                HoverRect {
                    width: Theme.controlSize; height: Theme.controlSize
                    hoverEnabled: !root.isRecentsView && !root.isHiddenView
                    opacity: hoverEnabled ? 1.0 : 0.4
                    onClicked: root.upRequested()
                    IconChevronUp { anchors.centerIn: parent; size: 18; color: Theme.text }
                }

                // Separator between the navigation buttons and the breadcrumb.
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 1
                    height: Math.round(Theme.controlSize * 0.55)
                    color: Theme.line
                }

                // Breadcrumb / address bar (hidden in search mode)
                Breadcrumb {
                    id: breadcrumb
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !root.searchMode
                    path: root.navigationPath
                    activeTab: root.activeTab
                    isRecentsView: root.isRecentsView
                    isHiddenView: root.isHiddenView
                    onNavigateRequested: (targetPath) => root.navigateRequested(targetPath)
                }

                // Search bar (shown in search mode)
                Loader {
                    id: searchBarLoader
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.compactControlSize
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.searchMode
                    active: root.searchMode
                    sourceComponent: SearchBar {
                        searchQuery: root.currentSearchQuery
                        filterPanelOpen: root.filterPanelOpen
                        onQueryChanged: (query) => root.searchQueryChanged(query)
                        onFilterToggled: root.searchFilterToggled()
                        onSearchClosed: root.searchClosed()
                        onEnterPressed: root.searchEnterPressed()
                        onNavigateDown: root.searchNavigateDown()
                    }
                    onLoaded: {
                        root.syncSearchBarState()
                        item.focusInput()
                    }
                }

                // Restore button (only in trash view)
                HoverRect {
                    width: restoreTrashRow.implicitWidth + 16; height: Theme.controlSize
                    visible: root.isTrashView && !root.searchMode
                    onClicked: root.restoreTrashRequested()
                    Row {
                        id: restoreTrashRow
                        anchors.centerIn: parent
                        spacing: 6
                        IconUndo { anchors.verticalCenter: parent.verticalCenter; size: 16; color: Theme.accent }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Restore"
                            color: Theme.text
                            font.pointSize: Theme.fontNormal
                            font.weight: Font.Medium
                        }
                    }
                }

                // Empty Trash button (only in trash view)
                HoverRect {
                    width: emptyTrashRow.implicitWidth + 16; height: Theme.controlSize
                    visible: root.isTrashView && !root.searchMode
                    onClicked: root.emptyTrashRequested()
                    Row {
                        id: emptyTrashRow
                        anchors.centerIn: parent
                        spacing: 6
                        IconTrash { anchors.verticalCenter: parent.verticalCenter; size: 16; color: Theme.error }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Empty Trash"
                            color: Theme.error
                            font.pointSize: Theme.fontNormal
                            font.weight: Font.Medium
                        }
                    }
                }

                // (D7) The Keyboard-Shortcuts toolbar button was removed — the
                // keyboard shortcut still opens the dialog (Main.qml). The
                // keyboardShortcutsRequested signal is retained for that path.

                Item {
                    visible: root.showWindowControls && root._parsedLayout.right.length > 0
                    width: visible ? 4 : 0
                    height: 1
                }

                // Right-side window controls
                Repeater {
                    model: root.showWindowControls ? root._parsedLayout.right : []
                    delegate: HoverRect {
                        required property string modelData
                        width: Theme.controlSize; height: Theme.controlSize
                        color: modelData === "close" && hovered
                            ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.9)
                            : (hovered ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : "transparent")
                        onClicked: {
                            if (modelData === "close") root.closeRequested()
                            else if (modelData === "minimize") root.minimizeRequested()
                            else if (modelData === "maximize") root.maximizeRequested()
                        }
                        IconX { anchors.centerIn: parent; size: 14; color: parent.modelData === "close" && parent.hovered ? Theme.base : Theme.text; visible: parent.modelData === "close" }
                        IconMinus { anchors.centerIn: parent; size: 14; color: Theme.text; visible: parent.modelData === "minimize" }
                        IconSquare { anchors.centerIn: parent; size: 12; color: Theme.text; visible: parent.modelData === "maximize" }
                    }
                }
            }
        }

        // ── Filter panel (slides in when toggled) ──
        Item {
            Layout.fillWidth: true
                Layout.preferredHeight: root.searchMode && filterPanelLoader.item && filterPanelLoader.item.visible
                    ? filterPanelLoader.item.implicitHeight : 0
            clip: true

            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: Theme.animDuration; easing.type: Theme.animEasingTransition; easing.bezierCurve: Theme.animBezierCurve }
            }

            Loader {
                id: filterPanelLoader
                anchors.fill: parent
                active: root.searchMode
                sourceComponent: FilterPanel {
                    visible: root.filterPanelOpen
                    onTypeFilterChanged: (filter) => root.typeFilterChanged(filter)
                    onDateFilterChanged: (filter) => root.dateFilterChanged(filter)
                    onSizeFilterChanged: (filter) => root.sizeFilterChanged(filter)
                    onClearAllFilters: root.clearAllFilters()
                }
                onLoaded: root.syncFilterPanelState()
            }
        }

    }
}
