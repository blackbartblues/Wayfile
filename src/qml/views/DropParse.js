.pragma library

// Shared drag-and-drop path parsing for the file views (grid / detailed /
// miller), which each had a byte-identical copy. Pure + stateless (.pragma
// library) so it can't reach QML scope — the view keeps its own dragHelper
// short-circuit and calls pathsFromDrop() only for the system-DnD payload.

// file:// URL → local path; anything else passes through unchanged.
function decodePath(value) {
    return value.startsWith("file://") ? decodeURIComponent(value.substring(7)) : value
}

// Resolve dropped file paths from a DropArea drop/drag event: prefer drop.urls
// (system DnD), else fall back to a newline-separated text/uri-list in drop.text.
function pathsFromDrop(drop) {
    var paths = []
    var urls = drop.urls || []
    for (var i = 0; i < urls.length; i++)
        paths.push(decodePath(urls[i].toString()))

    if (paths.length === 0 && drop.hasText) {
        var lines = drop.text.split("\n")
        for (var j = 0; j < lines.length; j++) {
            var line = lines[j].trim()
            if (line !== "")
                paths.push(decodePath(line))
        }
    }

    return paths
}
