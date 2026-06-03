import QtQuick
import QtQuick.Shapes
import Heimdall

// Shared git-status badge (handoff re-skin): an obsidian disc with a 1px ring,
// a top sheen, a faint drop-shadow, and a status-tinted glyph. Three variants
// driven by GitColors.kindFor():
//   • glyph / dot — obsidian gradient disc + tinted glyph
//   • solid        — disc filled with the status colour + dark glyph (conflicts)
//   • dim          — the whole badge at 0.72 opacity (ignored)
// The glyphs are inlined here (NOT the quill-icons submodule) so the re-skin
// lives entirely in Heimdall's own repo.
Item {
    id: badge

    property string statusIcon: ""
    property int size: 16

    width: size
    height: size
    visible: statusIcon !== ""
    opacity: badge.kind === "dim" ? 0.72 : 1.0

    readonly property string kind: GitColors.kindFor(statusIcon)
    readonly property bool solid: kind === "solid"
    readonly property color statusColor: GitColors.colorFor(statusIcon)
    readonly property color ink: solid ? GitColors.solidInk : statusColor

    // Faint drop-shadow — a dark disc nudged down behind the badge (cheaper
    // than a per-badge blur layer when many badges are on screen).
    Rectangle {
        anchors.fill: disc
        anchors.topMargin: Math.max(1, Math.round(badge.size * 0.08))
        radius: width / 2
        color: Qt.rgba(0, 0, 0, 0.55)
    }

    Rectangle {
        id: disc
        anchors.fill: parent
        radius: width / 2
        color: badge.solid ? badge.statusColor : "transparent"
        gradient: badge.solid ? null : discGradient
        border.width: 1
        border.color: badge.solid ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(1, 1, 1, 0.16)
        clip: true

        // Top sheen — a thin highlight just inside the upper rim.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 1
            width: parent.width * 0.55
            height: 1
            radius: 0.5
            color: badge.solid ? Qt.rgba(1, 1, 1, 0.4) : Qt.rgba(1, 1, 1, 0.11)
        }
    }

    Gradient {
        id: discGradient
        GradientStop { position: 0.0; color: "#20222b" }
        GradientStop { position: 1.0; color: "#111217" }
    }

    Loader {
        id: glyph
        anchors.centerIn: parent
        sourceComponent: {
            switch (badge.statusIcon) {
                case "git-modified":   return gModified
                case "git-staged":     return gStaged
                case "git-untracked":  return gUntracked
                case "git-deleted":    return gDeleted
                case "git-renamed":    return gRenamed
                case "git-conflicted": return gConflicted
                case "git-ignored":    return gIgnored
                case "git-dirty":      return gDirty
                default:               return null
            }
        }
        onLoaded: {
            item.size = Qt.binding(() => Math.round(badge.size * 0.72))
            item.color = Qt.binding(() => badge.ink)
        }
    }

    // ── Inlined status glyphs (24×24 viewBox, scaled to `size`) ──────
    // git-modified — filled pencil.
    Component {
        id: gModified
        Shape {
            property real size: 16
            property color color: "#E3A94B"
            width: size; height: size
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"; strokeWidth: 0
                fillColor: color
                scale: Qt.size(size / 24, size / 24)
                PathSvg { path: "M5.4 18.6l3.3-.9L18.6 7.8a1.7 1.7 0 0 0-2.4-2.4L6.3 15.3 5.4 18.6z" }
            }
        }
    }
    // git-staged — check.
    Component {
        id: gStaged
        Shape {
            property real size: 16
            property color color: "#6FA8DC"
            width: size; height: size
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: color; strokeWidth: Math.max(1, size * 2.4 / 24)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(size / 24, size / 24)
                PathSvg { path: "M5.5 12.5l4.5 4.5L18.5 7.5" }
            }
        }
    }
    // git-untracked — plus.
    Component {
        id: gUntracked
        Shape {
            property real size: 16
            property color color: "#8FC380"
            width: size; height: size
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: color; strokeWidth: Math.max(1, size * 2.4 / 24)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                scale: Qt.size(size / 24, size / 24)
                PathSvg { path: "M12 5.5v13" }
            }
            ShapePath {
                strokeColor: color; strokeWidth: Math.max(1, size * 2.4 / 24)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                scale: Qt.size(size / 24, size / 24)
                PathSvg { path: "M5.5 12h13" }
            }
        }
    }
    // git-deleted — minus.
    Component {
        id: gDeleted
        Shape {
            property real size: 16
            property color color: "#E06C75"
            width: size; height: size
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: color; strokeWidth: Math.max(1, size * 2.7 / 24)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                scale: Qt.size(size / 24, size / 24)
                PathSvg { path: "M5.5 12h13" }
            }
        }
    }
    // git-renamed — bar + arrowhead.
    Component {
        id: gRenamed
        Shape {
            property real size: 16
            property color color: "#BFA4E0"
            width: size; height: size
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: color; strokeWidth: Math.max(1, size * 2.2 / 24)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(size / 24, size / 24)
                PathSvg { path: "M4.5 12h10.5" }
            }
            ShapePath {
                strokeColor: color; strokeWidth: Math.max(1, size * 2.2 / 24)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(size / 24, size / 24)
                PathSvg { path: "M11.5 6.5l6 5.5-6 5.5" }
            }
        }
    }
    // git-conflicted — exclamation (rendered dark on a solid disc).
    Component {
        id: gConflicted
        Shape {
            property real size: 16
            property color color: "#E8543C"
            width: size; height: size
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: color; strokeWidth: Math.max(1, size * 2.7 / 24)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                scale: Qt.size(size / 24, size / 24)
                PathSvg { path: "M12 6.3v6.6" }
            }
            ShapePath {
                strokeColor: color; strokeWidth: Math.max(1, size * 2.7 / 24)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                scale: Qt.size(size / 24, size / 24)
                PathSvg { path: "M12 16.7v.1" }
            }
        }
    }
    // git-ignored — diagonal slash.
    Component {
        id: gIgnored
        Shape {
            property real size: 16
            property color color: "#62666E"
            width: size; height: size
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: color; strokeWidth: Math.max(1, size * 2.4 / 24)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                scale: Qt.size(size / 24, size / 24)
                PathSvg { path: "M6.8 17.2L17.2 6.8" }
            }
        }
    }
    // git-dirty — filled dot.
    Component {
        id: gDirty
        Shape {
            property real size: 16
            property color color: "#C98F3C"
            width: size; height: size
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"; strokeWidth: 0
                fillColor: color
                scale: Qt.size(size / 24, size / 24)
                PathSvg { path: "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z" }
            }
        }
    }
}
