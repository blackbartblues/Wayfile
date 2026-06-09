pragma Singleton
import QtQuick

// Self-hosted bundled fonts for the Wayfile 1.0.0 look (all OFL):
//   • Inter              — the UI family (registered app-wide in main.cpp;
//                          loaded here too so `ui` is bindable in QML).
//   • Cormorant Garamond — display serif (theme names / large labels).
//   • JetBrains Mono     — paths, sizes, type chips, keycaps.
// All are variable fonts; pick a weight via `font.weight` at the call site.
// The exposed families fall back to a generic family until the loader
// reports Ready, so the first paint never flashes an empty family.
QtObject {
    id: root

    property FontLoader inter: FontLoader { source: "qrc:/assets/fonts/Inter-VF.ttf" }
    property FontLoader cormorant: FontLoader { source: "qrc:/assets/fonts/CormorantGaramond-VF.ttf" }
    property FontLoader jetbrains: FontLoader { source: "qrc:/assets/fonts/JetBrainsMono-VF.ttf" }

    readonly property string ui: inter.status === FontLoader.Ready ? inter.name : "sans-serif"
    readonly property string display: cormorant.status === FontLoader.Ready ? cormorant.name : "serif"
    readonly property string mono: jetbrains.status === FontLoader.Ready ? jetbrains.name : "monospace"

    readonly property bool ready: inter.status === FontLoader.Ready
                                  && cormorant.status === FontLoader.Ready
                                  && jetbrains.status === FontLoader.Ready
}
