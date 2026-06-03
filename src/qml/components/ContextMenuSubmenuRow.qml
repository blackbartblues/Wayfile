import QtQuick
import QtQuick.Layouts
import Heimdall

// One row of an open submenu — an action item or a separator, based on
// rowData. Extracted from ContextMenu.qml. Imperative calls go through `menu`.
Loader {
    id: subRowLoader

    // A submenuItems entry: { text, icon, iconName, shortcut, action,
    // checked, separator, desktopFile, mimeType, ... }
    property var rowData: ({})
    // The ContextMenu root — used for the executeAction imperative call.
    property var menu: null

    sourceComponent: rowData.separator ? submenuSeparatorComponent : submenuItemComponent

    Component {
        id: submenuItemComponent
        Rectangle {
            width: parent ? parent.width : 248
            height: 30
            radius: Theme.radiusSm
            opacity: 1
            color: subItemMa.containsMouse ? Theme.raise2 : "transparent"
            Behavior on color {
                ColorAnimation { duration: 100; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 12
                spacing: 8
                Image {
                    source: subRowLoader.rowData && subRowLoader.rowData.iconName
                        ? ("image://icon/" + subRowLoader.rowData.iconName + "?theme=" + config.iconTheme + "&builtin=" + (config.builtinIcons ? "1" : "0"))
                        : ""
                    sourceSize: Qt.size(18, 18)
                    Layout.preferredWidth: visible ? 18 : 0
                    Layout.preferredHeight: 18
                    Layout.alignment: Qt.AlignVCenter
                    visible: !!(subRowLoader.rowData && subRowLoader.rowData.iconName) && status === Image.Ready
                }
                Loader {
                    Layout.preferredWidth: active ? 14 : 0
                    Layout.preferredHeight: 14
                    Layout.alignment: Qt.AlignVCenter
                    active: !!(subRowLoader.rowData && subRowLoader.rowData.icon)
                    source: (subRowLoader.rowData && subRowLoader.rowData.icon) ? "../icons/Icon" + subRowLoader.rowData.icon + ".qml" : ""
                    onLoaded: {
                        item.size = 14
                        item.color = Qt.binding(() => Theme.gold)
                    }
                }
                Text {
                    text: subRowLoader.rowData ? subRowLoader.rowData.text : ""
                    font.pointSize: Theme.fontSmall
                    color: Theme.text
                    Layout.fillWidth: true
                    verticalAlignment: Text.AlignVCenter
                }
                Text {
                    text: subRowLoader.rowData ? (subRowLoader.rowData.shortcut || "") : ""
                    font.family: Fonts.mono
                    font.pixelSize: 11
                    color: Theme.muted
                    visible: text !== ""
                    verticalAlignment: Text.AlignVCenter
                }
                IconCheck {
                    visible: subRowLoader.rowData ? !!subRowLoader.rowData.checked : false
                    size: 14
                    color: Theme.accent
                    Layout.alignment: Qt.AlignVCenter
                }
            }
            MouseArea {
                id: subItemMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (subRowLoader.rowData && subRowLoader.rowData.action)
                        subRowLoader.menu.executeAction(subRowLoader.rowData.action, subRowLoader.rowData.desktopFile || "", subRowLoader.rowData.mimeType || "")
                }
            }
        }
    }

    Component {
        id: submenuSeparatorComponent
        Item {
            height: 9
            width: parent ? parent.width : 248
            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 32
                height: 1
                color: Theme.line
            }
        }
    }
}
