import QtQuick
import QtQuick.Layouts
import Wayfile
import Quill as Q

// "Choose Application" dialog. Extracted from Main.qml (inline Q.Dialog).
// Callers set filePath / mimeType then call open(); fileModel is injected so
// the dialog can list installed apps and set the default handler. The host
// listens to usedAndClosed() to refresh any open Properties dialog.
Q.Dialog {
    id: appChooserDialog
    anchors.fill: parent
    title: "Choose Application"
    dialogWidth: 400
    z: 1100

    property var fileModel: null
    property string filePath: ""
    property string mimeType: ""
    property var allApps: []
    property string searchText: ""

    signal usedAndClosed()

    onOpened: {
        appSearchField.text = ""
        appChooserDialog.searchText = ""
        appChooserDialog.allApps = (appChooserDialog.fileModel || fsModel).allInstalledApps()
        appSearchField.inputItem.forceActiveFocus()
    }

    onClosed: {
        appChooserDialog.allApps = []
        appChooserDialog.usedAndClosed()
    }

    initialFocusItem: appSearchField.inputItem

    Q.TextField {
        id: appSearchField
        Layout.fillWidth: true
        placeholder: "Search applications…"
        variant: "filled"
        onTextEdited: (text) => appChooserDialog.searchText = text
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(360, Math.max(36, appListView.contentHeight))
        color: "transparent"
        clip: true

        ListView {
            id: appListView
            anchors.fill: parent
            model: {
                var query = appChooserDialog.searchText.toLowerCase()
                if (query === "")
                    return appChooserDialog.allApps
                return appChooserDialog.allApps.filter(function(app) {
                    return app.name.toLowerCase().indexOf(query) >= 0
                })
            }
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: appListView.width
                height: 40
                radius: Theme.radiusSmall
                color: delegateHover.hovered
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.1)
                    : "transparent"

                HoverHandler {
                    id: delegateHover
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 10

                    Image {
                        id: appChooserIcon
                        source: modelData.iconName
                            ? ("image://icon/" + modelData.iconName + "?theme=" + config.iconTheme + "&builtin=" + (config.builtinIcons ? "1" : "0"))
                            : ""
                        sourceSize: Qt.size(22, 22)
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        Layout.alignment: Qt.AlignVCenter
                        visible: modelData.iconName && status === Image.Ready
                    }

                    Text {
                        text: modelData.name
                        color: Theme.text
                        font.pointSize: Theme.fontNormal
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        elide: Text.ElideRight

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                fileOps.openFileWith(appChooserDialog.filePath, modelData.desktopFile)
                                appChooserDialog.close()
                            }
                        }
                    }

                    Rectangle {
                        id: setDefaultBtn
                        Layout.preferredWidth: setDefaultLabel.implicitWidth + 16
                        Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignVCenter
                        radius: Theme.radiusSmall
                        color: setDefaultMa.containsMouse
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                            : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.1)
                        visible: delegateHover.hovered && appChooserDialog.mimeType !== ""

                        Text {
                            id: setDefaultLabel
                            anchors.centerIn: parent
                            text: "Set Default"
                            color: Theme.accent
                            font.pointSize: Theme.fontSmall
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: setDefaultMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                (appChooserDialog.fileModel || fsModel).setDefaultApp(appChooserDialog.mimeType, modelData.desktopFile)
                                appChooserDialog.close()
                            }
                        }
                    }
                }
            }
        }
    }

    Text {
        visible: appListView.count === 0
        text: "No applications found"
        color: Theme.muted
        font.pointSize: Theme.fontSmall
        Layout.alignment: Qt.AlignHCenter
    }
}
