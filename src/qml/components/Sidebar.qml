import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import Wayfile
import Quill as Quill

Rectangle {
    id: root
    Accessible.role: Accessible.Pane
    Accessible.name: "Sidebar navigation"

    property var host: null
    property string currentPath: ""
    property string trashPath: fsModel.homePath() + "/.local/share/Trash/files"
    property bool isRecentsView: false
    property bool isHiddenView: false
    property Item tooltipLayer: null
    signal bookmarkClicked(string path)
    signal sidebarContextMenuRequested(var item, point position)
    signal recentsClicked()
    signal hiddenClicked()
    signal featureHintRequested(string message)

    // "Wayfile Unified" sidebar: obsidian vertical gradient + right hairline.
    gradient: Gradient {
        GradientStop { position: 0.0; color: Theme.panel }
        GradientStop { position: 1.0; color: Theme.mantle }
    }
    clip: false

    // Right edge divider separating the sidebar from the content panel. This
    // is the resting line for ALL non-gallery views; SidebarPane's drag handle
    // (z:10, on top of this) adds the accent highlight + resize cursor on hover
    // so the divider doubles as the sidebar's drag-to-resize splitter.
    Rectangle {
        z: 2
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 2
        color: Theme.divider
    }

    // Place/bookmark glyphs default to the muted (text-3) tint; the loaders in
    // each row rebind the color to gold when their row is the active one.
    Component { id: iconHome; IconHome { size: 18; color: Theme.muted } }
    Component { id: iconEyeOff; IconEyeOff { size: 18; color: Theme.muted } }
    Component { id: iconClock; IconClock { size: 18; color: Theme.muted } }
    Component { id: iconTrash; IconTrash { size: 18; color: Theme.muted } }
    Component { id: iconGlobe; IconGlobe { size: 18; color: Theme.muted } }
    Component { id: iconFolder; IconFolder { size: 18; color: Theme.muted } }
    Component { id: iconStarGold; IconStar { size: 11; color: Theme.gold } }

    // Inverse rounded corner — top right
    Shape {
        z: 1; width: Theme.radiusMedium; height: Theme.radiusMedium
        anchors.top: parent.top; anchors.left: parent.right
        ShapePath {
            fillColor: Theme.panel; strokeColor: "transparent"
            startX: 0; startY: 0
            PathLine { x: Theme.radiusMedium; y: 0 }
            PathArc {
                x: 0; y: Theme.radiusMedium
                radiusX: Theme.radiusMedium; radiusY: Theme.radiusMedium
                direction: PathArc.Clockwise
            }
            PathLine { x: 0; y: 0 }
        }
    }

    // Inverse rounded corner — bottom right
    Shape {
        z: 1; width: Theme.radiusMedium; height: Theme.radiusMedium
        anchors.bottom: parent.bottom; anchors.left: parent.right
        ShapePath {
            fillColor: Theme.mantle; strokeColor: "transparent"
            startX: 0; startY: Theme.radiusMedium
            PathLine { x: Theme.radiusMedium; y: Theme.radiusMedium }
            PathArc {
                x: 0; y: 0
                radiusX: Theme.radiusMedium; radiusY: Theme.radiusMedium
                direction: PathArc.Clockwise
            }
            PathLine { x: 0; y: 0 }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Top breathing room — the "Wayfile" wordmark + action icons moved
        // out of the sidebar (#8); the full-width toolbar now sits above this
        // panel, so the list just needs a little padding from the top edge.
        Item {
            Layout.fillWidth: true
            height: Theme.spacing
        }

        // Wayfile section header: FAVORITES — user-curated bookmarks.
        // Drag a folder onto the section to pin it (existing Wayfile logic);
        // the trailing "+" (revealed on header hover) pins the active folder.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing
            Layout.rightMargin: Theme.spacing
            Layout.topMargin: Theme.spacing / 2
            HoverHandler { id: favHeaderHover }
            Text {
                Layout.fillWidth: true
                text: "FAVORITES"
                color: Theme.muted
                font.pointSize: Theme.fontSmall - 1
                font.bold: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.3
            }
            IconPlus {
                id: favAdd
                size: 13
                color: favAddHover.containsMouse ? Theme.gold : Theme.muted
                opacity: favHeaderHover.hovered ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: Theme.animDurationFast } }
                MouseArea {
                    id: favAddHover
                    anchors.fill: parent; anchors.margins: -6
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var p = root.host ? root.host.activePanePath : ""
                        if (p && config.bookmarks.indexOf(p) < 0)
                            config.saveBookmarks(config.bookmarks.concat([p]))
                    }
                }
            }
        }

        // Bookmarks section — drag folders to add, drag items to reorder
        Item {
            id: bookmarksSection
            Layout.fillWidth: true
            implicitHeight: bookmarksList.height

            readonly property int rowHeight: 32
            readonly property bool externalDragActive:
                bookmarkDropArea.containsDrag
                && bookmarkDropArea._extDropIndex >= 0
                && dragCurrentIndex < 0
            readonly property real externalGapHeight: externalDragActive ? rowHeight : 0
            readonly property int externalDropIndex: bookmarkDropArea._extDropIndex

            property int dragCurrentIndex: -1
            property string dragName: ""
            property real dragMouseY: 0
            property string externalDragName: ""
            property real externalDragMouseY: 0

            function dragUrls(data) {
                var urls = data.urls || []
                if ((!urls || urls.length === 0) && data.text)
                    urls = data.text.split("\n").filter(u => u.trim() !== "")
                return urls
            }

            function decodedPath(url) {
                var value = url.toString().replace(/\/$/, "")
                return value.startsWith("file://") ? decodeURIComponent(value.replace("file://", "")) : value
            }

            function displayName(path) {
                if (!path)
                    return ""
                var trimmed = path.replace(/\/$/, "")
                if (trimmed === "")
                    return "/"
                var parts = trimmed.split("/")
                return parts[parts.length - 1] || trimmed
            }

            function updateExternalDrop(drag) {
                var clampedY = Math.max(0, Math.min(drag.y, bookmarks.count * rowHeight))
                bookmarkDropArea._extDropIndex = Math.max(0,
                    Math.min(Math.round(clampedY / rowHeight), bookmarks.count))
                externalDragMouseY = Math.max(0, Math.min(drag.y, bookmarksList.height))

                var urls = dragUrls(drag)
                if (urls.length === 1)
                    externalDragName = displayName(decodedPath(urls[0]))
                else if (urls.length > 1)
                    externalDragName = urls.length + " items"
                else
                    externalDragName = "New bookmark"
            }

            function clearExternalDrop() {
                bookmarkDropArea._extDropIndex = -1
                externalDragName = ""
                externalDragMouseY = 0
            }

            // External drop zone for adding new bookmarks
            DropArea {
                id: bookmarkDropArea
                anchors.fill: parent
                keys: ["text/uri-list"]

                onEntered: (drag) => bookmarksSection.updateExternalDrop(drag)
                onPositionChanged: (drag) => bookmarksSection.updateExternalDrop(drag)
                onExited: bookmarksSection.clearExternalDrop()
                onDropped: (drop) => {
                    var insertAt = bookmarkDropArea._extDropIndex
                    var urls = bookmarksSection.dragUrls(drop)
                    bookmarksSection.clearExternalDrop()
                    for (var i = 0; i < urls.length; i++) {
                        var path = bookmarksSection.decodedPath(urls[i])
                        if (path !== "")
                            bookmarks.insertBookmark(path, insertAt >= 0 ? insertAt : bookmarks.count)
                    }
                    drop.accept()
                }
                property int _extDropIndex: -1
            }

            ListView {
                id: bookmarksList
                width: parent.width
                height: contentHeight + bookmarksSection.externalGapHeight
                interactive: false

                model: bookmarks

                add: Transition {
                    enabled: bookmarksSection.dragCurrentIndex < 0
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve }
                        NumberAnimation { property: "scale"; from: 0.9; to: 1; duration: 250; easing.type: Easing.OutBack; easing.overshoot: 0.6 }
                    }
                }
                move: Transition {
                    NumberAnimation { properties: "x,y"; duration: 150; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve }
                }
                displaced: Transition {
                    NumberAnimation { properties: "x,y"; duration: 150; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve }
                }

                delegate: Item {
                    width: bookmarksList.width
                    height: bookmarksSection.rowHeight

                    Rectangle {
                        id: bmDelegate
                        width: parent.width - Theme.spacing
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: bookmarksSection.rowHeight
                        y: bookmarksSection.externalDragActive && index >= bookmarksSection.externalDropIndex
                            ? bookmarksSection.rowHeight : 0
                        Behavior on y { NumberAnimation { duration: 150; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve } }
                        opacity: bookmarksSection.dragCurrentIndex === index ? 0.35 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        readonly property bool isActive:
                            !root.isRecentsView && !root.isHiddenView && model.path === root.currentPath

                        color: {
                            if (bmInteraction.hoverIndex === index && bookmarksSection.dragCurrentIndex < 0 && !isActive)
                                return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.03)
                            return "transparent"
                        }
                        radius: Theme.radiusRow
                        Behavior on color { ColorAnimation { duration: Theme.animDuration } }

                        // Active: gold-wash → transparent gradient + goldLine ring.
                        Rectangle {
                            visible: bmDelegate.isActive
                            anchors.fill: parent
                            radius: parent.radius
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Theme.goldWash }
                                GradientStop { position: 1.0; color: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.02) }
                            }
                            border.width: 1
                            border.color: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.14)
                        }

                        // Active: 3px gold left bar with glow.
                        Rectangle {
                            visible: bmDelegate.isActive
                            anchors.left: parent.left
                            anchors.leftMargin: -(Theme.spacing / 2)
                            anchors.top: parent.top
                            anchors.topMargin: 5
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 5
                            width: 2
                            color: Theme.gold
                            topRightRadius: 3
                            bottomRightRadius: 3
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                autoPaddingEnabled: true
                                shadowEnabled: true
                                shadowColor: Theme.goldGlow
                                shadowBlur: 0.6
                            }
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacing
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacing

                            Loader {
                                width: 18; height: 18
                                anchors.verticalCenter: parent.verticalCenter
                                sourceComponent: iconFolder
                                onLoaded: item.color = Qt.binding(
                                    () => bmDelegate.isActive ? Theme.gold : Theme.muted)
                            }

                            Text {
                                text: model.name
                                color: bmDelegate.isActive ? Theme.text : Theme.subtext
                                font.pointSize: Theme.fontNormal
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                width: parent.width - 18 - 11 - Theme.spacing * 2
                            }

                            // Favorites carry a decorative trailing gold star.
                            Loader {
                                width: 11; height: 11
                                anchors.verticalCenter: parent.verticalCenter
                                sourceComponent: iconStarGold
                            }
                        }
                    }
                }
            }

            Rectangle {
                visible: bookmarksSection.externalDragActive
                z: 120
                width: bookmarksList.width - Theme.spacing
                height: bookmarksSection.rowHeight
                radius: Theme.radiusSmall
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                border.width: 1
                x: Theme.spacing / 2
                y: Math.max(0,
                            Math.min(bookmarksSection.externalDragMouseY - height / 2,
                                     bookmarksList.height - height))
                opacity: 0.95
                Behavior on y { NumberAnimation { duration: 150; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve } }
                Behavior on opacity { NumberAnimation { duration: 120 } }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacing
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacing

                    Loader {
                        width: 18; height: 18
                        anchors.verticalCenter: parent.verticalCenter
                        sourceComponent: iconFolder
                    }

                    Text {
                        text: bookmarksSection.externalDragName
                        color: Theme.text
                        font.pointSize: Theme.fontNormal
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        width: parent.width - 18 - Theme.spacing
                    }
                }
            }

            // Single MouseArea handles hover, click, and drag for all bookmarks
            MouseArea {
                id: bmInteraction
                anchors.fill: bookmarksList
                z: 100
                hoverEnabled: true
                cursorShape: bookmarksSection.dragCurrentIndex >= 0 ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                property int hoverIndex: -1
                property int pressIndex: -1
                property real pressY: 0
                property bool isDragging: false
                property int pressButton: Qt.NoButton

                function idxAt(y) {
                    return Math.max(0, Math.min(Math.floor(y / bookmarksSection.rowHeight), bookmarks.count - 1))
                }

                onPositionChanged: (mouse) => {
                    hoverIndex = (mouse.y >= 0 && mouse.y < bookmarks.count * bookmarksSection.rowHeight)
                        ? idxAt(mouse.y) : -1

                    if (!pressed) return
                    if (pressButton !== Qt.LeftButton) return
                    if (!isDragging && Math.abs(mouse.y - pressY) > 6 && pressIndex >= 0) {
                        isDragging = true
                        bookmarksSection.dragCurrentIndex = pressIndex
                        bookmarksSection.dragName = bookmarks.data(
                            bookmarks.index(pressIndex, 0), 257 /* NameRole */) || ""
                    }
                    if (isDragging) {
                        bookmarksSection.dragMouseY = mouse.y
                        var target = idxAt(mouse.y)
                        if (target !== bookmarksSection.dragCurrentIndex) {
                            bookmarks.moveBookmark(bookmarksSection.dragCurrentIndex, target)
                            bookmarksSection.dragCurrentIndex = target
                        }
                    }
                }
                onPressed: (mouse) => {
                    pressIndex = idxAt(mouse.y)
                    pressY = mouse.y
                    isDragging = false
                    pressButton = mouse.button
                }
                onReleased: (mouse) => {
                    if (isDragging) {
                        bookmarksSection.dragCurrentIndex = -1
                        isDragging = false
                    } else if (mouse.button === Qt.LeftButton && pressIndex >= 0 && pressIndex < bookmarks.count) {
                        var path = bookmarks.data(
                            bookmarks.index(pressIndex, 0), 258 /* PathRole */) || ""
                        if (path) root.bookmarkClicked(path)
                    }
                    pressIndex = -1
                    pressButton = Qt.NoButton
                }
                onClicked: (mouse) => {
                    if (mouse.button !== Qt.RightButton)
                        return

                    var index = (mouse.y >= 0 && mouse.y < bookmarks.count * bookmarksSection.rowHeight)
                        ? idxAt(mouse.y) : -1
                    if (index < 0 || index >= bookmarks.count)
                        return

                    var path = bookmarks.data(bookmarks.index(index, 0), 258 /* PathRole */) || ""
                    var mapped = bmInteraction.mapToItem(null, mouse.x, mouse.y)
                    root.sidebarContextMenuRequested({
                        kind: "bookmark",
                        index: index,
                        name: bookmarks.data(bookmarks.index(index, 0), 257 /* NameRole */) || "",
                        path: path
                    }, Qt.point(mapped.x, mapped.y))
                }
                onExited: hoverIndex = -1
                onCanceled: {
                    bookmarksSection.dragCurrentIndex = -1
                    isDragging = false
                    pressIndex = -1
                    pressButton = Qt.NoButton
                }
            }

            // Ghost bookmark following cursor
            Rectangle {
                visible: bookmarksSection.dragCurrentIndex >= 0
                z: 200
                width: bookmarksList.width - Theme.spacing
                height: bookmarksSection.rowHeight
                radius: Theme.radiusSmall
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.4)
                border.width: 1
                x: Theme.spacing / 2
                y: Math.max(0,
                            Math.min(bookmarksSection.dragMouseY - height / 2,
                                     bookmarksList.height - height))
                opacity: 0.9

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacing

                    Loader {
                        width: 18; height: 18
                        anchors.verticalCenter: parent.verticalCenter
                        sourceComponent: iconFolder
                    }
                    Text {
                        text: bookmarksSection.dragName
                        color: Theme.text
                        font.pointSize: Theme.fontNormal
                    }
                }
            }
        }

        // Separator between favorites and places
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing
            Layout.rightMargin: Theme.spacing
            height: 1
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
        }

        // Wayfile section header: PLACES — Linux home + common folders + the
        // curated-XDG folder forest below. Quick rows: Home (mono) / Recents /
        // Hidden; Trash + Network moved to their own sections.
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing
            Layout.topMargin: Theme.spacing / 2
            text: "PLACES"
            color: Theme.muted
            font.pointSize: Theme.fontSmall - 1
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.3
        }

        // Quick access section
        Column {
            Layout.fillWidth: true

            // Quick access entries
            Repeater {
                model: ListModel {
                    ListElement { name: "Home"; iconType: "home"; mono: true }
                    ListElement { name: "Recents"; iconType: "clock"; mono: false }
                    ListElement { name: "Hidden"; iconType: "eyeoff"; mono: false }
                }

                delegate: Rectangle {
                    id: quickAccessDelegate

                    readonly property string resolvedPath: {
                        const home = fsModel.homePath()
                        if (model.name === "Home") return home
                        if (model.name === "Hidden") return ""
                        if (model.name === "Recents") return ""
                        return ""
                    }

                    width: parent.width - Theme.spacing
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 32
                    readonly property bool isActive: {
                        if (model.name === "Recents") return root.isRecentsView
                        if (model.name === "Hidden") return root.isHiddenView
                        if (resolvedPath === "") return false
                        return !root.isRecentsView && !root.isHiddenView && resolvedPath === root.currentPath
                    }

                    color: {
                        if (qaHoverArea.containsMouse && !isActive)
                            return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.03)
                        return "transparent"
                    }
                    radius: Theme.radiusRow
                    Behavior on color { ColorAnimation { duration: Theme.animDuration } }

                    // Active: gold-wash → transparent gradient + faint goldLine
                    // inset ring (handoff .sb-item--active).
                    Rectangle {
                        visible: quickAccessDelegate.isActive
                        anchors.fill: parent
                        radius: parent.radius
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Theme.goldWash }
                            GradientStop { position: 1.0; color: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.02) }
                        }
                        border.width: 1
                        border.color: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.14)
                    }

                    // Active: 2px gold left bar with a soft glow, sitting at the
                    // sidebar's left edge (handoff .sb-item--active::before).
                    Rectangle {
                        visible: quickAccessDelegate.isActive
                        anchors.left: parent.left
                        anchors.leftMargin: -(Theme.spacing / 2)
                        anchors.top: parent.top
                        anchors.topMargin: 5
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 5
                        width: 2
                        color: Theme.gold
                        topRightRadius: 3
                        bottomRightRadius: 3
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            autoPaddingEnabled: true
                            shadowEnabled: true
                            shadowColor: Theme.goldGlow
                            shadowBlur: 0.6
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacing
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacing

                        Loader {
                            width: 18; height: 18
                            anchors.verticalCenter: parent.verticalCenter
                            sourceComponent: {
                                if (model.iconType === "home") return iconHome
                                if (model.iconType === "eyeoff") return iconEyeOff
                                if (model.iconType === "clock") return iconClock
                                return iconHome
                            }
                            onLoaded: item.color = Qt.binding(
                                () => quickAccessDelegate.isActive ? Theme.gold : Theme.muted)
                        }

                        Text {
                            text: model.name
                            color: quickAccessDelegate.isActive ? Theme.text : Theme.subtext
                            font.family: model.mono ? Fonts.mono : Qt.application.font.family
                            font.pointSize: Theme.fontNormal
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            width: parent.width - 32 - Theme.spacing
                        }
                    }

                    MouseArea {
                        id: qaHoverArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                var mapped = qaHoverArea.mapToItem(null, mouse.x, mouse.y)
                                root.sidebarContextMenuRequested({
                                    kind: "quickAccess",
                                    name: model.name,
                                    path: quickAccessDelegate.resolvedPath,
                                    isRecents: model.name === "Recents",
                                    isHidden: model.name === "Hidden"
                                }, Qt.point(mapped.x, mapped.y))
                                return
                            }

                            if (model.name === "Recents")
                                root.recentsClicked()
                            else if (model.name === "Hidden")
                                root.hiddenClicked()
                            else
                                root.bookmarkClicked(quickAccessDelegate.resolvedPath)
                        }
                    }
                }
            }
        }

        // Expandable curated-XDG folder forest (Desktop/Documents/… each a tree).
        SidebarPlacesTree {
            Layout.fillWidth: true
            host: root.host
        }

        // Separator between places and devices
        Rectangle {
            visible: devicesSection.visible
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing
            Layout.rightMargin: Theme.spacing
            height: 1
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
        }

        // Auto-navigate after mounting an unmounted device
        Connections {
            target: devices
            function onDeviceMounted(mountPoint) {
                root.bookmarkClicked(mountPoint)
            }
        }

        // Wayfile section header: DEVICES — mount points and USB.
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing
            Layout.topMargin: Theme.spacing / 2
            text: "DEVICES"
            color: Theme.muted
            font.pointSize: Theme.fontSmall - 1
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.3
            visible: devicesSection.visible
        }

        // Devices section
        Column {
            id: devicesSection
            Layout.fillWidth: true

            Repeater {
                model: devices

                delegate: SidebarDeviceRow {
                    tooltipLayer: root.tooltipLayer
                    sidebarWidth: root.width
                    onContextMenuRequested: (item, position) => root.sidebarContextMenuRequested(item, position)
                    onBookmarkClicked: (path) => root.bookmarkClicked(path)
                    onFeatureHintRequested: (message) => root.featureHintRequested(message)
                }
            }
        }

        // Separator above NETWORK — always visible: Network is a permanent,
        // always-reachable entry (network:///), so it always needs a divider
        // above it. (Unlike the devices separator, which hides with devices.)
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing
            Layout.rightMargin: Theme.spacing
            height: 1
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
        }

        // Wayfile section header: NETWORK — remote/virtual locations.
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing
            Layout.topMargin: Theme.spacing / 2
            text: "NETWORK"
            color: Theme.muted
            font.pointSize: Theme.fontSmall - 1
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.3
        }

        // Network section — single entry navigating to network:/// (gvfs mounts).
        Column {
            Layout.fillWidth: true

            Repeater {
                model: ListModel {
                    ListElement { name: "Network"; iconType: "globe" }
                }

                delegate: Rectangle {
                    id: networkDelegate

                    width: parent.width - Theme.spacing
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 32
                    readonly property bool isActive:
                        !root.isRecentsView && !root.isHiddenView && fileOps.isRemotePath(root.currentPath)

                    color: {
                        if (networkHoverArea.containsMouse && !isActive)
                            return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.03)
                        return "transparent"
                    }
                    radius: Theme.radiusRow
                    Behavior on color { ColorAnimation { duration: Theme.animDuration } }

                    // Active: gold-wash → transparent gradient + faint goldLine ring.
                    Rectangle {
                        visible: networkDelegate.isActive
                        anchors.fill: parent
                        radius: parent.radius
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Theme.goldWash }
                            GradientStop { position: 1.0; color: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.02) }
                        }
                        border.width: 1
                        border.color: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.14)
                    }

                    // Active: 2px gold left bar with a soft glow.
                    Rectangle {
                        visible: networkDelegate.isActive
                        anchors.left: parent.left
                        anchors.leftMargin: -(Theme.spacing / 2)
                        anchors.top: parent.top
                        anchors.topMargin: 5
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 5
                        width: 2
                        color: Theme.gold
                        topRightRadius: 3
                        bottomRightRadius: 3
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            autoPaddingEnabled: true
                            shadowEnabled: true
                            shadowColor: Theme.goldGlow
                            shadowBlur: 0.6
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacing
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacing

                        Loader {
                            width: 18; height: 18
                            anchors.verticalCenter: parent.verticalCenter
                            sourceComponent: iconGlobe
                            onLoaded: item.color = Qt.binding(
                                () => networkDelegate.isActive ? Theme.gold : Theme.muted)
                        }

                        Text {
                            text: model.name
                            color: networkDelegate.isActive ? Theme.text : Theme.subtext
                            font.pointSize: Theme.fontNormal
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            width: parent.width - 32 - Theme.spacing
                        }
                    }

                    MouseArea {
                        id: networkHoverArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                var mapped = networkHoverArea.mapToItem(null, mouse.x, mouse.y)
                                root.sidebarContextMenuRequested({
                                    kind: "quickAccess",
                                    name: "Network",
                                    path: "network:///",
                                    isRecents: false,
                                    isHidden: false
                                }, Qt.point(mapped.x, mapped.y))
                                return
                            }
                            root.bookmarkClicked("network:///")
                        }
                    }
                }
            }
        }

        // Spacer pushes operations bar to bottom
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        // Trash — pinned at the very bottom, with a mono item-count chip.
        Rectangle {
            id: trashRow
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing / 2
            Layout.rightMargin: Theme.spacing / 2
            Layout.bottomMargin: Theme.spacing / 2
            height: 32
            radius: Theme.radiusRow
            readonly property bool isActive:
                !root.isRecentsView && !root.isHiddenView && fileOps.isTrashPath(root.currentPath)
            color: trashHover.containsMouse && !isActive
                   ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.03) : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.animDuration } }

            // Active: gold-wash → transparent gradient + faint goldLine ring.
            Rectangle {
                visible: trashRow.isActive
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Theme.goldWash }
                    GradientStop { position: 1.0; color: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.02) }
                }
                border.width: 1
                border.color: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.14)
            }

            // Active: 2px gold left bar with a soft glow.
            Rectangle {
                visible: trashRow.isActive
                anchors.left: parent.left
                anchors.leftMargin: -(Theme.spacing / 2)
                anchors.top: parent.top
                anchors.topMargin: 5
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                width: 2
                color: Theme.gold
                topRightRadius: 3
                bottomRightRadius: 3
                layer.enabled: true
                layer.effect: MultiEffect {
                    autoPaddingEnabled: true
                    shadowEnabled: true
                    shadowColor: Theme.goldGlow
                    shadowBlur: 0.6
                }
            }

            Row {
                anchors.left: parent.left; anchors.leftMargin: Theme.spacing
                anchors.right: parent.right; anchors.rightMargin: Theme.spacing
                anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spacing
                Loader {
                    width: 18; height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: iconTrash
                    onLoaded: item.color = Qt.binding(() => trashRow.isActive ? Theme.gold : Theme.muted)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter; text: "Trash"
                    color: trashRow.isActive ? Theme.text : Theme.subtext
                    font.pointSize: Theme.fontNormal
                    elide: Text.ElideRight
                    width: parent.width - 18 - Theme.spacing * 2 - 24
                }
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: Theme.spacing
                anchors.verticalCenter: parent.verticalCenter
                visible: fsModel.trashEntryCount > 0
                text: fsModel.trashEntryCount
                font.family: Fonts.mono; font.pointSize: Theme.fontSmall
                color: Theme.muted
            }
            MouseArea {
                id: trashHover; anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (m) => {
                    if (m.button === Qt.RightButton) {
                        var p = trashHover.mapToItem(null, m.x, m.y)
                        root.sidebarContextMenuRequested({
                            kind: "quickAccess", name: "Trash",
                            path: root.trashPath, isRecents: false, isHidden: false
                        }, Qt.point(p.x, p.y))
                        return
                    }
                    root.bookmarkClicked(root.trashPath)
                }
            }
        }

        // File operations progress bar
        OperationsBar {
            Layout.fillWidth: true
        }
    }
}
