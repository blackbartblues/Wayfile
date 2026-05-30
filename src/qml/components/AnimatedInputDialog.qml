import QtQuick
import QtQuick.Layouts
import Heimdall
import Quill as Q

// Reusable modal single-input dialog with the shared scale/opacity/slide
// animation. Extracted from the three near-identical rename / new-folder /
// new-file dialogs that used to live inline in Main.qml (~500 duplicated
// lines).
//
// Usage: set title / placeholder / confirmText (+ selectAllOnOpen for rename),
// call openDialog(initialText), and handle submitted(name) — do validation in
// the handler and either call showError(msg) to keep the dialog open, or
// closeDialog() once the action succeeds.
Item {
    id: root
    anchors.fill: parent
    visible: false
    z: 1000
    Accessible.role: Accessible.Dialog
    Accessible.name: root.title

    property string title: ""
    property string placeholder: ""
    property string confirmText: "Create"
    // Rename selects the existing name on open so the user can type over it.
    property bool selectAllOnOpen: false

    // Confirmed with a non-empty, trimmed name. The host validates and either
    // calls showError(msg) (dialog stays open) or closeDialog() on success.
    signal submitted(string name)

    function openDialog(initialText) {
        errorText.text = ""
        field.text = initialText || ""
        visible = true
        box.opacity = 0
        box.scale = 0.88
        box.yOffset = -8
        openAnim.start()
        Qt.callLater(function() {
            field.inputItem.forceActiveFocus()
            if (root.selectAllOnOpen)
                field.inputItem.selectAll()
        })
        field.forceActiveFocus()
    }

    function closeDialog() {
        openAnim.stop()  // avoid open/close fighting if dismissed mid-open
        closeAnim.start()
    }
    function showError(message) { errorText.text = message }

    function _accept() {
        var name = field.text.trim()
        if (name === "")
            return
        root.submitted(name)
    }

    ParallelAnimation {
        id: openAnim
        NumberAnimation {
            target: box; property: "opacity"
            from: 0; to: 1; duration: Theme.animDurationFast
            easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve
        }
        NumberAnimation {
            target: box; property: "scale"
            from: 0.88; to: 1; duration: Theme.animDurationSlow
            easing.type: Easing.OutBack
            easing.overshoot: 0.8
        }
        NumberAnimation {
            target: box; property: "yOffset"
            from: -8; to: 0; duration: Theme.animDuration
            easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve
        }
    }
    SequentialAnimation {
        id: closeAnim
        ParallelAnimation {
            NumberAnimation {
                target: box; property: "opacity"
                to: 0; duration: Theme.animDurationFast
                easing.type: Theme.animEasingExit; easing.bezierCurve: Theme.animBezierCurve
            }
            NumberAnimation {
                target: box; property: "scale"
                to: 0.92; duration: Theme.animDurationFast
                easing.type: Theme.animEasingExit; easing.bezierCurve: Theme.animBezierCurve
            }
            NumberAnimation {
                target: box; property: "yOffset"
                to: -4; duration: Theme.animDurationFast
                easing.type: Theme.animEasingExit; easing.bezierCurve: Theme.animBezierCurve
            }
        }
        ScriptAction { script: root.visible = false }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.closeDialog()
    }

    Item {
        id: box
        width: 340
        height: card.implicitHeight
        anchors.centerIn: parent

        opacity: 0
        scale: 0.88
        transformOrigin: Item.Center

        property real yOffset: 0
        transform: Translate { y: box.yOffset }

        // Consume clicks on the dialog body so clicking inside it doesn't fall
        // through to the backdrop MouseArea and dismiss the dialog (only the
        // backdrop, Cancel, or Escape should close it).
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Q.Card {
            id: card
            anchors.fill: parent
            title: root.title
            padding: 20
            color: Theme.mantle
            border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)

            Q.TextField {
                id: field
                Layout.fillWidth: true
                autoFocus: true
                variant: "filled"
                placeholder: root.placeholder
                onTextChanged: errorText.text = ""
                Keys.onReturnPressed: root._accept()
                Keys.onEscapePressed: root.closeDialog()
            }

            Text {
                id: errorText
                Layout.fillWidth: true
                visible: text !== ""
                color: Theme.error
                font.pointSize: Theme.fontSmall
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 12

                Q.Button {
                    id: cancelButton
                    text: "Cancel"
                    variant: "ghost"
                    size: "small"
                    KeyNavigation.left: confirmButton
                    KeyNavigation.right: confirmButton
                    KeyNavigation.tab: confirmButton
                    KeyNavigation.backtab: confirmButton
                    Keys.onLeftPressed: confirmButton.forceActiveFocus()
                    Keys.onRightPressed: confirmButton.forceActiveFocus()
                    Keys.onEscapePressed: root.closeDialog()
                    onClicked: root.closeDialog()
                }

                Q.Button {
                    id: confirmButton
                    text: root.confirmText
                    variant: "primary"
                    size: "small"
                    KeyNavigation.left: cancelButton
                    KeyNavigation.right: cancelButton
                    KeyNavigation.tab: cancelButton
                    KeyNavigation.backtab: cancelButton
                    Keys.onLeftPressed: cancelButton.forceActiveFocus()
                    Keys.onRightPressed: cancelButton.forceActiveFocus()
                    Keys.onEscapePressed: root.closeDialog()
                    onClicked: root._accept()
                }
            }
        }
    }
}
