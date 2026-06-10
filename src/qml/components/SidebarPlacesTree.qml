import QtQuick
import QtQuick.Controls
import Wayfile

// Curated-XDG folder forest for the sidebar's Places section. A fixed list of
// XDG roots (Desktop/Documents/Downloads/Pictures/Music/Videos); each row has a
// chevron that expands an embedded TreeView rooted at that dir over the shared
// FolderTreeModel. The outer sidebar Flickable owns scrolling (inner TreeViews
// are interactive:false, height-bound to contentHeight). Clicking a folder name
// navigates the active pane + expands. Reuses the GalleryFolderNav delegate.
Column {
    id: root
    property var host: null          // Main.qml: navigateActivePaneTo + activePanePath
    readonly property string homeDir: fsModel.homePath()
    readonly property string currentDir: host ? host.activePanePath : ""
    readonly property int _indent: Math.round(14 * Theme.uiScale)
    readonly property int _rowHeight: Math.round(30 * Theme.uiScale)
    spacing: 0

    // One shared folders-only FS model for every subtree.
    FolderTreeModel {
        id: folderTree
        rootPath: root.homeDir
    }

    readonly property var xdgRoots: [
        { label: "Desktop",   dir: homeDir + "/Desktop"   },
        { label: "Documents", dir: homeDir + "/Documents" },
        { label: "Downloads", dir: homeDir + "/Downloads" },
        { label: "Pictures",  dir: homeDir + "/Pictures"  },
        { label: "Music",     dir: homeDir + "/Music"     },
        { label: "Videos",    dir: homeDir + "/Videos"    }
    ]

    Repeater {
        model: root.xdgRoots
        delegate: Column {
            id: xdgItem
            width: root.width
            required property var modelData
            // indexForPath() is an opaque function call, so a plain binding never
            // re-evaluates after QFileSystemModel finishes scanning Home. Seed it,
            // then re-check on every directoryLoaded so a valid XDG root that wasn't
            // scanned yet at construction stops being hidden once the model populates.
            property bool dirExists: folderTree.indexForPath(modelData.dir).valid
            Connections {
                target: folderTree
                function onDirectoryLoaded(p) {
                    xdgItem.dirExists = folderTree.indexForPath(xdgItem.modelData.dir).valid
                }
            }
            visible: dirExists
            height: visible ? implicitHeight : 0
            property bool expanded: false

            // XDG root header row.
            Rectangle {
                width: parent.width
                height: root._rowHeight
                color: xdgHeaderHover.hovered
                       ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
                       : "transparent"
                HoverHandler { id: xdgHeaderHover }

                // Chevron toggle — expands/collapses the subtree.
                Item {
                    id: xdgChev
                    x: 4; width: 16; height: parent.height
                    IconChevronRight {
                        anchors.centerIn: parent
                        size: 13
                        color: Theme.subtext
                        rotation: xdgItem.expanded ? 90 : 0
                        Behavior on rotation {
                            NumberAnimation { duration: Theme.animDurationFast }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: xdgItem.expanded = !xdgItem.expanded
                    }
                }

                // Folder icon + label — clicking navigates without expanding.
                Row {
                    anchors.left: xdgChev.right
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    FileIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        isDir: true
                        size: 15
                        hovered: xdgHeaderHover.hovered
                        selected: xdgItem.modelData.dir === root.currentDir
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 15 - 6
                        text: xdgItem.modelData.label
                        color: xdgItem.modelData.dir === root.currentDir
                               ? Theme.gold : Theme.text
                        font.pointSize: Theme.fontNormal
                        elide: Text.ElideRight
                    }
                }

                // Click the label area to navigate + auto-expand.
                MouseArea {
                    anchors.left: xdgChev.right
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.host)
                            root.host.navigateActivePaneTo(xdgItem.modelData.dir)
                        xdgItem.expanded = true
                    }
                }
            }

            // Lazy subtree — only loaded when the row is first expanded.
            Loader {
                id: subtreeLoader
                width: parent.width
                // Bind contentHeight from the loaded subtree for correct Column sizing.
                height: active && item ? item.contentHeight : 0
                active: xdgItem.expanded
                visible: active

                // Pass the root dir into the component via a Loader property
                // (avoids the parent.xxx anti-pattern inside sourceComponent).
                property string subtreeRootDir: xdgItem.modelData.dir

                sourceComponent: Component {
                    TreeView {
                        id: subtree
                        // subtreeRootDir is accessed via the Loader parent.
                        readonly property string rootDir: subtreeLoader.subtreeRootDir
                        width: subtreeLoader.width
                        // Non-interactive: the outer sidebar Flickable scrolls.
                        interactive: false
                        clip: false
                        model: folderTree
                        columnWidthProvider: function(column) { return subtree.width }
                        // Defer the relayout out of the binding-eval phase: this
                        // TreeView's contentHeight drives the Loader height, so a
                        // synchronous forceLayout() here risks a width↔height loop.
                        onWidthChanged: Qt.callLater(subtree.forceLayout)

                        Component.onCompleted: {
                            subtree.rootIndex = folderTree.indexForPath(subtree.rootDir)
                        }

                        Connections {
                            target: folderTree
                            function onDirectoryLoaded(p) {
                                if (p === subtree.rootDir)
                                    subtree.rootIndex = folderTree.indexForPath(subtree.rootDir)
                            }
                        }

                        delegate: Item {
                            id: rowItem
                            implicitHeight: root._rowHeight
                            implicitWidth: subtree.width

                            required property int row
                            required property string display
                            required property var treeView
                            required property int depth
                            required property bool expanded
                            required property bool hasChildren
                            required property bool isTreeNode

                            readonly property string fullPath: folderTree.pathAt(subtree.index(rowItem.row, 0))
                            readonly property bool isCurrent: rowItem.fullPath === root.currentDir
                            // Depth offset +1 so subtree items are indented one level
                            // past the XDG header row.
                            readonly property int _leftPad: 4 + (rowItem.depth + 1) * root._indent

                            // Background.
                            Rectangle {
                                anchors.fill: parent
                                color: rowItem.isCurrent
                                       ? Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.18)
                                       : (rowHover.hovered
                                          ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
                                          : "transparent")
                            }
                            // Gold accent bar for the active folder.
                            Rectangle {
                                visible: rowItem.isCurrent
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 2
                                color: Theme.gold
                            }

                            HoverHandler { id: rowHover }

                            // Chevron (expand/collapse, no navigation).
                            Item {
                                id: chev
                                x: rowItem._leftPad
                                width: 16
                                height: parent.height
                                IconChevronRight {
                                    anchors.centerIn: parent
                                    visible: rowItem.hasChildren
                                    size: 13
                                    color: Theme.subtext
                                    rotation: rowItem.expanded ? 90 : 0
                                    Behavior on rotation {
                                        NumberAnimation { duration: Theme.animDurationFast }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: rowItem.hasChildren
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: rowItem.treeView.toggleExpanded(rowItem.row)
                                }
                            }

                            // Folder glyph + name.
                            Row {
                                anchors.left: chev.right
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                FileIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    isDir: true
                                    size: 15
                                    hovered: rowHover.hovered
                                    selected: rowItem.isCurrent
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 15 - 6
                                    text: rowItem.display
                                    color: rowItem.isCurrent ? Theme.gold : Theme.text
                                    font.pointSize: Theme.fontNormal
                                    elide: Text.ElideRight
                                }
                            }

                            // Click label area to navigate + expand.
                            MouseArea {
                                anchors.left: chev.right
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.host)
                                        root.host.navigateActivePaneTo(rowItem.fullPath)
                                    if (rowItem.hasChildren && !rowItem.expanded)
                                        subtree.expand(rowItem.row)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
