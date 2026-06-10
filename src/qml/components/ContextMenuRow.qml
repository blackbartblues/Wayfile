import QtQuick
import QtQuick.Layouts
import Wayfile

// One row of the main context menu — resolves to an action item, a submenu
// trigger, or a separator based on rowData. Extracted from ContextMenu.qml.
// State flows down: rowData (the buildModel() entry) + the live submenu
// highlight state as typed props; imperative calls go back through `menu`.
//
// W8 restyle: hover = accent gradient (90deg gold .12→.04; red-tinted for
// danger rows); icons sit at text-2 and brighten to accent (red for danger)
// only on hover; rows ~28px, radius 5, 10px h-padding, 10px icon↔label gap.
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
            id: itemRect
            readonly property bool danger: !!(rowLoader.rowData && rowLoader.rowData.destructive)
            readonly property bool hovered: itemMa.containsMouse
            height: 28
            width: parent ? parent.width : 248
            radius: 5
            color: "transparent"

            // Hover: 90° accent gradient (gold .12→.04); danger rows tint red.
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                opacity: itemRect.hovered ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 100; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve }
                }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: itemRect.danger
                        ? Qt.rgba(FileTypeColors.pdf.r, FileTypeColors.pdf.g, FileTypeColors.pdf.b, 0.14)
                        : Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.12) }
                    GradientStop { position: 1.0; color: itemRect.danger
                        ? Qt.rgba(FileTypeColors.pdf.r, FileTypeColors.pdf.g, FileTypeColors.pdf.b, 0.04)
                        : Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.04) }
                }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10
                Loader {
                    // Swatch rows (the flattened favorite-star color picker) use
                    // the dot below for their leading glyph, so the icon slot
                    // collapses to avoid a double leading gap.
                    Layout.preferredWidth: (rowLoader.rowData && rowLoader.rowData.swatch) ? 0 : 14
                    Layout.preferredHeight: 14
                    Layout.alignment: Qt.AlignVCenter
                    active: !!(rowLoader.rowData && rowLoader.rowData.icon)
                    source: (rowLoader.rowData && rowLoader.rowData.icon) ? "../icons/Icon" + rowLoader.rowData.icon + ".qml" : ""
                    onLoaded: {
                        item.size = 14
                        // text-2 normally; accent (red for danger) on hover.
                        item.color = Qt.binding(() => itemRect.hovered
                            ? (itemRect.danger ? FileTypeColors.pdf : Theme.gold)
                            : Theme.subtext)
                    }
                }
                // W8.5: filled color dot for swatch rows (per-favorite star color
                // picker opened by double-clicking a favorite's star).
                Rectangle {
                    visible: !!(rowLoader.rowData && rowLoader.rowData.swatch)
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14
                    Layout.alignment: Qt.AlignVCenter
                    radius: width / 2
                    color: (rowLoader.rowData && rowLoader.rowData.swatch)
                        ? rowLoader.rowData.swatch : "transparent"
                    border.width: 1
                    border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.18)
                }
                Text {
                    text: rowLoader.rowData ? rowLoader.rowData.text : ""
                    font.pointSize: Theme.fontNormal
                    color: itemRect.danger ? FileTypeColors.pdf : Theme.text
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
            height: 28
            width: parent ? parent.width : 248
            radius: 5
            readonly property bool isActive: rowLoader.submenuVisible
                && rowLoader.activeSubmenuKey === rowLoader.menu.submenuKeyForItem(rowLoader.rowData)
            readonly property bool hot: submenuMa.containsMouse || isActive
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                opacity: submenuTrigger.hot ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 100; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve }
                }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.12) }
                    GradientStop { position: 1.0; color: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.04) }
                }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10
                Loader {
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14
                    Layout.alignment: Qt.AlignVCenter
                    active: !!(rowLoader.rowData && rowLoader.rowData.icon)
                    source: (rowLoader.rowData && rowLoader.rowData.icon) ? "../icons/Icon" + rowLoader.rowData.icon + ".qml" : ""
                    onLoaded: {
                        item.size = 14
                        item.color = Qt.binding(() => submenuTrigger.hot ? Theme.gold : Theme.subtext)
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
                    color: submenuTrigger.hot ? Theme.gold : Theme.muted
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
            // Hairline + a 1px warm sheen below it (handoff separator).
            Rectangle {
                id: sepLine
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 16
                height: 1
                color: Theme.lineSoft
            }
            Rectangle {
                anchors.left: sepLine.left
                anchors.right: sepLine.right
                anchors.top: sepLine.bottom
                height: 1
                color: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.04)
            }
        }
    }
}
