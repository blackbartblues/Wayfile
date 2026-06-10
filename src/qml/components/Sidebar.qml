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

    // Per-entry hide (W7): convenience flags for the Network/Trash sections,
    // whose header (Network) or whole row (Trash) must collapse with their id.
    readonly property bool networkHidden: config.hiddenSidebarEntries.indexOf("network") >= 0
    readonly property bool trashHidden: config.hiddenSidebarEntries.indexOf("trash") >= 0
    // W8: the Network section enumerates live GVFS network mounts and hides
    // entirely (header + separator + rows) when there are none (or it's hidden).
    readonly property bool networkSectionVisible: !networkHidden && networkModel.count > 0
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
    Component { id: iconHome; IconHome { size: 16; color: Theme.muted } }
    Component { id: iconEyeOff; IconEyeOff { size: 16; color: Theme.muted } }
    Component { id: iconClock; IconClock { size: 16; color: Theme.muted } }
    Component { id: iconTrash; IconTrash { size: 16; color: Theme.muted } }
    Component { id: iconGlobe; IconGlobe { size: 16; color: Theme.muted } }
    // W8: inline "network" glyph (Lucide network: three nodes + a connecting
    // bus) for the Network section. icons/ is a no-push submodule, so it lives
    // here in the main repo rather than as a new IconNetwork.qml.
    Component {
        id: iconNetwork
        Shape {
            id: netShape
            property real size: 16
            property color color: Theme.muted
            property real strokeWidth: Math.max(1, size / 12)
            width: size; height: size
            preferredRendererType: Shape.CurveRenderer
            // Three node boxes.
            ShapePath {
                strokeColor: netShape.color; strokeWidth: netShape.strokeWidth
                fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(netShape.size / 24, netShape.size / 24)
                PathSvg { path: "M9 2 H15 V8 H9 Z M2 16 H8 V22 H2 Z M16 16 H22 V22 H16 Z" }
            }
            // Connecting bus: centre drop, horizontal trunk, two leg drops.
            ShapePath {
                strokeColor: netShape.color; strokeWidth: netShape.strokeWidth
                fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(netShape.size / 24, netShape.size / 24)
                PathSvg { path: "M12 8 V12 M5 12 H19 M5 12 V16 M19 12 V16" }
            }
        }
    }
    Component { id: iconFolder; IconFolder { size: 16; color: Theme.muted } }
    Component { id: iconStarGold; IconStar { size: 11; color: Theme.gold } }
    // W8: FILLED star for the Favorites leading icon. IconStar (submodule) is a
    // stroke-only outline, so we inline a solid-fill variant here (same Lucide
    // path) — its `color` is rebound per-row to the bookmark's chosen color, or
    // Theme.gold by default. Keep this in the main repo; do not edit icons/.
    Component {
        id: iconStarFilled
        Shape {
            id: starShape
            property real size: 14
            property color color: Theme.gold
            width: size; height: size
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"; strokeWidth: 0
                fillColor: starShape.color
                joinStyle: ShapePath.RoundJoin
                scale: Qt.size(starShape.size / 24, starShape.size / 24)
                PathSvg { path: "M11.525 2.295a.53.53 0 0 1 .95 0l2.31 4.679a.53.53 0 0 0 .4.29l5.16.753a.53.53 0 0 1 .294.904l-3.733 3.638a.53.53 0 0 0-.152.469l.882 5.14a.53.53 0 0 1-.77.56l-4.614-2.426a.53.53 0 0 0-.494 0L7.14 18.728a.53.53 0 0 1-.77-.56l.882-5.14a.53.53 0 0 0-.152-.47L3.367 8.92a.53.53 0 0 1 .294-.905l5.16-.752a.53.53 0 0 0 .4-.29z" }
            }
        }
    }
    // Per-place icons for XDG roots in the compact rail (matching SidebarPlacesTree).
    Component { id: iconMonitor;  IconMonitor  { size: 16; color: Theme.muted } }
    Component { id: iconFileText; IconFileText { size: 16; color: Theme.muted } }
    Component { id: iconDownload; IconDownload { size: 16; color: Theme.muted } }
    Component { id: iconImage;    IconImage    { size: 16; color: Theme.muted } }
    Component { id: iconMusic;    IconMusic    { size: 16; color: Theme.muted } }
    Component { id: iconVideo;    IconVideo    { size: 16; color: Theme.muted } }

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

    // W7: full sidebar — only rendered in Full mode. In Compact mode the sibling
    // icon rail below replaces it.
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        visible: !(root.host && root.host.sidebarCompact)

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
            Layout.leftMargin: 14
            Layout.rightMargin: Theme.spacing
            Layout.topMargin: 12
            Layout.bottomMargin: 4
            HoverHandler { id: favHeaderHover }
            Text {
                Layout.fillWidth: true
                text: "FAVORITES"
                color: Theme.muted
                font.pointSize: Theme.fontSection
                font.weight: Font.DemiBold
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

            readonly property int rowHeight: 28
            readonly property bool externalDragActive:
                bookmarkDropArea.containsDrag
                && bookmarkDropArea._extDropIndex >= 0
                && dragCurrentIndex < 0
            readonly property real externalGapHeight: externalDragActive ? rowHeight : 0
            readonly property int externalDropIndex: bookmarkDropArea._extDropIndex

            // Per-entry hide (W7): a bookmark's path is its stable entryId. Hidden
            // bookmarks collapse their row to height 0, so the click/drag grid must
            // operate over the VISIBLE subset only. `visibleIndices` maps a packed
            // visible row position → the real BookmarkModel index; the helpers below
            // translate between the two so the fixed-row math stays correct while
            // mid-list rows are hidden. The binding re-runs on hidden-list change.
            readonly property var visibleIndices: {
                var hidden = config.hiddenSidebarEntries
                var n = bookmarks.count // force dependency registration even when n === 0
                var out = []
                for (var i = 0; i < n; i++) {
                    var p = bookmarks.data(bookmarks.index(i, 0), 258 /* PathRole */) || ""
                    if (hidden.indexOf(p) < 0)
                        out.push(i)
                }
                return out
            }
            readonly property int visibleCount: visibleIndices.length

            // Packed visible row → real model index (or -1 when out of range).
            function modelIndexOf(visibleRow) {
                if (visibleRow < 0 || visibleRow >= visibleIndices.length)
                    return -1
                return visibleIndices[visibleRow]
            }

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
                // Clamp + snap against the VISIBLE grid (mirrors idxAt), then translate
                // the visible row to a real model INSERTION index. When nothing is
                // hidden, visibleCount === bookmarks.count and this reduces to the old
                // math (round(clampedY/rowHeight) clamped to bookmarks.count).
                var clampedY = Math.max(0, Math.min(drag.y, visibleCount * rowHeight))
                var vr = Math.max(0, Math.min(Math.round(clampedY / rowHeight), visibleCount))
                var insertAt
                if (vr >= visibleCount) {
                    insertAt = bookmarks.count // append at end
                } else {
                    insertAt = modelIndexOf(vr) // insert before that visible row
                    if (insertAt < 0)
                        insertAt = bookmarks.count
                }
                bookmarkDropArea._extDropIndex = insertAt
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
                    // Hidden bookmarks (path in hiddenSidebarEntries) collapse to 0
                    // so ListView packs the visible ones contiguously; the MouseArea
                    // grid math runs over `visibleIndices` to stay aligned.
                    readonly property bool entryHidden:
                        config.hiddenSidebarEntries.indexOf(model.path) >= 0
                    visible: !entryHidden
                    height: entryHidden ? 0 : bookmarksSection.rowHeight

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
                            anchors.leftMargin: 16
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            // W8: filled star in the bookmark's chosen color
                            // (or accent gold by default). The trailing pin star
                            // below is unchanged.
                            Loader {
                                width: 14; height: 14
                                anchors.verticalCenter: parent.verticalCenter
                                sourceComponent: iconStarFilled
                                onLoaded: {
                                    item.size = 14
                                    item.color = Qt.binding(() =>
                                        (model.color && model.color.length > 0)
                                            ? model.color : Theme.gold)
                                }
                            }

                            Text {
                                text: model.name
                                color: bmDelegate.isActive ? Theme.text : Theme.subtext
                                font.pointSize: Theme.fontNormal
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                width: parent.width - 14 - 11 - 10 - Theme.spacing
                            }

                            // Favorites carry a decorative trailing gold star
                            // (the pin/unpin affordance — left untouched by W8).
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

                // Map a y within the (packed, visible-only) bookmark grid to the
                // real BookmarkModel index. Returns -1 if there are no visible rows.
                function idxAt(y) {
                    var n = bookmarksSection.visibleCount
                    if (n <= 0)
                        return -1
                    var visRow = Math.max(0, Math.min(Math.floor(y / bookmarksSection.rowHeight), n - 1))
                    return bookmarksSection.modelIndexOf(visRow)
                }

                onPositionChanged: (mouse) => {
                    hoverIndex = (mouse.y >= 0 && mouse.y < bookmarksSection.visibleCount * bookmarksSection.rowHeight)
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

                    var index = (mouse.y >= 0 && mouse.y < bookmarksSection.visibleCount * bookmarksSection.rowHeight)
                        ? idxAt(mouse.y) : -1
                    if (index < 0 || index >= bookmarks.count)
                        return

                    var path = bookmarks.data(bookmarks.index(index, 0), 258 /* PathRole */) || ""
                    var mapped = bmInteraction.mapToItem(null, mouse.x, mouse.y)
                    root.sidebarContextMenuRequested({
                        kind: "bookmark",
                        index: index,
                        name: bookmarks.data(bookmarks.index(index, 0), 257 /* NameRole */) || "",
                        path: path,
                        // A bookmark's own path is its stable hide id (W7).
                        entryId: path
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
            Layout.leftMargin: 14
            Layout.topMargin: 12
            Layout.bottomMargin: 4
            text: "PLACES"
            color: Theme.muted
            font.pointSize: Theme.fontSection
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.3
        }

        // Quick access section
        Column {
            Layout.fillWidth: true

            // Quick access entries
            Repeater {
                model: ListModel {
                    // Home carries no entryId and is never hideable. Recents and
                    // Hidden each get a stable id so the hidden-entries filter +
                    // "Hide from sidebar" action can target them individually.
                    ListElement { name: "Home"; iconType: "home"; mono: true; entryId: "" }
                    ListElement { name: "Recents"; iconType: "clock"; mono: false; entryId: "places.recents" }
                    ListElement { name: "Hidden"; iconType: "eyeoff"; mono: false; entryId: "places.hidden" }
                }

                delegate: Rectangle {
                    id: quickAccessDelegate

                    // Home (entryId "") is always visible; the rest collapse when
                    // their id is in the persisted hidden-entries list.
                    visible: model.entryId === ""
                             || config.hiddenSidebarEntries.indexOf(model.entryId) < 0
                    height: visible ? 28 : 0

                    readonly property string resolvedPath: {
                        const home = fsModel.homePath()
                        if (model.name === "Home") return home
                        if (model.name === "Hidden") return ""
                        if (model.name === "Recents") return ""
                        return ""
                    }

                    width: parent.width - Theme.spacing
                    anchors.horizontalCenter: parent.horizontalCenter
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
                        anchors.leftMargin: 16
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Loader {
                            width: 16; height: 16
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
                            width: parent.width - 16 - 10 - Theme.spacing
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
                                    isHidden: model.name === "Hidden",
                                    entryId: model.entryId
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
            id: placesTree
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
            Layout.leftMargin: 14
            Layout.topMargin: 12
            Layout.bottomMargin: 4
            text: "DEVICES"
            color: Theme.muted
            font.pointSize: Theme.fontSection
            font.weight: Font.DemiBold
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

        // Separator above NETWORK — hidden with the whole section when there
        // are no live network mounts (or it's hidden via W7 per-entry hide).
        Rectangle {
            visible: root.networkSectionVisible
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing
            Layout.rightMargin: Theme.spacing
            height: 1
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
        }

        // Wayfile section header: NETWORK — live GVFS network mounts (W8).
        Text {
            visible: root.networkSectionVisible
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.topMargin: 12
            Layout.bottomMargin: 4
            text: "NETWORK"
            color: Theme.muted
            font.pointSize: Theme.fontSection
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.3
        }

        // Network section — one row per live GVFS network mount (sftp/smb/nfs/…),
        // enumerated by NetworkLocationModel. Click navigates to the mount URI;
        // the whole section hides when the model is empty (W8).
        Column {
            Layout.fillWidth: true
            visible: root.networkSectionVisible

            Repeater {
                model: networkModel

                delegate: Rectangle {
                    id: networkDelegate
                    readonly property string entryName: model.name
                    readonly property string entryUri: model.uri

                    width: parent.width - Theme.spacing
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 28
                    readonly property bool isActive:
                        !root.isRecentsView && !root.isHiddenView
                        && root.currentPath.length > 0
                        && (root.currentPath === entryUri
                            || root.currentPath.indexOf(entryUri) === 0)

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
                        anchors.leftMargin: 16
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Loader {
                            width: 16; height: 16
                            anchors.verticalCenter: parent.verticalCenter
                            sourceComponent: iconNetwork
                            onLoaded: item.color = Qt.binding(
                                () => networkDelegate.isActive ? Theme.gold : Theme.muted)
                        }

                        Text {
                            text: networkDelegate.entryName
                            color: networkDelegate.isActive ? Theme.text : Theme.subtext
                            font.pointSize: Theme.fontNormal
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            width: parent.width - 16 - 10 - Theme.spacing
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
                                    name: networkDelegate.entryName,
                                    path: networkDelegate.entryUri,
                                    isRecents: false,
                                    isHidden: false,
                                    entryId: "network"
                                }, Qt.point(mapped.x, mapped.y))
                                return
                            }
                            root.bookmarkClicked(networkDelegate.entryUri)
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
        // Hide-from-sidebar (W7): "trash" id; ColumnLayout drops it when hidden.
        Rectangle {
            id: trashRow
            visible: !root.trashHidden
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing / 2
            Layout.rightMargin: Theme.spacing / 2
            Layout.bottomMargin: Theme.spacing / 2
            height: 28
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
                anchors.left: parent.left; anchors.leftMargin: 16
                anchors.right: parent.right; anchors.rightMargin: Theme.spacing
                anchors.verticalCenter: parent.verticalCenter; spacing: 10
                Loader {
                    width: 16; height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: iconTrash
                    onLoaded: item.color = Qt.binding(() => trashRow.isActive ? Theme.gold : Theme.muted)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter; text: "Trash"
                    color: trashRow.isActive ? Theme.text : Theme.subtext
                    font.pointSize: Theme.fontNormal
                    elide: Text.ElideRight
                    width: parent.width - 16 - 10 - Theme.spacing - 24
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
                            path: root.trashPath, isRecents: false, isHidden: false,
                            entryId: "trash"
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

    // ── W7 COMPACT RAIL ──────────────────────────────────────────────────────
    // 56px icon-only column shown when the sidebar is in Compact mode. Renders
    // the top-level visible entries (Favorites star · Home · Recents · Hidden ·
    // each existing XDG root · each mounted/known device · Network · Trash) as
    // centred icon buttons with hover tooltips, active state, and navigation
    // wired to the SAME handlers as the full rows. Respects the same hide filter.
    readonly property bool compactMode: root.host && root.host.sidebarCompact

    // Fixed width of the compact icon rail (icon column / Flickable / each button).
    readonly property int compactRailWidth: 56

    // XDG-existence checks reuse SidebarPlacesTree's already-resident
    // FolderTreeModel (placesTree.folderModel) — no second QFileSystemModel.

    readonly property var compactXdgRoots: {
        const home = fsModel.homePath()
        return [
            { label: "Desktop",   dir: home + "/Desktop"   },
            { label: "Documents", dir: home + "/Documents" },
            { label: "Downloads", dir: home + "/Downloads" },
            { label: "Pictures",  dir: home + "/Pictures"  },
            { label: "Music",     dir: home + "/Music"     },
            { label: "Videos",    dir: home + "/Videos"    }
        ]
    }

    // Reusable compact icon button. `iconKind` selects the glyph; `active` lights
    // the gold accent rail + wash; `tip` is the hover tooltip; onActivated runs
    // the navigation handler. XDG/device entries draw a folder/drive glyph.
    Component {
        id: compactButton
        Item {
            id: cbtn
            width: root.compactRailWidth
            height: 34
            property string iconKind: "folder"
            property bool active: false
            property string tip: ""
            // W8: optional fixed glyph color (used by colored favorite stars in
            // the rail). When unset (transparent), the active/muted rule applies.
            property color glyphColor: "transparent"
            signal activated()

            Rectangle {
                id: cbtnBg
                anchors.centerIn: parent
                width: 40
                height: 28
                radius: Theme.radiusRow
                color: cbtn.active
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10)
                    : (cbtnHover.hovered
                       ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
                       : "transparent")
                Behavior on color { ColorAnimation { duration: Theme.animDuration } }
            }

            // Active: 2px gold left rail with a soft glow (matches the full rows).
            Rectangle {
                visible: cbtn.active
                anchors.left: parent.left
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

            Loader {
                anchors.centerIn: parent
                width: 16; height: 16
                sourceComponent: {
                    switch (cbtn.iconKind) {
                    case "star":      return iconStarGold
                    case "favstar":   return iconStarFilled
                    case "home":      return iconHome
                    case "clock":     return iconClock
                    case "eyeoff":    return iconEyeOff
                    case "globe":     return iconGlobe
                    case "network":   return iconNetwork
                    case "trash":     return iconTrash
                    case "harddrive": return iconCompactDrive
                    case "usb":       return iconCompactUsb
                    case "desktop":   return iconMonitor
                    case "documents": return iconFileText
                    case "downloads": return iconDownload
                    case "pictures":  return iconImage
                    case "music":     return iconMusic
                    case "videos":    return iconVideo
                    default:          return iconFolder
                    }
                }
                onLoaded: {
                    if (!item)
                        return
                    // The "star" section anchor is intrinsically gold; leave it.
                    if (cbtn.iconKind === "star")
                        return
                    // A pinned-favorite star carries its own fixed color
                    // (glyphColor); every other glyph turns gold when active.
                    if (cbtn.glyphColor.a > 0)
                        item.color = Qt.binding(() => cbtn.glyphColor)
                    else
                        item.color = Qt.binding(() => cbtn.active ? Theme.gold : Theme.muted)
                }
            }

            HoverHandler { id: cbtnHover }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: cbtn.activated()
            }

            Quill.Tooltip {
                text: cbtn.tip
                visible: cbtnHover.hovered && cbtn.tip.length > 0
            }
        }
    }

    // Drive glyphs for the compact device buttons (full rows use SidebarDeviceRow).
    Component { id: iconCompactDrive; IconHardDrive { size: 18; color: Theme.muted } }
    Component { id: iconCompactUsb;   IconUsb { size: 18; color: Theme.muted } }

    // Compact Trash pinned to bottom of the rail. Rendered outside the Flickable
    // so it stays anchored to the bottom of the sidebar even when the scrollable
    // content is short. Height matches the rail button (34) + bottom padding.
    Loader {
        id: compactTrashLoader
        z: 1
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacing
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.compactRailWidth
        active: root.compactMode && !root.trashHidden
        visible: active
        height: active ? 34 : 0
        sourceComponent: compactButton
        onLoaded: {
            item.iconKind = "trash"
            item.tip = "Trash"
            item.active = Qt.binding(() =>
                !root.isRecentsView && !root.isHiddenView
                && fileOps.isTrashPath(root.currentPath))
            item.activated.connect(function() { root.bookmarkClicked(root.trashPath) })
        }
    }

    Flickable {
        id: compactRail
        anchors.fill: parent
        // Reserve room for the bottom-pinned compact Trash button so scrolled
        // content never slides under it: 34 (compactTrashLoader height) +
        // Theme.spacing (its bottom anchor margin) + 4 (gap above it).
        anchors.bottomMargin: root.compactMode && !root.trashHidden
            ? (34 + Theme.spacing + 4) : 0
        visible: root.compactMode
        contentWidth: width
        contentHeight: compactColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: compactColumn
            width: root.compactRailWidth
            spacing: 2
            topPadding: Theme.spacing
            bottomPadding: Theme.spacing

            // Favorites star — purely a section anchor in compact mode; keeps it
            // simple (navigates Home like the wordmark used to).
            Loader {
                width: root.compactRailWidth
                sourceComponent: compactButton
                onLoaded: {
                    item.iconKind = "star"
                    item.tip = "Favorites"
                    item.active = false
                    item.activated.connect(function() {
                        root.bookmarkClicked(fsModel.homePath())
                    })
                }
            }

            // Bookmarked favorites (respect per-bookmark hide).
            Repeater {
                model: bookmarks
                delegate: Loader {
                    width: root.compactRailWidth
                    readonly property bool entryHidden:
                        config.hiddenSidebarEntries.indexOf(model.path) >= 0
                    active: !entryHidden
                    visible: active
                    height: active ? 34 : 0
                    sourceComponent: compactButton
                    onLoaded: {
                        // W8: filled star in the bookmark's chosen color (gold
                        // default), matching the full Favorites rows.
                        item.iconKind = "favstar"
                        item.glyphColor = Qt.binding(() =>
                            (model.color && model.color.length > 0)
                                ? model.color : Theme.gold)
                        item.tip = model.name
                        item.active = Qt.binding(() =>
                            !root.isRecentsView && !root.isHiddenView
                            && model.path === root.currentPath)
                        var p = model.path
                        item.activated.connect(function() { root.bookmarkClicked(p) })
                    }
                }
            }

            // Thin divider before Places.
            Rectangle {
                width: 36; height: 1; anchors.horizontalCenter: parent.horizontalCenter
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
            }

            // Home — always visible.
            Loader {
                width: root.compactRailWidth
                sourceComponent: compactButton
                onLoaded: {
                    item.iconKind = "home"
                    item.tip = "Home"
                    item.active = Qt.binding(() =>
                        !root.isRecentsView && !root.isHiddenView
                        && fsModel.homePath() === root.currentPath)
                    item.activated.connect(function() {
                        root.bookmarkClicked(fsModel.homePath())
                    })
                }
            }

            // Recents.
            Loader {
                width: root.compactRailWidth
                active: config.hiddenSidebarEntries.indexOf("places.recents") < 0
                visible: active
                height: active ? 34 : 0
                sourceComponent: compactButton
                onLoaded: {
                    item.iconKind = "clock"
                    item.tip = "Recents"
                    item.active = Qt.binding(() => root.isRecentsView)
                    item.activated.connect(function() { root.recentsClicked() })
                }
            }

            // Hidden.
            Loader {
                width: root.compactRailWidth
                active: config.hiddenSidebarEntries.indexOf("places.hidden") < 0
                visible: active
                height: active ? 34 : 0
                sourceComponent: compactButton
                onLoaded: {
                    item.iconKind = "eyeoff"
                    item.tip = "Hidden"
                    item.active = Qt.binding(() => root.isHiddenView)
                    item.activated.connect(function() { root.hiddenClicked() })
                }
            }

            // XDG roots — only those that exist (re-checked on directoryLoaded).
            Repeater {
                model: root.compactXdgRoots
                delegate: Loader {
                    width: root.compactRailWidth
                    required property var modelData
                    property bool dirExists: placesTree.folderModel.indexForPath(modelData.dir).valid
                    Connections {
                        target: placesTree.folderModel
                        function onDirectoryLoaded(p) {
                            dirExists = placesTree.folderModel.indexForPath(modelData.dir).valid
                        }
                    }
                    active: dirExists
                    visible: active
                    height: active ? 34 : 0
                    sourceComponent: compactButton
                    onLoaded: {
                        // Map each XDG root to its unique semantic icon kind
                        // (mirrors the per-place icons in SidebarPlacesTree).
                        var lbl = modelData.label
                        if      (lbl === "Desktop")   item.iconKind = "desktop"
                        else if (lbl === "Documents") item.iconKind = "documents"
                        else if (lbl === "Downloads") item.iconKind = "downloads"
                        else if (lbl === "Pictures")  item.iconKind = "pictures"
                        else if (lbl === "Music")     item.iconKind = "music"
                        else if (lbl === "Videos")    item.iconKind = "videos"
                        else                          item.iconKind = "folder"
                        item.tip = modelData.label
                        item.active = Qt.binding(() =>
                            !root.isRecentsView && !root.isHiddenView
                            && modelData.dir === root.currentPath)
                        var d = modelData.dir
                        item.activated.connect(function() {
                            if (root.host) root.host.navigateActivePaneTo(d)
                        })
                    }
                }
            }

            // Devices — same model the full Devices section iterates.
            Item {
                width: root.compactRailWidth; height: devices.count > 0 ? 9 : 0
                visible: devices.count > 0
                Rectangle {
                    anchors.centerIn: parent
                    width: 36; height: 1
                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                }
            }
            Repeater {
                model: devices
                delegate: Loader {
                    id: deviceCompact
                    width: root.compactRailWidth
                    // Stable index for devices.mount(); model.mounted / model.mountPoint
                    // must be read LIVE inside the handler (not captured at load), so an
                    // unmounted-at-load device still mounts on click.
                    required property int index
                    required property var model
                    sourceComponent: compactButton
                    onLoaded: {
                        item.iconKind = model.removable ? "usb" : "harddrive"
                        item.tip = model.deviceName
                        item.active = Qt.binding(() =>
                            !root.isRecentsView && !root.isHiddenView
                            && model.mounted && model.mountPoint === root.currentPath)
                        item.activated.connect(function() {
                            // Mirror SidebarDeviceRow: mounted → navigate; unmounted →
                            // mount (after the udisks2-availability guard).
                            if (deviceCompact.model.mounted)
                                root.bookmarkClicked(deviceCompact.model.mountPoint)
                            else if (deviceCompact.model.backend === "udisks2"
                                     && !runtimeFeatures.udisksctlAvailable)
                                root.featureHintRequested(runtimeFeatures.installHint("deviceMount"))
                            else
                                devices.mount(deviceCompact.index)
                        })
                    }
                }
            }

            // Network — one compact button per live GVFS mount (W8). Empty
            // model (or hidden) → no rows.
            Repeater {
                model: root.networkHidden ? null : networkModel
                delegate: Loader {
                    readonly property string entryName: model.name
                    readonly property string entryUri: model.uri
                    width: root.compactRailWidth
                    height: 34
                    sourceComponent: compactButton
                    onLoaded: {
                        item.iconKind = "network"
                        item.tip = entryName
                        item.active = Qt.binding(() =>
                            !root.isRecentsView && !root.isHiddenView
                            && root.currentPath.length > 0
                            && (root.currentPath === entryUri
                                || root.currentPath.indexOf(entryUri) === 0))
                        item.activated.connect(function() { root.bookmarkClicked(entryUri) })
                    }
                }
            }

        }
    }
}
