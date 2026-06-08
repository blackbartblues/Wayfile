import QtQuick
import QtQuick.Controls
import Wayfile

// Folder TREE shown in the sidebar slot while the Gallery view is active
// (SidebarPane swaps it in for the normal Sidebar). A real, expandable
// filesystem tree rooted at Home over FolderTreeModel (a folders-only
// QFileSystemModel). A chevron expands/collapses a node without navigating;
// clicking a folder NAME navigates the active pane there (the gallery's
// thumbnails + preview refresh to the new directory) and expands that node.
// The folder currently shown is highlighted gold and auto-revealed.
Item {
    id: root
    Accessible.role: Accessible.Pane
    Accessible.name: "Folder tree"

    // Main.qml root — provides activePanePath + navigateActivePaneTo.
    property var host: null

    readonly property string homeDir: fsModel.homePath()
    readonly property string currentDir: host ? host.activePanePath : ""
    readonly property color _hoverBg: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
    readonly property color _currentBg: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.18)
    readonly property int _indent: Math.round(14 * Theme.uiScale)
    readonly property int _rowHeight: Math.round(30 * Theme.uiScale)

    FolderTreeModel {
        id: folderTree
        rootPath: root.homeDir
    }

    TreeView {
        id: tree
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: folderTree

        // One column that always fills the sidebar width.
        columnWidthProvider: function (column) { return tree.width }
        onWidthChanged: forceLayout()

        // Root the visible tree at Home. QFileSystemModel populates dirs
        // asynchronously, so (re)assign once Home's node is ready, then reveal.
        Component.onCompleted: tree.rootIndex = folderTree.indexForPath(root.homeDir)
        Connections {
            target: folderTree
            function onDirectoryLoaded(loadedPath) {
                if (loadedPath === root.homeDir)
                    tree.rootIndex = folderTree.indexForPath(root.homeDir)
                root._revealCurrent()
            }
        }

        delegate: Item {
            id: rowItem
            implicitHeight: root._rowHeight
            implicitWidth: tree.width

            // Required properties injected by TreeView for each delegate row.
            required property int row
            required property string display          // DisplayRole = file name
            required property var treeView            // the owning TreeView instance
            required property int depth               // nesting depth (0 = root children)
            required property bool expanded           // whether this node is expanded
            required property bool hasChildren        // whether this node has sub-folders
            required property bool isTreeNode         // always true for tree delegates

            readonly property string fullPath: folderTree.pathAt(tree.index(rowItem.row, 0))
            readonly property bool isCurrent: rowItem.fullPath === root.currentDir
            readonly property int _leftPad: 4 + rowItem.depth * root._indent

            // Background: gold for the current folder, faint hover otherwise.
            Rectangle {
                anchors.fill: parent
                color: rowItem.isCurrent ? root._currentBg
                     : (rowHover.hovered ? root._hoverBg : "transparent")
            }
            Rectangle {                       // gold left-bar for the current folder
                visible: rowItem.isCurrent
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 3
                color: Theme.gold
            }
            HoverHandler { id: rowHover }

            // Chevron (expand/collapse, no navigation) — only when the node has children.
            Item {
                id: chevron
                x: rowItem._leftPad
                width: 16
                height: parent.height
                IconChevronRight {
                    anchors.centerIn: parent
                    visible: rowItem.hasChildren
                    size: 13
                    color: Theme.subtext
                    rotation: rowItem.expanded ? 90 : 0
                    Behavior on rotation { NumberAnimation { duration: Theme.animDurationFast } }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: rowItem.hasChildren
                    cursorShape: Qt.PointingHandCursor
                    onClicked: rowItem.treeView.toggleExpanded(rowItem.row)
                }
            }

            // Folder glyph + name — clicking navigates the active pane + expands.
            Row {
                anchors.left: chevron.right
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                IconFolder {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 15
                    color: Theme.gold
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 15 - 6
                    text: rowItem.display
                    color: Theme.text
                    font.pointSize: Theme.fontNormal
                    elide: Text.ElideRight
                }
            }
            MouseArea {
                anchors.left: chevron.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.host)
                        root.host.navigateActivePaneTo(rowItem.fullPath)
                    if (rowItem.hasChildren && !rowItem.expanded)
                        tree.expand(rowItem.row)
                }
            }
        }
    }

    onCurrentDirChanged: _revealCurrent()

    // Expand the ancestor chain down to the active folder and scroll it into
    // view. Best-effort: if the path's node is not loaded yet, expandToIndex is
    // a no-op and this re-runs on the next directoryLoaded.
    function _revealCurrent() {
        if (!root.currentDir)
            return
        var idx = folderTree.indexForPath(root.currentDir)
        tree.expandToIndex(idx)
        Qt.callLater(function () {
            var r = tree.rowAtIndex(idx)
            if (r >= 0)
                tree.positionViewAtRow(r, TableView.Contain)
        })
    }
}
