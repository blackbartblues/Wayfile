import QtQuick
import QtQuick.Layouts
import Heimdall

// In-scene replacement for Quill's Q.Dropdown, used on the Settings pages.
//
// Quill's dropdown renders its list as a native Qt.Popup window placed by
// ABSOLUTE screen coordinates; on Wayland (Hyprland) the compositor ignores
// those coords and won't honour the outside-click grab, so the lists land on
// the wrong row, open upward over their trigger, stack when several are opened,
// and never dismiss. This component is only the trigger button — the actual
// list is ONE shared in-scene overlay that lives in SettingsPanel above the
// clipped page Flickable; clicking calls SettingsPanel.openDropdown(). Same
// approach as the PropertiesDialog "accessPopup" fix (C-2).
//
// NOTE: the owning-panel property is `settingsPanel`, NOT `panel`. The section
// pages declare their own `panel` property, so a `panel` here would shadow it:
// every binding written on a SettingsDropdown instance (model/currentIndex/
// onSelected) resolves `panel` against THIS object first, hitting the unset
// local instead of the section's panel (the classic `prop: prop` self-ref).
Item {
    id: root

    property string label: ""
    property var model: []
    property int currentIndex: 0
    // The owning SettingsPanel — provides the shared overlay via openDropdown()
    // and reports the currently-open trigger via openDropdownAnchor.
    property var settingsPanel: null

    signal selected(int index, string value)

    implicitHeight: 34
    Layout.fillWidth: true

    // True while THIS trigger's list is the one open in the shared overlay.
    readonly property bool dropdownOpen: settingsPanel && settingsPanel.openDropdownAnchor === buttonRect

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        height: 34
        spacing: 12

        Text {
            visible: root.label !== ""
            text: root.label
            color: Theme.text
            font.pointSize: Theme.fontSmall
            Layout.preferredWidth: 140
            elide: Text.ElideRight
        }

        Rectangle {
            id: buttonRect
            Layout.fillWidth: true
            height: 34
            radius: Theme.radiusSmall
            color: Theme.surface
            border.width: 1
            border.color: root.dropdownOpen
                ? Theme.accent
                : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.15)
            opacity: root.enabled ? 1.0 : 0.5
            Behavior on border.color { ColorAnimation { duration: Theme.animDurationFast } }

            Text {
                text: root.model[root.currentIndex] ?? ""
                color: Theme.text
                font.pointSize: Theme.fontSmall
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.right: chevron.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
            }

            IconChevronDown {
                id: chevron
                size: 14
                color: Theme.subtext
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                rotation: root.dropdownOpen ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Theme.animDurationFast } }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (!root.enabled || !root.settingsPanel)
                        return
                    root.settingsPanel.openDropdown(buttonRect, root.model, root.currentIndex,
                                                    (index, value) => root.selected(index, value))
                }
            }
        }
    }
}
