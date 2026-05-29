import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Heimdall
import Quill as Q

Q.Dialog {
    id: root
    anchors.fill: parent
    z: 1001
    dialogWidth: Math.min(640, width - 40)
    title: "Keyboard Shortcuts"
    subtitle: "Click a shortcut to rebind it, then press the new key combination."

    property var shortcutEntries: []
    property var draftShortcuts: ({})
    property bool syncingFromConfig: false
    property bool pendingShortcutsDirty: false
    property string recordingAction: ""
    property bool confirmResetAll: false
    // Set when a recorded combo is already bound to another action. Shown
    // in the footer; cleared when recording (re)starts or a bind succeeds.
    property string conflictWarning: ""

    function syncShortcutDrafts() {
        syncingFromConfig = true
        try {
            shortcutEntries = config.shortcutDefinitions

            var nextShortcuts = ({})
            for (var i = 0; i < shortcutEntries.length; ++i) {
                var entry = shortcutEntries[i]
                nextShortcuts[entry.action] = entry.sequence
            }
            draftShortcuts = nextShortcuts
        } finally {
            syncingFromConfig = false
        }
    }

    function setShortcutValue(action, value) {
        var nextShortcuts = ({})
        for (var key in draftShortcuts)
            nextShortcuts[key] = draftShortcuts[key]
        nextShortcuts[action] = value
        draftShortcuts = nextShortcuts

        var nextEntries = []
        for (var i = 0; i < shortcutEntries.length; ++i) {
            var entry = shortcutEntries[i]
            if (entry.action === action) {
                var updatedEntry = ({})
                for (var field in entry)
                    updatedEntry[field] = entry[field]
                updatedEntry.sequence = value
                nextEntries.push(updatedEntry)
            } else {
                nextEntries.push(entry)
            }
        }
        shortcutEntries = nextEntries
    }

    function queueShortcutApply() {
        if (syncingFromConfig)
            return

        pendingShortcutsDirty = true
        shortcutApplyTimer.restart()
    }

    function applyPendingShortcuts() {
        if (!pendingShortcutsDirty)
            return

        pendingShortcutsDirty = false
        shortcutApplyTimer.stop()
        config.saveShortcuts(draftShortcuts)
    }

    function openDialog() {
        recordingAction = ""
        syncShortcutDrafts()
        open()
    }

    function closeDialog() {
        recordingAction = ""
        confirmResetAll = false
        conflictWarning = ""
        resetConfirmTimer.stop()
        applyPendingShortcuts()
        close()
    }

    function startRecording(action) {
        recordingAction = action
        conflictWarning = ""
        keyCapture.forceActiveFocus()
    }

    function stopRecording() {
        recordingAction = ""
        conflictWarning = ""
    }

    // Returns the label of another action already bound to `seq`, or ""
    // if the sequence is free. `exceptAction` is the action currently
    // being rebound (so re-recording the same key on the same row is not
    // a conflict). Qt treats two WindowShortcuts with the same sequence
    // as ambiguous and fires neither, so we refuse the duplicate up front.
    function actionLabelUsingSequence(seq, exceptAction) {
        for (var i = 0; i < shortcutEntries.length; ++i) {
            var entry = shortcutEntries[i]
            if (entry.action === exceptAction)
                continue
            if (entry.sequence === seq)
                return entry.label
        }
        return ""
    }

    function resetToDefault(action) {
        for (var i = 0; i < shortcutEntries.length; ++i) {
            if (shortcutEntries[i].action === action) {
                setShortcutValue(action, shortcutEntries[i].defaultSequence)
                queueShortcutApply()
                return
            }
        }
    }

    function resetAllToDefaults() {
        var nextShortcuts = ({})
        var nextEntries = []
        for (var i = 0; i < shortcutEntries.length; ++i) {
            var entry = shortcutEntries[i]
            var defaultSeq = entry.defaultSequence
            nextShortcuts[entry.action] = defaultSeq

            var updatedEntry = ({})
            for (var field in entry)
                updatedEntry[field] = entry[field]
            updatedEntry.sequence = defaultSeq
            nextEntries.push(updatedEntry)
        }
        draftShortcuts = nextShortcuts
        shortcutEntries = nextEntries
        queueShortcutApply()
    }

    function keyEventToSequence(event) {
        var parts = []

        if (event.modifiers & Qt.ControlModifier) parts.push("Ctrl")
        if (event.modifiers & Qt.AltModifier) parts.push("Alt")
        if (event.modifiers & Qt.ShiftModifier) parts.push("Shift")
        if (event.modifiers & Qt.MetaModifier) parts.push("Meta")

        // Ignore bare modifier presses
        var key = event.key
        if (key === Qt.Key_Control || key === Qt.Key_Alt
            || key === Qt.Key_Shift || key === Qt.Key_Meta
            || key === Qt.Key_Super_L || key === Qt.Key_Super_R)
            return ""

        var keyName = ""
        var keyMap = {}
        keyMap[Qt.Key_A] = "A"; keyMap[Qt.Key_B] = "B"; keyMap[Qt.Key_C] = "C"
        keyMap[Qt.Key_D] = "D"; keyMap[Qt.Key_E] = "E"; keyMap[Qt.Key_F] = "F"
        keyMap[Qt.Key_G] = "G"; keyMap[Qt.Key_H] = "H"; keyMap[Qt.Key_I] = "I"
        keyMap[Qt.Key_J] = "J"; keyMap[Qt.Key_K] = "K"; keyMap[Qt.Key_L] = "L"
        keyMap[Qt.Key_M] = "M"; keyMap[Qt.Key_N] = "N"; keyMap[Qt.Key_O] = "O"
        keyMap[Qt.Key_P] = "P"; keyMap[Qt.Key_Q] = "Q"; keyMap[Qt.Key_R] = "R"
        keyMap[Qt.Key_S] = "S"; keyMap[Qt.Key_T] = "T"; keyMap[Qt.Key_U] = "U"
        keyMap[Qt.Key_V] = "V"; keyMap[Qt.Key_W] = "W"; keyMap[Qt.Key_X] = "X"
        keyMap[Qt.Key_Y] = "Y"; keyMap[Qt.Key_Z] = "Z"
        keyMap[Qt.Key_0] = "0"; keyMap[Qt.Key_1] = "1"; keyMap[Qt.Key_2] = "2"
        keyMap[Qt.Key_3] = "3"; keyMap[Qt.Key_4] = "4"; keyMap[Qt.Key_5] = "5"
        keyMap[Qt.Key_6] = "6"; keyMap[Qt.Key_7] = "7"; keyMap[Qt.Key_8] = "8"
        keyMap[Qt.Key_9] = "9"
        keyMap[Qt.Key_F1] = "F1"; keyMap[Qt.Key_F2] = "F2"; keyMap[Qt.Key_F3] = "F3"
        keyMap[Qt.Key_F4] = "F4"; keyMap[Qt.Key_F5] = "F5"; keyMap[Qt.Key_F6] = "F6"
        keyMap[Qt.Key_F7] = "F7"; keyMap[Qt.Key_F8] = "F8"; keyMap[Qt.Key_F9] = "F9"
        keyMap[Qt.Key_F10] = "F10"; keyMap[Qt.Key_F11] = "F11"; keyMap[Qt.Key_F12] = "F12"
        keyMap[Qt.Key_Space] = "Space"; keyMap[Qt.Key_Return] = "Return"
        keyMap[Qt.Key_Enter] = "Return"; keyMap[Qt.Key_Escape] = "Escape"
        keyMap[Qt.Key_Tab] = "Tab"; keyMap[Qt.Key_Backspace] = "Backspace"
        keyMap[Qt.Key_Delete] = "Delete"; keyMap[Qt.Key_Insert] = "Insert"
        keyMap[Qt.Key_Home] = "Home"; keyMap[Qt.Key_End] = "End"
        keyMap[Qt.Key_PageUp] = "PageUp"; keyMap[Qt.Key_PageDown] = "PageDown"
        keyMap[Qt.Key_Up] = "Up"; keyMap[Qt.Key_Down] = "Down"
        keyMap[Qt.Key_Left] = "Left"; keyMap[Qt.Key_Right] = "Right"
        keyMap[Qt.Key_Plus] = "+"; keyMap[Qt.Key_Minus] = "-"
        keyMap[Qt.Key_Equal] = "="; keyMap[Qt.Key_BracketLeft] = "["
        keyMap[Qt.Key_BracketRight] = "]"; keyMap[Qt.Key_Semicolon] = ";"
        keyMap[Qt.Key_Apostrophe] = "'"; keyMap[Qt.Key_Comma] = ","
        keyMap[Qt.Key_Period] = "."; keyMap[Qt.Key_Slash] = "/"
        keyMap[Qt.Key_Backslash] = "\\"; keyMap[Qt.Key_QuoteLeft] = "`"

        if (key in keyMap)
            keyName = keyMap[key]
        else
            keyName = event.text.toUpperCase()

        if (!keyName)
            return ""

        parts.push(keyName)
        return parts.join("+")
    }

    onRejected: { root.recordingAction = ""; root.applyPendingShortcuts() }
    onClosed: { root.recordingAction = ""; root.applyPendingShortcuts() }

    Timer {
        id: shortcutApplyTimer
        interval: 320
        onTriggered: root.applyPendingShortcuts()
    }

    Timer {
        id: resetConfirmTimer
        interval: 3000
        repeat: false
        onTriggered: root.confirmResetAll = false
    }

    // Invisible item that captures key presses while recording.
    // Zero-size layout row (no anchors — illegal inside the ColumnLayout
    // that Q.Dialog routes content into).
    Item {
        id: keyCapture
        Layout.preferredWidth: 0
        Layout.preferredHeight: 0
        focus: root.recordingAction !== ""

        // While recording, claim every key BEFORE Qt's global Shortcut
        // system can match it. Main.qml registers ~42 application-wide
        // Shortcut objects (Ctrl+N, F2, Delete, ...); without this
        // override they swallow the very combos the user is trying to
        // record and fire their actions instead. Accepting the event in
        // onShortcutOverride tells Qt "the focused item handles this key"
        // so it flows to Keys.onPressed below rather than to a Shortcut.
        Keys.onShortcutOverride: (event) => {
            if (root.recordingAction !== "")
                event.accepted = true
        }

        Keys.onPressed: (event) => {
            if (root.recordingAction === "")
                return

            // Escape cancels recording
            if (event.key === Qt.Key_Escape) {
                root.stopRecording()
                event.accepted = true
                return
            }

            var seq = root.keyEventToSequence(event)
            if (seq === "")
                return  // bare modifier — keep listening

            event.accepted = true

            // Refuse a combo already bound to another action: two global
            // Shortcuts with the same sequence are ambiguous in Qt and
            // fire neither. Keep recording so the user can pick another.
            var clash = root.actionLabelUsingSequence(seq, root.recordingAction)
            if (clash !== "") {
                root.conflictWarning = seq + " is already used by “" + clash + "”"
                return
            }

            root.conflictWarning = ""
            root.setShortcutValue(root.recordingAction, seq)
            root.queueShortcutApply()
            root.stopRecording()
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: Math.min(540, shortcutsFlick.contentHeight)

        Flickable {
            id: shortcutsFlick
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: shortcutsColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            boundsMovement: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: shortcutsColumn
                width: shortcutsFlick.width
                spacing: 0

                // Header row
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
                    radius: Theme.radiusSmall

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: "Action"
                            color: Theme.subtext
                            font.pointSize: Theme.fontSmall
                            font.weight: Font.DemiBold
                        }

                        Text {
                            Layout.preferredWidth: 180
                            text: "Shortcut"
                            color: Theme.subtext
                            font.pointSize: Theme.fontSmall
                            font.weight: Font.DemiBold
                        }

                        Item { width: 28 }
                    }
                }

                Repeater {
                    model: root.shortcutEntries

                    delegate: Column {
                        id: shortcutRowContainer
                        required property var modelData
                        required property int index

                        readonly property bool isRecording: root.recordingAction === modelData.action
                        readonly property bool isModified: modelData.sequence !== modelData.defaultSequence
                        readonly property bool isRebindable: modelData.rebindable === undefined
                            ? true
                            : modelData.rebindable
                        readonly property bool showGroupHeader: shortcutRowContainer.index === 0
                            || root.shortcutEntries[shortcutRowContainer.index - 1].group !== modelData.group

                        width: parent ? parent.width : 0
                        spacing: 0

                        // Group header band (only on group transitions)
                        Rectangle {
                            visible: shortcutRowContainer.showGroupHeader
                            width: parent.width
                            implicitHeight: visible ? 32 : 0
                            color: "transparent"

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 4
                                text: shortcutRowContainer.modelData.group
                                color: Theme.accent
                                font.pointSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                height: 1
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                            }
                        }

                        Rectangle {
                            id: shortcutRow
                            width: parent.width
                            implicitHeight: 44
                            color: {
                                if (shortcutRowContainer.isRecording)
                                    return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                                if (rowHover.hovered && shortcutRowContainer.isRebindable)
                                    return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
                                return "transparent"
                            }
                            Behavior on color { ColorAnimation { duration: Theme.animDuration } }

                            // Bottom separator (last row in group gets no separator)
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                height: 1
                                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
                                visible: shortcutRowContainer.index < root.shortcutEntries.length - 1
                                    && root.shortcutEntries[shortcutRowContainer.index + 1].group === shortcutRowContainer.modelData.group
                            }

                            HoverHandler {
                                id: rowHover
                                enabled: shortcutRowContainer.isRebindable
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 8

                                // Action label
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        Layout.fillWidth: true
                                        text: shortcutRowContainer.modelData.label
                                        color: shortcutRowContainer.isRebindable ? Theme.text : Theme.subtext
                                        font.pointSize: Theme.fontNormal
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: !shortcutRowContainer.isRebindable
                                        text: "View-local — fires from the active file view (Enter on selection)."
                                        color: Theme.subtext
                                        font.pointSize: Theme.fontSmall
                                        font.italic: true
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                // Shortcut badge / recording indicator
                                Rectangle {
                                    Layout.preferredWidth: 180
                                    Layout.preferredHeight: 30
                                    radius: Theme.radiusSmall
                                    color: {
                                        if (shortcutRowContainer.isRecording)
                                            return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                                        if (!shortcutRowContainer.isRebindable)
                                            return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.03)
                                        return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
                                    }
                                    border.width: shortcutRowContainer.isRecording ? 1 : 0
                                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
                                    opacity: shortcutRowContainer.isRebindable ? 1.0 : 0.6

                                    Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                                    Behavior on border.width { NumberAnimation { duration: Theme.animDuration } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 4

                                        Text {
                                            Layout.fillWidth: true
                                            text: shortcutRowContainer.isRecording
                                                ? "Press keys..."
                                                : shortcutRowContainer.modelData.sequence
                                            color: shortcutRowContainer.isRecording ? Theme.accent : Theme.text
                                            font.pointSize: Theme.fontNormal
                                            font.weight: Font.Medium
                                            font.italic: shortcutRowContainer.isRecording
                                            elide: Text.ElideRight

                                            SequentialAnimation on opacity {
                                                running: shortcutRowContainer.isRecording
                                                loops: Animation.Infinite
                                                NumberAnimation { to: 0.4; duration: 600; easing.type: Easing.InOutSine }
                                                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: shortcutRowContainer.isRebindable
                                            ? Qt.PointingHandCursor
                                            : Qt.ArrowCursor
                                        enabled: shortcutRowContainer.isRebindable
                                        onClicked: {
                                            if (shortcutRowContainer.isRecording)
                                                root.stopRecording()
                                            else
                                                root.startRecording(shortcutRowContainer.modelData.action)
                                        }
                                    }
                                }

                                // Reset button (visible when modified AND rebindable)
                                HoverRect {
                                    width: 28; height: 28
                                    visible: shortcutRowContainer.isModified
                                        && !shortcutRowContainer.isRecording
                                        && shortcutRowContainer.isRebindable
                                    opacity: visible ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.animDuration } }
                                    onClicked: root.resetToDefault(shortcutRowContainer.modelData.action)

                                    IconUndo {
                                        anchors.centerIn: parent
                                        size: 14
                                        color: Theme.subtext
                                    }
                                }

                                // Spacer when reset button is hidden
                                Item {
                                    width: 28
                                    visible: !(shortcutRowContainer.isModified
                                        && !shortcutRowContainer.isRecording
                                        && shortcutRowContainer.isRebindable)
                                }
                            }
                        }
                    }
                }
            }

            KineticWheelScroller {
                anchors.fill: parent
                z: 10
                flickable: shortcutsFlick
                wheelStep: 42
                mouseWheelMultiplier: 0.75
                touchpadMultiplier: 1.35
                minVelocity: 135
                maxVelocity: 3900
                kineticGain: 1.01
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Text {
            Layout.fillWidth: true
            text: root.conflictWarning !== ""
                ? root.conflictWarning + " — try another."
                : root.recordingAction !== ""
                    ? "Press Escape to cancel recording."
                    : root.confirmResetAll
                        ? "Click again to confirm — every binding goes back to its factory default."
                        : "Click a shortcut to change it. Changes save automatically."
            color: (root.conflictWarning !== "" || root.confirmResetAll) ? Theme.accent : Theme.subtext
            font.pointSize: Theme.fontSmall
            wrapMode: Text.WordWrap
        }

        Q.Button {
            text: root.confirmResetAll ? "Confirm reset" : "Reset all to defaults"
            variant: "ghost"
            onClicked: {
                if (root.confirmResetAll) {
                    root.confirmResetAll = false
                    resetConfirmTimer.stop()
                    root.resetAllToDefaults()
                } else {
                    root.confirmResetAll = true
                    resetConfirmTimer.restart()
                }
            }
        }

        Q.Button {
            text: "Done"
            onClicked: root.closeDialog()
        }
    }
}
