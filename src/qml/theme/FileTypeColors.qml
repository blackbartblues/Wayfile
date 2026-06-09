pragma Singleton
import QtQuick

// File-type tint palette for the thin-frame WayFile/WayFolder icons (W3): the
// stroke colour of a file's page-frame + motif, and of the folder frame. The
// file-type tints are immutable (NOT theme-overridable) so type identity stays
// consistent across presets. The ONE exception is `folder`, which tracks the
// active accent (W2). `iconFor` maps an extension/category to {kind, color}.
// Values come from the handoff `--h-ft-*` tokens.
QtObject {
    id: root

    // ── 9 type tints ──────────────────────────────────────────────
    readonly property color folder: Theme.gold // tracks the active accent (W2)
    readonly property color image:  "#8FC380"
    readonly property color doc:    "#6FA8DC"
    readonly property color md:     "#BFA4E0"
    readonly property color pdf:    "#E06C75"
    readonly property color zip:    "#E0B26C"
    readonly property color code:   "#7BC6BD"
    readonly property color audio:  "#D4A6A6"
    readonly property color video:  "#C68FE0"
    readonly property color other:  "#9CA0A8" // text-2, for unknown types
    readonly property color hidden: "#6C7177" // text-3, for dotfiles ("#")

    // extension/category -> { kind, color } for the thin-frame WayFile motif.
    // Resolution order: extension first, then category.
    function iconFor(ext, category, isHidden) {
        if (isHidden)
            return { "kind": "cfg", "color": hidden }
        var e = (ext || "").toLowerCase()
        if (e.indexOf(".") !== -1)
            e = e.substring(e.lastIndexOf(".") + 1)
        switch (e) {
        case "md": case "markdown":              return { "kind": "md",    "color": md }
        case "pdf":                              return { "kind": "pdf",   "color": pdf }
        case "json": case "ts": case "tsx":
        case "js": case "jsx":                   return { "kind": "code",  "color": code }
        case "png": case "jpg": case "jpeg":
        case "gif": case "svg": case "webp":     return { "kind": "image", "color": image }
        case "gz": case "zip": case "tar":
        case "7z": case "xz": case "bz2":        return { "kind": "zip",   "color": zip }
        case "txt":                              return { "kind": "txt",   "color": other }
        case "ini": case "conf": case "cfg":
        case "toml": case "yaml": case "yml":    return { "kind": "cfg",   "color": other }
        case "bin": case "exe": case "o":
        case "so":                               return { "kind": "bin",   "color": other }
        }
        switch (category) {
        case "image":    return { "kind": "image", "color": image }
        case "video":    return { "kind": "video", "color": video }
        case "audio":    return { "kind": "audio", "color": audio }
        case "code":     return { "kind": "code",  "color": code }
        case "archive":  return { "kind": "zip",   "color": zip }
        case "document": return { "kind": "doc",   "color": doc }
        }
        return { "kind": "doc", "color": other }
    }
}
