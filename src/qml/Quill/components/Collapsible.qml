import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: root
    property string title: ""
    property bool expanded: false
    default property alias content: contentContainer.data
    spacing: 0
    opacity: enabled ? 1.0 : 0.5
    Layout.fillWidth: true
    Accessible.role: Accessible.Grouping
    Accessible.name: root.title
    Accessible.description: root.expanded ? "expanded" : "collapsed"
    Rectangle {
        Layout.fillWidth: true
        height: 40; radius: Theme.radius
        color: headerMouse.containsMouse ? Theme.surface0 : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacing
            anchors.rightMargin: Theme.spacing
            Text {
                text: root.title
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSize
                font.family: Theme.fontFamily
                font.bold: true
                Layout.fillWidth: true
            }
            Text {
                text: "\uf078"
                color: Theme.textTertiary
                font.family: Theme.iconFont
                font.pixelSize: 10
                rotation: root.expanded ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } }
            }
        }
        MouseArea {
            id: headerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: { if (root.enabled) root.expanded = !root.expanded; }
        }
    }
    Item {
        Layout.fillWidth: true
        implicitHeight: root.expanded ? contentContainer.implicitHeight : 0
        clip: true
        Behavior on implicitHeight {
            NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic }
        }
        ColumnLayout {
            id: contentContainer
            width: parent.width
            spacing: Theme.spacing
        }
    }
}
