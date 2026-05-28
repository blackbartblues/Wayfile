import QtQuick
import QtQuick.Layouts
import Heimdall

// Heimdall browser-style tab bar.
//
// Placement: at the very top of the window, spanning full width above the
// sidebar (Chrome/Firefox layout). Lifted out of Toolbar.qml when tabs were
// moved above the breadcrumb row.
//
// Always visible — even with a single tab — per Heimdall design canvas.
//
// Width policy: each tab caps at maxTabWidth so they don't stretch into giant
// banners when only one tab is open. With many tabs they shrink toward the
// even-share width but never below minTabWidth — past that point the strip
// overflows the parent's clip (no scroll for now).
Item {
    id: root

    // Forward this so Main.qml can route drops onto a tab into a real
    // copy/move via UndoManager (same handler signature as Toolbar's).
    signal transferRequested(var paths, string destinationPath, bool moveOperation)

    // Chrome-ish bounds. Tune here if the design canvas tightens these later.
    readonly property int minTabWidth: 100
    readonly property int maxTabWidth: 220

    implicitHeight: Math.round(36 * Theme.uiScale)

    Rectangle {
        anchors.fill: parent
        color: Theme.mantle

        // Bottom separator divides the tab bar from the toolbar below.
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
            z: 2
        }

        // "+" button: always pinned to the right of the strip, click opens a
        // new tab in the user's home dir (tabModel.addTab() default).
        HoverRect {
            id: addTabBtn
            width: Theme.controlSize
            height: parent.height - 2  // leave 1 px above bottom separator
            anchors.right: parent.right
            anchors.top: parent.top
            z: 1
            onClicked: tabModel.addTab()

            IconPlus {
                anchors.centerIn: parent
                size: 16
                color: addTabBtn.hovered ? Theme.text : Theme.subtext
            }
        }

        // Flickable scroll area for tabs. When the strip can hold every tab at
        // minTabWidth or wider, contentWidth == flickable.width and there's
        // nothing to scroll. Past that point tabs sit at minTabWidth and the
        // overflow scrolls horizontally via drag or mouse wheel.
        Flickable {
            id: tabScroll
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: addTabBtn.left
            anchors.bottomMargin: 1  // sit above the separator
            clip: true
            // Compute the scrollable content width directly from the same
            // formula the delegate uses. Row.implicitWidth wasn't tracking
            // reactively (likely because per-tab width depends on tabScroll.
            // width through the Row, creating a chain Flickable didn't
            // re-evaluate). Explicit math keeps Flickable in sync.
            contentWidth: tabRow.effectiveCount * tabRow.perTabWidth
            contentHeight: height
            interactive: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            // Mouse wheel scrolls horizontally. Qt's Flickable doesn't bind
            // wheel by default; matching the pattern used in FileGridView et
            // al, an underlying MouseArea with acceptedButtons:NoButton picks
            // up wheel events while letting click events fall through to the
            // tab delegates above.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                z: -1
                onWheel: (wheel) => {
                    if (tabScroll.contentWidth <= tabScroll.width) {
                        wheel.accepted = false
                        return
                    }
                    var maxX = tabScroll.contentWidth - tabScroll.width
                    var delta = wheel.angleDelta.y !== 0
                        ? wheel.angleDelta.y
                        : wheel.angleDelta.x
                    tabScroll.contentX = Math.max(0,
                        Math.min(maxX, tabScroll.contentX - delta))
                    wheel.accepted = true
                }
            }

        // Plain Row (positioner), not RowLayout: with the clamped width below,
        // RowLayout was allocating each tab an even-share slot and rendering it
        // at its capped width, leaving dead space inside the slot ("tab sticks
        // to the left half of its slice" bug). Row packs items left-to-right
        // at their width; leftover space just stays at the end of the strip.
        Row {
            id: tabRow
            height: tabScroll.height
            spacing: 0

            // Track how many tabs are closing so others can grow immediately.
            property int closingCount: 0
            property int effectiveCount: Math.max(tabModel.count - closingCount, 1)
            property int hoveredIndex: -1

            // Single source of truth for the clamped per-tab width. Both the
            // delegate and Flickable.contentWidth bind to this so they can't
            // drift out of sync.
            property real perTabWidth: Math.min(root.maxTabWidth,
                                                Math.max(root.minTabWidth,
                                                         tabScroll.width / effectiveCount))

            Repeater {
                id: tabRepeater
                model: tabModel

                delegate: Rectangle {
                    id: tabDelegate

                    required property int index
                    required property var model

                    // Chrome-style clamp: even-share within [minTabWidth, maxTabWidth].
                    // With 1-3 tabs they stop growing at maxTabWidth; with 10+ they
                    // shrink toward minTabWidth and then overflow into the parent's
                    // clip rect.
                    // Pull from tabRow.perTabWidth so contentWidth and
                    // delegate width can't drift apart.
                    width: closing ? 0 : tabRow.perTabWidth
                    height: tabRow.height
                    property bool closing: false

                    Behavior on width {
                        NumberAnimation {
                            duration: Theme.animDuration
                            easing.type: Theme.animEasingTransition
                            easing.bezierCurve: Theme.animBezierCurve
                        }
                    }

                    opacity: 0
                    scale: 0.94

                    property int frozenIndex: -1

                    function startClose() {
                        if (closing) return
                        frozenIndex = tabDelegate.index
                        closing = true
                        tabRow.closingCount++
                        exitAnim.start()
                    }

                    Component.onCompleted: enterAnim.start()

                    ParallelAnimation {
                        id: enterAnim
                        NumberAnimation {
                            target: tabDelegate; property: "opacity"
                            from: 0; to: 1; duration: Theme.animDuration
                            easing.type: Theme.animEasingTransition
                            easing.bezierCurve: Theme.animBezierCurve
                        }
                        NumberAnimation {
                            target: tabDelegate; property: "scale"
                            from: 0.88; to: 1; duration: Theme.animDurationSlow
                            easing.type: Easing.OutBack; easing.overshoot: 0.5
                        }
                    }

                    color: "transparent"

                    DropArea {
                        id: tabDropArea
                        anchors.fill: parent
                        keys: ["text/uri-list"]

                        onDropped: (drop) => {
                            var destPath = tabDelegate.model.path
                            if (!destPath) return
                            var urls = drop.urls
                            var paths = []
                            for (var i = 0; i < urls.length; i++) {
                                var s = urls[i].toString()
                                paths.push(s.startsWith("file://")
                                    ? decodeURIComponent(s.substring(7))
                                    : s)
                            }
                            if (paths.length === 0) return
                            var allSameDir = paths.every(function (p) {
                                var parentDir = p.substring(0, p.lastIndexOf("/"))
                                return parentDir === destPath
                            })
                            if (allSameDir) return
                            root.transferRequested(paths, destPath,
                                                   drop.proposedAction === Qt.MoveAction)
                            drop.acceptProposedAction()
                        }
                    }

                    SequentialAnimation {
                        id: exitAnim
                        ParallelAnimation {
                            NumberAnimation {
                                target: tabDelegate; property: "opacity"
                                to: 0; duration: Theme.animDuration
                                easing.type: Theme.animEasingTransition
                                easing.bezierCurve: Theme.animBezierCurve
                            }
                            NumberAnimation {
                                target: tabDelegate; property: "scale"
                                to: 0.88; duration: Theme.animDuration
                                easing.type: Theme.animEasingTransition
                                easing.bezierCurve: Theme.animBezierCurve
                            }
                        }
                        ScriptAction {
                            script: {
                                tabRow.closingCount = Math.max(tabRow.closingCount - 1, 0)
                                tabModel.closeTab(tabDelegate.frozenIndex)
                            }
                        }
                    }

                    // Vertical hairline between tabs. Hidden when either
                    // neighbour is active or hovered to avoid visual noise.
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: parent.height * 0.5
                        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
                        visible: tabDelegate.index < tabModel.count - 1
                        opacity: (tabDelegate.index === tabModel.activeIndex
                            || tabDelegate.index + 1 === tabModel.activeIndex
                            || tabDelegate.index === tabRow.hoveredIndex
                            || tabDelegate.index + 1 === tabRow.hoveredIndex) ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: Theme.animDuration } }
                    }

                    HoverHandler {
                        id: tabDelegateHover
                        onHoveredChanged: {
                            if (hovered) tabRow.hoveredIndex = tabDelegate.index
                            else if (tabRow.hoveredIndex === tabDelegate.index)
                                tabRow.hoveredIndex = -1
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.MiddleButton)
                                tabDelegate.startClose()
                            else
                                tabModel.activeIndex = tabDelegate.index
                        }
                    }

                    // Inner highlight rectangle. Active tab gets a slightly
                    // lighter background + faint border; hover gives a softer
                    // wash. Margin keeps it inside the cell so the gold top
                    // stripe doesn't overlap it.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 5
                        radius: Theme.radiusSmall
                        color: {
                            if (tabDelegate.index === tabModel.activeIndex)
                                return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)
                            if (tabDelegateHover.hovered)
                                return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
                            return "transparent"
                        }
                        Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                        border.width: tabDelegate.index === tabModel.activeIndex ? 1 : 0
                        border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                    }

                    // Heimdall identity: gold top stripe on the active tab.
                    // Matches the design-canvas spec ("gold 1.5px top accent
                    // line"); 2px renders crisp at integer DPI.
                    Rectangle {
                        visible: tabDelegate.index === tabModel.activeIndex
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 2
                        color: Theme.accent
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: tabDelegate.model.title || "New Tab"
                        color: tabDelegate.index === tabModel.activeIndex ? Theme.text : Theme.subtext
                        font.pointSize: Theme.fontNormal
                        font.weight: tabDelegate.index === tabModel.activeIndex
                            ? Font.Medium : Font.Normal
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    Rectangle {
                        id: closeBtn
                        width: 20; height: 20; radius: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        // Hide on last tab — closing it would leave the app
                        // with no tabs, which the model rejects anyway.
                        visible: tabModel.count > 1 && tabDelegateHover.hovered
                        color: closeHover.hovered
                            ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.8)
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animDuration } }

                        IconX {
                            anchors.centerIn: parent; size: 10
                            color: closeHover.hovered ? Theme.base : Theme.muted
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: tabDelegate.startClose()
                        }

                        HoverHandler {
                            id: closeHover
                            cursorShape: Qt.PointingHandCursor
                        }
                    }
                }
            }
        }
        }  // Flickable tabScroll
    }
}
