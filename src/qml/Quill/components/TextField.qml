import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    property alias text: input.text
    property string placeholder: ""
    property string icon: ""
    property string variant: "default"
    property bool autoFocus: false
    property bool hasActiveFocus: input.activeFocus
    property int echoMode: TextInput.Normal
    property alias inputItem: input
    signal textEdited(string text)
    signal submitted(string text)
    implicitHeight: 34
    Layout.fillWidth: true
    radius: Theme.radius
    // Inset obsidian well; gold border on focus.
    color: variant === "transparent" ? "transparent" : Theme.backgroundDeep
    border.color: input.activeFocus ? Theme.primary : Theme.surface1
    border.width: variant === "default" ? 1 : 0
    opacity: enabled ? 1.0 : 0.5
    Accessible.role: Accessible.EditableText
    Accessible.name: root.placeholder
    Accessible.description: root.text
    Behavior on border.color { ColorAnimation { duration: Theme.animDurationFast } }

    // 3px gold focus ring (handoff): a soft gold halo just outside the border.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: parent.radius + 3
        color: "transparent"
        border.width: 3
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16)
        visible: input.activeFocus
        z: -1
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing
        spacing: Theme.spacing
        Text {
            visible: root.icon !== ""
            text: root.icon
            color: Theme.textTertiary
            font.family: Theme.iconFont
            font.pixelSize: Theme.fontSize
            anchors.verticalCenter: parent.verticalCenter
        }
        Item {
            width: parent.width - (root.icon !== "" ? Theme.fontSize + Theme.spacing : 0)
            height: parent.height
            TextInput {
                id: input
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                focus: root.autoFocus
                color: Theme.textPrimary
                selectionColor: Theme.primary
                selectedTextColor: Theme.base
                font.pixelSize: Theme.fontSize
                font.family: Theme.fontFamily
                clip: true
                enabled: root.enabled
                echoMode: root.echoMode
                onTextEdited: root.textEdited(text)
                onAccepted: root.submitted(text)
            }
            Text {
                visible: input.text === "" && !input.activeFocus
                text: root.placeholder
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSize
                font.family: Theme.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
