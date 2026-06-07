import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Wayfile

Rectangle {
    id: statusBar
    Accessible.role: Accessible.StatusBar
    Accessible.name: {
        var parts = []
        if (selectedCount > 0) parts.push(selectedCount + " selected")
        else parts.push(itemCount + " items")
        if (folderCount > 0) parts.push(folderCount + " folders")
        if (selectedSize) parts.push(selectedSize)
        return parts.join(", ")
    }

    property int itemCount: 0
    property int folderCount: 0
    property int selectedCount: 0
    property string selectedSize: ""
    property bool selectedSizePending: false
    property string searchStatus: ""

    // Wayfile design-canvas: active pane absolute path shown in mono font,
    // middle-truncated. Empty hides the segment so trash/recents/search views
    // (which don't have a meaningful path) don't render a stale label.
    property string activePath: ""

    // View-switch cluster (#8 pkt 7): mirrors the active tab's viewMode and
    // emits viewModeRequested when one of the footer icons is clicked. Main.qml
    // binds viewMode and handles the signal by flipping
    // tabModel.activeTab.viewMode.
    property string viewMode: "grid"
    signal viewModeRequested(string mode)

    height: 28
    color: Theme.mantle
    clip: false

    // Inverse rounded corner — top left
    Shape {
        z: 1; width: Theme.radiusMedium; height: Theme.radiusMedium
        anchors.bottom: parent.top; anchors.left: parent.left
        ShapePath {
            fillColor: Theme.mantle; strokeColor: "transparent"
            startX: 0; startY: Theme.radiusMedium
            PathLine { x: Theme.radiusMedium; y: Theme.radiusMedium }
            PathArc {
                x: 0; y: 0
                radiusX: Theme.radiusMedium; radiusY: Theme.radiusMedium
                direction: PathArc.Clockwise
            }
            PathLine { x: 0; y: Theme.radiusMedium }
        }
    }

    // Inverse rounded corner — top right
    Shape {
        z: 1; width: Theme.radiusMedium; height: Theme.radiusMedium
        anchors.bottom: parent.top; anchors.right: parent.right
        ShapePath {
            fillColor: Theme.mantle; strokeColor: "transparent"
            startX: Theme.radiusMedium; startY: Theme.radiusMedium
            PathLine { x: 0; y: Theme.radiusMedium }
            PathArc {
                x: Theme.radiusMedium; y: 0
                radiusX: Theme.radiusMedium; radiusY: Theme.radiusMedium
                direction: PathArc.Counterclockwise
            }
            PathLine { x: Theme.radiusMedium; y: Theme.radiusMedium }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing
        spacing: Theme.spacing

        Text {
            text: {
                const files = statusBar.itemCount - statusBar.folderCount
                return statusBar.itemCount + " items (" + statusBar.folderCount + " folders, " + files + " files)"
            }
            color: Theme.subtext
            font.pointSize: Theme.fontSmall
            verticalAlignment: Text.AlignVCenter
        }

        // Active-pane path. Mono font + middle-elide give a stable visual
        // anchor even when paths are long ("/home/blacku/.../some-folder").
        Text {
            Layout.fillWidth: true
            visible: statusBar.activePath !== ""
            text: statusBar.activePath
            color: Theme.subtext
            font.pointSize: Theme.fontSmall
            font.family: Fonts.mono
            elide: Text.ElideMiddle
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        // Spacer when the path is hidden so selected/search hug the right edge.
        Item { Layout.fillWidth: true; visible: statusBar.activePath === "" }

        Text {
            visible: statusBar.selectedCount > 0
            text: statusBar.selectedCount + " selected" + (statusBar.selectedSize ? " \u2014 " + statusBar.selectedSize : "")
            color: statusBar.selectedSizePending ? Theme.accent : Theme.subtext
            font.pointSize: Theme.fontSmall
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            visible: statusBar.searchStatus !== ""
            text: statusBar.searchStatus
            color: Theme.accent
            font.pointSize: Theme.fontSmall
            verticalAlignment: Text.AlignVCenter
        }

        // Divider sets the view-switch cluster apart from the status text.
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            width: 1
            height: 14
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.15)
        }

        // View-switch cluster (#8 pkt 7; hybrid added Phase 8): hybrid / grid /
        // miller / detailed. The active mode is accented; clicking requests a
        // switch via viewModeRequested.
        Row {
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            HoverRect {
                id: hybridViewBtn
                width: 24; height: 24
                onClicked: statusBar.viewModeRequested("hybrid")
                IconPanelTop {
                    anchors.centerIn: parent
                    size: 15
                    color: statusBar.viewMode === "hybrid" ? Theme.accent : Theme.subtext
                }
            }

            HoverRect {
                id: gridViewBtn
                width: 24; height: 24
                onClicked: statusBar.viewModeRequested("grid")
                IconGrid {
                    anchors.centerIn: parent
                    size: 15
                    color: statusBar.viewMode === "grid" ? Theme.accent : Theme.subtext
                }
            }

            HoverRect {
                id: millerViewBtn
                width: 24; height: 24
                onClicked: statusBar.viewModeRequested("miller")
                IconColumns {
                    anchors.centerIn: parent
                    size: 15
                    color: statusBar.viewMode === "miller" ? Theme.accent : Theme.subtext
                }
            }

            HoverRect {
                id: detailedViewBtn
                width: 24; height: 24
                onClicked: statusBar.viewModeRequested("detailed")
                IconList {
                    anchors.centerIn: parent
                    size: 15
                    color: statusBar.viewMode === "detailed" ? Theme.accent : Theme.subtext
                }
            }
        }
    }
}
