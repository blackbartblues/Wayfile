import QtQuick
import QtQuick.Layouts
import Wayfile
import Quill as Q

// Colours settings page (Phase C4) — a granular, power-user palette editor.
//
// Each token gets a live swatch + a hex field. Editing applies instantly via
// ThemeLoader.setColor (in-memory preview, Theme.qml's Behaviors cross-fade),
// and a debounced save serialises the whole palette to the writable
// `custom.toml` (config dir) and selects theme "custom". Wayland-safe: the
// editor is a plain in-scene hex field + swatch (no native colour dialog, no
// Quill dropdown — both unreliable on Hyprland).
//
// All draft state and helpers used by the other pages live on the typed
// `panel` (a SettingsPanel); here we drive the `theme`/`config` context
// objects directly because colours are theme tokens, not config.toml prefs.
ColumnLayout {
    id: colorsRoot
    property SettingsPanel panel
    spacing: 6

    // Bumped to force every editor row to re-read its seed colour (after a
    // reset or a theme reload).
    property int rev: 0

    // The 5 shipped accent presets (the obsidian base is shared; each preset
    // overrides only `accent`). The dot shows the accent; the picker is the
    // headline way to switch themes.
    readonly property var presets: [
        { name: "bifrost", label: "Bifröst", accent: "#D4AA6A" },
        { name: "aurora",  label: "Aurora",  accent: "#57C7BF" },
        { name: "nebula",  label: "Nebula",  accent: "#B292E8" },
        { name: "ember",   label: "Ember",   accent: "#E68B5C" },
        { name: "verdant", label: "Verdant", accent: "#84C98A" }
    ]

    // ── helpers ───────────────────────────────────────────────────────────
    function _h(x) {
        var s = Math.round(x * 255).toString(16)
        return s.length < 2 ? "0" + s : s
    }
    function hexOf(c) {
        if (c.a < 0.999)
            return "#" + _h(c.a) + _h(c.r) + _h(c.g) + _h(c.b)
        return "#" + _h(c.r) + _h(c.g) + _h(c.b)
    }
    function parseHex(s) {
        var t = ("" + (s || "")).trim()
        if (/^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(t))
            return { ok: true, color: Qt.color(t) }
        return { ok: false, color: Qt.color("transparent") }
    }
    function scheduleSave() { saveTimer.restart() }

    // WCAG relative-luminance contrast ratio — used (non-destructively) to warn
    // when the accent is too close to the background for selection outlines,
    // status dots and the device meter to read. We warn rather than clamp:
    // this is the power-user granular editor, the choice stays the user's.
    function _lin(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    function relLum(c) { return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b) }
    function contrastRatio(a, b) {
        var hi = Math.max(relLum(a), relLum(b))
        var lo = Math.min(relLum(a), relLum(b))
        return (hi + 0.05) / (lo + 0.05)
    }
    // Editing a base token writes custom.toml and forks the `custom` theme.
    // The gold ramp is derived from `accent` in Theme.qml, so there is no
    // separate gold to keep in sync here.
    function applyToken(token, c) {
        theme.setColor(token, c)
        colorsRoot.scheduleSave()
    }

    Timer {
        id: saveTimer
        interval: 220
        onTriggered: {
            theme.saveThemeFile(config.customThemePath())
            // First edit on a non-custom theme: switch to `custom` so the saved
            // palette is what loads on next launch. The reload of the file we
            // just wrote matches the live preview, so nothing flickers.
            if (config.theme !== "custom") {
                panel.setDraftTheme("custom")
                panel.applySettingsNow()
            }
        }
    }

    // ── editable token groups ───────────────────────────────────────────────
    readonly property var groupAccent: [{ t: "accent", l: "Accent" }]
    readonly property var groupSurfaces: [
        { t: "page", l: "Page" },
        { t: "bgA", l: "Window · top" },
        { t: "bgB", l: "Window · bottom" },
        { t: "panel", l: "Panel" },
        { t: "panel2", l: "Panel · raised" },
        { t: "raise", l: "Surface" },
        { t: "raise2", l: "Surface · high" }
    ]
    readonly property var groupSemantic: [
        { t: "base", l: "Base" },
        { t: "mantle", l: "Mantle" },
        { t: "crust", l: "Crust" },
        { t: "surface", l: "Surface (sem.)" },
        { t: "overlay", l: "Overlay" }
    ]
    readonly property var groupText: [
        { t: "text", l: "Text" },
        { t: "subtext", l: "Subtext" },
        { t: "muted", l: "Muted" }
    ]
    readonly property var groupLines: [
        { t: "line", l: "Line" },
        { t: "lineSoft", l: "Line · soft" },
        { t: "hair", l: "Hairline" }
    ]
    readonly property var groupAtmos: [
        { t: "sheen", l: "Sheen" },
        { t: "shadowInk", l: "Shadow" },
        { t: "scrim", l: "Scrim" },
        { t: "knob", l: "Knob" }
    ]
    readonly property var groupStatus: [
        { t: "success", l: "Success" },
        { t: "warning", l: "Warning" },
        { t: "error", l: "Error" }
    ]

    // ── one editor row (swatch + hex field) ─────────────────────────────────
    Component {
        id: colorRow
        RowLayout {
            id: rowItem
            required property var modelData
            Layout.fillWidth: true
            spacing: 10

            // Re-reads on rev bump (comma operator establishes the dependency).
            property color seedColor: (colorsRoot.rev, theme.currentColor(modelData.t))
            onSeedColorChanged: hexField.text = colorsRoot.hexOf(seedColor)
            Component.onCompleted: hexField.text = colorsRoot.hexOf(seedColor)

            Text {
                text: rowItem.modelData.l
                color: Theme.text
                font.pointSize: Theme.fontSmall
                Layout.preferredWidth: 110
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 22
                radius: Theme.radiusSmall
                border.width: 1
                border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.18)
                color: {
                    var c = colorsRoot.parseHex(hexField.text)
                    return c.ok ? c.color : rowItem.seedColor
                }
            }

            Q.TextField {
                id: hexField
                Layout.preferredWidth: 130
                placeholder: "#rrggbb"
                // onTextEdited fires only for user input (not programmatic
                // seeding), so there's no apply-loop on re-seed.
                onTextEdited: (t) => {
                    var c = colorsRoot.parseHex(t)
                    if (c.ok)
                        colorsRoot.applyToken(rowItem.modelData.t, c.color)
                }
            }

            Item { Layout.fillWidth: true }
        }
    }

    // ── content ──────────────────────────────────────────────────────────────
    SettingDescription {
        text: "Edit the active palette token by token. Changes apply live and are saved as a \"custom\" theme in your config folder."
    }

    // Live low-contrast warning: gold-on-dark marks (selection outlines, status
    // dots, the device meter) lose legibility when accent ≈ background.
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 4
        visible: colorsRoot.contrastRatio(Theme.accent, Theme.base) < 2.0
        Layout.preferredHeight: visible ? contrastWarnLabel.implicitHeight + 14 : 0
        radius: Theme.radiusSmall
        color: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.12)
        border.width: 1
        border.color: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.40)

        Text {
            id: contrastWarnLabel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            wrapMode: Text.WordWrap
            text: "Low accent contrast against the background — selection outlines, status dots and the device meter may be hard to see."
            color: Theme.warning
            font.pointSize: Theme.fontSmall
        }
    }

    Text {
        text: "Theme preset"
        color: Theme.accent
        font.pointSize: Theme.fontSmall
        font.bold: true
        Layout.topMargin: 6
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 12

        Repeater {
            model: colorsRoot.presets
            delegate: ColumnLayout {
                id: swatch
                required property var modelData
                readonly property bool active: config.theme === swatch.modelData.name
                spacing: 4

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 46
                    height: 46
                    radius: Theme.radiusMedium
                    color: Theme.panel
                    border.width: swatch.active ? 2 : 1
                    border.color: swatch.active
                        ? Theme.gold
                        : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, swatchHover.hovered ? 0.40 : 0.18)

                    Rectangle {
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        radius: 13
                        color: swatch.modelData.accent
                    }

                    HoverHandler { id: swatchHover }
                    TapHandler {
                        onTapped: {
                            colorsRoot.panel.setDraftTheme(swatch.modelData.name)
                            colorsRoot.panel.applySettingsNow()
                            colorsRoot.rev++ // re-seed the granular editor rows
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: swatch.modelData.label
                    color: swatch.active ? Theme.accent : Theme.subtext
                    font.pointSize: Theme.fontSmall
                }
            }
        }

        Item { Layout.fillWidth: true }
    }

    SettingDescription {
        text: "Pick an accent preset. The obsidian base stays the same; the accent retints folders, highlights, and controls. Edit tokens below to fork a custom theme."
    }

    Q.Separator { Layout.topMargin: 6; Layout.bottomMargin: 2 }

    Text { text: "Accent"; color: Theme.accent; font.pointSize: Theme.fontSmall; font.bold: true; Layout.topMargin: 4 }
    Repeater { model: colorsRoot.groupAccent; delegate: colorRow }

    Text { text: "Obsidian surfaces"; color: Theme.accent; font.pointSize: Theme.fontSmall; font.bold: true; Layout.topMargin: 8 }
    Repeater { model: colorsRoot.groupSurfaces; delegate: colorRow }

    Text { text: "Semantic surfaces"; color: Theme.accent; font.pointSize: Theme.fontSmall; font.bold: true; Layout.topMargin: 8 }
    Repeater { model: colorsRoot.groupSemantic; delegate: colorRow }

    Text { text: "Text"; color: Theme.accent; font.pointSize: Theme.fontSmall; font.bold: true; Layout.topMargin: 8 }
    Repeater { model: colorsRoot.groupText; delegate: colorRow }

    Text { text: "Lines"; color: Theme.accent; font.pointSize: Theme.fontSmall; font.bold: true; Layout.topMargin: 8 }
    Repeater { model: colorsRoot.groupLines; delegate: colorRow }

    Text { text: "Atmosphere"; color: Theme.accent; font.pointSize: Theme.fontSmall; font.bold: true; Layout.topMargin: 8 }
    Repeater { model: colorsRoot.groupAtmos; delegate: colorRow }

    Text { text: "Status"; color: Theme.accent; font.pointSize: Theme.fontSmall; font.bold: true; Layout.topMargin: 8 }
    Repeater { model: colorsRoot.groupStatus; delegate: colorRow }

    SettingDescription {
        Layout.topMargin: 8
        text: "Tip: type a hex value (#rrggbb, or #aarrggbb for translucency). Atmosphere tokens (sheen, shadow, scrim) read best with alpha."
    }
}
