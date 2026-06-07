import QtQuick
import Wayfile
import Quill as Q

// One row of the detailed (table) file view, extracted from FileDetailedView.qml
// as the ListView delegate. Layout metrics and selection state come down via the
// `view` reference (the FileDetailedView root); the shared collaborator objects
// (listView, selectionControllerRef, wheelScrollerRef) are passed in so the row can
// drive selection/scroll/focus exactly as it did inline. dragHelper, fileOps,
// clipboard, config are global context properties, referenced directly.
Item {
    id: detRow

    // The FileDetailedView root, used only for imperative calls in handlers:
    // dropPaths(), and the fileActivated/contextMenuRequested/transferRequested/
    // interactionStarted signals (emitted by calling them, as the inline
    // delegate did via `root`). Reactive state is passed as the explicit
    // properties below instead — reads through a var-typed `view` inside a
    // binding don't reliably capture the source's change signal, so the
    // selection highlight (isSelected) and live column widths would go stale.
    property var view
    property var listViewRef
    property var selectionControllerRef
    property var wheelScrollerRef

    // Reactive state, bound from the (typed) FileDetailedView root so the
    // bindings below re-evaluate when it changes.
    property var selectedIndices: []
    property var folderItemCounts: ({})
    property int colName: 0
    property int colSize: 0
    property int colModified: 0
    property int colType: 0
    property int rowHeight: 28
    property int detailIconSize: 16

    // listViewRef is the owning ListView, passed in by the parent. It is briefly
    // undefined while the delegate is being constructed (the parent assigns it
    // right after), so the width binding is guarded. The ListView.view attached
    // property is NOT used because it is only valid on the delegate root, not on
    // the nested handlers that also need the view (e.g. forceActiveFocus).
    width: listViewRef ? listViewRef.width : 0
    height: rowHeight
    Accessible.role: Accessible.ListItem
    Accessible.name: fileName + (isDir ? ", folder" : ", " + fileType + ", " + fileSizeText)
    Accessible.selected: isSelected

    required property int index
    required property string fileName
    required property string filePath
    required property var fileModified
    required property string fileSizeText
    required property string fileModifiedText
    required property string fileType
    required property bool isDir
    required property string fileIconName
    required property string gitStatus
    required property string gitStatusIcon
    required property bool hasImagePreview
    required property bool hasVideoPreview
    required property string fileCategory
    required property string fileExtension

    readonly property bool isSelected: selectedIndices.indexOf(index) >= 0
    readonly property bool isCutPending: clipboard.isCut && clipboard.contains(detRow.filePath)
    readonly property bool isPastePending: fileOps.pendingTargetPaths.indexOf(detRow.filePath) >= 0

    property bool dragStarted: false

    DropArea {
        id: folderDropArea
        anchors.fill: parent
        keys: ["text/uri-list"]
        enabled: detRow.isDir && !detRow.isSelected

        onDropped: (drop) => {
            var paths = view.dropPaths(drop)
            if (paths.length === 0) return
            var dominated = paths.some(function(p) {
                return detRow.filePath === p || detRow.filePath.startsWith(p + "/")
            })
            if (dominated) return
            view.transferRequested(paths, detRow.filePath, drop.proposedAction !== Qt.CopyAction)
            drop.acceptProposedAction()
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Theme.radiusSmall
        opacity: detRow.dragStarted ? 0.5 : 1.0
        color: {
            if (folderDropArea.containsDrag)
                return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
            if (rowMa.containsMouse)
                return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
            // Selection fill + outline drawn by FileDetailedView's overlay;
            // the row goes transparent so it shows through.
            if (detRow.isSelected)
                return "transparent"
            // Alternating rows
            if (detRow.index % 2 === 0)
                return "transparent"
            return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.025)
        }
        Behavior on color { ColorAnimation { duration: Theme.animDuration } }
        // Selection outline is the overlay; per-row border is drop-target only.
        border.color: folderDropArea.containsDrag ? Theme.accent : "transparent"
        border.width: folderDropArea.containsDrag ? 2 : 0

        // Handoff: right-edge gold chevron on every selected row (files too).
        IconChevronRight {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 6
            size: 14
            color: Theme.accent
            visible: detRow.isSelected
            z: 1
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 0

            // Name
            Row {
                width: colName
                height: parent.height
                spacing: 6

                // Icon with git badge
                Item {
                    id: iconSlot
                    width: detailIconSize
                    height: detailIconSize
                    anchors.verticalCenter: parent.verticalCenter

                    readonly property bool hasThumbnail: !fileOps.isRemotePath(detRow.filePath)
                        && (detRow.hasImagePreview || detRow.hasVideoPreview)

                    // Folders get a clean gold folder glyph (folder = gold tint;
                    // the glossy OsFolder is too muddy at row size).
                    IconFolder {
                        visible: !iconSlot.hasThumbnail && detRow.isDir
                        anchors.centerIn: parent
                        size: detailIconSize
                        color: FileTypeColors.folder
                    }

                    // Files (without a thumbnail) get a metallic type chip.
                    FileTypeChip {
                        visible: !iconSlot.hasThumbnail && !detRow.isDir
                        anchors.fill: parent
                        size: detailIconSize
                        readonly property var desc: FileTypeColors.chipFor(
                            detRow.fileExtension, detRow.fileCategory,
                            detRow.fileName.startsWith("."))
                        label: desc.label
                        tint: desc.color
                    }

                    Image {
                        anchors.fill: parent
                        visible: parent.hasThumbnail
                        fillMode: Image.PreserveAspectFit
                        source: parent.hasThumbnail
                            ? ("image://thumbnail/" + detRow.filePath
                               + "?mtime=" + new Date(detRow.fileModified).getTime())
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
                        opacity: detRow.isCutPending ? 1 : 0
                        scale: detRow.isCutPending ? 1 : 0.88
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
                        opacity: detRow.isPastePending ? 1 : 0
                        scale: detRow.isPastePending ? 1 : 0.9
                        visible: opacity > 0

                        Behavior on opacity { NumberAnimation { duration: Theme.animDurationFast; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve } }
                        Behavior on scale { NumberAnimation { duration: Theme.animDurationFast; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve } }

                        Q.Spinner {
                            anchors.centerIn: parent
                            size: "small"
                            color: Theme.accent
                            running: detRow.isPastePending
                            scale: 0.6
                        }
                    }

                    // Git status badge (handoff re-skin — obsidian disc + glyph).
                    GitBadge {
                        statusIcon: detRow.gitStatusIcon
                        size: 12
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: -3
                        anchors.bottomMargin: -3
                        z: 4
                    }
                }

                Text {
                    width: colName - 20
                    anchors.verticalCenter: parent.verticalCenter
                    text: detRow.fileName
                    color: Theme.text
                    font.pointSize: Theme.fontSmall
                    elide: Text.ElideRight
                }
            }

            // Modified
            Text {
                width: colModified
                anchors.verticalCenter: parent.verticalCenter
                text: detRow.fileModifiedText
                color: Theme.subtext
                font.pointSize: Theme.fontSmall
                horizontalAlignment: Text.AlignRight
                rightPadding: 8
            }

            // Type
            Text {
                width: colType
                anchors.verticalCenter: parent.verticalCenter
                text: detRow.fileType
                color: Theme.subtext
                font.pointSize: Theme.fontSmall
                elide: Text.ElideRight
                rightPadding: 8
            }

            // Size
            Text {
                width: colSize
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (detRow.isDir) {
                        var cnt = folderItemCounts[detRow.filePath]
                        if (cnt !== undefined)
                            return cnt + (cnt === 1 ? " item" : " items")
                        return "—"
                    }
                    return detRow.fileSizeText
                }
                color: Theme.subtext
                font.pointSize: Theme.fontSmall
                horizontalAlignment: Text.AlignRight
                rightPadding: 8
            }

        }

        MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            property point pressPos
            property bool dragPending: false

            onPressed: (mouse) => {
                wheelScrollerRef.stopAndSettle()
                view.interactionStarted()
                // Claim focus immediately so arrow keys / type-ahead
                // work after clicking a row. Without this, focus can
                // linger on the toolbar / path bar / other pane and
                // ListView.Keys handlers never fire.
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
                    if (!detRow.isSelected)
                        selectionControllerRef.selectIndex(detRow.index, false, false)
                    var paths = selectedIndices.length > 1
                        ? selectedIndices.map(function(i) { return selectionControllerRef.pathForRow(i) })
                        : [detRow.filePath]
                    detRow.dragStarted = true
                    dragHelper.startDrag(paths, detRow.fileIconName, paths.length)
                }
            }

            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    var mapped = rowMa.mapToItem(null, mouse.x, mouse.y)
                    // Right-clicking an unselected row selects it
                    // first (single-select) so the menu targets the
                    // clicked file; an already-selected row keeps
                    // the (possibly multi-) selection.
                    if (!detRow.isSelected)
                        selectionControllerRef.selectIndex(detRow.index, false, false)
                    view.contextMenuRequested(
                        detRow.filePath,
                        detRow.isDir,
                        Qt.point(mapped.x, mapped.y)
                    )
                    return
                }
                selectionControllerRef.selectIndex(
                    detRow.index,
                    mouse.modifiers & Qt.ControlModifier,
                    mouse.modifiers & Qt.ShiftModifier
                )
            }

            onDoubleClicked: (mouse) => {
                if (mouse.button !== Qt.LeftButton) return
                view.fileActivated(detRow.filePath, detRow.isDir)
            }

            onReleased: { dragPending = false }
            onCanceled: { dragPending = false }

            Connections {
                target: dragHelper
                function onDragFinished() { detRow.dragStarted = false }
            }
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
    }
}
