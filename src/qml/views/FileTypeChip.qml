import QtQuick
import Heimdall

// Metallic file-type chip — a small rounded tile carrying a short mono type
// label tinted by the file's category/extension (handoff file-row chip).
// Label + tint come from FileTypeColors.chipFor(ext, category, isHidden).
Rectangle {
    id: chip

    property string label: ""
    property color tint: Theme.subtext
    property int size: 22

    width: size
    height: size
    radius: Math.max(3, Math.round(size * 0.27))
    gradient: Gradient {
        GradientStop { position: 0.0; color: Theme.raise2 }
        GradientStop { position: 1.0; color: Theme.panel2 }
    }
    border.width: 1
    border.color: Theme.line

    Text {
        anchors.centerIn: parent
        width: chip.size - 4
        text: chip.label
        color: chip.tint
        font.family: Fonts.mono
        font.weight: Font.Bold
        font.pixelSize: Math.max(7, Math.round(chip.size * 0.42))
        // Short labels (M↓, {}, PDF, GZ, TS, #); auto-shrink the rare long one.
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 6
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
