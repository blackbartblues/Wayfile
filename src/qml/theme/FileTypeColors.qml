pragma Singleton
import QtQuick

// Fixed file-type tint palette for folder badges (Phase 5) and the metallic
// file-type chips in file rows (Phase 6). Per design decision D3 these are
// immutable — NOT theme-overridable — so type identity stays consistent across
// themes. Values come from the handoff `--u-ft-*` tokens.
QtObject {
    id: root

    // ── 7 type tints ──────────────────────────────────────────────
    readonly property color folder: "#E3A94B"
    readonly property color image:  "#8FC380"
    readonly property color doc:    "#6FA8DC"
    readonly property color md:     "#BFA4E0"
    readonly property color pdf:    "#E06C75"
    readonly property color zip:    "#E0B26C"
    readonly property color code:   "#7BC6BD"
    readonly property color other:  "#9CA0A8" // text-2, for unknown types
    readonly property color hidden: "#62666e" // text-3, for dotfiles ("#")

    // FileCategoryRole string -> tint.
    function colorForCategory(category) {
        switch (category) {
        case "folder":   return folder
        case "image":    return image
        case "video":    return image    // share the green media tint
        case "audio":    return md
        case "document": return doc
        case "code":     return code
        case "archive":  return zip
        default:         return other
        }
    }

    // extension -> { label, color } for the metallic file-type chip.
    readonly property var extMap: ({
        "md":       { "label": "M↓", "color": md },
        "markdown": { "label": "M↓", "color": md },
        "json":     { "label": "{}",  "color": code },
        "ts":       { "label": "TS",  "color": code },
        "tsx":      { "label": "TS",  "color": code },
        "js":       { "label": "JS",  "color": code },
        "jsx":      { "label": "JS",  "color": code },
        "png":      { "label": "PNG", "color": image },
        "jpg":      { "label": "JPG", "color": image },
        "jpeg":     { "label": "JPG", "color": image },
        "gif":      { "label": "GIF", "color": image },
        "svg":      { "label": "SVG", "color": image },
        "webp":     { "label": "WEBP","color": image },
        "pdf":      { "label": "PDF", "color": pdf },
        "gz":       { "label": "GZ",  "color": zip },
        "zip":      { "label": "ZIP", "color": zip },
        "tar":      { "label": "TAR", "color": zip },
        "7z":       { "label": "7Z",  "color": zip },
        "xz":       { "label": "XZ",  "color": zip },
        "bz2":      { "label": "BZ2", "color": zip }
    })

    // Resolve a chip descriptor { label, color } from an extension + category.
    // Handles dotfiles ("#"), multi-dot extensions (tar.gz -> GZ), and no-ext.
    function chipFor(ext, category, isHidden) {
        if (isHidden)
            return { "label": "#", "color": hidden }
        var e = (ext || "").toLowerCase()
        if (e.indexOf(".") !== -1)
            e = e.substring(e.lastIndexOf(".") + 1)
        if (extMap[e] !== undefined)
            return extMap[e]
        if (e.length > 0)
            return { "label": e.substring(0, 3).toUpperCase(), "color": colorForCategory(category) }
        return { "label": "•", "color": colorForCategory(category) }
    }
}
