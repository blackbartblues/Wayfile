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
    // Explicit paddingRect (not autoPadding) so the blurred halo renders into
    // a texture ~30% larger than the icon on every side — autoPadding under-
    // sizes it at the larger blur, clipping the bloom to the icon box (visible
    // as a hard-edged glow in the gallery filmstrip).
    layer.enabled: root.hovered || root.selected
    layer.effect: MultiEffect {
        autoPaddingEnabled: false
        paddingRect: Qt.rect(-root.size * 0.3, -root.size * 0.3,
                             root.size * 1.6, root.size * 1.6)
        shadowEnabled: true
        shadowColor: Theme.goldGlow
        shadowBlur: root.selected ? 0.6 : 0.4
    }
}
