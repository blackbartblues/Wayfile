import QtQuick
import QtQuick.Effects
import Wayfile

// Dispatches a file/folder to WayFolder (accent) or WayFile (type colour +
// motif), and carries the uniform-gold hover/select bloom (the existing
// FileGridView pattern). Thumbnails are handled by the caller; when a thumbnail
// shows, FileIcon is hidden, so its bloom never applies to thumbnails.
Item {
    id: root
    property bool isDir: false
    property string ext: ""
    property string category: ""
    property bool isHidden: false
    property real size: 24
    property bool hovered: false
    property bool selected: false
    width: size; height: size

    readonly property var _f: root.isDir ? null : FileTypeColors.iconFor(root.ext, root.category, root.isHidden)

    Loader {
        anchors.fill: parent
        sourceComponent: root.isDir ? folderComp : fileComp
    }
    Component {
        id: folderComp
        WayFolder { size: root.size; color: FileTypeColors.folder }
    }
    Component {
        id: fileComp
        WayFile { size: root.size; kind: root._f ? root._f.kind : "doc"; color: root._f ? root._f.color : FileTypeColors.other }
    }

    // Uniform gold bloom on hover/selected only (rest = plain Shape).
    layer.enabled: root.hovered || root.selected
    layer.effect: MultiEffect {
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: Theme.goldGlow
        shadowBlur: root.selected ? 0.7 : 0.45
    }
}
