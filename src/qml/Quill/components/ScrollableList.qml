import QtQuick
import QtQuick.Layouts
import ".."

Item {
    id: root
    property alias model: listView.model
    property alias delegate: listView.delegate
    property string emptyText: "No items"
    implicitHeight: 200
    Layout.fillWidth: true
    Accessible.role: Accessible.List
    Accessible.name: "Scrollable list"
    Text {
        visible: listView.count === 0
        anchors.centerIn: parent
        text: root.emptyText
        color: Theme.textTertiary
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
    }
    ListView {
        id: listView
        anchors.fill: parent
        clip: true
        spacing: Theme.spacing
        boundsBehavior: Flickable.StopAtBounds
        visible: count > 0
    }
    Rectangle {
        visible: listView.contentHeight > listView.height
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 4
        color: "transparent"
        Rectangle {
            width: parent.width; radius: 2
            color: Theme.surface2
            opacity: listView.moving ? 0.8 : 0.3
            Behavior on opacity { NumberAnimation { duration: Theme.animDuration } }
            y: listView.contentY / listView.contentHeight * parent.height
            height: Math.max(20, (listView.height / listView.contentHeight) * parent.height)
        }
    }
}
