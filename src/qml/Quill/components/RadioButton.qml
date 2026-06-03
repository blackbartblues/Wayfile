import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: root
    property string value: ""
    property string label: ""
    property bool checked: false
    property bool enabled: true
    signal toggled(bool value)
    property bool _inGroup: parent && parent.value !== undefined
    property bool _isSelected: _inGroup ? parent.value === root.value : root.checked
    spacing: Theme.spacing
    opacity: enabled ? 1.0 : 0.5
    Accessible.role: Accessible.RadioButton
    Accessible.name: root.label
    Accessible.checked: root._isSelected
    Rectangle {
        width: 20; height: 20
        radius: Theme.radiusFull
        color: "transparent"
        border.color: root._isSelected ? Theme.primary : Theme.surface2
        border.width: 2
        Behavior on border.color { ColorAnimation { duration: Theme.animDurationFast } }
        Rectangle {
            anchors.centerIn: parent
            width: 10; height: 10
            radius: Theme.radiusFull
            color: Theme.primary
            visible: root._isSelected
            scale: root._isSelected ? 1.0 : 0.0
            Behavior on scale { NumberAnimation { duration: Theme.animDurationFast; easing.type: Easing.OutCubic } }
        }
    }
    Text {
        visible: root.label !== ""
        text: root.label
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (!root.enabled) return;
            if (root._inGroup) {
                root.parent.value = root.value;
                root.parent.selected(root.value);
            } else {
                root.checked = !root.checked;
                root.toggled(root.checked);
            }
        }
    }
}
