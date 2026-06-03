import QtQuick
import ".."

Text {
    id: root

    property string variant: "body" // "heading" | "body" | "caption" | "overline"

    Accessible.role: variant === "heading" ? Accessible.Heading : Accessible.StaticText
    Accessible.name: root.text

    color: Theme.textPrimary
    font.family: Theme.fontFamily
    font.pixelSize: {
        switch (variant) {
            case "heading": return Theme.fontSizeHeading;
            case "caption": return Theme.fontSizeSmall;
            case "overline": return Theme.fontSizeSmall;
            default: return Theme.fontSize;
        }
    }
    font.bold: variant === "heading"
    font.capitalization: variant === "overline" ? Font.AllUppercase : Font.MixedCase
    font.letterSpacing: variant === "overline" ? 1.5 : 0

    opacity: variant === "caption" || variant === "overline" ? 0.7 : 1.0
}
