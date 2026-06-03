import QtQuick
import QtQuick.Shapes

// Glossy dark-stone folder — matte, top-lit, flat front with a back lip + tab.
// Translated from the handoff OsFolder (reference/app/heimdall-os-icons.jsx):
// authored in a 100×78 viewBox and uniformly scaled to `size`. Rendered width
// is `size`, height is `size * 0.78`.
Item {
    id: root
    property real size: 84
    width: size
    height: size * 0.78

    // Whole-folder silhouette (back wall + tab). Reused for the fill, the edge
    // vignette, and (optionally) a clipped grain overlay.
    readonly property string backPath:
        "M8 22 C8 17.6 11.5 14 16 14 H34 L41 21.5 H84 C88.5 21.5 92 25 92 29.5 V62 C92 66.5 88.5 70 84 70 H16 C11.5 70 8 66.5 8 62 Z"

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { xScale: root.size / 100; yScale: root.size / 100 }

        // Back wall + tab.
        ShapePath {
            fillGradient: LinearGradient {
                x1: 0; y1: 14; x2: 0; y2: 70
                GradientStop { position: 0.0; color: "#47433d" }
                GradientStop { position: 1.0; color: "#37332d" }
            }
            strokeColor: Qt.rgba(1.0, 0.94, 0.86, 0.05)
            strokeWidth: 1
            PathSvg { path: root.backPath }
        }

        // Front face — top-lit radial stone ramp.
        ShapePath {
            fillGradient: RadialGradient {
                centerX: 50; centerY: 3; centerRadius: 78
                focalX: 50; focalY: 3
                GradientStop { position: 0.0; color: "#44403a" }
                GradientStop { position: 0.52; color: "#2e2b26" }
                GradientStop { position: 1.0; color: "#181612" }
            }
            strokeColor: "transparent"
            strokeWidth: 0
            PathSvg { path: "M8 26.5 H92 V62 C92 66.5 88.5 70 84 70 H16 C11.5 70 8 66.5 8 62 Z" }
        }

        // Matte edge vignette.
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(0, 0, 0, 0.4)
            strokeWidth: 1.1
            PathSvg { path: root.backPath }
        }

        // Top rim highlight of the front face + seam shadow just below it.
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(1.0, 0.94, 0.86, 0.10)
            strokeWidth: 1
            PathSvg { path: "M9.5 27 H90.5" }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(0, 0, 0, 0.5)
            strokeWidth: 1
            PathSvg { path: "M8.5 26.1 H91.5" }
        }
    }
}
