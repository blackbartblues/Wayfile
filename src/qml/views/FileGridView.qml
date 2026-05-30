import QtQuick
import QtQuick.Controls
import Heimdall
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

    clip: true
    reuseItems: true
    // cacheBuffer deliberately modest — delegate reuse via reuseItems is the
    // big win; larger off-screen buffers just materialize thumbnails the
    // user may never scroll to.
    cacheBuffer: 512
    // Zoom controls column count, not icon size
    property int columnCount: 7
    readonly property int minColumns: 2
    readonly property int maxColumns: 12
    readonly property int minCellWidth: 140
    readonly property int effectiveColumnCount: Math.max(
        minColumns,
        Math.min(columnCount, Math.min(maxColumns, Math.max(1, Math.floor(width / minCellWidth))))
    )
    readonly property int labelHeight: 32  // two lines of text below icon
    readonly property int iconRequestSize: 96 * Screen.devicePixelRatio
    readonly property int thumbnailRequestSize: 256 * Screen.devicePixelRatio

    cellWidth: Math.floor(width / effectiveColumnCount)
    cellHeight: cellWidth  // square cells
    readonly property int iconSize: cellHeight - 8 - labelHeight - 5  // 8px top, 0px gap, 5px bottom

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
                from: 0.94
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
                to: 0.94
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
    Keys.onUpPressed: (event) => moveSelection(-effectiveColumnCount, event.modifiers & Qt.ShiftModifier)
    Keys.onDownPressed: (event) => moveSelection(effectiveColumnCount, event.modifiers & Qt.ShiftModifier)
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
        target: root.model
        ignoreUnknownSignals: true

        function onModelReset() {
            selectionController.schedulePendingFocus()
        }

        function onRowsInserted() {
            selectionController.schedulePendingFocus()
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

        Image {
            id: iconImg
            visible: !delegateItem.hasThumbnail
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 8
            width: root.iconSize
            height: root.iconSize
            source: "image://icon/" + delegateItem.fileIconName + "?theme=" + config.iconTheme + "&builtin=" + (config.builtinIcons ? "1" : "0")
            sourceSize: Qt.size(root.iconRequestSize, root.iconRequestSize)
            asynchronous: true
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

        // Git status overlay badge
        Loader {
            id: gitBadge
            active: delegateItem.gitStatus !== ""
            anchors.right: (iconImg.visible ? iconImg : thumbImg).right
            anchors.bottom: (iconImg.visible ? iconImg : thumbImg).bottom
            anchors.rightMargin: -2
            anchors.bottomMargin: -2
            width: 12
            height: 12
            sourceComponent: {
                switch (delegateItem.gitStatusIcon) {
                    case "git-modified":   return gitModifiedIcon
                    case "git-staged":     return gitStagedIcon
                    case "git-untracked":  return gitUntrackedIcon
                    case "git-deleted":    return gitDeletedIcon
                    case "git-renamed":    return gitRenamedIcon
                    case "git-conflicted": return gitConflictedIcon
                    case "git-ignored":    return gitIgnoredIcon
                    case "git-dirty":      return gitDirtyIcon
                    default: return null
                }
            }
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
                if (delegateItem.isSelected)
                    return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                if (ma.containsMouse)
                    return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.07)
                return "transparent"
            }
            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
            border.color: folderDropArea.containsDrag ? Theme.accent
                        : delegateItem.isSelected ? Theme.accent : "transparent"
            border.width: folderDropArea.containsDrag ? 2
                        : delegateItem.isSelected ? 2 : 0
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

        // Subtle background hint — only when not hovering a specific folder
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
            border.width: 1
            radius: Theme.radiusMedium
            visible: parent.containsDrag
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
                // Scroll up = zoom in = fewer columns (bigger icons)
                var delta = wheelScroller.deltaFor(wheel)
                if (delta === 0) {
                    wheel.accepted = false
                    return
                }
                var step = delta < 0 ? -1 : 1
                root.columnCount = Math.max(root.minColumns, Math.min(root.maxColumns, root.columnCount + step))
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

    Component { id: gitModifiedIcon;   IconGitModified   { size: 12 } }
    Component { id: gitStagedIcon;     IconGitStaged     { size: 12 } }
    Component { id: gitUntrackedIcon;  IconGitUntracked  { size: 12 } }
    Component { id: gitDeletedIcon;    IconGitDeleted    { size: 12 } }
    Component { id: gitRenamedIcon;    IconGitRenamed    { size: 12 } }
    Component { id: gitConflictedIcon; IconGitConflicted { size: 12 } }
    Component { id: gitIgnoredIcon;    IconGitIgnored    { size: 12 } }
    Component { id: gitDirtyIcon;      IconGitDirty      { size: 12 } }
}
