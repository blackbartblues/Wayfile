import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: root
    property bool checked: false
    property string label: ""
    signal toggled(bool value)
    spacing: Theme.spacing
    opacity: enabled ? 1.0 : 0.5
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.label
    Accessible.checked: root.checked
    Rectangle {
        width: 20; height: 20
        radius: Theme.radiusSm
        color: root.checked ? Theme.primary : "transparent"
        border.color: root.checked ? Theme.primary : Theme.surface2
        border.width: 2
        Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }
        Behavior on border.color { ColorAnimation { duration: Theme.animDurationFast } }
        Text {
            anchors.centerIn: parent
            text: "\uf00c"
            color: Theme.backgroundDeep
            font.family: Theme.iconFont
            font.pixelSize: 12
            visible: root.checked
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (!root.enabled) return;
                root.checked = !root.checked;
                root.toggled(root.checked);
            }
        }
    }
    Text {
        visible: root.label !== ""
        text: root.label
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        MouseArea {
            anchors.fill: parent
            cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (!root.enabled) return;
                root.checked = !root.checked;
                root.toggled(root.checked);
            }
        }
    }
}
