import QtQuick
import QtQuick.Shapes
import Wayfile

// W8: Lucide-style arrow glyph drawn inline as a Shape. The icons dir is a
// no-push submodule and has no arrow glyphs, so Back/Fwd/Up draw their arrows
// here (same inline-Shape precedent as the merge chain-link in Toolbar.qml).
//
// `direction` picks the Lucide path (arrow-left / arrow-right / arrow-up),
// authored in a 24×24 viewBox and uniformly scaled down to `size`.
Item {
    id: root

    property string direction: "left"
    property int size: 15
    property color color: Theme.text

    width: size
    height: size

    readonly property string _path: {
        if (direction === "right")
            return "M5 12h14M12 5l7 7-7 7"
        if (direction === "up")
            return "M12 19V5M5 12l7-7 7 7"
        return "M19 12H5M12 19l-7-7 7-7"
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            strokeWidth: Math.max(1, root.size / 10)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            scale: Qt.size(root.size / 24, root.size / 24)
            PathSvg { path: root._path }
        }
    }
}
