import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import ".."

RowLayout {
    id: root
    property real value: 0
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property string label: ""
    property bool showValue: false
    property int decimals: 0
    property color trackColor: Theme.primary
    signal moved(real value)
    spacing: Theme.spacingMd
    opacity: root.enabled ? 1.0 : 0.5
    Layout.fillWidth: true
    Accessible.role: Accessible.Slider
    Accessible.name: root.label
    Accessible.description: root.value.toString()
    Text {
        visible: root.label !== ""
        text: root.label
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        Layout.preferredWidth: 140
    }
    Item {
        Layout.fillWidth: true
        height: 24
        property real ratio: Math.max(0, Math.min(1, (root.value - root.from) / (root.to - root.from)))
        // Inset obsidian track well.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 4; radius: 2
            color: Theme.backgroundDeep
            border.width: 1
            border.color: Theme.surface1
        }
        // Gold gradient fill.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * parent.ratio
            height: 4; radius: 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.goldMid }
                GradientStop { position: 1.0; color: root.trackColor }
            }
        }
        // Warm-white knob + gold glow.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width * parent.ratio - 7
            width: 14; height: 14; radius: 7
            color: sliderMouse.pressed ? "#ffffff" : Theme.knob
            Behavior on color { ColorAnimation { duration: 80 } }
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(root.trackColor.r, root.trackColor.g, root.trackColor.b, 0.55)
                shadowBlur: 0.5
                autoPaddingEnabled: true
            }
        }
        MouseArea {
            id: sliderMouse
            anchors.fill: parent
            cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onPressed: (event) => { if (root.enabled) updateValue(event); }
            onPositionChanged: (event) => { if (pressed && root.enabled) updateValue(event); }
            function updateValue(event) {
                let r = Math.max(0, Math.min(1, event.x / width));
                let raw = root.from + r * (root.to - root.from);
                let step = root.stepSize;
                let val = Math.round(raw / step) * step;
                if (root.decimals > 0) val = parseFloat(val.toFixed(root.decimals));
                root.value = val;
                root.moved(val);
            }
        }
    }
    Rectangle {
        visible: root.showValue
        width: 52; height: 24; radius: Theme.radiusSm
        color: Theme.surface0
        Text {
            anchors.centerIn: parent
            text: root.decimals > 0 ? root.value.toFixed(root.decimals) : Math.round(root.value)
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSizeSmall
            font.family: Theme.fontFamily
        }
    }
}
