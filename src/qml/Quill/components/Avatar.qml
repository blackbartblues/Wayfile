import QtQuick
import ".."

Rectangle {
    id: root
    property string source: ""
    property string fallback: ""
    property string size: "medium"
    property bool rounded: true
    property int _size: size === "small" ? 28 : size === "large" ? 48 : 36
    implicitWidth: _size
    implicitHeight: _size
    radius: rounded ? Theme.radiusFull : Theme.radius
    color: Theme.surface1
    clip: true
    Accessible.role: Accessible.Graphic
    Accessible.name: root.fallback !== "" ? root.fallback : "Avatar"
    Image {
        id: img
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready
    }
    Text {
        visible: img.status !== Image.Ready
        anchors.centerIn: parent
        text: root.fallback
        color: Theme.textPrimary
        font.pixelSize: root._size * 0.4
        font.family: Theme.fontFamily
        font.bold: true
    }
}
