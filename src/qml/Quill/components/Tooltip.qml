import QtQuick
import QtQuick.Templates as T
import ".."

// shadcn-style tooltip: opaque dark popover surface, thin hairline border,
// soft small radius, tight padding, subtle fade.
T.ToolTip {
    id: root

    // Force the popup to render in the parent window's overlay layer
    // (Item) rather than as a separate xdg-popup window. With Qt 6.6+'s
    // default `Popup.Window`, the tooltip becomes a Wayland subsurface
    // that inherits the main window's translucent surface format on
    // Hyprland/KWin — bg Rectangles inside paint into a buffer that
    // never composites onto the screen, so the chip looks "missing".
    // Item-mode rendering is bullet-proof for short-lived hover chips.
    popupType: T.Popup.Item

    delay: 500
    timeout: -1

    padding: 0
    leftPadding: Theme.spacingMd
    rightPadding: Theme.spacingMd
    topPadding: Math.round(Theme.spacing * 0.75)
    bottomPadding: Math.round(Theme.spacing * 0.75)

    // Centre horizontally on the trigger and hover *below* it.  IconButtons
    // in HyprFM live in the titlebar; a tooltip placed above the parent
    // would land at y<0 and clip against the top of the parent window now
    // that we render Item-style (in-window) instead of as a Wayland popup.
    x: parent ? Math.round((parent.width - implicitWidth) / 2) : 0
    y: parent ? parent.height + 6 : 6

    contentItem: Text {
        text: root.text
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeSmall
        font.family: Theme.fontFamily
        Accessible.role: Accessible.ToolTip
        Accessible.name: root.text
    }

    background: Rectangle {
        // Force alpha to 1.0 so the popover is always visible. Use a raised
        // surface instead of backgroundAlt; backgroundAlt matches the sidebar.
        color: Qt.rgba(Theme.surface1.r,
                       Theme.surface1.g,
                       Theme.surface1.b,
                       1.0)
        radius: Theme.radiusSm
        border.width: 1
        // Crisp hairline ring so the chip separates from both dark and light themes.
        border.color: Qt.rgba(Theme.textPrimary.r,
                              Theme.textPrimary.g,
                              Theme.textPrimary.b,
                              0.22)
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"
                              from: 0.0; to: 1.0
                              duration: 150; easing.type: Easing.OutQuad }
            // Slide *down* a few pixels into place — matches the chip
            // appearing under its trigger.
            NumberAnimation { property: "y"
                              from: root.y - 4; to: root.y
                              duration: 150; easing.type: Easing.OutQuad }
        }
    }

    exit: Transition {
        NumberAnimation { property: "opacity"
                          from: 1.0; to: 0.0
                          duration: 100; easing.type: Easing.InQuad }
    }
}
