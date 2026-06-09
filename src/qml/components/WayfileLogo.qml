import QtQuick
import QtQuick.Shapes
import Wayfile

// Wayfile brand mark (handoff WayfileLogo): a folder cradling a wayfinding
// compass — "find your way through your files". One geometry, three
// renderings via `variant`:
//   "app"  — glossy dark folder + faceted gold compass star. `plate: true`
//            wraps it in the rounded app-icon squircle tile.
//   "gold" — symbolic accent line/fill cut (toolbars / splash / About).
//   "mono" — neutral steel (trays / disabled).
// The compass retints with the active theme accent; the obsidian folder
// shell of the app variant is fixed. Legible 16 → 140 px.
Item {
    id: root

    property real size: 96
    property string variant: "app"   // "app" | "gold" | "mono"
    property bool plate: false

    width: size
    height: size

    readonly property bool isApp: variant === "app"
    readonly property bool isMono: variant === "mono"

    // Line colour: steel for mono, accent for gold, light steel for app.
    readonly property color lineC: isMono ? "#9CA0A8"
                                  : (variant === "gold" ? Theme.gold : "#C7CBD1")
    readonly property color ringC: isApp ? "#5C636B" : lineC
    readonly property real ringOp: isApp ? 0.55 : 0.9

    // Compass blade colours derived from the accent via Theme._shade so the
    // star retints with every preset; the deltas reproduce the handoff hexes
    // exactly at the default gold #D4AA6A. Mono uses fixed steel.
    readonly property color bladeLightTop: isMono ? "#C2C7CE" : Theme._shade(Theme.gold,  0.255, 1.64,  0.0155)
    readonly property color bladeLightBot: isMono ? "#C2C7CE" : Theme._shade(Theme.gold,  0.012, 1.07,  0.0055)
    readonly property color bladeDarkTop:  isMono ? "#7A7F86" : Theme._shade(Theme.gold, -0.080, 0.94,  0.004)
    readonly property color bladeDarkBot:  isMono ? "#7A7F86" : Theme._shade(Theme.gold, -0.243, 0.86,  0)
    readonly property color bladeFlatLight: isMono ? "#C2C7CE" : Theme._shade(Theme.gold,  0.192, 1.31,  0.0122)
    readonly property color bladeFlatDark:  isMono ? "#7A7F86" : Theme._shade(Theme.gold, -0.155, 0.857, 0.004)
    readonly property color starOutlineC:  isMono ? lineC : Theme._shade(Theme.gold, -0.294, 0.82, 0)
    readonly property color hubC: isApp ? Theme._shade(Theme.gold, -0.467, 0.815, 0.011) : lineC

    // All geometry lives in the 120×120 handoff viewBox; scaling the inner
    // Item (not ShapePath.scale) keeps fillGradient coordinates correct.
    Item {
        width: 120
        height: 120
        scale: root.size / 120
        transformOrigin: Item.TopLeft

        // App-icon plate (squircle tile + top sheen).
        Rectangle {
            visible: root.plate
            x: 6; y: 6; width: 108; height: 108; radius: 26
            border.color: Qt.rgba(1, 1, 1, 0.07)
            border.width: 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#2B3037" }
                GradientStop { position: 1.0; color: "#15181C" }
            }
        }
        Rectangle {
            visible: root.plate
            x: 6.5; y: 6.5; width: 107; height: 54; radius: 25.5
            color: Qt.rgba(1, 1, 1, 0.025)
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // ── Folder shell ──────────────────────────────────────────
            // App: glossy obsidian fill + faint rim. Gold/mono: 3px line cut.
            ShapePath {
                strokeColor: root.isApp ? Qt.rgba(1, 1, 1, 0.10) : root.lineC
                strokeWidth: root.isApp ? 1.2 : 3
                joinStyle: ShapePath.RoundJoin
                fillGradient: root.isApp ? bodyGrad : null
                fillColor: "transparent"
                PathSvg { path: "M16 45 Q16 31 30 31 H50.5 L59.5 40 H92 Q104 40 104 52 V92 Q104 106 90 106 H30 Q16 106 16 92 Z" }
            }
            // Top lip-light (app only).
            ShapePath {
                strokeColor: root.isApp ? Qt.rgba(1, 240 / 255, 215 / 255, 0.16) : "transparent"
                strokeWidth: 1.1
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"
                PathSvg { path: "M16 46 Q16 32 30 32 H50 L59 40.5 H92 Q103 41 103.6 51" }
            }

            // ── Compass ring + 8 ticks ────────────────────────────────
            ShapePath {
                strokeColor: Qt.rgba(root.ringC.r, root.ringC.g, root.ringC.b, root.ringOp)
                strokeWidth: root.isApp ? 2 : 2.4
                fillColor: "transparent"
                PathAngleArc { centerX: 60; centerY: 74; radiusX: 23; radiusY: 23; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: Qt.rgba(root.ringC.r, root.ringC.g, root.ringC.b, root.ringOp)
                strokeWidth: 2
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"
                startX: 60; startY: 51
                PathLine { x: 60; y: 55.5 }
                PathMove { x: 76.26; y: 57.74 }
                PathLine { x: 74.28; y: 59.72 }
                PathMove { x: 83; y: 74 }
                PathLine { x: 78.5; y: 74 }
                PathMove { x: 76.26; y: 90.26 }
                PathLine { x: 74.28; y: 88.28 }
                PathMove { x: 60; y: 97 }
                PathLine { x: 60; y: 92.5 }
                PathMove { x: 43.74; y: 90.26 }
                PathLine { x: 45.72; y: 88.28 }
                PathMove { x: 37; y: 74 }
                PathLine { x: 41.5; y: 74 }
                PathMove { x: 43.74; y: 57.74 }
                PathLine { x: 45.72; y: 59.72 }
            }

            // ── 4-point star: 8 alternating blades (3D pinwheel) ──────
            ShapePath {
                strokeColor: "transparent"
                fillGradient: root.isApp ? lightGrad : null
                fillColor: root.isApp ? "transparent" : root.bladeFlatLight
                PathSvg { path: "M60 74 L55.8 69.8 L60 56 Z M60 74 L64.2 69.8 L74.5 74 Z M60 74 L64.2 78.2 L60 92 Z M60 74 L55.8 78.2 L45.5 74 Z" }
            }
            ShapePath {
                strokeColor: "transparent"
                fillGradient: root.isApp ? darkGrad : null
                fillColor: root.isApp ? "transparent" : root.bladeFlatDark
                PathSvg { path: "M60 74 L60 56 L64.2 69.8 Z M60 74 L74.5 74 L64.2 78.2 Z M60 74 L60 92 L55.8 78.2 Z M60 74 L45.5 74 L55.8 69.8 Z" }
            }
            ShapePath {
                strokeColor: root.isApp
                             ? Qt.rgba(root.starOutlineC.r, root.starOutlineC.g, root.starOutlineC.b, 0.5)
                             : root.lineC
                strokeWidth: root.isApp ? 1 : 1.6
                joinStyle: ShapePath.RoundJoin
                fillColor: "transparent"
                PathSvg { path: "M60 56 L64.2 69.8 L74.5 74 L64.2 78.2 L60 92 L55.8 78.2 L45.5 74 L55.8 69.8 Z" }
            }
            // Hub.
            ShapePath {
                strokeColor: "transparent"
                fillColor: root.hubC
                PathAngleArc { centerX: 60; centerY: 74; radiusX: 2.1; radiusY: 2.1; startAngle: 0; sweepAngle: 360 }
            }
        }

        // Gradients in 120-space (shared by the ShapePaths above).
        LinearGradient {
            id: bodyGrad
            x1: 0; y1: 31; x2: 0; y2: 106
            GradientStop { position: 0.0; color: "#343A41" }
            GradientStop { position: 0.55; color: "#262A30" }
            GradientStop { position: 1.0; color: "#1A1D22" }
        }
        LinearGradient {
            id: lightGrad
            x1: 0; y1: 56; x2: 0; y2: 92
            GradientStop { position: 0.0; color: root.bladeLightTop }
            GradientStop { position: 1.0; color: root.bladeLightBot }
        }
        LinearGradient {
            id: darkGrad
            x1: 0; y1: 56; x2: 0; y2: 92
            GradientStop { position: 0.0; color: root.bladeDarkTop }
            GradientStop { position: 1.0; color: root.bladeDarkBot }
        }
    }
}
