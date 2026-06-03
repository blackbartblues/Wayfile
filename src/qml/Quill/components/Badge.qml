import QtQuick
import ".."

Rectangle {
    id: root
    property string text: ""
    property string variant: "primary"
    property bool _isDot: text === ""
    implicitWidth: _isDot ? 8 : badgeText.implicitWidth + Theme.spacingMd * 2
    implicitHeight: _isDot ? 8 : 20
    radius: Theme.radiusFull
    color: {
        switch (variant) {
            case "success": return Theme.success;
            case "warning": return Theme.warning;
            case "error": return Theme.error;
            default: return Theme.primary;
        }
    }
    Accessible.role: Accessible.StaticText
    Accessible.name: root.text !== "" ? root.text : root.variant + " indicator"
    Text {
        id: badgeText
        visible: !root._isDot
        anchors.centerIn: parent
        text: root.text
        color: Theme.backgroundDeep
        font.pixelSize: Theme.fontSizeSmall
        font.family: Theme.fontFamily
        font.bold: true
    }
}
