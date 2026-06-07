import QtQuick
import QtQuick.Shapes
import Wayfile

// Glossy document page with a folded corner and a type-tinted glyph.
// Translated from the handoff OsFile (reference/app/wayfile-os-icons.jsx):
// authored in a 64×80 viewBox and uniformly scaled to `size`. Rendered width
// is `size * 0.8`, height is `size`.
//   variant: "doc" (ruled lines) | "json" (braces) | "img" (picture)
//   accent:  glyph tint (a file-type colour)
Item {
    id: root
    property real size: 64
    property string variant: "doc"
    property color accent: "#9CA0A8"
    width: size * 0.8
    height: size

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { xScale: root.size / 80; yScale: root.size / 80 }

        // Page body.
        ShapePath {
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: 80
                GradientStop { position: 0.0; color: "#2c2d33" }
                GradientStop { position: 1.0; color: "#191a1f" }
            }
            strokeColor: Qt.rgba(1.0, 0.94, 0.84, 0.08)
            strokeWidth: 1.2
            PathSvg { path: "M10 4 H40 L54 18 V72 a4 4 0 0 1 -4 4 H14 a4 4 0 0 1 -4 -4 V8 a4 4 0 0 1 4 -4 Z" }
        }

        // Folded corner.
        ShapePath {
            fillColor: Qt.rgba(0, 0, 0, 0.3)
            strokeColor: Qt.rgba(1.0, 0.94, 0.84, 0.10)
            strokeWidth: 1.2
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M40 4 V18 H54" }
        }
    }

    // ── Variant glyphs ────────────────────────────────────────────
    // Ruled lines (documents / default).
    Shape {
        anchors.fill: parent
        visible: root.variant === "doc"
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { xScale: root.size / 80; yScale: root.size / 80 }
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
            strokeWidth: 2.4
            capStyle: ShapePath.RoundCap
            PathSvg { path: "M18 40 H44" }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
            strokeWidth: 2.4
            capStyle: ShapePath.RoundCap
            PathSvg { path: "M18 50 H44" }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
            strokeWidth: 2.4
            capStyle: ShapePath.RoundCap
            PathSvg { path: "M18 60 H34" }
        }
    }

    // Picture (images without a thumbnail).
    Shape {
        anchors.fill: parent
        visible: root.variant === "img"
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { xScale: root.size / 80; yScale: root.size / 80 }
        ShapePath {
            fillColor: Qt.rgba(1, 1, 1, 0.03)
            strokeColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.65)
            strokeWidth: 2
            PathSvg { path: "M15 38 H46 a2.5 2.5 0 0 1 2.5 2.5 V59.5 a2.5 2.5 0 0 1 -2.5 2.5 H15 a2.5 2.5 0 0 1 -2.5 -2.5 V40.5 a2.5 2.5 0 0 1 2.5 -2.5 Z" }
        }
        ShapePath {
            fillColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85)
            strokeColor: "transparent"
            PathSvg { path: "M27.2 47 a3.2 3.2 0 1 1 -6.4 0 a3.2 3.2 0 0 1 6.4 0 Z" }
        }
        ShapePath {
            fillColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
            strokeColor: "transparent"
            PathSvg { path: "M17 60 L29 49 L38 58 L44 53 L47 56 V60 Z" }
        }
    }

    // Braces (code / json).
    Text {
        visible: root.variant === "json"
        anchors.horizontalCenter: parent.horizontalCenter
        // Glyph baseline sits ~54/80 down the page in the source art.
        y: root.height * 0.42
        text: "{ }"
        color: root.accent
        font.family: Fonts.mono
        font.weight: Font.Bold
        font.pixelSize: root.size * 0.30
    }
}
