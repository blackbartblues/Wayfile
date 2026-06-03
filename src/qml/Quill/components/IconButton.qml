import QtQuick
import ".."

Rectangle {
    id: root
    property string icon: ""
    property string tooltip: ""
    property string variant: "ghost"
    property string size: "medium"
    property bool enabled: true
    signal clicked()
    implicitWidth: size === "small" ? 28 : size === "large" ? 40 : 34
    implicitHeight: implicitWidth
    radius: Theme.radiusFull
    color: {
        if (!enabled) return Theme.surface0;
        let base;
        switch (variant) {
            case "primary": base = Theme.primary; break;
            case "secondary": base = Theme.surface1; break;
            case "ghost": base = "transparent"; break;
            case "danger": base = Theme.error; break;
            default: base = "transparent";
        }
        if (mouse.pressed && enabled) return Qt.darker(base, 1.2);
        if (mouse.containsMouse && enabled) {
            if (variant === "ghost") return Theme.surface0;
            return Qt.lighter(base, 1.15);
        }
        return base;
    }
    opacity: enabled ? 1.0 : 0.5
    Accessible.role: Accessible.Button
    Accessible.name: root.tooltip !== "" ? root.tooltip : root.icon
    Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }
    Text {
        anchors.centerIn: parent
        text: root.icon
        color: {
            if (root.variant === "ghost" || root.variant === "secondary") return Theme.textPrimary;
            return Theme.backgroundDeep;
        }
        font.family: Theme.iconFont
        font.pixelSize: root.size === "small" ? 12 : root.size === "large" ? 16 : 14
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.enabled) root.clicked()
    }
    Tooltip {
        text: root.tooltip
        visible: root.tooltip !== "" && mouse.containsMouse
    }
}
