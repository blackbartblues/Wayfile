import QtQuick
import QtQuick.Layouts
import Heimdall

// One-line (wrapping) helper text shown directly beneath a setting control.
// Keeps description styling consistent across SettingsPanel without touching
// the Quill submodule, whose controls have no `description` property.
Text {
    Layout.fillWidth: true
    Layout.topMargin: -2
    Layout.bottomMargin: 4
    color: Theme.subtext
    font.pointSize: Theme.fontSmall
    wrapMode: Text.WordWrap
    // Dim alongside the control it describes; callers set `enabled` to match.
    opacity: enabled ? 0.85 : 0.4
}
