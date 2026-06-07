import QtQuick
import QtQuick.Layouts
import Wayfile
import Quill as Q

Q.Dialog {
    id: dialog
    anchors.fill: parent
    z: 9998
    dialogWidth: 360
    initialFocusItem: cancelButton

    property string bodyText: ""
    property string confirmLabel: "Delete"
    signal confirmed()

    onAccepted: dialog.confirmed()

    Text {
        Layout.fillWidth: true
        text: dialog.bodyText
        color: Theme.subtext
        font.pointSize: Theme.fontNormal
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
            onClicked: dialog.reject()
        }

        Q.Button {
            id: confirmButton
            text: dialog.confirmLabel
            variant: "danger"
            size: "small"
            KeyNavigation.left: cancelButton
            KeyNavigation.right: cancelButton
            KeyNavigation.tab: cancelButton
            KeyNavigation.backtab: cancelButton
            Keys.onLeftPressed: cancelButton.forceActiveFocus()
            Keys.onRightPressed: cancelButton.forceActiveFocus()
            onClicked: dialog.accept()
        }
    }
}
