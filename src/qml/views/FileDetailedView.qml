import QtQuick
import QtQuick.Controls
import Wayfile
import Quill as Q

FocusScope {
    id: root
    Accessible.role: Accessible.Table
    Accessible.name: "File details"
    focus: visible

    property alias selectedIndices: selectionController.selectedIndices
    property alias lastSelectedIndex: selectionController.lastSelectedIndex   // anchor for shift-selection
    property alias cursorIndex: selectionController.cursorIndex               // moving end for keyboard navigation
    property string sortColumn: "name"
    property bool sortAscending: true

    // Current directory path (used as drop target)
    property string currentPath: ""
    onCurrentPathChanged: {
        selectionController.clearSelection()
        selectionController.pendingFocusPath = ""
        selectionController.resetTypeAhead()
        // Reset any sticky `interactive=false` left behind by an in-flight
        // rubberband / drag in the previous directory — otherwise the wheel
        // handler short-circuits until the user clicks something.
        if (listView) listView.interactive = true
        clearFolderItemCounts()
        Qt.callLater(refreshFolderItemCounts)
    }
    onVisibleChanged: {
        if (visible)
            Qt.callLater(refreshFolderItemCounts)
        else
            clearFolderItemCounts()
    }

    // Model bound by FileViewContainer
    property var viewModel

    property int rowHeight: 28
    // Top-corner radius of the column header. Rounded when this view sits at the
    // top of a pane (standalone); HybridView sets it to 0 because there the
    // header is a mid-content "Files" section divider, not a pane top.
    property int headerRadius: Theme.radiusMedium
    readonly property int minRowHeight: 22
    readonly property int maxRowHeight: 56
    readonly property int detailIconSize: Math.round(rowHeight * 0.643)  // 18 at default 28

    // Contiguous runs of selected rows — one merged outline block each.
    readonly property var selectionRuns: {
        var sel = selectedIndices
        if (!sel || sel.length === 0)
            return []
        var s = sel.slice().sort(function(a, b) { return a - b })
        var runs = []
        var start = s[0]
        var prev = s[0]
        for (var i = 1; i < s.length; i++) {
            if (s[i] === prev + 1) { prev = s[i]; continue }
            runs.push({ start: start, end: prev })
            start = s[i]
            prev = s[i]
        }
        runs.push({ start: start, end: prev })
        return runs
    }

    // Map of folder path → item count
    property var folderItemCounts: ({})

    // Drop all cached counts. Called when the listing itself changes (new dir,
    // row count change) — NOT on plain scrolling.
    function clearFolderItemCounts() {
        folderItemCounts = ({})
    }

    // Fill-only: scan just the visible folders we have not counted yet and merge
    // them into the cache. Each folder count is a sync entryList(), so re-scanning
    // already-known folders on every scroll-stop was pure waste; caching across
    // scrolls scans each visible folder once until the listing is invalidated.
    function refreshFolderItemCounts() {
        if (!root.visible || !viewModel || listView.count <= 0 || !viewModel.folderItemCounts)
            return

        var first = Math.max(0, Math.floor(listView.contentY / root.rowHeight) - 12)
        var last = Math.min(listView.count - 1,
            Math.ceil((listView.contentY + listView.height) / root.rowHeight) + 12)

        var cache = root.folderItemCounts
        var paths = []
        for (var i = first; i <= last; ++i) {
            if (selectionController.isDirForRow(i)) {
                var p = selectionController.pathForRow(i)
                if (p && cache[p] === undefined && !fileOps.isRemotePath(p))
                    paths.push(p)
            }
        }
        if (paths.length === 0)
            return

        var fresh = viewModel.folderItemCounts(paths)
        // New object so the property change notifies bindings.
        var merged = ({})
        for (var k in cache)
            merged[k] = cache[k]
        for (var nk in fresh)
            merged[nk] = fresh[nk]
        root.folderItemCounts = merged
    }

    signal fileActivated(string filePath, bool isDirectory)
    signal contextMenuRequested(string filePath, bool isDirectory, point position)
    signal sortRequested(string column, bool ascending)
    signal interactionStarted()
    signal transferRequested(var paths, string destinationPath, bool moveOperation)

    function dropPaths(drop) {
        if (dragHelper.active && dragHelper.activePaths.length > 0)
            return dragHelper.activePaths.slice()

        var paths = []
        var urls = drop.urls || []

        for (var i = 0; i < urls.length; i++) {
            var s = urls[i].toString()
            paths.push(s.startsWith("file://") ? decodeURIComponent(s.substring(7)) : s)
        }

        if (paths.length === 0 && drop.hasText) {
            var lines = drop.text.split("\n")
            for (var j = 0; j < lines.length; j++) {
                var line = lines[j].trim()
                if (line !== "")
                    paths.push(line.startsWith("file://") ? decodeURIComponent(line.substring(7)) : line)
            }
        }

        return paths
    }

    function activateCurrentSelection() {
        var idx = cursorIndex >= 0 ? cursorIndex : (selectedIndices.length > 0 ? selectedIndices[selectedIndices.length - 1] : -1)
        if (idx < 0)
            return

        root.fileActivated(selectionController.pathForRow(idx), selectionController.isDirForRow(idx))
    }

    SelectionController {
        id: selectionController
        fileModel: root.viewModel
        itemCount: listView.count
        onEnsureIndexVisible: (index, mode) => listView.positionViewAtIndex(
            index, mode === selectionController.positionBeginning ? ListView.Beginning : ListView.Contain)
        onRequestFocus: listView.forceActiveFocus()
    }

    // Forwarders for external callers (FileViewContainer / Main.qml).
    function focusPath(path, reveal) { selectionController.focusPath(path, reveal) }
    function selectAll() { selectionController.selectAll() }
    function clearSelection() { selectionController.clearSelection() }

    function clickHeader(col) {
        if (sortColumn === col) {
            sortAscending = !sortAscending
        } else {
            sortColumn = col
            sortAscending = true
        }
        root.sortRequested(sortColumn, sortAscending)
    }

    // Column widths. The 20px tail keeps the right-aligned Size column clear of
    // the right edge / the AsNeeded scrollbar (handoff right margin).
    readonly property int rightGutter: 40
    readonly property int colName: root.width - colSize - colModified - colType - rightGutter
    readonly property int colSize: 110
    readonly property int colModified: 140
    readonly property int colType: 80

    Column {
        anchors.fill: parent

        // Header row
        Rectangle {
            width: root.width
            height: root.rowHeight
            color: Theme.mantle
            radius: root.headerRadius

            // Cover the bottom corners so only the top is rounded
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.radius
                color: parent.color
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 0

                Repeater {
                    model: [
                        { key: "name",     label: "Name",        width: root.colName },
                        { key: "modified", label: "Modified",    width: root.colModified },
                        { key: "type",     label: "Type",        width: root.colType },
                        { key: "size",     label: "Size",        width: root.colSize }
                    ]

                    delegate: Item {
                        width: modelData.width
                        height: 28

                        Rectangle {
                            anchors.fill: parent
                            color: hdrMa.containsMouse
                                ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.07)
                                : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 4
                            spacing: 3

                            Text {
                                text: modelData.label
                                color: root.sortColumn === modelData.key ? Theme.accent : Theme.muted
                                font.pointSize: Theme.fontSmall
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            IconChevronDown {
                                visible: root.sortColumn === modelData.key
                                size: 12
                                color: Theme.accent
                                rotation: root.sortAscending ? 180 : 0
                                Behavior on rotation {
                                    NumberAnimation { duration: 200; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve }
                                }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Right border separator
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.topMargin: 4
                            anchors.bottomMargin: 4
                            width: 1
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
                        }

                        MouseArea {
                            id: hdrMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: {
                                wheelScroller.stopAndSettle()
                                root.interactionStarted()
                                listView.forceActiveFocus()
                            }
                            onClicked: root.clickHeader(modelData.key)
                        }
                    }
                }
            }

            // Top hairline (handoff header inset).
            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Theme.hair
            }

            // Bottom border
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
            }
        }

        // File list
        ListView {
            id: listView
            width: root.width
            height: root.height - root.rowHeight
            clip: true
            reuseItems: true
            cacheBuffer: 512

            // Listing changed → counts may be stale: invalidate then refill.
            onCountChanged: {
                root.clearFolderItemCounts()
                Qt.callLater(root.refreshFolderItemCounts)
            }
            // Plain scroll → only fill newly-visible folders (cache kept).
            onMovementEnded: Qt.callLater(root.refreshFolderItemCounts)

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
            add: Transition {
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
                        from: 0.98
                        to: 1
                        duration: Theme.animDuration
                        easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve
                    }
                }
            }
            addDisplaced: Transition {
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
                        to: 0.98
                        duration: Theme.animDurationFast
                        easing.type: Theme.animEasingExit; easing.bezierCurve: Theme.animBezierCurve
                    }
                }
            }
            removeDisplaced: Transition {
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
                var current = root.cursorIndex >= 0 ? root.cursorIndex : (root.selectedIndices.length > 0 ? root.selectedIndices[root.selectedIndices.length - 1] : -1)
                var next = Math.max(0, Math.min(count - 1, current + delta))
                if (next === current && current >= 0) return
                if (extend && root.lastSelectedIndex >= 0) {
                    var lo = Math.min(next, root.lastSelectedIndex)
                    var hi = Math.max(next, root.lastSelectedIndex)
                    var newSel = []
                    for (var i = lo; i <= hi; i++) newSel.push(i)
                    root.selectedIndices = newSel
                } else {
                    root.selectedIndices = [next]
                    root.lastSelectedIndex = next
                }
                root.cursorIndex = next
                positionViewAtIndex(next, ListView.Contain)
            }

            Keys.onUpPressed: (event) => moveSelection(-1, event.modifiers & Qt.ShiftModifier)
            Keys.onDownPressed: (event) => moveSelection(1, event.modifiers & Qt.ShiftModifier)
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
                    root.activateCurrentSelection()
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Escape) {
                    if (selectionController.typeAheadBuffer.length > 0) {
                        selectionController.resetTypeAhead()
                    } else if (root.selectedIndices.length > 0) {
                        selectionController.clearSelection()
                    }
                    event.accepted = true
                    return
                }
                selectionController.handleTypeAhead(event)
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                // Above the z:10 rubber-band MouseArea so the thumb is draggable.
                z: 20
                interactive: true
            }

            model: root.viewModel

            delegate: FileDetailedRow {
                view: root
                listViewRef: listView
                selectionControllerRef: selectionController
                wheelScrollerRef: wheelScroller
                selectedIndices: root.selectedIndices
                folderItemCounts: root.folderItemCounts
                colName: root.colName
                colSize: root.colSize
                colModified: root.colModified
                colType: root.colType
                rowHeight: root.rowHeight
                detailIconSize: root.detailIconSize
            }

            // ── Merged-selection overlay ─────────────────────────────────
            // One block per contiguous run of selected rows. Uses the same
            // transparent-Rectangle+border pattern as the drop-area hint and the
            // RubberBand (both render as ListView children), so the gold outline
            // sits on the background and is visible. Two rects per run: inset
            // fill + transparent-fill outline. z:-1 keeps row text untinted; a
            // ListView child is viewport-fixed, so y tracks contentY. Rows render
            // their selection transparent and defer the look to here.
            Item {
                anchors.fill: parent
                z: -1
                Repeater {
                    model: root.selectionRuns
                    delegate: Item {
                        x: 2
                        y: modelData.start * root.rowHeight - listView.contentY + 2
                        width: listView.width - 4
                        height: (modelData.end - modelData.start + 1) * root.rowHeight - 4

                        Rectangle {   // inset fill — handoff accent gradient .10→.04
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: Math.max(0, Theme.radiusSm - 1)
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10) }
                                GradientStop { position: 1.0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.04) }
                            }
                        }
                        Rectangle {   // inset 1px accent.18 outline, r4
                            anchors.fill: parent
                            radius: Theme.radiusSm
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                        }
                    }
                }
            }

            // ── Drop area ─────────────────────────────────────────────────
            DropArea {
                anchors.fill: parent
                keys: ["text/uri-list"]
                z: -2

                onDropped: (drop) => {
                    if (!root.currentPath) return
                    var paths = root.dropPaths(drop)
                    if (paths.length === 0) return
                    // Don't move files into the directory they're already in
                    var allSameDir = paths.every(function(p) {
                        var parentDir = p.substring(0, p.lastIndexOf("/"))
                        return parentDir === root.currentPath
                    })
                    if (allSameDir) return
                    if (drop.proposedAction === Qt.MoveAction)
                        root.transferRequested(paths, root.currentPath, true)
                    else
                        root.transferRequested(paths, root.currentPath, false)
                    drop.acceptProposedAction()
                }
            }

            // ── Rubber-band selection + empty space clicks ───────────────
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
                        var delta = wheelScroller.deltaFor(wheel)
                        if (delta === 0) {
                            wheel.accepted = false
                            return
                        }
                        var step = delta < 0 ? 2 : -2
                        root.rowHeight = Math.max(root.minRowHeight, Math.min(root.maxRowHeight, root.rowHeight + step))
                        wheel.accepted = true
                    } else {
                        wheel.accepted = false
                    }
                }

                onPressed: (mouse) => {
                    var idx = listView.indexAt(mouse.x + listView.contentX, mouse.y + listView.contentY)
                    if (idx >= 0) {
                        mouse.accepted = false
                        return
                    }
                    wheelScroller.stopAndSettle()
                    root.interactionStarted()
                    root.forceActiveFocus()
                    if (mouse.button === Qt.LeftButton) {
                        listView.interactive = false
                        dragStart = Qt.point(mouse.x, mouse.y)
                        detailedRubberBand.begin(dragStart)
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
                        detailedRubberBand.update(Qt.point(mouse.x, mouse.y))
                        selectIntersecting()
                    }
                }

                onReleased: {
                    var wasRubberBand = rubberBandActive && detailedRubberBand.visible
                    detailedRubberBand.end()
                    rubberBandActive = false
                    rubberBandJustFinished = wasRubberBand
                    listView.interactive = true
                }

                function selectIntersecting() {
                    var rb = detailedRubberBand.selectionRect
                    if (rb.width < 4 && rb.height < 4) return

                    var newSel = []
                    var c = listView.count
                    for (var i = 0; i < c; i++) {
                        var item = listView.itemAtIndex(i)
                        if (!item) continue
                        var itemPos = listView.mapFromItem(item, 0, 0)
                        var itemRect = Qt.rect(itemPos.x, itemPos.y, item.width, item.height)
                        if (selectionController.rectsIntersect(rb, itemRect))
                            newSel.push(i)
                    }
                    root.selectedIndices = newSel
                }
            }

            RubberBand {
                id: detailedRubberBand
                anchors.fill: parent
                z: 11
            }

        }
    }

    KineticWheelScroller {
        id: wheelScroller
        anchors.fill: parent
        z: 12
        flickable: listView
        wheelStep: 42
        mouseWheelMultiplier: 0.75 * config.scrollSpeed
        touchpadMultiplier: 1.35
        minVelocity: 135
        maxVelocity: 3900
        kineticGain: 1.01
        onScrollStarted: root.interactionStarted()
    }

    Connections {
        target: root.viewModel
        ignoreUnknownSignals: true

        function onModelReset() {
            selectionController.schedulePendingFocus()
        }

        function onRowsInserted() {
            selectionController.schedulePendingFocus()
        }
    }

}
