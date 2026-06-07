import QtQuick
import QtQuick.Layouts
import Wayfile
import Quill as Q

// Copy/move conflict resolution dialog. Extracted from Main.qml. The host
// (openTransferConflict / resolveTransferConflict) drives it: set currentItem
// and renameText, call open(); the dialog emits resolveRequested(action) for
// the skip/overwrite/rename buttons and the rename field's Enter key, and the
// standard rejected() for Cancel/Escape (host resets state on reject).
Q.Dialog {
    id: conflictDialog
    anchors.fill: parent
    z: 9998
    dialogWidth: 460
    title: conflictDialog.isMoveOperation ? "Move Conflict" : "Copy Conflict"
    initialFocusItem: conflictRenameField

    property bool isMoveOperation: false
    property var currentItem: ({})
    property alias renameText: conflictRenameField.text
    property alias errorText: conflictErrorText.text

    signal resolveRequested(string action)

    function focusRenameField() { conflictRenameField.forceActiveFocus() }

    Text {
        Layout.fillWidth: true
        text: conflictDialog.currentItem.samePath
            ? "\"" + (conflictDialog.currentItem.sourceName || "") + "\" is already in this folder."
            : "\"" + (conflictDialog.currentItem.sourceName || "") + "\" already exists in the destination."
        color: Theme.text
        font.pointSize: Theme.fontNormal
        wrapMode: Text.WordWrap
    }

    Text {
        Layout.fillWidth: true
        text: conflictDialog.isMoveOperation
            ? "Choose whether to skip it, replace the existing item, or keep both with a new name."
            : "Choose whether to skip it, overwrite the existing item, or keep both with a new name."
        color: Theme.subtext
        font.pointSize: Theme.fontNormal
        wrapMode: Text.WordWrap
    }

    Q.TextField {
        id: conflictRenameField
        Layout.fillWidth: true
        autoFocus: true
        variant: "filled"
        placeholder: "New name"
        Keys.onReturnPressed: conflictDialog.resolveRequested("rename")
        Keys.onEscapePressed: conflictDialog.reject()
    }

    Text {
        id: conflictErrorText
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
            id: cancelConflictButton
            text: "Cancel"
            variant: "ghost"
            size: "small"
            onClicked: conflictDialog.reject()
        }

        Q.Button {
            id: skipConflictButton
            text: "Skip"
            variant: "ghost"
            size: "small"
            onClicked: conflictDialog.resolveRequested("skip")
        }

        Q.Button {
            id: overwriteConflictButton
            text: conflictDialog.isMoveOperation ? "Replace" : "Overwrite"
            variant: "danger"
            size: "small"
            enabled: !(conflictDialog.currentItem.samePath || false)
            onClicked: conflictDialog.resolveRequested("overwrite")
        }

        Q.Button {
            id: renameConflictButton
            text: "Rename"
            variant: "primary"
            size: "small"
            onClicked: conflictDialog.resolveRequested("rename")
        }
    }
}
