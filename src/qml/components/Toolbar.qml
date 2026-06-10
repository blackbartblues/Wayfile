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
    property alias filterPanel: filterPanelLoader.item

    function startEditing() {
        if (!searchMode) breadcrumb.startEditing()
    }

    function syncFilterPanelState() {
        if (!filterPanelLoader.item)
            return

        filterPanelLoader.item.visible = filterPanelOpen
        filterPanelLoader.item.applyState(searchTypeFilter, searchDateFilter, searchSizeFilter)
    }

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
    signal refreshRequested()
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

    // 1px bottom border separating the toolbar from the content below (handoff --h-border-soft #2A2E33).
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.lineSoft
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
                anchors.leftMargin: Theme.spacing + 4   // 12px row padding (handoff .h-toolbar)
                anchors.rightMargin: Theme.spacing + 4
                spacing: 6                               // handoff .h-toolbar gap

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

                // ── Nav cluster (handoff order: Back · Fwd · Up · Refresh) ──
                // Arrows (not chevrons) drawn inline via NavArrow — the icons
                // dir is a no-push submodule with no arrow glyphs.
                // Back button
                HoverRect {
                    width: Theme.compactControlSize; height: Theme.compactControlSize
                    radius: Theme.radiusButton
                    hoverEnabled: root.canGoBack
                    opacity: hoverEnabled ? 1.0 : 0.4
                    onClicked: root.backRequested()
                    NavArrow { anchors.centerIn: parent; direction: "left"; size: 15; color: Theme.text }
                    Q.Tooltip { text: "Back"; visible: parent.hovered }
                }

                // Forward button
                HoverRect {
                    width: Theme.compactControlSize; height: Theme.compactControlSize
                    radius: Theme.radiusButton
                    hoverEnabled: root.canGoForward
                    opacity: hoverEnabled ? 1.0 : 0.4
                    onClicked: root.forwardRequested()
                    NavArrow { anchors.centerIn: parent; direction: "right"; size: 15; color: Theme.text }
                    Q.Tooltip { text: "Forward"; visible: parent.hovered }
                }

                // Up button
                HoverRect {
                    width: Theme.compactControlSize; height: Theme.compactControlSize
                    radius: Theme.radiusButton
                    hoverEnabled: !root.isRecentsView && !root.isHiddenView
                    opacity: hoverEnabled ? 1.0 : 0.4
                    onClicked: root.upRequested()
                    NavArrow { anchors.centerIn: parent; direction: "up"; size: 15; color: Theme.text }
                    Q.Tooltip { text: "Up"; visible: parent.hovered }
                }

                // Refresh button (W8 — reloads the active pane's model)
                HoverRect {
                    id: refreshBtn
                    width: Theme.compactControlSize; height: Theme.compactControlSize
                    radius: Theme.radiusButton
                    onClicked: root.refreshRequested()
                    IconRefreshCw { anchors.centerIn: parent; size: 14; color: Theme.text }
                    Q.Tooltip { text: "Refresh"; visible: refreshBtn.hovered }
                }

                // Separator: nav cluster | new-folder/merge group
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 4; Layout.rightMargin: 4
                    width: 1; height: 18
                    color: Theme.line
                }

                // ── New Folder · Merge group ──
                HoverRect {
                    id: newFolderBtn
                    width: Theme.compactControlSize; height: Theme.compactControlSize
                    radius: Theme.radiusButton
                    visible: !root.isTrashView
                    onClicked: root.newFolderRequested()
                    IconFolder { anchors.centerIn: parent; size: 16; color: Theme.text }
                    IconPlus {
                        anchors.right: parent.right; anchors.bottom: parent.bottom
                        anchors.rightMargin: 6; anchors.bottomMargin: 6
                        size: 11; color: Theme.accent
                    }
                    Q.Tooltip { text: "New folder"; visible: newFolderBtn.hovered }
                }

                // Signature merge action. Idle = gold-wash + goldLine border +
                // gold link glyph (handoff .iconbtn--gold). Armed (the active
                // tab is a supertab / a merge is pending) = solid gold gradient
                // + dark glyph + gold glow (handoff .iconbtn--armed).
                HoverRect {
                    id: mergeBtn
                    width: Theme.compactControlSize; height: Theme.compactControlSize
                    radius: Theme.radiusButton
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
                        width: 16; height: 16
                        visible: !root.mergeWillUnmerge
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            // dark glyph on the bright armed gradient; gold glyph
                            // on the subtle idle gold-wash (matches handoff).
                            strokeColor: root.mergeOn ? Theme.goldInk : Theme.gold
                            strokeWidth: Math.max(1, 16 / 12)
                            fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                            scale: Qt.size(16 / 24, 16 / 24)
                            PathSvg { path: "M10.4 13.6a4 4 0 0 0 6 .43l2.2-2.2a4 4 0 0 0-5.66-5.66l-1.26 1.25" }
                        }
                        ShapePath {
                            // dark glyph on the bright armed gradient; gold glyph
                            // on the subtle idle gold-wash (matches handoff).
                            strokeColor: root.mergeOn ? Theme.goldInk : Theme.gold
                            strokeWidth: Math.max(1, 16 / 12)
                            fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                            scale: Qt.size(16 / 24, 16 / 24)
                            PathSvg { path: "M13.6 10.4a4 4 0 0 0-6-.43l-2.2 2.2a4 4 0 0 0 5.66 5.66l1.25-1.25" }
                        }
                    }
                    IconUnlink { anchors.centerIn: parent; size: 16; color: Theme.goldInk; visible:  root.mergeWillUnmerge }
                    Q.Tooltip { text: root.mergeTooltip; visible: mergeBtn.hovered && root.mergeTooltip.length > 0 }
                }

                // Separator: new-folder/merge group | breadcrumb
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 4; Layout.rightMargin: 4
                    width: 1; height: 18
                    color: Theme.line
                }

                // ── Breadcrumb / address bar (always visible — search no longer
                //    swaps it out; results render in the content area while the
                //    breadcrumb stays put, handoff toolbar order). ──
                Breadcrumb {
                    id: breadcrumb
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    path: root.navigationPath
                    activeTab: root.activeTab
                    isRecentsView: root.isRecentsView
                    isHiddenView: root.isHiddenView
                    onNavigateRequested: (targetPath) => root.navigateRequested(targetPath)
                }

                // Restore button (only in trash view)
                HoverRect {
                    width: restoreTrashRow.implicitWidth + 16; height: Theme.compactControlSize
                    radius: Theme.radiusButton
                    visible: root.isTrashView
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
                    width: emptyTrashRow.implicitWidth + 16; height: Theme.compactControlSize
                    radius: Theme.radiusButton
                    visible: root.isTrashView
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

                // Separator: breadcrumb | search box
                Rectangle {
                    visible: !root.isTrashView && !root.isRemoteView
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 4; Layout.rightMargin: 4
                    width: 1; height: 18
                    color: Theme.line
                }

                // ── Always-visible search box (240×30, handoff .h-search).
                //    Typing drives the existing per-pane search backend: a
                //    non-empty query activates search (results render in the
                //    content area while the breadcrumb stays visible); clearing
                //    the box / Esc closes it. The old full-width SearchBar swap
                //    and the standalone toggle button are gone. ──
                Rectangle {
                    id: searchBox
                    visible: !root.isTrashView && !root.isRemoteView
                    Layout.preferredWidth: 240
                    Layout.preferredHeight: 30
                    Layout.alignment: Qt.AlignVCenter
                    radius: Theme.radiusButton
                    color: Theme.crust
                    border.width: 1
                    border.color: searchInput.activeFocus ? Theme.goldLine : Theme.lineSoft

                    // subtle inset top shadow (handoff box-shadow: inset 0 1px 2px)
                    Rectangle {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 1
                        height: 1; radius: 1
                        color: Qt.rgba(0, 0, 0, 0.4)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 6

                        IconSearch {
                            Layout.alignment: Qt.AlignVCenter
                            size: 14
                            color: searchInput.activeFocus || searchInput.text.length > 0 ? Theme.text : Theme.subtext
                        }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            color: Theme.text
                            font.pointSize: Theme.fontNormal
                            selectionColor: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.35)
                            selectedTextColor: Theme.text
                            // No `text:` binding — the box owns its own text and
                            // pushes it to the backend on edit. External resets
                            // (pane switch / closeSearch elsewhere) flow back in
                            // via the Connections below, guarded so an echo of
                            // the user's own keystroke never clobbers the cursor.
                            property bool _internalEdit: false
                            onTextEdited: {
                                _internalEdit = true
                                if (text.length > 0) {
                                    // Activate search (no-op if already on) then push
                                    // the query through the existing backend.
                                    if (!root.searchMode)
                                        root.searchClicked()
                                    root.searchQueryChanged(text)
                                } else {
                                    root.searchClosed()
                                }
                                _internalEdit = false
                            }
                            Keys.onEscapePressed: {
                                searchInput.text = ""
                                root.searchClosed()
                                searchInput.focus = false
                            }
                            Keys.onReturnPressed: root.searchEnterPressed()
                            Keys.onEnterPressed: root.searchEnterPressed()
                            Keys.onDownPressed: root.searchNavigateDown()

                            // Mirror external query changes (pane switch, programmatic
                            // close) into the box without disturbing live typing.
                            Connections {
                                target: root
                                function onCurrentSearchQueryChanged() {
                                    if (!searchInput._internalEdit
                                        && searchInput.text !== root.currentSearchQuery)
                                        searchInput.text = root.currentSearchQuery
                                }
                            }

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: searchInput.text.length === 0
                                text: "Search current folder"
                                color: Theme.subtext
                                font: searchInput.font
                                elide: Text.ElideRight
                            }
                        }

                        // Filter chip — keeps the FilterPanel reachable now that
                        // the old SearchBar (which hosted the filter toggle) is
                        // gone. Highlighted while the panel is open.
                        HoverRect {
                            Layout.alignment: Qt.AlignVCenter
                            width: 22; height: 22
                            radius: Theme.radiusSmall
                            color: root.filterPanelOpen
                                ? Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.16)
                                : (hovered ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : "transparent")
                            onClicked: root.searchFilterToggled()
                            IconSlidersH {
                                anchors.centerIn: parent
                                size: 13
                                color: root.filterPanelOpen ? Theme.gold : Theme.subtext
                            }
                        }

                    }
                }

                // ── Settings (standalone toolbar button, far right). The old
                //    ⋯More overflow was removed; sidebar collapse now lives on
                //    the sidebar itself. ──
                HoverRect {
                    id: settingsBtn
                    width: Theme.compactControlSize; height: Theme.compactControlSize
                    radius: Theme.radiusButton
                    onClicked: root.settingsRequested()
                    IconSettings {
                        anchors.centerIn: parent
                        size: 16
                        color: settingsBtn.hovered ? Theme.text : Theme.subtext
                    }
                    Q.Tooltip { text: "Settings"; visible: settingsBtn.hovered }
                }

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
