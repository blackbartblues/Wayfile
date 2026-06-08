pragma Singleton

import QtQuick

QtObject {
    id: root

    // Colors — Surface hierarchy
    property color background: "#1e1e2e"
    property color backgroundAlt: "#181825"
    property color backgroundDeep: "#11111b"
    property color surface0: "#313244"
    property color surface1: "#45475a"
    property color surface2: "#585b70"
    property color overlay0: "#6c7086"
    property color overlay1: "#7f849c"

    // Colors — Text
    property color textPrimary: "#cdd6f4"
    property color textSecondary: "#bac2de"
    property color textTertiary: "#a6adc8"

    // Colors — Semantic
    property color primary: "#89b4fa"
    property color secondary: "#b4befe"
    property color accent: "#cba6f7"
    property color success: "#a6e3a1"
    property color warning: "#f9e2af"
    property color error: "#f38ba8"
    property color info: "#89dceb"

    // Wayfile obsidian+gold accent layer (bridged from Wayfile's Theme in
    // Main.qml; defaults match Bifröst so Quill renders coherently before the
    // bridge runs). The gold-skinned controls (Button/Toggle/Slider) consume
    // these; `primary` stays the generic accent for the rest of the library.
    property color gold: "#E3A94B"
    property color goldMid: "#C98F3C"
    property color goldLight: "#FFE7B6"
    property color knob: "#fff3df"

    // Catppuccin aliases (readonly bindings for migration ease)
    readonly property color blue: primary
    readonly property color lavender: secondary
    readonly property color mauve: accent
    readonly property color green: success
    readonly property color yellow: warning
    readonly property color red: error
    readonly property color teal: info
    readonly property color base: background
    readonly property color mantle: backgroundAlt
    readonly property color crust: backgroundDeep
    readonly property color text: textPrimary
    readonly property color subtext1: textSecondary
    readonly property color subtext0: textTertiary

    // Typography
    property string fontFamily: Qt.application.font.family
    property string iconFont: "Maple Mono NF"
    property int fontSizeSmall: 11
    property int fontSize: 13
    property int fontSizeLarge: 16
    property int fontSizeHeading: 20

    // Spacing
    property int spacingXs: 4
    property int spacingSm: 6
    property int spacing: 8
    property int spacingMd: 12
    property int spacingLg: 16
    property int spacingXl: 24

    // Radii
    property int radius: 8
    property int radiusSm: 4
    property int radiusLg: 12
    property int radiusFull: 9999

    // Animation
    property int animDuration: 200
    property int animDurationFast: 100
    property int animDurationSlow: 350

    // Transparency
    property bool transparencyEnabled: false
    property real transparencyLevel: 0.85

    function bg(color, opacity) {
        if (!transparencyEnabled) return color;
        return Qt.rgba(color.r, color.g, color.b, opacity !== undefined ? opacity : transparencyLevel);
    }
}
