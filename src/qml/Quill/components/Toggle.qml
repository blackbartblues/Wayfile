import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: root
    property bool checked: false
    property string label: ""
    signal toggled(bool value)
    spacing: Theme.spacingMd
    opacity: enabled ? 1.0 : 0.5
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.label
    Accessible.checked: root.checked
    Text {
        visible: root.label !== ""
        text: root.label
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        Layout.fillWidth: true
    }
    Rectangle {
        width: 40; height: 22; radius: 11
        color: root.checked ? Theme.primary : Theme.surface1
        Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }
        Rectangle {
            width: 18; height: 18; radius: 9
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 2 : 2
            color: Theme.textPrimary
            Behavior on x { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } }
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
}
