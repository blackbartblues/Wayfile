import QtQuick
import QtQuick.Effects
import Heimdall
import Quill as Quill

// One device row in the sidebar's DEVICES section (extracted from Sidebar.qml).
// Used as the Repeater delegate over the `devices` model: name + storage-usage
// bar, hover tooltip with free/total space, and click-to-mount / open / context
// menu. devices and runtimeFeatures are global context properties, so they are
// referenced directly as in the original.
Rectangle {
    id: deviceDelegate

    required property var model
    required property int index
    property Item tooltipLayer: null
    property real sidebarWidth: 0

    signal contextMenuRequested(var item, point position)
    signal bookmarkClicked(string path)
    signal featureHintRequested(string message)

    Component { id: iconHardDrive; IconHardDrive { size: 18; color: Theme.muted } }
    Component { id: iconHardDriveOff; IconHardDriveOff { size: 18; color: Theme.muted } }
    Component { id: iconUsb; IconUsb { size: 18; color: Theme.muted } }
    Component { id: iconUsbOff; IconUsb { size: 18; color: Theme.muted } }

    width: parent.width - Theme.spacing
    anchors.horizontalCenter: parent.horizontalCenter
    height: 52
    z: deviceHoverArea.containsMouse || tooltipOpen ? 100 : 0
    property bool tooltipOpen: false
    property real tooltipX: 0
    property real tooltipY: 0
    readonly property bool lightTheme:
        (Theme.base.r * 0.299 + Theme.base.g * 0.587 + Theme.base.b * 0.114) > 0.5
    readonly property int tooltipMaxWidth:
        Math.max(Math.round(sidebarWidth * 1.16), Math.round(Theme.spacing * 32))
    readonly property string tooltipText: model.mounted
        ? Quill.Format.bytes(model.freeSpace)
          + " free of "
          + Quill.Format.bytes(model.totalSize)
          + " (" + Math.round(model.usagePercent) + "% used)"
        : "Not mounted — click to mount"

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(value, Math.max(minValue, maxValue)))
    }

    function placeTooltip() {
        var target = tooltipLayer ? tooltipLayer : deviceDelegate
        var cursor = deviceDelegate.mapToItem(target, deviceHoverArea.mouseX, deviceHoverArea.mouseY)
        var gap = Theme.spacing
        var minX = Theme.spacing
        var minY = Theme.spacing
        var maxX = target.width - deviceTooltip.width - gap
        var maxY = target.height - deviceTooltip.height - gap
        var belowY = cursor.y + gap
        var aboveY = cursor.y - deviceTooltip.height - gap
        var preferredY = belowY > maxY ? aboveY : belowY

        tooltipX = clamp(cursor.x - deviceTooltip.width / 2, minX, maxX)
        tooltipY = clamp(preferredY, minY, maxY)
        tooltipOpen = true
    }

    color: deviceHoverArea.containsMouse
        ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.07)
        : "transparent"
    radius: Theme.radiusSmall
    Behavior on color { ColorAnimation { duration: Theme.animDuration } }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing

        // Drive icon: removable vs fixed, mounted vs unmounted
        Loader {
            width: 18; height: 18
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: model.removable
                ? (model.mounted ? iconUsb : iconUsbOff)
                : (model.mounted ? iconHardDrive : iconHardDriveOff)
        }

        // Right side: name + progress bar + free/total caption
        Column {
            width: parent.width - 18 - Theme.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Text {
                text: model.deviceName
                color: model.mounted ? Theme.subtext : Theme.muted
                font.pointSize: Theme.fontNormal
                elide: Text.ElideRight
                width: parent.width
            }

            // Storage usage bar: obsidian well + gold gradient fill + glow
            // (handoff .dev__bar / .dev__fill).
            Rectangle {
                width: parent.width
                height: 5
                radius: 3
                color: Theme.bgB

                Rectangle {
                    width: model.mounted
                        ? parent.width * Math.min(model.usagePercent / 100.0, 1.0)
                        : 0
                    height: parent.height
                    radius: parent.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Theme.goldDeep }
                        GradientStop { position: 1.0; color: Theme.gold }
                    }
                    layer.enabled: model.mounted
                    layer.effect: MultiEffect {
                        autoPaddingEnabled: true
                        shadowEnabled: true
                        shadowColor: Theme.goldGlow
                        shadowBlur: 0.4
                    }
                }
            }

            // Always-visible free/total caption.
            Text {
                text: model.mounted
                    ? Quill.Format.bytes(model.freeSpace) + " free of " + Quill.Format.bytes(model.totalSize)
                    : "Not mounted"
                color: Theme.muted
                font.family: Fonts.mono
                font.pointSize: Math.max(8, Theme.fontSmall - 1)
                elide: Text.ElideRight
                width: parent.width
            }
        }
    }

    MouseArea {
        id: deviceHoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: deviceTooltipDelay.restart()
        onExited: {
            deviceTooltipDelay.stop()
            deviceDelegate.tooltipOpen = false
        }
        onCanceled: {
            deviceTooltipDelay.stop()
            deviceDelegate.tooltipOpen = false
        }
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                var mapped = deviceHoverArea.mapToItem(null, mouse.x, mouse.y)
                deviceDelegate.contextMenuRequested({
                    kind: "device",
                    index: index,
                    name: model.deviceName,
                    path: model.mountPoint,
                    devicePath: model.devicePath,
                    backend: model.backend,
                    mounted: model.mounted,
                    removable: model.removable
                }, Qt.point(mapped.x, mapped.y))
                return
            }

            if (model.mounted)
                deviceDelegate.bookmarkClicked(model.mountPoint)
            else if (model.backend === "udisks2" && !runtimeFeatures.udisksctlAvailable)
                deviceDelegate.featureHintRequested(runtimeFeatures.installHint("deviceMount"))
            else
                devices.mount(index)
        }
    }

    Timer {
        id: deviceTooltipDelay
        interval: 500
        repeat: false
        onTriggered: {
            if (deviceHoverArea.containsMouse)
                deviceDelegate.placeTooltip()
        }
    }

    Rectangle {
        id: deviceTooltip
        parent: deviceDelegate.tooltipLayer ? deviceDelegate.tooltipLayer : deviceDelegate
        visible: deviceDelegate.tooltipOpen || opacity > 0.01
        z: 1000
        width: Math.min(deviceTooltipText.implicitWidth + Math.round(Theme.spacing * 3),
                        deviceDelegate.tooltipMaxWidth)
        height: deviceTooltipText.implicitHeight + Math.round(Theme.spacing * 1.5)
        x: Math.round(deviceDelegate.tooltipX)
        y: Math.round(deviceDelegate.tooltipY + slideOffset)
        radius: Theme.radiusSmall
        color: deviceDelegate.lightTheme
            ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 1.0)
            : Qt.rgba(Theme.crust.r, Theme.crust.g, Theme.crust.b, 1.0)
        border.width: 1
        border.color: deviceDelegate.lightTheme
            ? Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.16)
            : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.14)
        opacity: deviceDelegate.tooltipOpen ? 1 : 0
        property real slideOffset: deviceDelegate.tooltipOpen ? 0 : -4
        transformOrigin: Item.Top

        Behavior on opacity {
            NumberAnimation {
                duration: deviceDelegate.tooltipOpen ? 150 : 100
                easing.type: deviceDelegate.tooltipOpen ? Easing.OutQuad : Easing.InQuad
            }
        }
        Behavior on slideOffset {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        Rectangle {
            z: -1
            x: 0
            y: 3
            width: parent.width
            height: parent.height
            radius: parent.radius
            color: Qt.rgba(0, 0, 0, 0.22)
        }

        Text {
            id: deviceTooltipText
            anchors.fill: parent
            anchors.leftMargin: Math.round(Theme.spacing * 1.5)
            anchors.rightMargin: Math.round(Theme.spacing * 1.5)
            anchors.topMargin: Math.round(Theme.spacing * 0.75)
            anchors.bottomMargin: Math.round(Theme.spacing * 0.75)
            text: deviceDelegate.tooltipText
            color: deviceDelegate.lightTheme ? Theme.base : Theme.text
            opacity: deviceDelegate.tooltipOpen ? 1 : 0
            font.pointSize: Theme.fontSmall
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap

            Behavior on opacity {
                NumberAnimation {
                    duration: deviceDelegate.tooltipOpen ? 150 : 100
                    easing.type: deviceDelegate.tooltipOpen ? Easing.OutQuad : Easing.InQuad
                }
            }
        }
    }
}
