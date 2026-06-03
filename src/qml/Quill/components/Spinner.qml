import QtQuick
import ".."

Item {
    id: root
    property string size: "medium"
    property color color: Theme.primary
    property bool running: true
    property int _size: size === "small" ? 16 : size === "large" ? 32 : 24
    implicitWidth: _size
    implicitHeight: _size
    Accessible.role: Accessible.Indicator
    Accessible.name: root.running ? "Loading" : "Idle"
    Rectangle {
        id: spinner
        anchors.fill: parent
        radius: Theme.radiusFull
        color: "transparent"
        border.color: Theme.surface1
        border.width: 2
        Canvas {
            id: canvas
            anchors.fill: parent
            onPaint: {
                let ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.strokeStyle = root.color.toString();
                ctx.lineWidth = 2;
                ctx.lineCap = "round";
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, width / 2 - 2, 0, Math.PI * 1.2);
                ctx.stroke();
            }
            Component.onCompleted: requestPaint()
        }
        RotationAnimation on rotation {
            running: root.running
            from: 0; to: 360
            duration: 1000
            loops: Animation.Infinite
        }
    }
    onColorChanged: canvas.requestPaint()
}
