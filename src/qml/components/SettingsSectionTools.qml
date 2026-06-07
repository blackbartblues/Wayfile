import QtQuick
import QtQuick.Layouts
import Wayfile
import Quill as Q

// Tools settings page — utilities and bookmark guidance.
// Extracted from SettingsPanel.qml. All draft state and helpers live on
// the typed `panel` (a SettingsPanel), so reads stay reactive.
ColumnLayout {
    property SettingsPanel panel
    spacing: 6


    Text {
        text: "Utilities"
        color: Theme.accent
        font.pointSize: Theme.fontSmall
        font.bold: true
        Layout.bottomMargin: 4
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Q.Button {
            Layout.fillWidth: true
            text: "Keyboard Shortcuts"
            onClicked: panel.openKeyboardShortcuts()
        }

        Q.Button {
            Layout.fillWidth: true
            text: "Connect to Network Location"
            variant: "ghost"
            onClicked: panel.openRemoteConnect()
        }
    }

    SettingDescription {
        text: "View the keyboard shortcut reference, or mount an SMB, SFTP, or other network share."
    }

    // Wayfile: dependency check moved off the startup auto-popup
    // path and into a manual trigger here. Click only when you want
    // to see what extra tools the file manager can use.
    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Q.Button {
            Layout.fillWidth: true
            text: "Check Optional Dependencies"
            variant: "ghost"
            onClicked: panel.openDependencyCheck()
        }
    }

    SettingDescription {
        text: "Scan for optional CLI tools (rsync, gio, wl-copy) and report which features they unlock."
    }

    Text {
        text: "Bookmarks"
        color: Theme.accent
        font.pointSize: Theme.fontSmall
        font.bold: true
        Layout.topMargin: 12
        Layout.bottomMargin: 4
    }

    Text {
        Layout.fillWidth: true
        text: "Pinned folders are managed from the sidebar — right-click a folder and choose Pin (or drag it onto the sidebar). They live in one place, so there is no separate editor here."
        color: Theme.subtext
        font.pointSize: Theme.fontSmall
        wrapMode: Text.WordWrap
    }
}
