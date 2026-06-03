import QtQuick
import ".."

Text {
    id: root

    property string glyph: ""
    property string size: "medium" // "small" | "medium" | "large"

    Accessible.role: Accessible.Graphic
    Accessible.ignored: true

    text: glyph
    color: Theme.textPrimary
    font.family: Theme.iconFont
    font.pixelSize: {
        switch (size) {
            case "small": return Theme.fontSizeSmall;
            case "large": return Theme.fontSizeLarge;
            default: return Theme.fontSize;
        }
    }
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
