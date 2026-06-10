import QtQuick
import QtQuick.Layouts
import Wayfile

// Sidebar region: the animated layout host, the Sidebar widget, and the
// drag-to-resize handle. The sidebar's shared state (visible / width / resize)
// lives on the host (Main.qml) because the toolbar and global shortcuts read
// it; this component reads and writes it through `host`.
//
// The sidebar context menu stays at the host's root level (it is a full-screen
// overlay Item with z: 9999, not a popup, so it must not live inside this
// clipped host) and is passed back in via `sidebarContextMenu`.
Item {
    id: sidebarPane

    // Main.qml root — shared sidebar state + navigation functions.
    property var host: null
    // A stable ancestor used as the coordinate space for resize deltas: the
    // host's own width changes mid-drag, so deltas must be measured against a
    // fixed parent (mainContent), not against this item.
    property var coordSpace: null
    // Root-level singletons/overlays owned by Main.qml, injected by id.
    property var sidebarContextMenu: null
    property var sidebarTooltipLayer: null
    property var toast: null

    Layout.preferredWidth: host ? (host.sidebarVisible ? host.sidebarWidth : 0) : 0
    Layout.fillHeight: true
    clip: true

    Behavior on Layout.preferredWidth {
        enabled: host ? !host.sidebarResizeActive : true
        NumberAnimation { duration: Theme.animDuration; easing.type: Theme.animEasingTransition; easing.bezierCurve: Theme.animBezierCurve }
    }

    function sidebarMenuItems(item) {
        if (!item)
            return withHideEntries(item, [])

        if (item.kind === "quickAccess") {
            if (item.isRecents || item.isHidden)
                return withHideEntries(item, [
                    { text: "Open", shortcut: "", action: "open" }
                ])

            if (fileOps.isTrashPath(item.path))
                return withHideEntries(item, [
                    { text: "Open", shortcut: "Return", action: "open" },
                    { text: "Open in New Tab", shortcut: "", action: "opennewtab" },
                    { text: "Open in Split View", shortcut: "", action: "split_open", icon: "SquareSplitHorizontal" },
                    { separator: true },
                    { text: "Empty Trash", shortcut: "", action: "emptytrash", destructive: true }
                ])

            return withHideEntries(item, [
                { text: "Open", shortcut: "Return", action: "open" },
                { text: "Open in New Tab", shortcut: "", action: "opennewtab" },
                { text: "Open in Split View", shortcut: "", action: "split_open", icon: "SquareSplitHorizontal" },
                { separator: true },
                { text: "Open in Terminal", shortcut: "", action: "terminal" },
                { text: "Properties", shortcut: "", action: "properties" }
            ])
        }

        if (item.kind === "bookmark") {
            return withHideEntries(item, [
                { text: "Open", shortcut: "Return", action: "open" },
                { text: "Open in New Tab", shortcut: "", action: "opennewtab" },
                { text: "Open in Split View", shortcut: "", action: "split_open", icon: "SquareSplitHorizontal" },
                { separator: true },
                { text: "Open in Terminal", shortcut: "", action: "terminal" },
                { text: "Properties", shortcut: "", action: "properties" },
                { separator: true },
                { text: "Remove from Bookmarks", shortcut: "", action: "removebookmark", destructive: true }
            ])
        }

        if (item.kind === "device") {
            if (!item.mounted)
                return withHideEntries(item, [
                    { text: "Mount", shortcut: "", action: "mountdevice" }
                ])

            return withHideEntries(item, [
                { text: "Open", shortcut: "Return", action: "open" },
                { text: "Open in New Tab", shortcut: "", action: "opennewtab" },
                { text: "Open in Split View", shortcut: "", action: "split_open", icon: "SquareSplitHorizontal" },
                { separator: true },
                { text: "Open in Terminal", shortcut: "", action: "terminal" },
                { text: "Properties", shortcut: "", action: "properties" },
                { separator: true },
                { text: "Unmount", shortcut: "", action: "unmountdevice" }
            ])
        }

        return withHideEntries(item, [])
    }

    // W7 per-entry hide: append the "Hide from sidebar" action (only for rows
    // carrying a non-empty entryId — Home and devices carry none, so they are
    // not hideable) and a universal "Show hidden entries (N)" restore affordance
    // whenever anything is hidden. The restore item is added on EVERY sidebar
    // right-click so the user can recover even after hiding the row they'd
    // normally click. `hideSidebarEntry`/`clearHiddenSidebarEntries` persist.
    function withHideEntries(item, baseItems) {
        var items = baseItems.slice()
        var entryId = item ? (item.entryId || "") : ""
        var hiddenCount = config.hiddenSidebarEntries.length

        if (entryId !== "") {
            if (items.length > 0)
                items.push({ separator: true })
            items.push({ text: "Hide from sidebar", shortcut: "", action: "hide-entry", icon: "EyeOff" })
        }

        if (hiddenCount > 0) {
            items.push({ separator: true })
            items.push({ text: "Show hidden entries (" + hiddenCount + ")", shortcut: "", action: "show-hidden", icon: "Eye" })
        }

        return items
    }

    // Gallery mode swaps the sidebar's Places list for a folder navigator, with a
    // Places/Folders toggle on top. Outside Gallery this is the normal sidebar.
    readonly property bool galleryActive:
        tabModel.activeTab ? tabModel.activeTab.viewMode === "gallery" : false
    readonly property bool showFolderNav:
        galleryActive && (host ? host.galleryFolderNavActive : false)

    // Obsidian background for the Gallery sidebar. In Gallery mode the normal
    // Sidebar (which paints its own gradient) is hidden and replaced by the
    // background-less folder tree + toggle, so paint the same obsidian gradient
    // and right hairline here. Outside Gallery this stays hidden and the normal
    // Sidebar paints itself, so nothing double-paints.
    Rectangle {
        anchors.fill: parent
        visible: sidebarPane.galleryActive
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.panel }
            GradientStop { position: 1.0; color: Theme.mantle }
        }
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 2
            color: Theme.divider
        }
    }

    Column {
        id: sidebarStack
        width: host ? host.sidebarWidth : 0
        height: parent.height

        // Places / Folders toggle — only while the Gallery view is active.
        Item {
            id: navToggle
            width: parent.width
            height: sidebarPane.galleryActive ? 34 : 0
            visible: sidebarPane.galleryActive
            clip: true

            Row {
                anchors.centerIn: parent
                spacing: 4

                Rectangle {
                    id: placesSeg
                    width: 74; height: 22; radius: Theme.radiusSmall
                    readonly property bool on: !sidebarPane.showFolderNav
                    color: on ? Theme.gold : "transparent"
                    border.width: 1
                    border.color: on ? Theme.gold : Theme.line
                    Text {
                        anchors.centerIn: parent
                        text: "Places"
                        color: placesSeg.on ? Theme.base : Theme.subtext
                        font.pointSize: Theme.fontSmall
                        font.weight: placesSeg.on ? Font.DemiBold : Font.Normal
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (host) host.galleryFolderNavActive = false
                    }
                }
                Rectangle {
                    id: foldersSeg
                    width: 74; height: 22; radius: Theme.radiusSmall
                    readonly property bool on: sidebarPane.showFolderNav
                    color: on ? Theme.gold : "transparent"
                    border.width: 1
                    border.color: on ? Theme.gold : Theme.line
                    Text {
                        anchors.centerIn: parent
                        text: "Folders"
                        color: foldersSeg.on ? Theme.base : Theme.subtext
                        font.pointSize: Theme.fontSmall
                        font.weight: foldersSeg.on ? Font.DemiBold : Font.Normal
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (host) host.galleryFolderNavActive = true
                    }
                }
            }
        }

        Item {
            id: sidebarContent
            width: parent.width
            height: parent.height - navToggle.height

            Sidebar {
                anchors.fill: parent
                visible: !sidebarPane.showFolderNav
                host: sidebarPane.host
                tooltipLayer: sidebarPane.sidebarTooltipLayer
                currentPath: host ? host.activePanePath : ""
                trashPath: host ? host.unifiedTrashPath : ""
                isRecentsView: host ? host.isRecentsView : false
                isHiddenView: host ? host.isHiddenView : false
                onBookmarkClicked: (path) => {
                    host.navigateActivePaneTo(path)
                }
                onSidebarContextMenuRequested: (item, position) => {
                    sidebarPane.sidebarContextMenu.sidebarItem = item
                    sidebarPane.sidebarContextMenu.contextData = item
                    sidebarPane.sidebarContextMenu.customItems = sidebarPane.sidebarMenuItems(item)
                    sidebarPane.sidebarContextMenu.targetPath = item.path || ""
                    sidebarPane.sidebarContextMenu.targetIsDir = !!item.path
                    sidebarPane.sidebarContextMenu.isEmptySpace = false
                    sidebarPane.sidebarContextMenu.selectedPaths = item.path ? [item.path] : []
                    sidebarPane.sidebarContextMenu.popup(position.x, position.y)
                }
                onRecentsClicked: {
                    host.setPaneRecents(host.activePaneIndex, true)
                }
                onHiddenClicked: {
                    host.setPaneHidden(host.activePaneIndex, true)
                }
                onFeatureHintRequested: (message) => sidebarPane.toast.show(message, "info")
            }

            GalleryFolderNav {
                anchors.fill: parent
                visible: sidebarPane.showFolderNav
                host: sidebarPane.host
            }
        }
    }

    // Drag-to-resize handle on the sidebar's INNER edge (the one facing the
    // content): the right edge when the sidebar is on the left, the left edge
    // when it is on the right. The row's LayoutMirroring no longer cascades
    // into the sidebar (childrenInherit:false), so the edge is selected
    // explicitly by sidebarPosition rather than relying on inherited mirroring.
    //
    // Deltas are measured in coordSpace (mainContent), which is NOT mirrored,
    // so its X always increases left→right. For a right-positioned sidebar the
    // inner edge faces left, so a leftward drag (decreasing X) must grow the
    // sidebar — hence the delta negation keyed on sidebarPosition.
    MouseArea {
        id: sidebarResizeHandle
        readonly property bool sidebarOnRight: config.sidebarPosition === "right"
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: sidebarOnRight ? undefined : parent.right
        anchors.left: sidebarOnRight ? parent.left : undefined
        width: 10
        hoverEnabled: true
        enabled: host ? host.sidebarVisible : false
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.SizeHorCursor
        preventStealing: true
        z: 10

        // Subtle accent line on hover/drag so the resize edge is discoverable.
        Rectangle {
            // Accent sits on the same inner edge as the handle.
            anchors.right: sidebarResizeHandle.sidebarOnRight ? undefined : parent.right
            anchors.left: sidebarResizeHandle.sidebarOnRight ? parent.left : undefined
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 2
            visible: sidebarResizeHandle.containsMouse || sidebarResizeHandle.pressed
            color: Theme.accent
            opacity: sidebarResizeHandle.pressed ? 0.9 : 0.6
        }

        onPressed: (mouse) => {
            host.sidebarResizeActive = true
            host.sidebarResizeStartGlobalX = sidebarResizeHandle.mapToItem(sidebarPane.coordSpace, mouse.x, mouse.y).x
            host.sidebarResizeStartWidth = host.sidebarWidth
            mouse.accepted = true
        }

        onPositionChanged: (mouse) => {
            if (!pressed)
                return
            var globalX = sidebarResizeHandle.mapToItem(sidebarPane.coordSpace, mouse.x, mouse.y).x
            var delta = globalX - host.sidebarResizeStartGlobalX
            if (config.sidebarPosition === "right") delta = -delta
            host.sidebarWidth = host.clampedSidebarWidth(host.sidebarResizeStartWidth + delta)
            mouse.accepted = true
        }

        onReleased: {
            host.sidebarResizeActive = false
            config.saveSidebarWidth(host.sidebarWidth)
        }

        onCanceled: {
            host.sidebarResizeActive = false
            config.saveSidebarWidth(host.sidebarWidth)
        }
    }
}
