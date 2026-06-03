import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: root
    property string value: ""
    property bool enabled: true
    signal selected(string value)
    spacing: Theme.spacing
    opacity: enabled ? 1.0 : 0.5
    Accessible.role: Accessible.Grouping
    Accessible.name: "Radio button group"
}
