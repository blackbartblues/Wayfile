import QtQuick
import QtQuick.Layouts
import Heimdall

// One file-browser pane.  Wraps SplitPaneHeader + FileViewContainer with a
// rounded background, accent border for the active pane, and the splitTrans-
// itionProgress-driven radius/border-fade animation.
//
// Phase 1 M6: lifted out of Main.qml where the same ~70-line block existed
// twice (primaryPaneFrame + secondaryPaneFrame).  Per-pane positioning,
// the divider, and the secondary's scale/opacity envelope stay in Main.qml;
// this component renders the inside of one pane.
Rectangle {
    id: paneFrame

    // Bindings from Main.qml: which pane this is and the metadata + handlers
    // it needs.  Strings are passed through so existing dispatch helpers
    // (paneModel, panePath, etc.) keep working unchanged
    // for now; M7 swaps the dispatch over to indices.
    property int paneIndex: 0
    property bool active: false
    property bool splitViewPresented: false
    property real splitTransitionProgress: 0
    property var paneFileModel: null
    property string paneCurrentPath: ""
    property string paneViewMode: "grid"

    readonly property bool isPrimary: paneIndex === 0

    signal interactionStarted()
    signal fileActivated(string filePath, bool isDirectory)
    signal selectionChanged()
    signal transferRequested(var paths, string destinationPath, bool moveOperation)
    signal contextMenuRequested(string filePath, bool isDirectory, var position)
    // Column-header sort from this pane's detailed view; Main.qml applies it
    // tab-wide (see FileViewContainer.sortRequested).
    signal sortRequested(string column, bool ascending)
    // Phase 2 P2-M9: user-driven 'close this pane' (X button or Ctrl+W).
    // Main.qml routes this to TabModel.removePane(paneIndex); the receiver
    // handles the demote-to-single-pane / kill-the-tab edge cases.
    signal closeRequested()

    // Expose the inner FileViewContainer so Main.qml's fileViewForPane() can
    // still reach it through primaryPaneFrame.fileView or
    // secondaryPaneLoader.item.fileView (the old alias surface this replaced).
    property alias fileView: fileViewContainer

    // Primary fades its rounded corner in/out as split view opens/closes so it
    // visually "expands" to fill the whole content area.  Secondary keeps a
    // permanent rounded edge — its appearance is animated via opacity/scale on
    // the Loader wrapper in Main.qml.
    radius: isPrimary ? Theme.radiusMedium * splitTransitionProgress
                      : Theme.radiusMedium
    clip: true
    color: Theme.containerColor(Theme.crust, 0.14)

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        SplitPaneHeader {
            Layout.preferredHeight: visible ? 26 : 0
            visible: paneFrame.splitViewPresented
            path: paneFrame.paneCurrentPath
            // fileCount/folderCount are reactive (NOTIFY countsChanged) so the
            // strip count updates on every reload of this pane's model.
            itemCount: paneFrame.paneFileModel
                ? paneFrame.paneFileModel.fileCount + paneFrame.paneFileModel.folderCount
                : 0
            activePaneHeader: paneFrame.active
        }

        FileViewContainer {
            id: fileViewContainer
            Layout.fillWidth: true
            Layout.fillHeight: true
            fileModel: paneFrame.paneFileModel
            viewMode: paneFrame.paneViewMode
            currentPath: paneFrame.paneCurrentPath

            onInteractionStarted: paneFrame.interactionStarted()
            onFileActivated: (filePath, isDirectory) =>
                paneFrame.fileActivated(filePath, isDirectory)
            onSelectionChanged: paneFrame.selectionChanged()
            onTransferRequested: (paths, destinationPath, moveOperation) =>
                paneFrame.transferRequested(paths, destinationPath, moveOperation)
            onContextMenuRequested: (filePath, isDirectory, position) =>
                paneFrame.contextMenuRequested(filePath, isDirectory, position)
            onSortRequested: (column, ascending) =>
                paneFrame.sortRequested(column, ascending)
        }
    }

    // Border overlay: accent gold for the active pane, faint mantle line
    // otherwise.  Primary's border-width fades with the split transition so
    // it disappears when split is closed; secondary's stays at 1 px because
    // it only exists while split is presented anyway.
    Rectangle {
        anchors.fill: parent
        z: 10
        color: "transparent"
        radius: parent.radius
        border.width: paneFrame.isPrimary ? paneFrame.splitTransitionProgress : 1
        border.color: paneFrame.active
            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b,
                      paneFrame.isPrimary
                          ? 0.45 * paneFrame.splitTransitionProgress
                          : 0.45)
            : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b,
                      paneFrame.isPrimary
                          ? 0.08 * paneFrame.splitTransitionProgress
                          : 0.08)
        Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }
    }

    // Phase 2 P2-M9: close-this-pane button.  Shown only when the row is
    // already multi-pane (splitViewPresented) — single-pane tabs use the
    // tab strip's × instead.  Sits above the border overlay so it stays
    // clickable.
    Rectangle {
        id: closePaneButton
        visible: paneFrame.splitViewPresented
        width: 22
        height: 22
        radius: 11
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 6
        anchors.rightMargin: 6
        z: 11
        color: closePaneHover.hovered
            ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.85)
            : Qt.rgba(Theme.mantle.r, Theme.mantle.g, Theme.mantle.b, 0.55)
        Behavior on color { ColorAnimation { duration: Theme.animDuration } }
        opacity: closePaneHover.hovered || closePaneArea.containsMouse ? 1 : 0.65

        IconX {
            anchors.centerIn: parent
            size: 11
            color: closePaneHover.hovered ? Theme.base : Theme.text
        }

        MouseArea {
            id: closePaneArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onClicked: paneFrame.closeRequested()
        }
        HoverHandler { id: closePaneHover; cursorShape: Qt.PointingHandCursor }
    }
}
