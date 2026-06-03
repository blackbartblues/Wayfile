pragma Singleton
import QtQuick

// Fixed git-status palette + badge-variant map for the "Heimdall Unified"
// re-skin (handoff GIT map). Immutable per design decision D3 — git status
// identity stays consistent across themes. Gold is reserved for "modified".
QtObject {
    id: root

    readonly property color modified:   "#E3A94B"
    readonly property color staged:     "#6FA8DC"
    readonly property color untracked:  "#8FC380"
    readonly property color deleted:    "#E06C75"
    readonly property color renamed:    "#BFA4E0"
    readonly property color conflicted: "#E8543C"
    readonly property color ignored:    "#62666E"
    readonly property color dirty:      "#C98F3C"

    // Dark ink for the glyph on a solid (filled) disc.
    readonly property color solidInk: "#19120c"

    // gitStatusIcon key -> status colour.
    function colorFor(key) {
        switch (key) {
        case "git-modified":   return modified
        case "git-staged":     return staged
        case "git-untracked":  return untracked
        case "git-deleted":    return deleted
        case "git-renamed":    return renamed
        case "git-conflicted": return conflicted
        case "git-ignored":    return ignored
        case "git-dirty":      return dirty
        default:               return modified
        }
    }

    // Disc variant: "glyph" (obsidian disc + tinted glyph) | "solid" (filled
    // disc + dark glyph) | "dim" (whole badge at 0.72) | "dot" (filled marker).
    function kindFor(key) {
        if (key === "git-conflicted") return "solid"
        if (key === "git-ignored")    return "dim"
        if (key === "git-dirty")      return "dot"
        return "glyph"
    }
}
