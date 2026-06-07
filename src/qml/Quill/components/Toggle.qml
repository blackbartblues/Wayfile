import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
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
        // Off: obsidian inset well; on: painted by the gold gradient below.
        color: root.checked ? "transparent" : Theme.backgroundDeep
        border.width: root.checked ? 0 : 1
        border.color: Theme.surface2
        Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }
        // Gold gradient track when on + soft glow.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: root.checked
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.goldLight }
                GradientStop { position: 0.55; color: Theme.gold }
                GradientStop { position: 1.0; color: Theme.goldMid }
            }
            layer.enabled: root.checked
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.40)
                shadowBlur: 0.5
                autoPaddingEnabled: true
            }
        }
        Rectangle {
            width: 18; height: 18; radius: 9
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 2 : 2
            color: root.checked ? Theme.knob : Theme.textTertiary
            Behavior on x { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }
            layer.enabled: root.checked
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.5)
                shadowBlur: 0.4
                autoPaddingEnabled: true
            }
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
