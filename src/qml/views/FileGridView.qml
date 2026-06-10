import QtQuick
import QtQuick.Controls
import Wayfile
import Quill as Q

GridView {
    id: root
    Accessible.role: Accessible.List
    Accessible.name: "File grid"

    property alias selectedIndices: selectionController.selectedIndices
    property alias lastSelectedIndex: selectionController.lastSelectedIndex   // anchor for shift-selection
    property alias cursorIndex: selectionController.cursorIndex               // moving end for keyboard navigation

    // Current directory path (used as drop target)
    property string currentPath: ""
    onCurrentPathChanged: {
        selectionController.clearSelection()
        selectionController.pendingFocusPath = ""
        selectionController.resetTypeAhead()
        // Reset any sticky state from the outgoing directory (rubberband,
        // in-progress drag) so wheel scrolling works immediately in the
        // new one instead of waiting for the user to click.
        isDragging = false
        interactive = true
    }

    signal fileActivated(string filePath, bool isDirectory)
    signal contextMenuRequested(string filePath, bool isDirectory, point position)
    signal interactionStarted()
    signal transferRequested(var paths, string destinationPath, bool moveOperation)

    SelectionController {
        id: selectionController
        fileModel: root.model
        itemCount: root.count
        onEnsureIndexVisible: (index, mode) => root.positionViewAtIndex(
            index, mode === selectionController.positionBeginning ? GridView.Beginning : GridView.Contain)
        onRequestFocus: root.forceActiveFocus()
    }

    // Forwarders for external callers (FileViewContainer / Main.qml).
    function focusPath(path, reveal) { selectionController.focusPath(path, reveal) }
    function selectAll() { selectionController.selectAll() }
    function clearSelection() { selectionController.clearSelection() }

    // HybridView reuses this grid for its folders section at a fixed cell size;
    // it sets zoomEnabled:false so Ctrl+scroll doesn't resize (and persist) the
    // main grid's zoom from inside the folders strip.
    property bool zoomEnabled: true

    // Ctrl+scroll zoom. Changing cellSize resizes every cell, which moves
    // every delegate. We suppress the position-animating transitions, change
    // the size, then forceLayout() so delegates land directly on their new
    // cells instead of animating (and overlapping) into stale positions.
    // The reset timer is (re)started on every step so a burst of rapid zooms
    // coalesces into a single re-enable once the user stops.
    function applyZoom(step) {
        if (!root.zoomEnabled)
            return
        // step keeps the legacy column-delta sign: negative = scroll up =
        // zoom IN (bigger icons), positive = zoom OUT. Translate to a
        // cell-size delta — icon size is pinned to cellSize, so this is the
        // ONLY thing that resizes icons (never the available width).
        var next = Math.max(minCellSize, Math.min(maxCellSize, cellSize - step * cellSizeStep))
        if (next === cellSize)
            return
        zoomRelayoutActive = true
        cellSize = next
        // Snap the (now resized) cells into place immediately, with transitions
        // disabled, so nothing is left mid-animation at the wrong coordinates.
        forceLayout()
        zoomResetTimer.restart()
    }

    Timer {
        id: zoomResetTimer
        // Outlast the displaced animation; floor keeps it sane when animations
        // are disabled (animDurationSlow == 0) so a zoom burst still coalesces.
        interval: Math.max(120, Theme.animDurationSlow + 40)
        repeat: false
        onTriggered: {
            root.zoomRelayoutActive = false
            // Persist the settled zoom so it survives restarts. Debounced here
            // (not per scroll step) so a zoom burst writes the config once.
            config.saveGridCellSize(root.cellSize)
        }
    }

    clip: true
    reuseItems: true
    // cacheBuffer deliberately modest — delegate reuse via reuseItems is the
    // big win; larger off-screen buffers just materialize thumbnails the
    // user may never scroll to.
    cacheBuffer: 512
    // Zoom controls a fixed cell SIZE; the column count reflows with the
    // available width. This pins the icon to cellSize so it keeps a constant
    // size when the view is resized (sidebar toggle, window resize, split
    // view) — only Ctrl+scroll zoom changes it.
    // Seeded from the persisted preference; Ctrl+scroll zoom breaks this binding
    // and the new size is saved back (debounced) when the zoom burst settles.
    property int cellSize: config.gridCellSize
    readonly property int minCellSize: 110
    readonly property int maxCellSize: 320
    readonly property int cellSizeStep: 24
    readonly property int labelHeight: 32  // two lines of text below icon
    readonly property int iconRequestSize: 96 * Screen.devicePixelRatio
    readonly property int thumbnailRequestSize: 256 * Screen.devicePixelRatio

    // Reflow: as many cellSize-wide columns as fit, then stretch them to fill
    // the width (justified, no trailing gap). cellWidth therefore grows with
    // the view, but the icon below is pinned to cellSize, so icons never
    // resize when the available width changes — they just respace.
    readonly property int columnsPerRow: Math.max(1, Math.floor(width / cellSize))
    cellWidth: Math.floor(width / columnsPerRow)
    cellHeight: cellSize  // pinned row height (not = cellWidth) so rows stay evenly spaced
    // Extra inset shaved off the icon so the gold select/hover bloom has room
    // to render without being clipped by the view's edge. Multi-column grids
    // leave 0 (the bloom overflows harmlessly into neighbour cells); the narrow
    // single-column gallery filmstrip sets this so the halo fits the strip.
    property int iconInset: 0
    // 8px top, 0px gap, 5px bottom. Clamp to cellWidth for the pathological
    // single-column case where the pane is narrower than cellSize.
    readonly property int iconSize: Math.min(cellSize, cellWidth) - 8 - labelHeight - 5 - iconInset

    focus: visible
    keyNavigationEnabled: false
    boundsMovement: Flickable.StopAtBounds
    boundsBehavior: Flickable.StopAtBounds
    rebound: Transition {
        NumberAnimation {
            properties: "x,y"
            duration: Theme.animDurationSlow + 60
            easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve
        }
    }
    // While a Ctrl+scroll zoom relayout is in flight, the cellWidth/cellHeight
    // change moves every delegate to a new cell. Letting the add / displaced
    // transitions animate those moves means rapid consecutive zoom steps stack
    // overlapping animations and leave delegates parked at stale, intermediate
    // coordinates (the "scramble"). Disable the animating transitions during
    // the relayout so delegates snap straight to their correct cells.
    property bool zoomRelayoutActive: false
    add: Transition {
        enabled: !root.zoomRelayoutActive
        ParallelAnimation {
            NumberAnimation {
                properties: "opacity"
                from: 0
                to: 1
                duration: Theme.animDurationFast
                easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve
            }
            NumberAnimation {
                properties: "scale"
                from: 0.94
                to: 1
                duration: Theme.animDuration
                easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve
            }
        }
    }
    addDisplaced: Transition {
        enabled: !root.zoomRelayoutActive
        NumberAnimation {
            properties: "x,y"
            duration: Theme.animDurationSlow
            easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve
        }
    }
    remove: Transition {
        ParallelAnimation {
            NumberAnimation {
                properties: "opacity"
                to: 0
                duration: Theme.animDurationFast
                easing.type: Theme.animEasingExit; easing.bezierCurve: Theme.animBezierCurve
            }
            NumberAnimation {
                properties: "scale"
                to: 0.94
                duration: Theme.animDurationFast
                easing.type: Theme.animEasingExit; easing.bezierCurve: Theme.animBezierCurve
            }
        }
    }
    removeDisplaced: Transition {
        enabled: !root.zoomRelayoutActive
        NumberAnimation {
            properties: "x,y"
            duration: Theme.animDurationSlow
            easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve
        }
    }

    function moveSelection(delta, extend) {
        wheelScroller.stopAndSettle()
        if (count <= 0)
            return
        var current = cursorIndex >= 0 ? cursorIndex : (selectedIndices.length > 0 ? selectedIndices[selectedIndices.length - 1] : -1)
        var next = Math.max(0, Math.min(count - 1, current + delta))
        if (next === current && current >= 0) return
        if (extend && lastSelectedIndex >= 0) {
            var lo = Math.min(next, lastSelectedIndex)
            var hi = Math.max(next, lastSelectedIndex)
            var newSel = []
            for (var i = lo; i <= hi; i++) newSel.push(i)
            selectedIndices = newSel
        } else {
            selectedIndices = [next]
            lastSelectedIndex = next
        }
        cursorIndex = next
        positionViewAtIndex(next, GridView.Contain)
    }

    Keys.onLeftPressed: (event) => moveSelection(-1, event.modifiers & Qt.ShiftModifier)
    Keys.onRightPressed: (event) => moveSelection(1, event.modifiers & Qt.ShiftModifier)
    Keys.onUpPressed: (event) => moveSelection(-columnsPerRow, event.modifiers & Qt.ShiftModifier)
    Keys.onDownPressed: (event) => moveSelection(columnsPerRow, event.modifiers & Qt.ShiftModifier)
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Home) {
            wheelScroller.stopAndSettle()
            selectionController.moveSelectionTo(0, event.modifiers & Qt.ShiftModifier)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_End) {
            wheelScroller.stopAndSettle()
            selectionController.moveSelectionTo(count - 1, event.modifiers & Qt.ShiftModifier)
            event.accepted = true
            return
        }
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            activateCurrentSelection()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Escape) {
            if (selectionController.typeAheadBuffer.length > 0) {
                selectionController.resetTypeAhead()
            } else if (selectedIndices.length > 0) {
                selectionController.clearSelection()
            }
            event.accepted = true
            return
        }
        selectionController.handleTypeAhead(event)
    }

    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
        // Above the z:10 rubber-band MouseArea below, otherwise a press on the
        // scrollbar starts a selection instead of dragging the thumb.
        z: 20
        interactive: true
    }

    function activateCurrentSelection() {
        var idx = cursorIndex >= 0 ? cursorIndex : (selectedIndices.length > 0 ? selectedIndices[selectedIndices.length - 1] : -1)
        if (idx < 0)
            return

        root.fileActivated(selectionController.pathForRow(idx), selectionController.isDirForRow(idx))
    }

    // Parse file paths from a drop event
    function parseDragPaths(drop) {
        if (dragHelper.active && dragHelper.activePaths.length > 0)
            return dragHelper.activePaths.slice()

        var paths = []

        function decodePath(value) {
            return value.startsWith("file://") ? decodeURIComponent(value.substring(7)) : value
        }

        // Try drop.urls first (system DnD)
        if (drop.urls && drop.urls.length > 0) {
            for (var i = 0; i < drop.urls.length; i++) {
                var s = drop.urls[i].toString()
                paths.push(decodePath(s))
            }
        }

        // Fallback: parse text/uri-list from text mime data
        if (paths.length === 0 && drop.hasText) {
            var text = drop.text
            var lines = text.split("\n")
            for (var j = 0; j < lines.length; j++) {
                var line = lines[j].trim()
                if (line !== "")
                    paths.push(decodePath(line))
            }
        }

        return paths
    }

    // ── Drag state ─────────────────────────────────────────────────────────
    property string dragIconName: ""
    property string dragFileName: ""
    property bool isDragging: false

    // Start a drag from a delegate — uses C++ QDrag for system-wide DnD
    function beginDrag(filePath, iconName, fileName, mouseX, mouseY) {
        var paths = selectedIndices.length > 1
            ? selectedIndices.map(function(i) { return selectionController.pathForRow(i) })
            : [filePath]
        dragIconName = iconName
        dragFileName = selectedIndices.length > 1
            ? (selectedIndices.length + " items")
            : fileName
        isDragging = true

        dragHelper.startDrag(paths, iconName, paths.length)
    }

    function updateDrag(mouseX, mouseY) {
        // System drag handles cursor tracking
    }

    function endDrag() {
        if (isDragging) {
            isDragging = false
            interactive = true
            dragIconName = ""
            dragFileName = ""
        }
    }

    function cancelDrag() {
        if (isDragging) {
            isDragging = false
            interactive = true
            dragIconName = ""
            dragFileName = ""
        }
    }

    Connections {
        target: dragHelper
        function onDragFinished() { root.endDrag() }
    }

    Connections {
        // Coalesce undefined -> null: a bare `root.model` momentarily resolves to
        // undefined during construction/teardown, which QML rejects for a QObject*
        // target and surfaces as an intermittent warning (flaky qml smoke).
        target: root.model || null
        ignoreUnknownSignals: true

        function onModelReset() {
            selectionController.schedulePendingFocus()
        }

        function onRowsInserted() {
            selectionController.schedulePendingFocus()
        }
    }

    // ── Merged-selection overlay ────────────────────────────────────────────
    // Draws the whole selection as ONE rounded shape: the selected cells' union
    // outline is traced and every corner — convex AND concave — is rounded with
    // arcTo, then filled + stroked gold. Pinned to the viewport (x/y follow
    // contentX/contentY) and only traces rows in view. NOTE: this is compiled
    // into the binary — `cmake --build build` after editing or it won't change.
    Canvas {
        id: selectionOverlay
        x: root.contentX
        y: root.contentY
        width: root.width
        height: root.height
        z: -1
        antialiasing: true
        renderStrategy: Canvas.Cooperative

        Connections {
            target: root
            function onContentYChanged() { selectionOverlay.requestPaint() }
            function onContentXChanged() { selectionOverlay.requestPaint() }
        }
        property var selRef: root.selectedIndices
        property int colsRef: root.columnsPerRow
        property int cwRef: root.cellWidth
        property int chRef: root.cellHeight
        property bool dragRef: root.isDragging
        onSelRefChanged: requestPaint()
        onColsRefChanged: requestPaint()
        onCwRefChanged: requestPaint()
        onChRefChanged: requestPaint()
        onDragRefChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var sel = root.selectedIndices
            if (!sel || sel.length === 0)
                return
            var cols = root.columnsPerRow
            var cw = root.cellWidth
            var ch = root.cellHeight
            var cnt = root.count
            if (cols < 1 || cw <= 0 || ch <= 0)
                return
            var cY = root.contentY
            var rad = Math.min(Theme.radiusMedium, cw / 2, ch / 2)

            var firstRow = Math.max(0, Math.floor(cY / ch) - 1)
            var lastRow = Math.floor((cY + height) / ch) + 1

            var set = {}
            for (var k = 0; k < sel.length; k++)
                set[sel[k]] = true
            function selAt(c, r) {
                if (c < 0 || c >= cols || r < firstRow || r > lastRow)
                    return false
                var i = r * cols + c
                if (i < 0 || i >= cnt)
                    return false
                return set[i] === true
            }

            var edges = {}
            function addEdge(c1, r1, c2, r2) { edges[c1 + "," + r1] = { c: c2, r: r2 } }
            for (var key in set) {
                var idx = parseInt(key)
                if (idx < 0 || idx >= cnt)
                    continue
                var c = idx % cols
                var r = Math.floor(idx / cols)
                if (r < firstRow || r > lastRow)
                    continue
                if (!selAt(c, r - 1)) addEdge(c, r, c + 1, r)
                if (!selAt(c + 1, r)) addEdge(c + 1, r, c + 1, r + 1)
                if (!selAt(c, r + 1)) addEdge(c + 1, r + 1, c, r + 1)
                if (!selAt(c - 1, r)) addEdge(c, r + 1, c, r)
            }

            ctx.beginPath()
            var visited = {}
            for (var startKey in edges) {
                if (visited[startKey])
                    continue
                var loop = []
                var cur = startKey
                var guard = 0
                while (cur !== undefined && edges[cur] && !visited[cur] && guard < 200000) {
                    visited[cur] = true
                    var parts = cur.split(",")
                    // +0.5 so a 1px stroke lands on one pixel column/row instead
                    // of straddling two (which reads as a frayed/soft edge).
                    loop.push({ x: parseInt(parts[0]) * cw + 0.5, y: parseInt(parts[1]) * ch - cY + 0.5 })
                    var nxt = edges[cur]
                    cur = nxt.c + "," + nxt.r
                    guard++
                }
                if (loop.length < 3)
                    continue
                var n = loop.length
                var sx = (loop[n - 1].x + loop[0].x) / 2
                var sy = (loop[n - 1].y + loop[0].y) / 2
                ctx.moveTo(sx, sy)
                for (var v = 0; v < n; v++) {
                    var curr = loop[v]
                    var next = loop[(v + 1) % n]
                    ctx.arcTo(curr.x, curr.y, next.x, next.y, rad)
                }
                ctx.closePath()
            }
            ctx.fillStyle = Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, root.isDragging ? 0.06 : 0.1)
            ctx.fill()
            ctx.lineWidth = 1
            ctx.strokeStyle = Theme.accent
            ctx.stroke()
        }
    }

    // ── Delegate ───────────────────────────────────────────────────────────
    delegate: Item {
        id: delegateItem
        width: root.cellWidth
        height: root.cellHeight
        Accessible.role: Accessible.ListItem
        Accessible.name: fileName + (isDir ? ", folder" : "")
        Accessible.selected: isSelected

        required property int index
        required property string fileName
        required property string filePath
        required property var fileModified
        required property bool isDir
        required property string fileIconName
        required property string gitStatus
        required property string gitStatusIcon
        required property bool hasImagePreview
        required property bool hasVideoPreview
        required property string fileCategory
        required property string fileExtension
        required property string folderType

        readonly property bool isSelected: root.selectedIndices.indexOf(index) >= 0
        readonly property bool isCutPending: clipboard.isCut && clipboard.contains(delegateItem.filePath)
        readonly property bool isPastePending: fileOps.pendingTargetPaths.indexOf(delegateItem.filePath) >= 0

        // Per-folder drop target
        DropArea {
            id: folderDropArea
            anchors.fill: parent
            keys: ["text/uri-list"]
            enabled: delegateItem.isDir && !delegateItem.isSelected

            onDropped: (drop) => {
                var paths = root.parseDragPaths(drop)
                if (paths.length === 0) return
                // Don't move into itself or its own parent
                var dominated = paths.some(function(p) {
                    return delegateItem.filePath === p || delegateItem.filePath.startsWith(p + "/")
                })
                if (dominated) return
                root.transferRequested(paths, delegateItem.filePath, drop.proposedAction !== Qt.CopyAction)
                drop.accept()
            }
        }

        readonly property bool hasThumbnail: !fileOps.isRemotePath(delegateItem.filePath)
            && (delegateItem.hasImagePreview || delegateItem.hasVideoPreview)

        Image {
            id: thumbImg
            visible: delegateItem.hasThumbnail
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 8
            width: root.iconSize
            height: root.iconSize
            fillMode: Image.PreserveAspectFit
            source: delegateItem.hasThumbnail
                ? ("image://thumbnail/" + delegateItem.filePath
                   + "?mtime=" + new Date(delegateItem.fileModified).getTime())
                : ""
            sourceSize: Qt.size(root.thumbnailRequestSize,
                                root.thumbnailRequestSize)
            asynchronous: true
        }

        // Gold folder glyph / metallic file chip (matches the detailed + miller
        // rows, user pref). Kept as an Item slot named `iconImg` so the cut/
        // paste/git badges, the typed-folder emblems, and the label keep
        // anchoring to it / to `folderArt` exactly as before.
        Item {
            id: iconImg
            visible: !delegateItem.hasThumbnail
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            // Static on hover (user pref): the icon + label stay completely
            // still; only the hover highlight rect suggests hover. (Previously
            // the art lifted 2px, which carried the label up with it.)
            anchors.topMargin: 8
            width: root.iconSize
            height: root.iconSize

            FileIcon {
                id: folderArt
                anchors.centerIn: parent
                isDir: delegateItem.isDir
                ext: delegateItem.fileExtension
                category: delegateItem.fileCategory
                isHidden: delegateItem.fileName.startsWith(".")
                size: root.iconSize
                hovered: ma.containsMouse
                selected: delegateItem.isSelected
            }

            // Typed-folder marker (handoff v2 §B). Home gets a centred gold
            // "arch" emblem; other XDG dirs get a bottom-right obsidian badge.
            Rectangle {
                visible: delegateItem.isDir && delegateItem.folderType === "home"
                anchors.centerIn: folderArt
                anchors.verticalCenterOffset: Math.round(folderArt.height * 0.06)
                width: Math.round(root.iconSize * 0.20)
                height: Math.round(root.iconSize * 0.26)
                topLeftRadius: width * 0.5
                topRightRadius: width * 0.5
                bottomLeftRadius: 2
                bottomRightRadius: 2
                // Bottom-lit gold (handoff radial ellipse at 50% 120%).
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.goldDeep }
                    GradientStop { position: 0.45; color: Theme.gold }
                    GradientStop { position: 1.0; color: Theme.goldLight }
                }
            }

            Rectangle {
                id: folderBadge
                visible: delegateItem.isDir
                         && delegateItem.folderType !== ""
                         && delegateItem.folderType !== "home"
                anchors.right: folderArt.right
                anchors.bottom: folderArt.bottom
                anchors.rightMargin: Math.round(root.iconSize * 0.05)
                anchors.bottomMargin: Math.round(root.iconSize * 0.02)
                width: Math.round(root.iconSize * 0.30)
                height: width
                radius: Math.round(width * 0.28)
                color: Qt.rgba(Theme.mantle.r, Theme.mantle.g, Theme.mantle.b, 0.9)
                border.width: 1
                border.color: Theme.line

                Loader {
                    anchors.centerIn: parent
                    sourceComponent: {
                        switch (delegateItem.folderType) {
                            case "documents": return badgeDocs
                            case "downloads": return badgeDownload
                            case "pictures":  return badgeImage
                            case "music":     return badgeMusic
                            case "videos":    return badgeVideo
                            case "desktop":   return badgeMonitor
                            case "projects":  return badgeTerminal
                            default:          return null
                        }
                    }
                    onLoaded: item.size = Qt.binding(() => Math.round(folderBadge.width * 0.55))
                }
            }

            // The uniform gold hover/select bloom now lives inside FileIcon
            // (it owns its own MultiEffect), so the icon slot no longer applies
            // a layer effect. The pkt-11 selection outline is still drawn by
            // selectionOverlay independently.
        }

        Rectangle {
            anchors.top: (iconImg.visible ? iconImg : thumbImg).top
            anchors.right: (iconImg.visible ? iconImg : thumbImg).right
            anchors.topMargin: -4
            anchors.rightMargin: -4
            width: 22
            height: 22
            radius: 11
            z: 2
            color: Qt.rgba(Theme.mantle.r, Theme.mantle.g, Theme.mantle.b, 0.96)
            border.width: 1
            border.color: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.9)
            opacity: delegateItem.isCutPending ? 1 : 0
            scale: delegateItem.isCutPending ? 1 : 0.88
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: Theme.animDurationFast; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve } }
            Behavior on scale { NumberAnimation { duration: Theme.animDurationFast; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve } }

            IconScissors {
                anchors.centerIn: parent
                size: 13
                color: Theme.warning
            }
        }

        Rectangle {
            anchors.centerIn: (iconImg.visible ? iconImg : thumbImg)
            width: 28
            height: 28
            radius: 14
            z: 3
            color: Qt.rgba(Theme.mantle.r, Theme.mantle.g, Theme.mantle.b, 0.92)
            border.width: 1
            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
            opacity: delegateItem.isPastePending ? 1 : 0
            scale: delegateItem.isPastePending ? 1 : 0.9
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: Theme.animDurationFast; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve } }
            Behavior on scale { NumberAnimation { duration: Theme.animDurationFast; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve } }

            Q.Spinner {
                anchors.centerIn: parent
                size: "small"
                color: Theme.accent
                running: delegateItem.isPastePending
            }
        }

        // Git status overlay badge (handoff re-skin — obsidian disc + glyph).
        GitBadge {
            statusIcon: delegateItem.gitStatusIcon
            size: 16
            anchors.right: (iconImg.visible ? iconImg : thumbImg).right
            anchors.bottom: (iconImg.visible ? iconImg : thumbImg).bottom
            anchors.rightMargin: -2
            anchors.bottomMargin: -2
            z: 4
        }

        // Hidden text to check if name fits in 2 lines
        Text {
            id: measureText
            visible: false
            width: labelText.width
            font: labelText.font
            text: delegateItem.fileName
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 3
        }

        Text {
            id: labelText
            width: parent.width - 12
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: (iconImg.visible ? iconImg : thumbImg).bottom
            anchors.topMargin: 0
            text: {
                var name = delegateItem.fileName
                // If it fits in 2 lines, show as-is
                if (measureText.lineCount <= 2) return name
                // Middle-elide: keep last 6 chars (extension + some context)
                var keep = Math.min(6, Math.floor(name.length / 4))
                var maxFront = name.length - keep - 3
                // Approximate: 2 lines worth of chars
                var charsPerLine = Math.floor(labelText.width / (labelText.font.pixelSize * 0.55))
                var frontChars = Math.min(maxFront, charsPerLine * 2 - keep - 3)
                if (frontChars < 1) frontChars = 1
                return name.substring(0, frontChars) + "\u2026" + name.substring(name.length - keep)
            }
            color: Theme.text
            font.pointSize: Theme.fontSmall
            horizontalAlignment: Text.AlignHCenter
            maximumLineCount: 2
            wrapMode: Text.WrapAnywhere
            clip: true
            height: root.labelHeight
        }


        // Selection/hover rect wraps tightly around the content
        Rectangle {
            id: selectionRect
            anchors.fill: parent
            anchors.margins: 0
            radius: Theme.radiusMedium
            z: -1
            opacity: (root.isDragging && delegateItem.isSelected) ? 0.4 : 1.0
            color: {
                if (folderDropArea.containsDrag)
                    return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                if (ma.containsMouse)
                    return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.025)
                return "transparent"
            }
            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
            // Selection fill + outline are drawn by selectionOverlay (the merged
            // Canvas). Per-cell border is only the drop-target highlight.
            border.color: folderDropArea.containsDrag ? Theme.accent : "transparent"
            border.width: folderDropArea.containsDrag ? 2 : 0
        }

        MouseArea {
            id: ma
            anchors.fill: selectionRect
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            property point pressPos
            property bool dragPending: false

            onPressed: (mouse) => {
                wheelScroller.stopAndSettle()
                root.interactionStarted()
                pressPos = Qt.point(mouse.x, mouse.y)
                dragPending = (mouse.button === Qt.LeftButton)
                if (dragPending)
                    root.interactive = false  // Prevent Flickable from stealing grab
            }

            onPositionChanged: (mouse) => {
                if (!dragPending && !root.isDragging) return
                var dx = mouse.x - pressPos.x
                var dy = mouse.y - pressPos.y
                if (Math.sqrt(dx*dx + dy*dy) > 10) {
                    dragPending = false
                    if (!delegateItem.isSelected)
                        selectionController.selectIndex(delegateItem.index, false, false)
                    // Map mouse to GridView coordinates
                    var mapped = ma.mapToItem(root, mouse.x, mouse.y)
                    root.beginDrag(
                        delegateItem.filePath,
                        delegateItem.fileIconName,
                        delegateItem.fileName,
                        mapped.x, mapped.y
                    )
                }
                if (root.isDragging) {
                    var mapped2 = ma.mapToItem(root, mouse.x, mouse.y)
                    root.updateDrag(mapped2.x, mapped2.y)
                }
            }

            onClicked: (mouse) => {
                if (!root.isDragging) root.interactive = true
                root.forceActiveFocus()
                if (mouse.button === Qt.RightButton) {
                    var mapped = ma.mapToItem(null, mouse.x, mouse.y)
                    // Right-clicking an unselected item selects it first
                    // (single-select), so the menu targets the clicked file
                    // — standard file-manager behaviour. An already-selected
                    // item keeps the (possibly multi-) selection.
                    if (!delegateItem.isSelected)
                        selectionController.selectIndex(delegateItem.index, false, false)
                    root.contextMenuRequested(
                        delegateItem.filePath,
                        delegateItem.isDir,
                        Qt.point(mapped.x, mapped.y)
                    )
                    return
                }
                selectionController.selectIndex(
                    delegateItem.index,
                    mouse.modifiers & Qt.ControlModifier,
                    mouse.modifiers & Qt.ShiftModifier
                )
            }

            onDoubleClicked: (mouse) => {
                if (mouse.button !== Qt.LeftButton) return
                root.fileActivated(delegateItem.filePath, delegateItem.isDir)
            }

            onReleased: {
                dragPending = false
                if (root.isDragging)
                    root.endDrag()
                else
                    root.interactive = true
            }

            onCanceled: {
                dragPending = false
                root.cancelDrag()
            }
        }
    }

    // ── Drop area: accept files dropped onto this view ───────────────────────
    DropArea {
        id: viewDropArea
        anchors.fill: parent
        keys: ["text/uri-list"]
        z: -2

        // ── Discovery note (selection-outline work, GH #10) ──────────────
        // A transparent Rectangle + border renders a VISIBLE outline because the
        // border sits on the background — UNLIKE a Rectangle.border drawn over
        // its own fill (gold-on-gold → no contrast → invisible) and UNLIKE a
        // Canvas (which does NOT composite inside a ListView's contentItem, only
        // inside a GridView). This drag hint was the live example of that pattern.
        // NOTE: this element is drag-only — it is NOT the gold border seen on a
        // normal selection (that is `selectionRect`'s border, above). Muted per
        // request (visible:false, border 0) so it never shows. See #10 to reuse
        // the transparent-Rectangle+border pattern for a merged-selection outline.
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
            border.width: 0
            radius: Theme.radiusMedium
            visible: false
        }

        onDropped: (drop) => {
            if (!root.currentPath) return
            var paths = root.parseDragPaths(drop)
            if (paths.length === 0) return
            // Don't move files into the directory they're already in
            var allSameDir = paths.every(function(p) {
                var parentDir = p.substring(0, p.lastIndexOf("/"))
                return parentDir === root.currentPath
            })
            if (allSameDir) return
            root.transferRequested(paths, root.currentPath, drop.proposedAction !== Qt.CopyAction)
            drop.accept()
        }
    }

    // ── Rubber-band selection + empty space clicks ───────────────────────────
    // z:10 so it receives presses BEFORE the Flickable can steal them
    MouseArea {
        id: bgMa
        anchors.fill: parent
        z: 10
        preventStealing: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        property point dragStart
        property bool rubberBandActive: false
        property bool rubberBandJustFinished: false

        onWheel: (wheel) => {
            if (wheel.modifiers & Qt.ControlModifier) {
                wheelScroller.stopAndSettle()
                root.interactionStarted()
                // Scroll up = zoom in = bigger cells (bigger icons)
                var delta = wheelScroller.deltaFor(wheel)
                if (delta === 0) {
                    wheel.accepted = false
                    return
                }
                var step = delta < 0 ? -1 : 1
                root.applyZoom(step)
                wheel.accepted = true
            } else {
                wheel.accepted = false
            }
        }

        onPressed: (mouse) => {
            var idx = root.indexAt(mouse.x + root.contentX, mouse.y + root.contentY)
            if (idx >= 0) {
                mouse.accepted = false
                return
            }
            // Empty space (between cells or outside content rects)
            wheelScroller.stopAndSettle()
            root.interactionStarted()
            root.forceActiveFocus()
            if (mouse.button === Qt.LeftButton) {
                root.interactive = false
                dragStart = Qt.point(mouse.x, mouse.y)
                rubberBand.begin(dragStart)
                rubberBandActive = true
            }
        }

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                var mp = bgMa.mapToItem(null, mouse.x, mouse.y)
                root.contextMenuRequested("", false, Qt.point(mp.x, mp.y))
                return
            }
            if (rubberBandJustFinished) {
                rubberBandJustFinished = false
                return
            }
            selectionController.clearSelection()
        }

        onPositionChanged: (mouse) => {
            if (rubberBandActive) {
                rubberBand.update(Qt.point(mouse.x, mouse.y))
                selectIntersecting()
            }
        }

        onReleased: {
            var wasRubberBand = rubberBandActive && rubberBand.visible
            rubberBand.end()
            rubberBandActive = false
            rubberBandJustFinished = wasRubberBand
            root.interactive = true
        }

        function selectIntersecting() {
            var rb = rubberBand.selectionRect
            if (rb.width < 4 && rb.height < 4) return

            var newSel = []
            var c = root.count
            for (var i = 0; i < c; i++) {
                var item = root.itemAtIndex(i)
                if (!item) continue
                var itemPos = root.mapFromItem(item, 0, 0)
                var itemRect = Qt.rect(itemPos.x, itemPos.y, item.width, item.height)
                if (selectionController.rectsIntersect(rb, itemRect))
                    newSel.push(i)
            }
            root.selectedIndices = newSel
        }
    }

    RubberBand {
        id: rubberBand
        anchors.fill: parent
        z: 11
    }

    KineticWheelScroller {
        id: wheelScroller
        anchors.fill: parent
        z: 12
        flickable: root
        wheelStep: 42
        mouseWheelMultiplier: 0.75 * config.scrollSpeed
        touchpadMultiplier: 1.35
        minVelocity: 135
        maxVelocity: 3900
        kineticGain: 1.01
        onScrollStarted: root.interactionStarted()
    }

    // Typed-folder badge glyphs (gold), keyed off folderType.
    Component { id: badgeDocs;     IconFileText { color: Theme.gold } }
    Component { id: badgeDownload; IconDownload { color: Theme.gold } }
    Component { id: badgeImage;    IconImage    { color: Theme.gold } }
    Component { id: badgeMusic;    IconMusic    { color: Theme.gold } }
    Component { id: badgeVideo;    IconVideo    { color: Theme.gold } }
    Component { id: badgeMonitor;  IconMonitor  { color: Theme.gold } }
    Component { id: badgeTerminal; IconTerminal { color: Theme.gold } }
}
