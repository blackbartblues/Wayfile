import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import ".."

Rectangle {
    id: root
    property string text: ""
    property string icon: ""
    property string variant: "primary"
    property string size: "medium"
    signal clicked()
    readonly property color contentColor: {
        if (!enabled)
            return variant === "ghost" ? Theme.textSecondary : Theme.textTertiary
        if (variant === "ghost" || variant === "secondary")
            return Theme.textPrimary
        return Theme.backgroundDeep
    }
    activeFocusOnTab: enabled
    implicitWidth: contentRow.implicitWidth + (size === "small" ? 16 : size === "large" ? 32 : 24)
    implicitHeight: size === "small" ? 28 : size === "large" ? 40 : 34
    radius: Theme.radius
    border.width: activeFocus ? 2 : 0
    border.color: {
        if (variant === "danger")
            return Qt.lighter(Theme.error, 1.6)
        if (variant === "ghost")
            return Theme.textPrimary
        return Qt.lighter(Theme.primary, 1.5)
    }
    color: {
        if (!enabled) {
            switch (variant) {
                case "ghost": return Qt.rgba(Theme.surface1.r, Theme.surface1.g, Theme.surface1.b, 0.35);
                case "secondary": return Theme.surface0;
                default: return Theme.surface1;
            }
        }
        // Primary is painted by the gold-gradient overlay below.
        if (variant === "primary")
            return "transparent";
        let base;
        switch (variant) {
            case "primary": base = Theme.primary; break;
            case "secondary": base = Theme.surface1; break;
            case "ghost": base = "transparent"; break;
            case "danger": base = Theme.error; break;
            default: base = Theme.primary;
        }
        if (mouse.pressed && enabled) return Qt.darker(base, 1.2);
        if (activeFocus && enabled) {
            if (variant === "ghost") return Theme.surface1;
            if (variant === "danger") return Qt.lighter(base, 1.25);
            return Qt.lighter(base, 1.08);
        }
        if (mouse.containsMouse && enabled) {
            if (variant === "ghost") return Theme.surface0;
            return Qt.lighter(base, 1.15);
        }
        return base;
    }
    opacity: enabled ? 1.0 : 0.82
    Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animDurationFast } }

    Accessible.role: Accessible.Button
    Accessible.name: root.text !== "" ? root.text : root.icon
    Accessible.description: root.text

    Keys.onPressed: (event) => {
        if (!root.enabled)
            return
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            event.accepted = true
            root.clicked()
        }
    }

    // Primary: gold gradient fill (#F0CE8F→gold→#C98F3C) + soft gold glow.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        visible: root.variant === "primary" && root.enabled
        opacity: mouse.pressed ? 0.85 : (mouse.containsMouse ? 1.0 : 0.96)
        Behavior on opacity { NumberAnimation { duration: Theme.animDurationFast } }
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#F0CE8F" }
            GradientStop { position: 0.6; color: Theme.primary }
            GradientStop { position: 1.0; color: "#C98F3C" }
        }
        layer.enabled: visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
            shadowBlur: 0.6
            autoPaddingEnabled: true
        }
    }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: root.text && root.icon ? 6 : 0
        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.contentColor
            font.family: Theme.iconFont
            font.pixelSize: root.size === "small" ? 12 : root.size === "large" ? 16 : 14
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: root.text !== ""
            text: root.text
            color: root.contentColor
            font.family: Theme.fontFamily
            font.pixelSize: root.size === "small" ? 11 : root.size === "large" ? 15 : 13
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: if (root.enabled) root.forceActiveFocus()
        onClicked: if (root.enabled) root.clicked()
    }
}
