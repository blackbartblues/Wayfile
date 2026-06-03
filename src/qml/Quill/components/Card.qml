import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    property string title: ""
    property string subtitle: ""
    default property alias content: contentColumn.data
    property int padding: Theme.spacingLg
    implicitHeight: mainColumn.implicitHeight + padding * 2
    Layout.fillWidth: true
    radius: Theme.radiusLg
    color: Theme.surface0
    border.color: Theme.surface1
    border.width: 1
    Accessible.role: Accessible.Grouping
    Accessible.name: root.title
    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: Theme.spacing
        ColumnLayout {
            visible: root.title !== ""
            spacing: 2
            Layout.bottomMargin: Theme.spacing
            Text {
                text: root.title
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeLarge
                font.family: Theme.fontFamily
                font.bold: true
            }
            Text {
                visible: root.subtitle !== ""
                text: root.subtitle
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeSmall
                font.family: Theme.fontFamily
            }
        }
        ColumnLayout {
            id: contentColumn
            Layout.fillWidth: true
            spacing: Theme.spacing
        }
    }
}
