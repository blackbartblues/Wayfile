import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    property int orientation: Qt.Horizontal
    Layout.fillWidth: orientation === Qt.Horizontal
    Layout.fillHeight: orientation === Qt.Vertical
    implicitWidth: orientation === Qt.Horizontal ? 100 : 1
    implicitHeight: orientation === Qt.Horizontal ? 1 : 100
    color: Theme.surface1
    Accessible.role: Accessible.Separator
    Accessible.ignored: true
}
