import QtQuick
import QtQuick.Layouts
import ".."

Item {
    id: root
    property var model: []
    property int currentIndex: 0
    property int orientation: Qt.Horizontal
    property string labelRole: ""
    property string descriptionRole: ""
    property string iconRole: ""
    property string iconComponentRole: ""
    property int sideTabHeight: 68
    property int sideTabWidth: 228
    signal tabChanged(int index)
    implicitWidth: orientation === Qt.Horizontal ? tabRow.implicitWidth : sideTabWidth
    implicitHeight: orientation === Qt.Horizontal ? 36 : verticalColumn.implicitHeight
    opacity: enabled ? 1.0 : 0.5
    Layout.fillWidth: orientation === Qt.Horizontal
    Layout.fillHeight: orientation === Qt.Vertical
    Accessible.role: Accessible.PageTabList
    Accessible.name: "Tab bar"

    function tabLabel(value) {
        if (value === undefined || value === null)
            return ""
        if (typeof value === "string")
            return value
        if (labelRole !== "" && value[labelRole] !== undefined)
            return value[labelRole]
        if (value.title !== undefined)
            return value.title
        if (value.label !== undefined)
            return value.label
        return String(value)
    }

    function tabDescription(value) {
        if (value === undefined || value === null || typeof value === "string")
            return ""
        if (descriptionRole !== "" && value[descriptionRole] !== undefined)
            return value[descriptionRole]
        if (value.subtitle !== undefined)
            return value.subtitle
        if (value.description !== undefined)
            return value.description
        return ""
    }

    function tabIconSource(value) {
        if (value === undefined || value === null || typeof value === "string")
            return ""
        if (iconRole !== "" && value[iconRole] !== undefined)
            return value[iconRole]
        if (value.iconSource !== undefined)
            return value.iconSource
        return ""
    }

    function tabIconComponent(value) {
        if (value === undefined || value === null || typeof value === "string")
            return null
        if (iconComponentRole !== "" && value[iconComponentRole] !== undefined)
            return value[iconComponentRole]
        if (value.iconComponent !== undefined)
            return value.iconComponent
        return null
    }

    function selectTab(index) {
        if (!enabled || index < 0 || index >= model.length)
            return
        currentIndex = index
        tabChanged(index)
    }

    Item {
        anchors.fill: parent
        visible: root.orientation === Qt.Horizontal

        Row {
            id: tabRow
            anchors.fill: parent
            spacing: 0

            Repeater {
                id: tabRepeater
                model: root.model

                Item {
                    required property var modelData
                    required property int index

                    width: tabText.implicitWidth + Theme.spacingXl * 2
                    height: root.height

                    Text {
                        id: tabText
                        anchors.centerIn: parent
                        text: root.tabLabel(modelData)
                        color: index === root.currentIndex ? Theme.primary : Theme.textTertiary
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                        font.bold: index === root.currentIndex
                        Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectTab(index)
                    }
                }
            }
        }

        Rectangle {
            id: underline
            height: 2
            radius: 1
            color: Theme.primary
            anchors.bottom: parent.bottom
            property Item currentTab: tabRepeater.itemAt(root.currentIndex)
            x: currentTab ? currentTab.x : 0
            width: currentTab ? currentTab.width : 0
            Behavior on x { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.surface1
        }
    }

    Item {
        anchors.fill: parent
        visible: root.orientation === Qt.Vertical

        Column {
            id: verticalColumn
            width: parent.width
            spacing: Theme.spacingSm

            Repeater {
                id: verticalRepeater
                model: root.model

                Item {
                    required property var modelData
                    required property int index

                    readonly property string description: root.tabDescription(modelData)
                    readonly property string iconSource: root.tabIconSource(modelData)
                    readonly property var iconComponent: root.tabIconComponent(modelData)

                    width: verticalColumn.width
                    height: description !== "" ? root.sideTabHeight : 36

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius
                        color: index === root.currentIndex
                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                            : tabMouse.containsMouse ? Theme.surface0 : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingLg
                        anchors.rightMargin: Theme.spacingLg
                        anchors.topMargin: description !== "" ? Theme.spacingMd : 0
                        anchors.bottomMargin: description !== "" ? Theme.spacingMd : 0
                        spacing: 10

                        Loader {
                            active: iconSource !== "" || iconComponent !== null
                            sourceComponent: iconComponent
                            source: iconComponent !== null ? "" : iconSource
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: active ? 14 : 0
                            Layout.preferredHeight: active ? 14 : 0

                            onLoaded: {
                                if (!item)
                                    return
                                item.size = 14
                                item.color = Qt.binding(function() {
                                    return index === root.currentIndex ? Theme.primary : Theme.overlay0
                                })
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: root.tabLabel(modelData)
                                color: index === root.currentIndex ? Theme.primary : Theme.textPrimary
                                font.pixelSize: Theme.fontSize
                                font.family: Theme.fontFamily
                                font.bold: index === root.currentIndex
                                elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: description !== ""
                                text: description
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }
                            }
                        }
                    }

                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectTab(index)
                    }
                }
            }
        }
    }
}
