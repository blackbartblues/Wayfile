import QtQuick
import QtQuick.Layouts
import ".."

Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property int dialogWidth: 360
    property int dialogPadding: 20
    property color dialogColor: Theme.mantle
    property color dialogBorderColor: Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.1)
    property real dialogRadius: Theme.radiusLg
    property bool closeOnOverlayPress: true
    property bool closeOnEscape: true
    property Item initialFocusItem: null
    default property alias content: dialogCard.content

    signal opened()
    signal closed()
    signal accepted()
    signal rejected()

    visible: false

    Accessible.role: Accessible.Dialog
    Accessible.name: root.title

    function open() {
        visible = true
        dialogBox.opacity = 0
        dialogBox.scale = 0.88
        dialogBox.yOffset = -8
        openAnim.start()
        Qt.callLater(function() {
            if (root.initialFocusItem)
                root.initialFocusItem.forceActiveFocus()
            else
                dialogBox.forceActiveFocus()
            root.opened()
        })
    }

    function close() {
        closeAnim.start()
    }

    function accept() {
        root.accepted()
        root.close()
    }

    function reject() {
        root.rejected()
        root.close()
    }

    ParallelAnimation {
        id: openAnim
        NumberAnimation {
            target: dialogBox; property: "opacity"
            from: 0; to: 1; duration: Theme.animDurationFast
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: dialogBox; property: "scale"
            from: 0.88; to: 1; duration: Theme.animDurationSlow
            easing.type: Easing.OutBack
            easing.overshoot: 0.8
        }
        NumberAnimation {
            target: dialogBox; property: "yOffset"
            from: -8; to: 0; duration: Theme.animDuration
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        id: closeAnim
        ParallelAnimation {
            NumberAnimation {
                target: dialogBox; property: "opacity"
                to: 0; duration: Theme.animDurationFast
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: dialogBox; property: "scale"
                to: 0.92; duration: Theme.animDurationFast
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: dialogBox; property: "yOffset"
                to: -4; duration: Theme.animDurationFast
                easing.type: Easing.InCubic
            }
        }
        ScriptAction {
            script: {
                root.visible = false
                root.closed()
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (root.closeOnOverlayPress)
                root.reject()
        }
    }

    Item {
        id: dialogBox
        anchors.centerIn: parent
        width: root.dialogWidth
        height: dialogCard.implicitHeight
        opacity: 0
        scale: 0.88
        transformOrigin: Item.Center
        focus: root.visible

        property real yOffset: 0
        transform: Translate { y: dialogBox.yOffset }

        Behavior on width {
            enabled: root.visible && !openAnim.running && !closeAnim.running
            NumberAnimation {
                duration: Theme.animDuration
                easing.type: Easing.OutCubic
            }
        }

        Behavior on height {
            enabled: root.visible && !openAnim.running && !closeAnim.running
            NumberAnimation {
                duration: Theme.animDuration
                easing.type: Easing.OutCubic
            }
        }

        Keys.onEscapePressed: (event) => {
            if (!root.closeOnEscape)
                return
            event.accepted = true
            root.reject()
        }

        Card {
            id: dialogCard
            anchors.fill: parent
            title: root.title
            subtitle: root.subtitle
            padding: root.dialogPadding
            color: root.dialogColor
            border.color: root.dialogBorderColor
            radius: root.dialogRadius
        }
    }
}
