import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    spacing: Theme.spacingXl

    // ── Buttons ──
    Text {
        text: "Buttons"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
    }

    ColumnLayout {
        spacing: Theme.spacingMd

        Text {
            text: "Variants"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        RowLayout {
            spacing: Theme.spacing
            Button { text: "Primary"; variant: "primary" }
            Button { text: "Secondary"; variant: "secondary" }
            Button { text: "Ghost"; variant: "ghost" }
            Button { text: "Danger"; variant: "danger" }
        }

        Text {
            text: "Sizes"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        RowLayout {
            spacing: Theme.spacing
            Button { text: "Small"; size: "small" }
            Button { text: "Medium"; size: "medium" }
            Button { text: "Large"; size: "large" }
        }

        Text {
            text: "With icon"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        RowLayout {
            spacing: Theme.spacing
            Button { text: "Save"; icon: "\uf0c7"; variant: "primary" }
            Button { text: "Delete"; icon: "\uf1f8"; variant: "danger" }
        }

        Text {
            text: "Icon buttons"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        RowLayout {
            spacing: Theme.spacing
            IconButton { icon: "\uf013"; variant: "ghost" }
            IconButton { icon: "\uf015"; variant: "primary" }
            IconButton { icon: "\uf1f8"; variant: "danger" }
            IconButton { icon: "\uf00d"; variant: "secondary" }
        }

        Text {
            text: "Disabled"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        RowLayout {
            spacing: Theme.spacing
            Button { text: "Disabled"; variant: "primary"; enabled: false }
            IconButton { icon: "\uf013"; variant: "ghost"; enabled: false }
        }
    }

    // ── Toggle ──
    Text {
        text: "Toggle"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
    }

    ColumnLayout {
        spacing: Theme.spacingMd
        Layout.preferredWidth: 300

        Toggle { label: "Enable notifications"; checked: true }
        Toggle { label: "Dark mode"; checked: false }
        Toggle {}
        Toggle { label: "Disabled toggle"; enabled: false; checked: true }
    }

    // ── Checkbox ──
    Text {
        text: "Checkbox"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
    }

    ColumnLayout {
        spacing: Theme.spacingMd

        Checkbox { label: "Accept terms"; checked: true }
        Checkbox { label: "Subscribe to newsletter" }
        Checkbox { label: "Disabled option"; enabled: false; checked: true }
    }

    // ── Slider ──
    Text {
        text: "Slider"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
    }

    ColumnLayout {
        spacing: Theme.spacingMd
        Layout.fillWidth: true

        Slider {
            label: "Volume"
            value: 65
            from: 0; to: 100
            showValue: true
            Layout.fillWidth: true
        }
        Slider {
            label: "Step (10)"
            value: 30
            from: 0; to: 100
            stepSize: 10
            showValue: true
            Layout.fillWidth: true
        }
        Slider {
            label: "Disabled"
            value: 40
            from: 0; to: 100
            showValue: true
            enabled: false
            Layout.fillWidth: true
        }
    }

    // ── TextField ──
    Text {
        text: "TextField"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
    }

    ColumnLayout {
        spacing: Theme.spacingMd
        Layout.fillWidth: true

        TextField {
            placeholder: "Default text field"
            Layout.fillWidth: true
        }
        TextField {
            placeholder: "Filled variant"
            variant: "filled"
            Layout.fillWidth: true
        }
        TextField {
            placeholder: "Search..."
            icon: "\uf002"
            Layout.fillWidth: true
        }
        TextField {
            placeholder: "Disabled"
            enabled: false
            Layout.fillWidth: true
        }
    }

    // ── Radio ──
    Text {
        text: "Radio"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
    }

    ColumnLayout {
        spacing: Theme.spacingMd

        RadioGroup {
            id: themeGroup
            value: "dark"
            onSelected: (val) => { radioLabel.text = "Selected: " + val; }
            RadioButton { value: "light"; label: "Light" }
            RadioButton { value: "dark"; label: "Dark" }
            RadioButton { value: "auto"; label: "Auto" }
        }

        Text {
            id: radioLabel
            text: "Selected: dark"
            color: Theme.textTertiary
            font.pixelSize: Theme.fontSizeSmall
            font.family: Theme.fontFamily
        }

        RadioGroup {
            enabled: false
            value: "a"
            RadioButton { value: "a"; label: "Disabled A" }
            RadioButton { value: "b"; label: "Disabled B" }
        }
    }

    // ── Dropdown ──
    Text {
        text: "Dropdown"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
    }

    ColumnLayout {
        spacing: Theme.spacingMd
        Layout.fillWidth: true

        Dropdown {
            label: "Theme"
            model: ["Catppuccin Mocha", "Catppuccin Latte", "Catppuccin Frappe", "Catppuccin Macchiato"]
            currentIndex: 0
            Layout.fillWidth: true
        }
        Dropdown {
            model: ["Option A", "Option B", "Option C"]
            currentIndex: 1
            Layout.fillWidth: true
        }
        Dropdown {
            label: "Disabled"
            model: ["Cannot change"]
            enabled: false
            Layout.fillWidth: true
        }
    }
}
