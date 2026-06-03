import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    spacing: Theme.spacingXl

    // ── Icon ──
    Text {
        text: "Icon"
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
        GridLayout {
            columns: 6
            columnSpacing: Theme.spacingLg
            rowSpacing: Theme.spacingMd

            Icon { glyph: "\uf015"; size: "small" }
            Icon { glyph: "\uf013"; size: "small" }
            Icon { glyph: "\uf007"; size: "small" }
            Icon { glyph: "\uf002"; size: "small" }
            Icon { glyph: "\uf0f3"; size: "small" }
            Icon { glyph: "\uf004"; size: "small" }

            Icon { glyph: "\uf015"; size: "medium" }
            Icon { glyph: "\uf013"; size: "medium" }
            Icon { glyph: "\uf007"; size: "medium" }
            Icon { glyph: "\uf002"; size: "medium" }
            Icon { glyph: "\uf0f3"; size: "medium" }
            Icon { glyph: "\uf004"; size: "medium" }

            Icon { glyph: "\uf015"; size: "large" }
            Icon { glyph: "\uf013"; size: "large" }
            Icon { glyph: "\uf007"; size: "large" }
            Icon { glyph: "\uf002"; size: "large" }
            Icon { glyph: "\uf0f3"; size: "large" }
            Icon { glyph: "\uf004"; size: "large" }
        }

        Text {
            text: "Colors"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        RowLayout {
            spacing: Theme.spacingLg
            Icon { glyph: "\uf015"; color: Theme.primary }
            Icon { glyph: "\uf00c"; color: Theme.success }
            Icon { glyph: "\uf00d"; color: Theme.error }
            Icon { glyph: "\uf071"; color: Theme.warning }
            Icon { glyph: "\uf05a"; color: Theme.info }
        }
    }

    // ── Label ──
    Text {
        text: "Label"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
    }

    ColumnLayout {
        spacing: Theme.spacingMd

        Label { text: "Heading variant"; variant: "heading" }
        Label { text: "Body variant — the default style for general text content."; variant: "body" }
        Label { text: "Caption variant — smaller, for secondary information"; variant: "caption" }
        Label { text: "Overline variant"; variant: "overline" }
    }

    // ── Avatar ──
    Text {
        text: "Avatar"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
    }

    ColumnLayout {
        spacing: Theme.spacingMd

        Text {
            text: "Sizes with initials"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        RowLayout {
            spacing: Theme.spacingMd
            Avatar { fallback: "S"; size: "small" }
            Avatar { fallback: "M"; size: "medium" }
            Avatar { fallback: "L"; size: "large" }
        }

        Text {
            text: "Rounded vs square"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        RowLayout {
            spacing: Theme.spacingMd
            Avatar { fallback: "JD"; size: "large"; rounded: true }
            Avatar { fallback: "JD"; size: "large"; rounded: false }
        }
    }
}
