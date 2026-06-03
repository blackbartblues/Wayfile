import QtQuick
import Heimdall
import Quill as Q

// One row of the Miller middle (current) column, extracted from
// FileMillerView.qml as the ListView delegate. Layout metrics and selection
// state come down via explicit typed properties (rowHeight, millerIconSize,
// selectedIndices) so their bindings re-fire when the source changes; the
// shared collaborator objects (rowRoot, listViewRef, selectionControllerRef,
// wheelScrollerRef) are passed in for imperative calls in handlers. dragHelper,
// fileOps, clipboard, config are global context properties, referenced directly.
Item {
    id: row

    // The FileMillerView root, used only for imperative calls in handlers:
    // dropPaths(), and the interactionStarted/contextMenuRequested/
    // transferRequested signals (emitted by calling them, as the inline
    // delegate did via `root`). Reactive state is passed as the explicit typed
    // properties below instead — reads through a var-typed ref inside a binding
    // don't reliably capture the source's change signal, so the selection
    // highlight (isSelected) would go stale.
    property var rowRoot
    property var listViewRef
    property var selectionControllerRef
    property var wheelScrollerRef

    // Reactive state, bound from the (typed) FileMillerView root so the
    // bindings below re-evaluate when it changes.
    property var selectedIndices: []
    property int rowHeight: 28
    property int millerIconSize: 16

    // listViewRef is the owning ListView (currentColumn), passed in by the
    // parent. It is briefly undefined while the delegate is being constructed
    // (the parent assigns it right after), so the width binding is guarded. The
    // ListView.view attached property is NOT used because it is only valid on
    // the delegate root, not on the nested handlers that also need the view
    // (e.g. forceActiveFocus).
    width: listViewRef ? listViewRef.width : 0
    height: rowHeight

    required property int index
    required property string fileName
    required property string filePath
    required property var fileModified
    required property string fileSizeText
    required property string fileModifiedText
    required property bool isDir
    required property string fileIconName
    required property string gitStatus
    required property string gitStatusIcon
    required property bool hasImagePreview
    required property bool hasVideoPreview
    required property string fileCategory
    required property string fileExtension

    readonly property bool isSelected: selectedIndices.indexOf(index) >= 0
    readonly property bool isCutPending: clipboard.isCut && clipboard.contains(row.filePath)
    readonly property bool isPastePending: fileOps.pendingTargetPaths.indexOf(row.filePath) >= 0

    property bool dragStarted: false

    DropArea {
        id: folderDropArea
        anchors.fill: parent
        keys: ["text/uri-list"]
        enabled: row.isDir && !row.isSelected

        onDropped: (drop) => {
            var paths = rowRoot.dropPaths(drop)
            if (paths.length === 0) return
            var dominated = paths.some(function(p) {
                return row.filePath === p || row.filePath.startsWith(p + "/")
            })
            if (dominated) return
            rowRoot.transferRequested(paths, row.filePath, drop.proposedAction !== Qt.CopyAction)
            drop.acceptProposedAction()
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Theme.radiusSmall
        opacity: row.dragStarted ? 0.5 : 1.0
        color: {
            if (folderDropArea.containsDrag)
                return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
            if (currentDelegateMa.containsMouse)
                return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
            // Selection fill + outline drawn by FileMillerView's overlay;
            // the row goes transparent so it shows through.
            if (row.isSelected)
                return "transparent"
            if (row.index % 2 === 1)
                return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.025)
            return "transparent"
        }
        // Selection outline is the overlay; per-row border is drop-target only.
        border.color: folderDropArea.containsDrag ? Theme.accent : "transparent"
        border.width: folderDropArea.containsDrag ? 2 : 0

        Row {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 4
            spacing: 6

            Item {
                id: iconSlot
                width: millerIconSize + 2; height: millerIconSize + 2
                anchors.verticalCenter: parent.verticalCenter

                readonly property bool hasThumbnail: !fileOps.isRemotePath(row.filePath)
                    && (row.hasImagePreview || row.hasVideoPreview)

                // Folders get a clean gold folder glyph (folder = gold tint;
                // the glossy OsFolder is too muddy at row size).
                IconFolder {
                    visible: !iconSlot.hasThumbnail && row.isDir
                    anchors.centerIn: parent
                    size: millerIconSize + 2
                    color: FileTypeColors.folder
                }

                // Files (without a thumbnail) get a metallic type chip.
                FileTypeChip {
                    visible: !iconSlot.hasThumbnail && !row.isDir
                    anchors.fill: parent
                    size: millerIconSize + 2
                    readonly property var desc: FileTypeColors.chipFor(
                        row.fileExtension, row.fileCategory,
                        row.fileName.startsWith("."))
                    label: desc.label
                    tint: desc.color
                }

                Image {
                    anchors.fill: parent
                    visible: parent.hasThumbnail
                    fillMode: Image.PreserveAspectFit
                    source: parent.hasThumbnail
                        ? ("image://thumbnail/" + row.filePath
                           + "?mtime=" + new Date(row.fileModified).getTime())
                        : ""
                    sourceSize: Qt.size(64 * Screen.devicePixelRatio, 64 * Screen.devicePixelRatio)
                    asynchronous: true
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: -3
                    anchors.rightMargin: -3
                    width: 12
                    height: 12
                    radius: 6
                    z: 2
                    color: Qt.rgba(Theme.mantle.r, Theme.mantle.g, Theme.mantle.b, 0.96)
                    border.width: 1
                    border.color: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.9)
                    opacity: row.isCutPending ? 1 : 0
                    scale: row.isCutPending ? 1 : 0.88
                    visible: opacity > 0

                    Behavior on opacity { NumberAnimation { duration: Theme.animDurationFast; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve } }
                    Behavior on scale { NumberAnimation { duration: Theme.animDurationFast; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve } }

                    IconScissors {
                        anchors.centerIn: parent
                        size: 7
                        color: Theme.warning
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    radius: 8
                    z: 3
                    color: Qt.rgba(Theme.mantle.r, Theme.mantle.g, Theme.mantle.b, 0.92)
                    border.width: 1
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                    opacity: row.isPastePending ? 1 : 0
                    scale: row.isPastePending ? 1 : 0.9
                    visible: opacity > 0

                    Behavior on opacity { NumberAnimation { duration: Theme.animDurationFast; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve } }
                    Behavior on scale { NumberAnimation { duration: Theme.animDurationFast; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve } }

                    Q.Spinner {
                        anchors.centerIn: parent
                        size: "small"
                        color: Theme.accent
                        running: row.isPastePending
                        scale: 0.6
                    }
                }

                // Git status badge — backing disc keeps the small
                // icon legible over the file icon and above the
                // cut/paste overlays (z:2/3).
                Rectangle {
                    visible: row.gitStatus !== ""
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: -3
                    anchors.bottomMargin: -3
                    width: 14
                    height: 14
                    radius: 7
                    z: 4
                    color: Qt.rgba(Theme.mantle.r, Theme.mantle.g, Theme.mantle.b, 0.92)
                    border.width: 1
                    border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.18)

                    Loader {
                        anchors.centerIn: parent
                        width: 10; height: 10
                        sourceComponent: {
                            switch (row.gitStatusIcon) {
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
                }
            }

            Text {
                width: parent.width - (millerIconSize + 2) - (row.isDir ? (millerIconSize + 2) : 0) - parent.spacing * (row.isDir ? 2 : 1) - parent.anchors.leftMargin - parent.anchors.rightMargin
                anchors.verticalCenter: parent.verticalCenter
                text: row.fileName
                color: Theme.text
                font.pointSize: Theme.fontSmall
                elide: Text.ElideRight
            }

            IconChevronRight {
                visible: row.isDir
                size: millerIconSize + 2
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.subtext
            }
        }
    }

    MouseArea {
        id: currentDelegateMa
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        property point pressPos
        property bool dragPending: false

        onPressed: (mouse) => {
            wheelScrollerRef.stopAndSettle()
            rowRoot.interactionStarted()
            listViewRef.forceActiveFocus()
            pressPos = Qt.point(mouse.x, mouse.y)
            dragPending = (mouse.button === Qt.LeftButton)
        }

        onPositionChanged: (mouse) => {
            if (!dragPending) return
            var dx = mouse.x - pressPos.x
            var dy = mouse.y - pressPos.y
            if (Math.sqrt(dx*dx + dy*dy) > 10) {
                dragPending = false
                if (!row.isSelected)
                    selectionControllerRef.selectIndex(row.index, false, false)
                var paths = selectedIndices.length > 1
                    ? selectedIndices.map(function(i) { return selectionControllerRef.pathForRow(i) })
                    : [row.filePath]
                row.dragStarted = true
                dragHelper.startDrag(paths, row.fileIconName, paths.length)
            }
        }

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                var mapped = currentDelegateMa.mapToItem(null, mouse.x, mouse.y)
                // Right-clicking an unselected item selects it first
                // (single-select) so the menu targets the clicked
                // file; an already-selected item keeps the selection.
                if (!row.isSelected)
                    selectionControllerRef.selectIndex(row.index, false, false)
                rowRoot.contextMenuRequested(
                    row.filePath,
                    row.isDir,
                    Qt.point(mapped.x, mapped.y)
                )
                return
            }
            selectionControllerRef.selectIndex(
                row.index,
                mouse.modifiers & Qt.ControlModifier,
                mouse.modifiers & Qt.ShiftModifier
            )
        }

        onDoubleClicked: (mouse) => {
            if (mouse.button !== Qt.LeftButton) return
            listViewRef.activateCurrentSelection()
        }

        onReleased: { dragPending = false }
        onCanceled: { dragPending = false }

        Connections {
            target: dragHelper
            function onDragFinished() { row.dragStarted = false }
        }
    }

    Component { id: gitModifiedIcon;   IconGitModified   { size: 10 } }
    Component { id: gitStagedIcon;     IconGitStaged     { size: 10 } }
    Component { id: gitUntrackedIcon;  IconGitUntracked  { size: 10 } }
    Component { id: gitDeletedIcon;    IconGitDeleted    { size: 10 } }
    Component { id: gitRenamedIcon;    IconGitRenamed    { size: 10 } }
    Component { id: gitConflictedIcon; IconGitConflicted { size: 10 } }
    Component { id: gitIgnoredIcon;    IconGitIgnored    { size: 10 } }
    Component { id: gitDirtyIcon;      IconGitDirty      { size: 10 } }
}
