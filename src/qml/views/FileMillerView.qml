import QtQuick
import QtQuick.Controls
import Wayfile
import Quill as Q

FocusScope {
    id: root
    Accessible.role: Accessible.Pane
    Accessible.name: "Miller columns view"

    property var fileModel: null
    property string currentPath: ""

    property alias selectedIndices: selectionController.selectedIndices
    property alias lastSelectedIndex: selectionController.lastSelectedIndex
    property alias cursorIndex: selectionController.cursorIndex

    signal fileActivated(string filePath, bool isDirectory)
    signal contextMenuRequested(string filePath, bool isDirectory, point position)
    signal selectionChanged()
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

    // Track which folder in parent column leads to currentPath
    readonly property string parentPath: {
        if (!currentPath || currentPath === "/") return ""
        var parent = fileOps.parentPath(currentPath)
        return parent === currentPath ? "" : parent
    }

    readonly property string currentDirName: currentPath ? fileOps.displayNameForPath(currentPath) : ""

    property int rowHeight: 28
    readonly property int minRowHeight: 22
    readonly property int maxRowHeight: 56
    readonly property int millerIconSize: Math.round(rowHeight * 0.571)  // 16 at default 28

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

    function syncParentModel() {
        if (!visible)
            return

        if (parentPath) {
            millerParentModel.setRootPath(parentPath)
        } else {
            millerParentModel.setRootPath("")
        }
    }

    onCurrentPathChanged: {
        syncParentModel()
        // See FileGridView/FileDetailedView: reset sticky drag state so
        // wheel scrolling works immediately after navigation without the
        // user needing to click an item first.
        if (currentColumn) currentColumn.interactive = true
        if (parentColumn) parentColumn.interactive = true
    }

    // Forwarders for external callers (FileViewContainer / Main.qml).
    function selectAll() { selectionController.selectAll() }
    function focusPath(path, reveal) { selectionController.focusPath(path, reveal) }
    function clearSelection() { selectionController.clearSelection() }

    function ensureCurrentColumnFocus() {
        currentColumn.forceActiveFocus()
        if (selectionController.cursorIndex >= 0) {
            currentColumn.positionViewAtIndex(selectionController.cursorIndex, ListView.Contain)
            return
        }
        if (selectionController.selectedIndices.length > 0) {
            currentColumn.positionViewAtIndex(
                selectionController.selectedIndices[selectionController.selectedIndices.length - 1],
                ListView.Contain
            )
            return
        }
        if (currentColumn.count > 0) {
            selectionController.selectIndex(0, false, false)
            currentColumn.positionViewAtIndex(0, ListView.Beginning)
        }
    }

    onVisibleChanged: {
        if (!visible)
            return
        syncParentModel()
        Qt.callLater(root.ensureCurrentColumnFocus)
    }

    Component.onCompleted: {
        if (visible)
            Qt.callLater(root.ensureCurrentColumnFocus)
    }

    function enterDirectory(dirPath) {
        root.fileActivated(dirPath, true)
    }

    function goUp() {
        if (parentPath) {
            // Remember current dir so we can highlight it after navigating up
            selectionController.pendingFocusPath = currentPath
            selectionController.pendingFocusReveal = true
            root.fileActivated(parentPath, true)
        }
    }

    function updatePreview() {
        if (!visible) {
            millerPreviewModel.setRootPath("")
            previewColumn.previewFilePath = ""
            previewColumn.previewIsDir = false
            return
        }

        var idx = selectionController.cursorIndex >= 0 ? selectionController.cursorIndex
            : (selectionController.selectedIndices.length > 0 ? selectionController.selectedIndices[selectionController.selectedIndices.length - 1] : -1)
        if (idx < 0 || !fileModel) {
            millerPreviewModel.setRootPath("")
            previewColumn.previewFilePath = ""
            previewColumn.previewIsDir = false
            return
        }
        var fp = selectionController.pathForRow(idx)
        var isDir = selectionController.isDirForRow(idx)
        // Set previewIsDir BEFORE previewFilePath. The shared PreviewState
        // binds filePath to previewFilePath, so assigning previewFilePath
        // triggers its refresh(), which reads isDir (bound to previewIsDir) to
        // pick the preview type (isImage/isPdf/isText are gated on !isDir).
        // Setting it afterward left the first refresh running against the
        // previous item's previewIsDir (e.g. true from a folder), so every type
        // flag was false and the first preview after a directory load was blank.
        previewColumn.previewIsDir = isDir
        previewColumn.previewFilePath = fp
        if (isDir) {
            millerPreviewModel.setRootPath(fp)
        } else {
            millerPreviewModel.setRootPath("")
        }
    }

    // Shared selection / type-ahead / focus state. Lives at root level (not on
    // currentColumn) so root, the delegate, and the rubber-band MouseArea all
    // reach it. Every mutating function emits selectionChanged(); Miller wires
    // that to BOTH updatePreview() and root.selectionChanged() so selecting an
    // item refreshes the preview column and the status bar — the side-effects
    // each currentColumn mutator used to fire inline.
    SelectionController {
        id: selectionController
        fileModel: root.fileModel
        itemCount: currentColumn.count
        onSelectionChanged: {
            root.updatePreview()
            root.selectionChanged()
        }
        onEnsureIndexVisible: (index, mode) => currentColumn.positionViewAtIndex(
            index, mode === selectionController.positionBeginning ? ListView.Beginning : ListView.Contain)
        onRequestFocus: currentColumn.forceActiveFocus()
    }

    Row {
        anchors.fill: parent

        // ── Parent column (20%) ───────────────────────────────────────────
        ListView {
            id: parentColumn
            width: Math.floor(root.width * 0.2)
            height: root.height
            clip: true
            reuseItems: true
            cacheBuffer: 512
            model: millerParentModel
            focus: false
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: false

            property bool revealScheduled: false

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            function pathForRow(row) {
                if (!millerParentModel || row < 0)
                    return ""
                if (millerParentModel.filePath)
                    return millerParentModel.filePath(row)
                return millerParentModel.data(millerParentModel.index(row, 0), 258) || ""
            }

            function rowForPath(path) {
                if (!path)
                    return -1
                for (var i = 0; i < count; ++i) {
                    if (pathForRow(i) === path)
                        return i
                }
                return -1
            }

            function revealCurrentDir() {
                if (!root.parentPath || count <= 0)
                    return
                var idx = rowForPath(root.currentPath)
                if (idx >= 0)
                    positionViewAtIndex(idx, ListView.Contain)
            }

            function scheduleRevealCurrentDir() {
                if (revealScheduled)
                    return
                revealScheduled = true
                Qt.callLater(function() {
                    revealScheduled = false
                    revealCurrentDir()
                })
            }

            Connections {
                target: root

                function onCurrentPathChanged() {
                    parentColumn.scheduleRevealCurrentDir()
                }
            }

            Connections {
                target: millerParentModel
                ignoreUnknownSignals: true

                function onModelReset() {
                    parentColumn.scheduleRevealCurrentDir()
                }

                function onRowsInserted() {
                    parentColumn.scheduleRevealCurrentDir()
                }
            }

            // Right arrow from parent → focus middle column
            Keys.onRightPressed: (event) => {
                root.ensureCurrentColumnFocus()
                event.accepted = true
            }

            delegate: Item {
                id: parentDelegate
                width: parentColumn.width
                height: root.rowHeight

                required property int index
                required property string fileName
                required property string filePath
                required property bool isDir
                required property string fileIconName
                required property string fileCategory
                required property string fileExtension
                required property string gitStatusIcon

                readonly property bool isCurrentDir: parentDelegate.fileName === root.currentDirName

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: Theme.radiusSmall
                    color: {
                        if (parentDelegate.isCurrentDir)
                            return parentMa.containsMouse
                                ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.95)
                                : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.72)
                        if (parentMa.containsMouse)
                            return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
                        if (parentDelegate.index % 2 === 1)
                            return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.025)
                        return "transparent"
                    }
                    border.color: "transparent"
                    border.width: 0

                    Rectangle {
                        visible: parentDelegate.isCurrentDir
                        width: 3
                        height: parent.height - 10
                        radius: width / 2
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.9)
                    }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: parentDelegate.isCurrentDir ? 12 : 6
                        anchors.rightMargin: 4
                        spacing: 6

                        Item {
                            width: root.millerIconSize; height: root.millerIconSize
                            anchors.verticalCenter: parent.verticalCenter
                            opacity: parentDelegate.isCurrentDir ? 0.95 : 0.8

                            IconFolder {
                                visible: parentDelegate.isDir
                                anchors.centerIn: parent
                                size: root.millerIconSize
                                color: FileTypeColors.folder
                            }
                            FileTypeChip {
                                visible: !parentDelegate.isDir
                                anchors.fill: parent
                                size: root.millerIconSize
                                readonly property var desc: FileTypeColors.chipFor(
                                    parentDelegate.fileExtension, parentDelegate.fileCategory,
                                    parentDelegate.fileName.startsWith("."))
                                label: desc.label
                                tint: desc.color
                            }
                            GitBadge {
                                statusIcon: parentDelegate.gitStatusIcon
                                size: 11
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.rightMargin: -2
                                anchors.bottomMargin: -2
                                z: 4
                            }
                        }

                        Text {
                            width: parent.width - root.millerIconSize - parent.spacing - (parentDelegate.isDir ? root.millerIconSize : 0) - parent.anchors.leftMargin - parent.anchors.rightMargin
                            anchors.verticalCenter: parent.verticalCenter
                            text: parentDelegate.fileName
                            color: parentDelegate.isCurrentDir ? Theme.text : Theme.subtext
                            font.pointSize: Theme.fontSmall
                            font.bold: parentDelegate.isCurrentDir
                            elide: Text.ElideRight
                        }

                        IconChevronRight {
                            visible: parentDelegate.isDir
                            size: root.millerIconSize
                            anchors.verticalCenter: parent.verticalCenter
                            color: parentDelegate.isCurrentDir
                                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.75)
                                : Theme.subtext
                        }
                    }
                }

                MouseArea {
                    id: parentMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.interactionStarted()
                        parentColumn.forceActiveFocus()
                        if (parentDelegate.isDir) {
                            root.fileActivated(parentDelegate.filePath, true)
                        }
                    }
                }
            }
        }

        Rectangle {
            width: 1
            height: root.height
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)
        }

        // ── Current column (50%) ─────────────────────────────────────────
        ListView {
            id: currentColumn
            width: Math.floor(root.width * 0.5) - 1
            height: root.height
            clip: true
            reuseItems: true
            cacheBuffer: 512
            model: root.fileModel
            focus: root.visible
            boundsBehavior: Flickable.StopAtBounds
            boundsMovement: Flickable.StopAtBounds
            keyNavigationEnabled: false
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

            Connections {
                target: root
                function onCurrentPathChanged() {
                    selectionController.resetTypeAhead()
                    // If we have a pendingFocusPath (going up), don't clear — let focusPath handle it
                    if (selectionController.pendingFocusPath === "") {
                        selectionController.selectedIndices = []
                        selectionController.lastSelectedIndex = -1
                        selectionController.cursorIndex = -1
                        // Auto-select first item after model loads
                        selectionController.autoSelectFirst = true
                    }
                    root.updatePreview()
                }
            }

            // z:20 keeps the thumb above the z:10 rubber-band MouseArea so it stays draggable.
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; z: 20; interactive: true }

            // Linear up/down navigation stays in the view (arrow-key coupled);
            // it delegates the actual state change + positioning + side-effects
            // to the shared controller's moveSelectionTo.
            function moveSelection(delta, extend) {
                if (count <= 0) return
                var current = selectionController.cursorIndex >= 0 ? selectionController.cursorIndex
                    : (selectionController.selectedIndices.length > 0 ? selectionController.selectedIndices[selectionController.selectedIndices.length - 1] : -1)
                var next = Math.max(0, Math.min(count - 1, current + delta))
                if (next === current && current >= 0) return
                selectionController.moveSelectionTo(next, extend)
            }

            // Stays in the view: the activate policy is Miller-specific
            // (dirs drill in via enterDirectory, files open via fileActivated).
            function activateCurrentSelection() {
                var idx = selectionController.cursorIndex >= 0 ? selectionController.cursorIndex
                    : (selectionController.selectedIndices.length > 0 ? selectionController.selectedIndices[selectionController.selectedIndices.length - 1] : -1)
                if (idx < 0) return
                var fp = selectionController.pathForRow(idx)
                var isDir = selectionController.isDirForRow(idx)
                if (isDir) {
                    root.enterDirectory(fp)
                } else {
                    root.fileActivated(fp, false)
                }
            }

            Connections {
                target: root.fileModel
                ignoreUnknownSignals: true
                function onModelReset() { selectionController.schedulePendingFocus() }
                function onRowsInserted() { selectionController.schedulePendingFocus() }
            }

            Keys.onUpPressed: (event) => moveSelection(-1, event.modifiers & Qt.ShiftModifier)
            Keys.onDownPressed: (event) => moveSelection(1, event.modifiers & Qt.ShiftModifier)
            Keys.onRightPressed: (event) => {
                activateCurrentSelection()
                event.accepted = true
            }
            Keys.onLeftPressed: (event) => {
                root.goUp()
                event.accepted = true
            }
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Home) {
                    selectionController.moveSelectionTo(0, event.modifiers & Qt.ShiftModifier)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_End) {
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
                    } else if (selectionController.selectedIndices.length > 0) {
                        selectionController.clearSelection()
                    }
                    event.accepted = true
                    return
                }
                selectionController.handleTypeAhead(event)
            }

            delegate: MillerCurrentRow {
                rowHeight: root.rowHeight
                millerIconSize: root.millerIconSize
                selectedIndices: root.selectedIndices
                rowRoot: root
                listViewRef: currentColumn
                selectionControllerRef: selectionController
                wheelScrollerRef: currentWheelScroller
            }

            // ── Merged-selection overlay ─────────────────────────────────
            // Same transparent-Rectangle+border pattern as FileDetailedView
            // (renders as a ListView child, border on bg = visible). One block
            // per contiguous run; y tracks contentY; rows render transparent.
            Item {
                anchors.fill: parent
                z: -1
                Repeater {
                    model: root.selectionRuns
                    delegate: Item {
                        x: 2
                        y: modelData.start * root.rowHeight - currentColumn.contentY + 2
                        width: currentColumn.width - 4
                        height: (modelData.end - modelData.start + 1) * root.rowHeight - 4

                        Rectangle {   // inset fill — handoff gold gradient
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: Math.max(0, Theme.radiusMedium - 1)
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.18) }
                                GradientStop { position: 1.0; color: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.04) }
                            }
                        }
                        Rectangle {   // outline — transparent fill, gold border
                            anchors.fill: parent
                            radius: Theme.radiusMedium
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.accent
                        }
                    }
                }
            }

            DropArea {
                anchors.fill: parent
                keys: ["text/uri-list"]
                z: -2

                onDropped: (drop) => {
                    if (!root.currentPath) return
                    var paths = root.dropPaths(drop)
                    if (paths.length === 0) return
                    var allSameDir = paths.every(function(p) {
                        var parentDir = p.substring(0, p.lastIndexOf("/"))
                        return parentDir === root.currentPath
                    })
                    if (allSameDir) return
                    root.transferRequested(paths, root.currentPath, drop.proposedAction !== Qt.CopyAction)
                    drop.accept()
                }
            }

            // ── Rubber-band selection + empty space clicks ───────────────
            MouseArea {
                id: currentBgMa
                anchors.fill: parent
                z: 10
                preventStealing: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                property point dragStart
                property bool rubberBandActive: false
                property bool rubberBandJustFinished: false

                onWheel: (wheel) => {
                    if (wheel.modifiers & Qt.ControlModifier) {
                        currentWheelScroller.stopAndSettle()
                        root.interactionStarted()
                        var delta = currentWheelScroller.deltaFor(wheel)
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
                    var idx = currentColumn.indexAt(mouse.x + currentColumn.contentX, mouse.y + currentColumn.contentY)
                    if (idx >= 0) {
                        mouse.accepted = false
                        return
                    }
                    currentWheelScroller.stopAndSettle()
                    root.interactionStarted()
                    currentColumn.forceActiveFocus()
                    if (mouse.button === Qt.LeftButton) {
                        currentColumn.interactive = false
                        dragStart = Qt.point(mouse.x, mouse.y)
                        currentRubberBand.begin(dragStart)
                        rubberBandActive = true
                    }
                }

                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        var mp = currentBgMa.mapToItem(null, mouse.x, mouse.y)
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
                        currentRubberBand.update(Qt.point(mouse.x, mouse.y))
                        selectIntersecting()
                    }
                }

                onReleased: {
                    var wasRubberBand = rubberBandActive && currentRubberBand.visible
                    currentRubberBand.end()
                    rubberBandActive = false
                    rubberBandJustFinished = wasRubberBand
                    currentColumn.interactive = true
                }

                function selectIntersecting() {
                    var rb = currentRubberBand.selectionRect
                    if (rb.width < 4 && rb.height < 4) return

                    var newSel = []
                    var c = currentColumn.count
                    for (var i = 0; i < c; i++) {
                        var item = currentColumn.itemAtIndex(i)
                        if (!item) continue
                        var itemPos = currentColumn.mapFromItem(item, 0, 0)
                        var itemRect = Qt.rect(itemPos.x, itemPos.y, item.width, item.height)
                        if (selectionController.rectsIntersect(rb, itemRect))
                            newSel.push(i)
                    }
                    selectionController.selectedIndices = newSel
                }
            }

            RubberBand {
                id: currentRubberBand
                anchors.fill: parent
                z: 11
            }

            KineticWheelScroller {
                id: currentWheelScroller
                anchors.fill: parent
                z: 12
                flickable: currentColumn
                wheelStep: 42
                mouseWheelMultiplier: 0.75 * config.scrollSpeed
                touchpadMultiplier: 1.35
                minVelocity: 135
                maxVelocity: 3900
                kineticGain: 1.01
                onScrollStarted: root.interactionStarted()
            }
        }

        Rectangle {
            width: 1
            height: root.height
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)
        }

        // ── Preview column (30%) ─────────────────────────────────────────
        MillerPreviewColumn {
            id: previewColumn
            width: root.width - Math.floor(root.width * 0.2) - Math.floor(root.width * 0.5) - 1
            height: root.height
            clip: true
        }
    }
}
