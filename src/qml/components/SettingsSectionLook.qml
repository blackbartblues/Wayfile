import QtQuick
import QtQuick.Layouts
import Heimdall
import Quill as Q

// Look & Feel settings page — theme, typography, icons, surface styling.
// Extracted from SettingsPanel.qml. All draft state and helpers live on
// the typed `panel` (a SettingsPanel), so reads stay reactive.
ColumnLayout {
    property SettingsPanel panel
    spacing: 6


    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        spacing: 12

        Text {
            text: "Dark Mode"
            color: Theme.text
            font.pointSize: Theme.fontNormal + 2
            font.bold: true
        }

        Item { Layout.fillWidth: true }

        Q.Toggle {
            label: ""
            checked: panel.draftDarkMode
            onToggled: (value) => {
                panel.setDraftTheme(value ? "catppuccin-mocha" : "catppuccin-latte")
                panel.applySettingsNow()
            }
        }
    }

    SettingDescription {
        text: "Switch between the dark and light Catppuccin theme palette."
    }

    Q.Separator { Layout.bottomMargin: 8 }

    Text {
        text: "Theme"
        color: Theme.accent
        font.pointSize: Theme.fontSmall
        font.bold: true
        Layout.bottomMargin: 4
    }

    SettingsDropdown {
        settingsPanel: panel
        Layout.fillWidth: true
        label: "Theme"
        model: panel.themeOptions
        currentIndex: panel.optionIndex(panel.themeOptions, panel.draftTheme, 0)
        onSelected: (_, value) => {
            panel.setDraftTheme(value)
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        text: "Color palette used across the whole interface."
    }

    SettingsDropdown {
        settingsPanel: panel
        Layout.fillWidth: true
        label: "Font"
        model: panel.fontOptions
        currentIndex: panel.optionIndex(panel.fontOptions, panel.draftFontFamily === "" ? panel.systemFontLabel : panel.draftFontFamily, 0)
        onSelected: (_, value) => {
            panel.draftFontFamily = value === panel.systemFontLabel ? "" : value
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        text: "Font family for all interface text; System Default follows your desktop."
    }

    SettingsDropdown {
        settingsPanel: panel
        Layout.fillWidth: true
        label: "Icon Pack"
        model: panel.iconThemeOptions
        currentIndex: panel.optionIndex(panel.iconThemeOptions, panel.draftIconTheme, 0)
        onSelected: (_, value) => {
            panel.draftIconTheme = value
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        text: "Icon theme used for files, folders, and apps in the file list."
    }

    Q.Toggle {
        Layout.fillWidth: true
        label: "Use built-in icons as fallback"
        checked: panel.draftBuiltinIcons
        onToggled: (value) => {
            panel.draftBuiltinIcons = value
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        text: "Fall back to Heimdall's bundled icons when the icon pack has no match."
    }

    Text {
        text: "Surface Styling"
        color: Theme.accent
        font.pointSize: Theme.fontSmall
        font.bold: true
        Layout.topMargin: 12
        Layout.bottomMargin: 4
    }

    Q.Toggle {
        Layout.fillWidth: true
        label: "Transparent containers"
        checked: panel.draftTransparencyEnabled
        onToggled: (value) => {
            panel.draftTransparencyEnabled = value
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        text: "Let panels and surfaces blend with the wallpaper instead of using a solid fill."
    }

    Q.Slider {
        Layout.fillWidth: true
        label: "Transparency"
        from: 0
        to: 100
        stepSize: 1
        showValue: true
        enabled: panel.draftTransparencyEnabled
        value: panel.draftTransparencyLevel * 100
        onMoved: (value) => {
            panel.draftTransparencyLevel = value / 100
            panel.queueSettingsApply()
        }
    }

    SettingDescription {
        enabled: panel.draftTransparencyEnabled
        text: "How opaque the transparent surfaces are; lower values show more of the background."
    }

    Q.Slider {
        Layout.fillWidth: true
        label: "Small radius"
        from: 0
        to: 24
        stepSize: 1
        showValue: true
        value: panel.draftRadiusSmall
        onMoved: (value) => {
            panel.draftRadiusSmall = Math.round(value)
            if (panel.draftRadiusMedium < panel.draftRadiusSmall)
                panel.draftRadiusMedium = panel.draftRadiusSmall
            if (panel.draftRadiusLarge < panel.draftRadiusMedium)
                panel.draftRadiusLarge = panel.draftRadiusMedium
            panel.queueSettingsApply()
        }
    }

    SettingDescription {
        text: "Corner rounding for small elements like buttons, chips, and inputs."
    }

    Q.Slider {
        Layout.fillWidth: true
        label: "Medium radius"
        from: panel.draftRadiusSmall
        to: 28
        stepSize: 1
        showValue: true
        value: panel.draftRadiusMedium
        onMoved: (value) => {
            panel.draftRadiusMedium = Math.round(value)
            if (panel.draftRadiusLarge < panel.draftRadiusMedium)
                panel.draftRadiusLarge = panel.draftRadiusMedium
            panel.queueSettingsApply()
        }
    }

    SettingDescription {
        text: "Corner rounding for medium surfaces such as cards and menus."
    }

    Q.Slider {
        Layout.fillWidth: true
        label: "Large radius"
        from: panel.draftRadiusMedium
        to: 32
        stepSize: 1
        showValue: true
        value: panel.draftRadiusLarge
        onMoved: (value) => {
            panel.draftRadiusLarge = Math.round(value)
            panel.queueSettingsApply()
        }
    }

    SettingDescription {
        text: "Corner rounding for large surfaces like dialogs and the main window."
    }
}
