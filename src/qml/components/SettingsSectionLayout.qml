import QtQuick
import QtQuick.Layouts
import Wayfile
import Quill as Q

// Layout settings page — browsing, sidebar, window controls.
// Extracted from SettingsPanel.qml. All draft state and helpers live on
// the typed `panel` (a SettingsPanel), so reads stay reactive.
ColumnLayout {
    property SettingsPanel panel
    spacing: 6


    Text {
        text: "Browsing"
        color: Theme.accent
        font.pointSize: Theme.fontSmall
        font.bold: true
        Layout.bottomMargin: 4
    }

    Q.Checkbox {
        label: "Show hidden files"
        checked: panel.draftShowHidden
        onToggled: (value) => {
            panel.draftShowHidden = value
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        text: "Reveal dotfiles and hidden entries in the file list."
    }

    SettingsDropdown {
        settingsPanel: panel
        Layout.fillWidth: true
        label: "Default view for new tabs"
        model: panel.viewModeLabels
        currentIndex: Math.max(0, panel.viewModeValues.indexOf(panel.draftDefaultView))
        onSelected: (index, _) => {
            panel.draftDefaultView = panel.viewModeValues[index]
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        text: "Layout newly opened tabs start in: grid, Miller columns, or detailed list."
    }

    Q.Toggle {
        Layout.fillWidth: true
        label: "Remember view per folder"
        checked: panel.draftRememberFolderView
        onToggled: (value) => {
            panel.draftRememberFolderView = value
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        text: "When on, each folder reopens in the view you last set for it. New folders keep the current pane's view."
    }

    SettingsDropdown {
        settingsPanel: panel
        Layout.fillWidth: true
        label: "Default sort for new tabs"
        model: panel.sortByLabels
        currentIndex: Math.max(0, panel.sortByValues.indexOf(panel.draftSortBy))
        onSelected: (index, _) => {
            panel.draftSortBy = panel.sortByValues[index]
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        text: "Which column newly opened tabs sort by: name, size, date modified, or type."
    }

    Q.Toggle {
        Layout.fillWidth: true
        label: "Sort ascending by default"
        checked: panel.draftSortAscending
        onToggled: (value) => {
            panel.draftSortAscending = value
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        text: "Sort new tabs in ascending order (A→Z, smallest first); off sorts descending."
    }

    Q.Toggle {
        Layout.fillWidth: true
        label: "Show sidebar"
        checked: panel.draftSidebarVisible
        onToggled: (value) => {
            panel.draftSidebarVisible = value
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        text: "Show the sidebar with pinned folders, devices, and quick locations."
    }

    Q.Toggle {
        Layout.fillWidth: true
        label: "Sidebar on right"
        enabled: panel.draftSidebarVisible
        checked: panel.draftSidebarPosition === "right"
        onToggled: (value) => {
            panel.draftSidebarPosition = value ? "right" : "left"
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        enabled: panel.draftSidebarVisible
        text: "Place the sidebar on the right edge of the window instead of the left."
    }

    Q.Slider {
        Layout.fillWidth: true
        label: "Sidebar width"
        from: 160
        to: 480
        stepSize: 10
        showValue: true
        enabled: panel.draftSidebarVisible
        value: panel.draftSidebarWidth
        onMoved: (value) => {
            panel.draftSidebarWidth = Math.round(value)
            panel.queueSettingsApply()
        }
    }

    SettingDescription {
        enabled: panel.draftSidebarVisible
        text: "Default width of the sidebar in pixels."
    }

    Q.Slider {
        Layout.fillWidth: true
        label: "Scroll speed"
        from: 1.0
        to: 10.0
        stepSize: 0.5
        showValue: true
        value: panel.draftScrollSpeed
        onMoved: (value) => {
            panel.draftScrollSpeed = value
            panel.queueSettingsApply()
        }
    }

    SettingDescription {
        text: "How far the file view scrolls per mouse-wheel notch; higher is faster."
    }

    Text {
        text: "Window Controls"
        color: Theme.accent
        font.pointSize: Theme.fontSmall
        font.bold: true
        Layout.topMargin: 12
        Layout.bottomMargin: 4
    }

    Q.Toggle {
        Layout.fillWidth: true
        label: "Show window controls"
        checked: panel.draftShowWindowControls
        onToggled: (value) => {
            panel.draftShowWindowControls = value
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        text: "Draw minimize, maximize, and close buttons in the window's title area."
    }

    Q.Toggle {
        Layout.fillWidth: true
        label: "Buttons on left"
        enabled: panel.draftShowWindowControls
        checked: panel._layoutParts.side === "left"
        onToggled: (value) => {
            panel.rebuildButtonLayout(
                value ? "left" : "right",
                panel._layoutParts.hasClose,
                panel._layoutParts.hasMinimize,
                panel._layoutParts.hasMaximize
            )
        }
    }

    SettingDescription {
        enabled: panel.draftShowWindowControls
        text: "Group the window buttons on the left side instead of the right."
    }

    Q.Checkbox {
        label: "Close button"
        enabled: panel.draftShowWindowControls
        checked: panel._layoutParts.hasClose
        onToggled: (value) => {
            panel.rebuildButtonLayout(panel._layoutParts.side, value, panel._layoutParts.hasMinimize, panel._layoutParts.hasMaximize)
        }
    }

    SettingDescription {
        enabled: panel.draftShowWindowControls
        text: "Include the close button in the window controls."
    }

    Q.Checkbox {
        label: "Minimize button"
        enabled: panel.draftShowWindowControls
        checked: panel._layoutParts.hasMinimize
        onToggled: (value) => {
            panel.rebuildButtonLayout(panel._layoutParts.side, panel._layoutParts.hasClose, value, panel._layoutParts.hasMaximize)
        }
    }

    SettingDescription {
        enabled: panel.draftShowWindowControls
        text: "Include the minimize button in the window controls."
    }

    Q.Checkbox {
        label: "Maximize button"
        enabled: panel.draftShowWindowControls
        checked: panel._layoutParts.hasMaximize
        onToggled: (value) => {
            panel.rebuildButtonLayout(panel._layoutParts.side, panel._layoutParts.hasClose, panel._layoutParts.hasMinimize, value)
        }
    }

    SettingDescription {
        enabled: panel.draftShowWindowControls
        text: "Include the maximize button in the window controls."
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 54
        radius: Theme.radiusMedium
        color: Theme.containerColor(Theme.surface, 0.22)
        border.width: 1
        border.color: panel.sectionBorderColor
        opacity: panel.draftShowWindowControls ? 1 : 0.6

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                visible: panel._layoutParts.side === "left"
                spacing: 6

                Rectangle { visible: panel._layoutParts.hasMinimize; width: 12; height: 12; radius: 6; color: Theme.warning }
                Rectangle { visible: panel._layoutParts.hasMaximize; width: 12; height: 12; radius: 6; color: Theme.success }
                Rectangle { visible: panel._layoutParts.hasClose; width: 12; height: 12; radius: 6; color: Theme.error }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 6
                radius: 3
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
            }

            RowLayout {
                visible: panel._layoutParts.side !== "left"
                spacing: 6

                Rectangle { visible: panel._layoutParts.hasMinimize; width: 12; height: 12; radius: 6; color: Theme.warning }
                Rectangle { visible: panel._layoutParts.hasMaximize; width: 12; height: 12; radius: 6; color: Theme.success }
                Rectangle { visible: panel._layoutParts.hasClose; width: 12; height: 12; radius: 6; color: Theme.error }
            }
        }
    }
}
