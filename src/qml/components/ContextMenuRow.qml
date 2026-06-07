import QtQuick
import QtQuick.Layouts
import Wayfile

// One row of the main context menu — resolves to an action item, a submenu
// trigger, or a separator based on rowData. Extracted from ContextMenu.qml.
// State flows down: rowData (the buildModel() entry) + the live submenu
// highlight state as typed props; imperative calls go back through `menu`.
Loader {
    id: rowLoader

    // The buildModel() payload: { text, icon, shortcut, action, separator,
    // isSubmenu, destructive, desktopFile, mimeType, ... }
    property var rowData: ({})
    // The ContextMenu root — used only for imperative calls
    // (executeAction / openSubmenu / closeSubmenu / submenuKeyForItem).
    property var menu: null
    // Live submenu state as TYPED props so the active-highlight binding
    // re-fires when it changes (a var-typed `menu` ref would not — see
    // lessons-qml-delegate-extraction).
    property bool submenuVisible: false
    property string activeSubmenuKey: ""

    sourceComponent: rowData.separator ? separatorComponent
                   : rowData.isSubmenu ? submenuTriggerComponent
                   : itemComponent

    Component {
        id: itemComponent
        Rectangle {
            height: 32
            width: parent ? parent.width : 248
            radius: Theme.radiusSm
            color: itemMa.containsMouse ? Theme.raise2 : "transparent"
            Behavior on color {
                ColorAnimation { duration: 100; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8
                Loader {
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    Layout.alignment: Qt.AlignVCenter
                    active: !!(rowLoader.rowData && rowLoader.rowData.icon)
                    source: (rowLoader.rowData && rowLoader.rowData.icon) ? "../icons/Icon" + rowLoader.rowData.icon + ".qml" : ""
                    onLoaded: {
                        item.size = 16
                        item.color = Qt.binding(() => rowLoader.rowData && rowLoader.rowData.destructive ? FileTypeColors.pdf : Theme.gold)
                    }
                }
                Text {
                    text: rowLoader.rowData ? rowLoader.rowData.text : ""
                    font.pointSize: Theme.fontNormal
                    color: rowLoader.rowData && rowLoader.rowData.destructive ? FileTypeColors.pdf : Theme.text
                    Layout.fillWidth: true
                    verticalAlignment: Text.AlignVCenter
                }
                Text {
                    text: rowLoader.rowData ? (rowLoader.rowData.shortcut || "") : ""
                    font.family: Fonts.mono
                    font.pointSize: Theme.fontSmall
                    color: Theme.muted
                    visible: text !== ""
                    verticalAlignment: Text.AlignVCenter
                }
            }
            MouseArea {
                id: itemMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: rowLoader.menu.closeSubmenu(true)
                onClicked: {
                    if (rowLoader.rowData && rowLoader.rowData.action)
                        rowLoader.menu.executeAction(rowLoader.rowData.action, rowLoader.rowData.desktopFile || "", rowLoader.rowData.mimeType || "")
                }
            }
        }
    }

    // ── Side submenu trigger row ───────────────────────────────────────────
    Component {
        id: submenuTriggerComponent
        Rectangle {
            id: submenuTrigger
            height: 32
            width: parent ? parent.width : 248
            radius: Theme.radiusSm
            readonly property bool isActive: rowLoader.submenuVisible
                && rowLoader.activeSubmenuKey === rowLoader.menu.submenuKeyForItem(rowLoader.rowData)
            color: (submenuMa.containsMouse || isActive) ? Theme.raise2 : "transparent"
            Behavior on color {
                ColorAnimation { duration: 100; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8
                Loader {
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    Layout.alignment: Qt.AlignVCenter
                    active: !!(rowLoader.rowData && rowLoader.rowData.icon)
                    source: (rowLoader.rowData && rowLoader.rowData.icon) ? "../icons/Icon" + rowLoader.rowData.icon + ".qml" : ""
                    onLoaded: {
                        item.size = 16
                        item.color = Qt.binding(() => submenuTrigger.isActive ? Theme.goldLight : Theme.gold)
                    }
                }
                Text {
                    text: rowLoader.rowData ? rowLoader.rowData.text : ""
                    font.pointSize: Theme.fontNormal
                    color: Theme.text
                    Layout.fillWidth: true
                    verticalAlignment: Text.AlignVCenter
                }
                Text {
                    text: rowLoader.rowData ? (rowLoader.rowData.shortcut || "") : ""
                    font.family: Fonts.mono
                    font.pointSize: Theme.fontSmall
                    color: Theme.muted
                    visible: text !== ""
                    verticalAlignment: Text.AlignVCenter
                }
                IconChevronRight {
                    size: 14
                    color: submenuTrigger.isActive ? Theme.gold : Theme.muted
                    Layout.alignment: Qt.AlignVCenter
                }
            }
            MouseArea {
                id: submenuMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: rowLoader.menu.openSubmenu(rowLoader.rowData, submenuTrigger)
                onClicked: rowLoader.menu.openSubmenu(rowLoader.rowData, submenuTrigger)
            }
        }
    }

    Component {
        id: separatorComponent
        Item {
            height: 9
            width: parent ? parent.width : 248
            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 16
                height: 1
                color: Theme.line
            }
        }
    }
}
