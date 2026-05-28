import QtQuick
import QtQuick.Layouts
import Heimdall

// 34 px header strip drawn at the top of each pane in split view.  Shows the
// pane's display title and tints it gold when the pane is the active one.
//
// Phase 1 M6: lifted out of Main.qml's inline `component SplitPaneHeader`
// declaration so PaneFrame.qml (which lives in the Heimdall module) can
// instantiate it without falling outside its own scope.
Item {
    id: splitPaneHeader

    property string title: ""
    property bool activePaneHeader: false

    Layout.fillWidth: true
    Layout.preferredHeight: 34

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: Qt.rgba(Theme.mantle.r, Theme.mantle.g, Theme.mantle.b, 0.7)
    }

    // Bottom skirt covers the rounded corner of the background rect so the
    // header reads as a flat strip glued to the pane content below.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.radiusMedium
        color: Qt.rgba(Theme.mantle.r, Theme.mantle.g, Theme.mantle.b, 0.7)
    }

    Text {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        text: splitPaneHeader.title
        color: splitPaneHeader.activePaneHeader ? Theme.accent : Theme.text
        font.pointSize: Theme.fontNormal
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }
}
