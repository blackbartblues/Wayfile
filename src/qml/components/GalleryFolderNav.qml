import QtQuick
import QtQuick.Layouts
import Wayfile

// Folder navigator shown in the sidebar slot while the Gallery view is active
// (SidebarPane swaps it in for the normal Sidebar). Lists the active pane's
// subfolders plus a ".." parent entry; clicking navigates the active pane, so
// the gallery's thumbnail strip + preview refresh to the new directory.
//
// Reflects the primary pane via fsModel (FoldersOnly proxy) + navigateActivePaneTo;
// single-pane is exact, a non-primary split pane is best-effort.
Item {
    id: root
    Accessible.role: Accessible.Pane
    Accessible.name: "Folder navigator"

    // Main.qml root — provides activePanePath + navigateActivePaneTo.
    property var host: null

    readonly property string currentDir: host ? host.activePanePath : ""
    readonly property string parentDir: {
        var p = root.currentDir
        if (!p || p === "/")
            return ""
        var i = p.lastIndexOf("/")
        return i <= 0 ? "/" : p.substring(0, i)
    }

    readonly property color _hoverBg: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)

    // Subfolders of the current directory (folders-only over the primary model).
    DirFilterProxyModel {
        id: folderProxy
        mode: DirFilterProxyModel.FoldersOnly
    }
    Component.onCompleted: folderProxy.switchSourceModel(fsModel)

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ".." parent row.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            visible: root.parentDir !== ""
            color: upHover.hovered ? root._hoverBg : "transparent"

            Row {
                anchors.fill: parent
                anchors.leftMargin: 12
                spacing: 9
                IconChevronUp {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 15
                    color: Theme.subtext
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ".."
                    color: Theme.subtext
                    font.pointSize: Theme.fontNormal
                }
            }
            HoverHandler { id: upHover }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.host) root.host.navigateActivePaneTo(root.parentDir)
            }
        }

        // Subfolder list.
        ListView {
            id: folderList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: folderProxy
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: folderRow
                required property string fileName
                required property string filePath
                width: ListView.view ? ListView.view.width : 0
                height: 32
                color: rowHover.hovered ? root._hoverBg : "transparent"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 9
                    IconFolder {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 15
                        color: Theme.gold
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 36
                        text: folderRow.fileName
                        color: Theme.text
                        font.pointSize: Theme.fontNormal
                        elide: Text.ElideRight
                    }
                }
                HoverHandler { id: rowHover }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.host) root.host.navigateActivePaneTo(folderRow.filePath)
                }
            }
        }
    }
}
