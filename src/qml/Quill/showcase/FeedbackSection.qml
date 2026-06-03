import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    spacing: Theme.spacingXl

    // ── Tooltip ──
    Text {
        text: "Tooltip"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
    }

    ColumnLayout {
        spacing: Theme.spacingMd

        Text {
            text: "Hover over the icon buttons to see tooltips"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        RowLayout {
            spacing: Theme.spacing
            IconButton { icon: "\uf015"; tooltip: "Home"; variant: "ghost" }
            IconButton { icon: "\uf013"; tooltip: "Settings"; variant: "ghost" }
            IconButton { icon: "\uf007"; tooltip: "Profile"; variant: "ghost" }
            IconButton { icon: "\uf002"; tooltip: "Search"; variant: "ghost" }
        }

        Text {
            text: "Child-component form on a bare item"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        Rectangle {
            width: 220
            height: 48
            radius: Theme.radiusSm
            color: Theme.surface1
            border.color: Theme.surface2
            Text {
                anchors.centerIn: parent
                text: "Hover me"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
            }
            HoverHandler { id: hoverArea }
            Tooltip {
                visible: hoverArea.hovered
                text: "Attached via HoverHandler"
            }
        }
    }

    // ── Badge ──
    Text {
        text: "Badge"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
    }

    ColumnLayout {
        spacing: Theme.spacingMd

        Text {
            text: "With text"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        RowLayout {
            spacing: Theme.spacing
            Badge { text: "New"; variant: "primary" }
            Badge { text: "Done"; variant: "success" }
            Badge { text: "Warn"; variant: "warning" }
            Badge { text: "Error"; variant: "error" }
        }

        Text {
            text: "Dot badges"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        RowLayout {
            spacing: Theme.spacing
            Badge { variant: "primary" }
            Badge { variant: "success" }
            Badge { variant: "warning" }
            Badge { variant: "error" }
        }
    }

    // ── ProgressBar ──
    Text {
        text: "ProgressBar"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
    }

    ColumnLayout {
        spacing: Theme.spacingMd
        Layout.fillWidth: true

        Text {
            text: "Fixed values"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        ProgressBar { value: 0.25; Layout.fillWidth: true }
        ProgressBar { value: 0.5; Layout.fillWidth: true }
        ProgressBar { value: 0.75; Layout.fillWidth: true }

        Text {
            text: "Interactive (drag the slider)"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        Slider {
            id: progressSlider
            label: "Progress"
            value: 50
            from: 0; to: 100
            showValue: true
            Layout.fillWidth: true
        }
        ProgressBar { value: progressSlider.value / 100; Layout.fillWidth: true }

        Text {
            text: "Indeterminate"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        ProgressBar { indeterminate: true; Layout.fillWidth: true }

        Text {
            text: "Variants"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        ProgressBar { value: 0.6; variant: "primary"; Layout.fillWidth: true }
        ProgressBar { value: 0.6; variant: "success"; Layout.fillWidth: true }
        ProgressBar { value: 0.6; variant: "warning"; Layout.fillWidth: true }
        ProgressBar { value: 0.6; variant: "error"; Layout.fillWidth: true }
    }

    // ── Spinner ──
    Text {
        text: "Spinner"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
    }

    ColumnLayout {
        spacing: Theme.spacingMd

        Text {
            text: "Sizes"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        RowLayout {
            spacing: Theme.spacingLg
            Spinner { size: "small" }
            Spinner { size: "medium" }
            Spinner { size: "large" }
        }

        Text {
            text: "Custom color"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        RowLayout {
            spacing: Theme.spacingLg
            Spinner { color: Theme.success }
            Spinner { color: Theme.warning }
            Spinner { color: Theme.error }
        }
    }
}
