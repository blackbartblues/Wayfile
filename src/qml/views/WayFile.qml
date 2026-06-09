import QtQuick
import QtQuick.Shapes

// Thin page frame + dog-ear (handoff WayFile), stroked in the file's type
// colour, with a single-weight line-motif per kind inside. No text chip.
Item {
    id: root
    property real size: 24
    property color color: "#9CA0A8"   // type tint
    property string kind: "doc"
    property real strokeWidth: Math.max(1, size * 1.35 / 24)
    property real motifWidth: Math.max(0.75, size * 1.25 / 24)
    width: size; height: size

    // Page frame + folded corner.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color; strokeWidth: root.strokeWidth; fillColor: "transparent"
            capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
            scale: Qt.size(root.size / 24, root.size / 24)
            PathSvg { path: "M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" }
        }
        ShapePath {
            strokeColor: root.color; strokeWidth: root.strokeWidth; fillColor: "transparent"
            capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
            scale: Qt.size(root.size / 24, root.size / 24)
            PathSvg { path: "M14 3v5h5" }
        }
    }

    // Per-kind motif.
    Loader {
        anchors.fill: parent
        sourceComponent: {
            switch (root.kind) {
            case "md":    return motifMd
            case "code":  return motifCode
            case "zip":   return motifZip
            case "image": return motifImage
            case "audio": return motifAudio
            case "video": return motifVideo
            case "cfg":   return motifCfg
            case "bin":   return motifBin
            default:      return motifDoc // doc/txt/pdf + fallback
            }
        }
    }

    // ── motif components (24-space; stroked in the type colour) ──
    Component {
        id: motifDoc
        Shape {
            anchors.fill: parent; preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: root.color; strokeWidth: root.motifWidth; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(root.size / 24, root.size / 24)
                PathSvg { path: "M9 13h6M9 16.4h6M9 19h3.4" }
            }
        }
    }
    Component {
        id: motifMd
        Shape {
            anchors.fill: parent; preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: root.color; strokeWidth: root.motifWidth; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(root.size / 24, root.size / 24)
                PathSvg { path: "M8.6 19v-6l2.4 2.8L13.4 13v6M16 13.4v4.4M14.4 16.4 16 18.2l1.6-1.8" }
            }
        }
    }
    Component {
        id: motifCode
        Shape {
            anchors.fill: parent; preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: root.color; strokeWidth: root.motifWidth; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(root.size / 24, root.size / 24)
                PathSvg { path: "M10.4 13.6 8.4 15.6l2 2M13.6 13.6l2 2-2 2" }
            }
        }
    }
    Component {
        id: motifZip
        Shape {
            anchors.fill: parent; preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: root.color; strokeWidth: root.motifWidth; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(root.size / 24, root.size / 24)
                PathSvg { path: "M12 12.6v1.3M12 14.7v1.3M12 16.8v1.3" }
            }
        }
    }
    Component {
        id: motifImage
        Shape {
            anchors.fill: parent; preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: root.color; strokeWidth: root.motifWidth; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(root.size / 24, root.size / 24)
                PathSvg { path: "M8 18.6 11 15.4l1.7 1.7 2-2.1 2.3 2.4" }
            }
            ShapePath {
                strokeColor: root.color; strokeWidth: root.motifWidth; fillColor: "transparent"
                scale: Qt.size(root.size / 24, root.size / 24)
                PathAngleArc { centerX: 9.9; centerY: 13.2; radiusX: 1.05; radiusY: 1.05; startAngle: 0; sweepAngle: 360 }
            }
        }
    }
    Component {
        id: motifAudio
        Shape {
            anchors.fill: parent; preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: root.color; strokeWidth: root.motifWidth; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(root.size / 24, root.size / 24)
                PathSvg { path: "M11 17.6v-4.4l4-1v3.6" }
            }
            ShapePath {
                strokeColor: root.color; strokeWidth: root.motifWidth; fillColor: "transparent"
                scale: Qt.size(root.size / 24, root.size / 24)
                PathAngleArc { centerX: 9.7; centerY: 17.6; radiusX: 1.3; radiusY: 1.3; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: root.color; strokeWidth: root.motifWidth; fillColor: "transparent"
                scale: Qt.size(root.size / 24, root.size / 24)
                PathAngleArc { centerX: 15; centerY: 15.8; radiusX: 1.3; radiusY: 1.3; startAngle: 0; sweepAngle: 360 }
            }
        }
    }
    Component {
        id: motifVideo
        Shape {
            anchors.fill: parent; preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"; fillColor: root.color   // filled triangle
                scale: Qt.size(root.size / 24, root.size / 24)
                PathSvg { path: "M10.4 13.7 14.3 16l-3.9 2.3z" }
            }
        }
    }
    Component {
        id: motifCfg
        Shape {
            anchors.fill: parent; preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: root.color; strokeWidth: root.motifWidth; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(root.size / 24, root.size / 24)
                PathSvg { path: "M12 12.4v1.1M12 17.7v1.1M14.8 14 13.85 14.6M10.15 16.6 9.2 17.2M14.8 17.2 13.85 16.6M10.15 14.6 9.2 14" }
            }
            ShapePath {
                strokeColor: root.color; strokeWidth: root.motifWidth; fillColor: "transparent"
                scale: Qt.size(root.size / 24, root.size / 24)
                PathAngleArc { centerX: 12; centerY: 15.6; radiusX: 1.8; radiusY: 1.8; startAngle: 0; sweepAngle: 360 }
            }
        }
    }
    Component {
        id: motifBin
        Shape {
            anchors.fill: parent; preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: root.color; strokeWidth: root.motifWidth; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(root.size / 24, root.size / 24)
                PathSvg { path: "M9 13.4v3.4M11.4 13.4v3.4M14 13.4v3.4M16.4 13.4v3.4" }
            }
        }
    }
}
