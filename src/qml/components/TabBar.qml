import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Wayfile

// Wayfile browser-style tab bar.
//
// Placement: at the very top of the window, spanning full width above the
// sidebar (Chrome/Firefox layout). Lifted out of Toolbar.qml when tabs were
// moved above the breadcrumb row.
//
// Always visible — even with a single tab — per Wayfile design canvas.
//
// Width policy: each tab caps at maxTabWidth so they don't stretch into giant
// banners when only one tab is open. With many tabs they shrink toward the
// even-share width but never below minTabWidth — past that point the strip
// overflows the parent's clip (no scroll for now).
Item {
    id: root

    // Forward this so Main.qml can route drops onto a tab into a real
    // copy/move via UndoManager (same handler signature as Toolbar's).
    signal newTabRequested()
    signal transferRequested(var paths, string destinationPath, bool moveOperation)

    // P2-M7: which sub-pane within the active supertab currently has
    // keyboard focus.  Used to highlight the matching mini folder icon
    // in the merged tab.  Owned by Main.qml as a window-level concept
    // (it follows the active tab's active pane), so we just mirror it.
    property int activePaneIndex: 0
    // P2-M7: left-click on one of the mini folder icons inside a supertab.
    // Main.qml handles by activating the tab and routing focus into the
    // matching pane, so the user can switch sub-pane without leaving the
    // tab strip.
    signal subPaneClicked(int tabIndex, int paneIdx)

    // Chrome-ish bounds. Tune here if the design canvas tightens these later.
    readonly property int minTabWidth: 128
    readonly property int maxTabWidth: 210

    // "Wayfile Unified" tab strip: 40px tall, tabs bottom-aligned with a 9px
    // gap above so their rounded top corners read against the strip gradient.
    implicitHeight: Math.round(40 * Theme.uiScale)
    readonly property int tabTopGap: Math.round(9 * Theme.uiScale)

    Rectangle {
        anchors.fill: parent
        // Obsidian vertical gradient (handoff .tabstrip).
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.bgB }
            GradientStop { position: 1.0; color: Theme.bgA }
        }

        // Bottom hairline divides the tab strip from the toolbar below. 1px near-black
        // (handoff --h-divider #1A1D21); the active tab's bg matches the toolbar so the seam vanishes.
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.hair
            z: 2
        }

        // Phase 2: "+" lives INSIDE the Row positioner below so it sits
        // right next to the last tab when few are open and scrolls with
        // the rest once the strip overflows.  The old anchored-right
        // version pinned it to the bar edge regardless of tab count.

        // App wordmark / chrome mark removed — the tab strip holds only tabs
        // (no logo). Tabs start flush at the left edge of the bar.

        // Flickable scroll area for tabs. When the strip can hold every tab at
        // minTabWidth or wider, contentWidth == flickable.width and there's
        // nothing to scroll. Past that point tabs sit at minTabWidth and the
        // overflow scrolls horizontally via drag or mouse wheel.
        Flickable {
            id: tabScroll
            anchors.left: parent.left
            anchors.leftMargin: Math.round(8 * Theme.uiScale)
            anchors.top: parent.top
            anchors.topMargin: root.tabTopGap   // tabs sit 9px below the strip top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.bottomMargin: 0              // tab bottoms meet the hairline
            clip: true
            // Compute the scrollable content width directly from the same
            // formula the delegate uses. Row.implicitWidth wasn't tracking
            // reactively (likely because per-tab width depends on tabScroll.
            // width through the Row, creating a chain Flickable didn't
            // re-evaluate). Explicit math keeps Flickable in sync.
            contentWidth: tabRow.effectiveCount * tabRow.perTabWidth + tabRow.addBtnWidth
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

            // Phase 2 drag-reorder visual state.  draggingIndex is the tab
            // currently lifted under the cursor; dropTargetIndex is the
            // slot the cursor is hovering.  Both -1 when no plain drag is
            // in progress.  Non-dragged tabs read these to decide whether
            // to slide left/right by one slot, mirroring browser behaviour.
            property int draggingIndex: -1
            property int dropTargetIndex: -1

            // Animate slot reflow when the model commits a moveTab() so the
            // dropped tab and its neighbours slide rather than jump.
            move: Transition {
                NumberAnimation {
                    properties: "x"
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }

            // Width reserved for the inline "+" button at the end of the
            // strip so the tab-width clamp knows there's something else
            // sharing the row.
            readonly property real addBtnWidth: Theme.controlSize

            // Single source of truth for the clamped per-tab width. Both the
            // delegate and Flickable.contentWidth bind to this so they can't
            // drift out of sync.  Subtract the "+" footprint so tabs and the
            // add button never overlap inside the visible strip.
            property real perTabWidth: Math.min(root.maxTabWidth,
                                                Math.max(root.minTabWidth,
                                                         (tabScroll.width - addBtnWidth)
                                                             / effectiveCount))

            Repeater {
                id: tabRepeater
                model: tabModel

                delegate: Rectangle {
                    id: tabDelegate

                    required property int index
                    required property var model
                    // Phase 2 P2-M1: per-tab selected flag, read from the
                    // tablistmodel's new IsSelectedRole.
                    required property bool isSelected
                    // P2-M7: surfaced from TabListModel so the delegate can
                    // swap its title area for a mini folder-icon row when
                    // this tab is a merged supertab.  paneTitles holds the
                    // basename of each live pane in display order.
                    required property bool isSupertab
                    required property int paneCount
                    required property var paneTitles

                    // Phase 2: drag-lift visual.  Mirrors tabMouseArea's
                    // drag state through transforms — a Scale pops the tab
                    // above its neighbours and a Translate slides it along
                    // the strip following the cursor in real time.  Snaps
                    // back to 0 on release so the Row positioner re-slots
                    // the delegate cleanly.
                    readonly property bool dragLifted: tabMouseArea.dragStarted
                                                       && !tabMouseArea.ctrlSweepArmed

                    // Browser-style slot reflow: while another tab is being
                    // dragged over this one's slot, shift sideways by one
                    // slot to make room.  Direction depends on whether the
                    // dragged tab started left or right of us.
                    readonly property real slotShift: {
                        const dIdx = tabRow.draggingIndex
                        const tIdx = tabRow.dropTargetIndex
                        if (dIdx === -1 || tIdx === -1 || dIdx === tIdx)
                            return 0
                        if (index === dIdx)
                            return 0
                        const w = tabRow.perTabWidth
                        if (tIdx > dIdx && index > dIdx && index <= tIdx)
                            return -w
                        if (tIdx < dIdx && index >= tIdx && index < dIdx)
                            return w
                        return 0
                    }

                    z: dragLifted ? 10 : 0
                    transform: [
                        Scale {
                            origin.x: tabDelegate.width / 2
                            origin.y: tabDelegate.height / 2
                            xScale: tabDelegate.dragLifted ? 1.06 : 1
                            yScale: tabDelegate.dragLifted ? 1.06 : 1
                            Behavior on xScale {
                                NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                            }
                            Behavior on yScale {
                                NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                            }
                        },
                        Translate {
                            id: tabDragTranslate
                            x: tabDelegate.dragLifted
                                ? tabMouseArea.dragOffsetX
                                : tabDelegate.slotShift
                            // Animate the slot shift for neighbours, but
                            // leave the dragged tab unsmoothed so it tracks
                            // the cursor 1:1.  Duration + easing match the
                            // Row.move transition below so that translate
                            // shrinks at the same rate Row.x grows — the
                            // two cancel out, keeping every tab visually
                            // stationary across the model reorder.
                            Behavior on x {
                                enabled: !tabDelegate.dragLifted
                                NumberAnimation {
                                    duration: 220
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    ]

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

                    // Release-snap animation: drives dragOffsetX → 0 in lock-
                    // step with the Row.move transition that's animating
                    // Row.x from old slot to new slot.  Same duration and
                    // easing, so the sum (scene position) stays constant
                    // while one shrinks and the other grows — the tab
                    // slides smoothly from cursor to its new slot without
                    // ever visiting the old slot.  dragStarted stays true
                    // for the whole animation so dragLifted (and the
                    // dragOffsetX binding on Translate.x) doesn't toggle
                    // mid-flight.
                    NumberAnimation {
                        id: releaseSnap
                        target: tabMouseArea
                        property: "dragOffsetX"
                        to: 0
                        duration: 220
                        easing.type: Easing.OutCubic
                        onStopped: {
                            tabMouseArea.dragStarted = false
                        }
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
                        id: tabMouseArea
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        // Phase 2: track drag-vs-click state so plain drag
                        // reorders and Ctrl+drag sweep-selects without
                        // double-firing the click handler.
                        // Local-coords pressPoint is only used for the
                        // drag-threshold check.  The follow-cursor maths use
                        // pressPointRow (tabRow space) instead so it isn't
                        // contaminated by our own Translate transform —
                        // otherwise dx halves every frame and the tab lags
                        // behind the cursor.
                        property point pressPoint
                        property point pressPointRow
                        property bool dragStarted: false
                        property bool ctrlSweepArmed: false
                        property int sweepLastIdx: -1
                        // Live x-offset for the drag-lift Translate.  Set
                        // every mouse move during a plain reorder drag;
                        // reset on press / release.
                        property real dragOffsetX: 0
                        readonly property int dragThreshold: 6

                        onPressed: (mouse) => {
                            // Abort any in-flight release snap from the
                            // previous gesture so the new press starts
                            // from a clean slate.
                            if (releaseSnap.running)
                                releaseSnap.stop()
                            pressPoint = Qt.point(mouse.x, mouse.y)
                            const inRow = tabMouseArea.mapToItem(tabRow, mouse.x, mouse.y)
                            pressPointRow = Qt.point(inRow.x, inRow.y)
                            dragStarted = false
                            ctrlSweepArmed = (mouse.modifiers & Qt.ControlModifier) !== 0
                            sweepLastIdx = -1
                            dragOffsetX = 0
                        }

                        onPositionChanged: (mouse) => {
                            if (!pressed)
                                return
                            const dxLocal = mouse.x - pressPoint.x
                            const dyLocal = mouse.y - pressPoint.y
                            if (!dragStarted
                                && (Math.abs(dxLocal) > dragThreshold
                                    || Math.abs(dyLocal) > dragThreshold))
                                dragStarted = true
                            // Plain reorder drag: map to tabRow space so
                            // the offset isn't disturbed by our own
                            // Translate, then update the lift offset and
                            // hovered drop slot in one place.
                            if (dragStarted && !ctrlSweepArmed) {
                                const cur = tabMouseArea.mapToItem(tabRow, mouse.x, mouse.y)
                                dragOffsetX = cur.x - pressPointRow.x
                                if (tabRow.draggingIndex !== tabDelegate.index)
                                    tabRow.draggingIndex = tabDelegate.index
                                const w = tabRow.perTabWidth
                                let slot = w > 0 ? Math.floor(cur.x / w) : tabDelegate.index
                                slot = Math.max(0, Math.min(tabModel.count - 1, slot))
                                tabRow.dropTargetIndex = slot
                            }
                            if (!dragStarted || !ctrlSweepArmed)
                                return
                            // Lazy-arm: the first movement also adds the
                            // original tab so a 1-cell sweep still works.
                            if (sweepLastIdx === -1) {
                                sweepLastIdx = tabDelegate.index
                                if (!tabModel.isSelected(tabDelegate.index))
                                    tabModel.toggleSelected(tabDelegate.index)
                            }
                            const localPos = tabMouseArea.mapToItem(tabRow, mouse.x, mouse.y)
                            const under = tabRow.childAt(localPos.x, tabRow.height / 2)
                            if (under && under.index !== undefined && under.index !== sweepLastIdx) {
                                sweepLastIdx = under.index
                                if (!tabModel.isSelected(under.index))
                                    tabModel.toggleSelected(under.index)
                            }
                        }

                        onReleased: (mouse) => {
                            if (dragStarted && !ctrlSweepArmed) {
                                // Plain drag => reorder.  Use the slot the
                                // visual reflow has been tracking; falls
                                // back to a fresh childAt() lookup if the
                                // drop target was never set (e.g. release
                                // immediately after threshold cross).
                                let target = tabRow.dropTargetIndex
                                if (target === -1) {
                                    const lp = tabMouseArea.mapToItem(tabRow, mouse.x, mouse.y)
                                    const drop = tabRow.childAt(lp.x, tabRow.height / 2)
                                    if (drop && drop.index !== undefined)
                                        target = drop.index
                                }
                                // Clear the drag-state first so neighbours'
                                // slotShift collapses to 0 and their
                                // Behavior on translate.x animates -w → 0
                                // in lock-step with Row.move.
                                tabRow.draggingIndex = -1
                                tabRow.dropTargetIndex = -1
                                if (target !== -1 && target !== tabDelegate.index)
                                    tabModel.moveTab(tabDelegate.index, target)
                                // Kick off the dragged tab's own snap.
                                // We deliberately leave dragStarted=true
                                // so dragLifted stays true: Translate.x's
                                // binding remains on dragOffsetX (which the
                                // animation drives to 0) instead of
                                // switching to slotShift mid-flight.
                                // dragStarted resets in releaseSnap.onStopped.
                                releaseSnap.from = dragOffsetX
                                releaseSnap.restart()
                            } else {
                                tabRow.draggingIndex = -1
                                tabRow.dropTargetIndex = -1
                                dragStarted = false
                                dragOffsetX = 0
                            }
                            ctrlSweepArmed = false
                        }

                        onClicked: (mouse) => {
                            if (mouse.button === Qt.MiddleButton) {
                                tabDelegate.startClose()
                                return
                            }
                            // Skip the click branch when the gesture was a
                            // drag (Ctrl-sweep or plain reorder); those
                            // already mutated state in their own handlers.
                            if (dragStarted)
                                return
                            // Phase 2 P2-M1: modifiers drive the selection.
                            //   Shift+click — range-select [active..clicked]
                            //   Ctrl+click  — toggle clicked in / out of the
                            //                 merge set
                            //   plain click — collapse selection to clicked
                            //                 and make it active
                            if (mouse.modifiers & Qt.ShiftModifier)
                                tabModel.selectRangeTo(tabDelegate.index)
                            else if (mouse.modifiers & Qt.ControlModifier)
                                tabModel.toggleSelected(tabDelegate.index)
                            else
                                tabModel.activateAndCollapseSelection(tabDelegate.index)
                        }
                    }

                    // Tab body — full-height, top-rounded. Active gets the
                    // obsidian gradient + 1px line border + inset top sheen;
                    // hover gives a faint wash. (handoff .tab / .tab--active)
                    Rectangle {
                        id: tabBody
                        anchors.fill: parent
                        anchors.leftMargin: 2
                        anchors.rightMargin: 2
                        topLeftRadius: Theme.radiusTab
                        topRightRadius: Theme.radiusTab
                        bottomLeftRadius: 0
                        bottomRightRadius: 0
                        readonly property bool active: tabDelegate.index === tabModel.activeIndex
                        gradient: active ? activeTabGrad : null
                        color: active ? "transparent"
                             : (tabDelegateHover.hovered
                                ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.03)
                                : "transparent")
                        border.width: 0
                        border.color: Theme.line
                        Behavior on color { ColorAnimation { duration: Theme.animDuration } }

                        Gradient {
                            id: activeTabGrad
                            GradientStop { position: 0.0; color: Theme.raise }
                            GradientStop { position: 1.0; color: Theme.panel2 }
                        }

                        // Inset top sheen.
                        Rectangle {
                            visible: tabBody.active
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 1
                            height: 1
                            color: Qt.rgba(Theme.sheen.r, Theme.sheen.g, Theme.sheen.b, 0.06)
                        }

                        // Soft top-down accent wash on active/selected tabs (handoff
                        // .tab--active wash). Stronger on the focused tab, gentler on a
                        // selected-but-not-focused tab.
                        Rectangle {
                            visible: tabBody.active || tabDelegate.isSelected
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 1
                            height: parent.height * 0.44
                            radius: Theme.radiusTab
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, tabBody.active ? 0.12 : 0.07) }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }
                    }

                    // 2px gold top-bar marker (handoff .tab--active::after)
                    // with a soft glow. Shared by the active tab AND any
                    // selected tab — selecting tabs for a merge lights the same
                    // glowing bar (no separate ring).
                    Rectangle {
                        visible: (tabDelegate.index === tabModel.activeIndex) || tabDelegate.isSelected
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 18
                        height: 2
                        radius: 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.5; color: Theme.gold }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            autoPaddingEnabled: true
                            shadowEnabled: true
                            shadowColor: Theme.goldGlow
                            shadowBlur: 0.5
                        }
                        z: 3
                    }

                    // P2-M7: single-tab title.  Hidden for supertabs so the
                    // mini-icon Row below can take over.  Keeping both items
                    // declarative (visible toggles) rather than a Loader
                    // keeps the binding fast in the common path where the
                    // strip is mostly single tabs.
                    // Single-tab content: leading folder glyph (gold when
                    // active, muted otherwise) + left-aligned title.
                    // (handoff .tab__ic + .tab__title)
                    Item {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 13
                        anchors.rightMargin: 28  // leave room for the × button
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        visible: !(tabDelegate.isSupertab && tabDelegate.paneCount > 1)

                        IconFolder {
                            id: tabLeadingIcon
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            size: 15
                            color: tabDelegate.index === tabModel.activeIndex
                                ? Theme.gold : Theme.muted
                        }
                        Text {
                            anchors.left: tabLeadingIcon.right
                            anchors.leftMargin: 9
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: tabDelegate.model.title || "New Tab"
                            color: (tabDelegate.index === tabModel.activeIndex)
                                   ? Theme.text
                                   : (tabDelegate.isSelected ? Theme.subtext : Theme.subtext)
                            font.pointSize: Theme.fontNormal
                            font.weight: tabDelegate.index === tabModel.activeIndex
                                ? Font.Medium : Font.Normal
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    // P2-M7: supertab strip.  N mini folder icons followed
                    // by a tightly-elided joined title.  Active sub-pane
                    // glows in the accent colour; inactive panes dim toward
                    // subtext so the eye lands on focus immediately.
                    // Clicking an icon both activates the tab and switches
                    // sub-pane focus to that pane.
                    Row {
                        id: supertabRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        anchors.rightMargin: 28
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        visible: tabDelegate.isSupertab && tabDelegate.paneCount > 1

                        readonly property bool tabIsActive: tabDelegate.index === tabModel.activeIndex
                        readonly property int tileSize: Math.round(22 * Theme.uiScale)
                        readonly property int tileStep: Math.round(15 * Theme.uiScale) // 22 - 7 overlap

                        // Stacked metallic tiles (handoff .tab__stack) overlapping
                        // -7px, first tile on top. Each carries a pane glyph that
                        // turns gold for the focused sub-pane; clicking switches
                        // sub-pane focus (root.subPaneClicked).
                        Item {
                            id: tabStack
                            anchors.verticalCenter: parent.verticalCenter
                            width: supertabRow.tileSize + (tabDelegate.paneCount - 1) * supertabRow.tileStep
                            height: supertabRow.tileSize

                            Repeater {
                                model: tabDelegate.paneCount
                                delegate: Rectangle {
                                    id: stackTile
                                    required property int index
                                    readonly property bool isActiveSubPane:
                                        supertabRow.tabIsActive && index === root.activePaneIndex
                                    x: index * supertabRow.tileStep
                                    z: tabDelegate.paneCount - index   // first tile on top
                                    width: supertabRow.tileSize
                                    height: supertabRow.tileSize
                                    radius: 6
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: Theme.raise2 }
                                        GradientStop { position: 1.0; color: Theme.panel2 }
                                    }
                                    border.width: 1
                                    border.color: stackTile.isActiveSubPane ? Theme.goldLine : Theme.line

                                    Rectangle {  // inset top sheen
                                        anchors.top: parent.top; anchors.left: parent.left
                                        anchors.right: parent.right; anchors.margins: 1
                                        height: 1
                                        color: Qt.rgba(Theme.sheen.r, Theme.sheen.g, Theme.sheen.b, 0.06)
                                    }

                                    IconFolder {
                                        anchors.centerIn: parent
                                        size: Math.round(11 * Theme.uiScale)
                                        color: stackTile.isActiveSubPane
                                            ? Theme.gold
                                            : (supertabRow.tabIsActive ? Theme.text : Theme.subtext)
                                        opacity: stackTile.isActiveSubPane ? 1.0 : 0.82
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        acceptedButtons: Qt.LeftButton
                                        onClicked: root.subPaneClicked(tabDelegate.index, stackTile.index)
                                    }
                                }
                            }
                        }

                        // ×N count badge (handoff .tab__badge): gold mono.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            height: Math.round(16 * Theme.uiScale)
                            width: badgeText.implicitWidth + Math.round(9 * Theme.uiScale)
                            radius: 4
                            color: Theme.goldWash
                            border.width: 1
                            border.color: Theme.goldLine
                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: "×" + tabDelegate.paneCount
                                color: Theme.gold
                                font.family: Fonts.mono
                                font.pixelSize: Math.round(10 * Theme.uiScale)
                            }
                        }

                        // Joined pane titles, elided when the tab is narrow.
                        Text {
                            id: supertabTitle
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, supertabRow.width - tabStack.width - Math.round(46 * Theme.uiScale))
                            text: {
                                var titles = tabDelegate.paneTitles
                                if (titles && titles.length > 0)
                                    return titles.join(" · ")
                                return tabDelegate.model.title || ""
                            }
                            color: supertabRow.tabIsActive
                                   ? Theme.text
                                   : (tabDelegate.isSelected ? Theme.subtext : Theme.subtext)
                            font.pointSize: Theme.fontNormal
                            font.weight: supertabRow.tabIsActive ? Font.Medium : Font.Normal
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                            visible: width > 16
                        }
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

            // Phase 2: inline "+" tucked behind the last tab.  As soon as
            // a new tab is added it shifts right by one slot; with many
            // tabs it rides the overflow into the Flickable's scroll.
            HoverRect {
                id: addTabBtn
                width: tabRow.addBtnWidth
                height: tabRow.height
                onClicked: root.newTabRequested()

                IconPlus {
                    anchors.centerIn: parent
                    size: 16
                    color: addTabBtn.hovered ? Theme.gold : Theme.subtext
                }
            }
        }
        }  // Flickable tabScroll
    }
}
