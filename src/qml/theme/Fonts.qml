pragma Singleton
import QtQuick

// Self-hosted bundled fonts for the "Heimdall Unified" look (both OFL):
//   • Cinzel       — the "HEIMDALL" display wordmark only.
//   • JetBrains Mono — paths, sizes, type chips, keycaps.
// Both are variable fonts; pick a weight via `font.weight` at the call site.
// The exposed `display`/`mono` families fall back to a generic family until
// the loader reports Ready, so the first paint never flashes an empty family.
QtObject {
    id: root

    property FontLoader cinzel: FontLoader { source: "qrc:/assets/fonts/Cinzel-VF.ttf" }
    property FontLoader jetbrains: FontLoader { source: "qrc:/assets/fonts/JetBrainsMono-VF.ttf" }

    readonly property string display: cinzel.status === FontLoader.Ready ? cinzel.name : "serif"
    readonly property string mono: jetbrains.status === FontLoader.Ready ? jetbrains.name : "monospace"

    readonly property bool ready: cinzel.status === FontLoader.Ready
                                  && jetbrains.status === FontLoader.Ready
}
