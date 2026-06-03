import QtQuick
import Heimdall

Item {
    id: root

    // "hybrid" | "grid" | "detailed" | "miller"
    property string viewMode: "grid"
    property var fileModel: null
    property string currentPath: ""

    signal fileActivated(string filePath, bool isDirectory)
    signal contextMenuRequested(string filePath, bool isDirectory, point position)
    signal selectionChanged()
    signal interactionStarted()
    signal transferRequested(var paths, string destinationPath, bool moveOperation)
    // Column-header sort. Routed up to Main.qml (rather than sorting this one
    // pane's model locally) so the request updates tab metadata and re-sorts
    // every pane in a merged supertab — sort is a tab-level setting.
    signal sortRequested(string column, bool ascending)
    // Empty-state create action (kind "folder" | "file") from whichever view is
    // currently empty. Routed up to Main's new-folder/new-file dialogs.
    signal createItemRequested(string kind, string parentPath)

    function selectAll() {
        if (viewMode === "hybrid") hybridView.selectAll()
        else if (viewMode === "grid") gridView.selectAll()
        else if (viewMode === "miller") millerView.selectAll()
        else detailedView.selectAll()
    }

    function focusPath(path, reveal) {
        hybridView.focusPath(path, reveal)
        gridView.focusPath(path, reveal)
        detailedView.focusPath(path, reveal)
        millerView.focusPath(path, reveal)
    }

    // Expose sub-views so main.qml can access selection state
    property alias hybridViewItem: hybridView
    property alias gridViewItem: gridView
    property alias detailedViewItem: detailedView
    property alias millerViewItem: millerView

    HybridView {
        id: hybridView
        anchors.fill: parent
        visible: root.viewMode === "hybrid"
        viewModel: visible ? root.fileModel : null
        currentPath: root.currentPath

        onFileActivated: (fp, isDir) => root.fileActivated(fp, isDir)
        onContextMenuRequested: (fp, isDir, pos) => root.contextMenuRequested(fp, isDir, pos)
        onSelectionChanged: root.selectionChanged()
        onInteractionStarted: root.interactionStarted()
        onTransferRequested: (paths, destinationPath, moveOperation) => root.transferRequested(paths, destinationPath, moveOperation)
    }

    FileGridView {
        id: gridView
        anchors.fill: parent
        visible: root.viewMode === "grid"
        model: visible ? root.fileModel : null
        currentPath: root.currentPath

        onFileActivated: (fp, isDir) => root.fileActivated(fp, isDir)
        onContextMenuRequested: (fp, isDir, pos) => root.contextMenuRequested(fp, isDir, pos)
        onSelectedIndicesChanged: root.selectionChanged()
        onInteractionStarted: root.interactionStarted()
        onTransferRequested: (paths, destinationPath, moveOperation) => root.transferRequested(paths, destinationPath, moveOperation)
    }

    FileDetailedView {
        id: detailedView
        anchors.fill: parent
        visible: root.viewMode === "detailed"
        viewModel: visible ? root.fileModel : null
        currentPath: root.currentPath

        onFileActivated: (fp, isDir) => root.fileActivated(fp, isDir)
        onContextMenuRequested: (fp, isDir, pos) => root.contextMenuRequested(fp, isDir, pos)
        onSortRequested: (col, asc) => root.sortRequested(col, asc)
        onSelectedIndicesChanged: root.selectionChanged()
        onInteractionStarted: root.interactionStarted()
        onTransferRequested: (paths, destinationPath, moveOperation) => root.transferRequested(paths, destinationPath, moveOperation)
    }

    FileMillerView {
        id: millerView
        anchors.fill: parent
        visible: root.viewMode === "miller"
        fileModel: visible ? root.fileModel : null
        currentPath: root.currentPath

        onFileActivated: (fp, isDir) => root.fileActivated(fp, isDir)
        onContextMenuRequested: (fp, isDir, pos) => root.contextMenuRequested(fp, isDir, pos)
        onSelectionChanged: root.selectionChanged()
        onInteractionStarted: root.interactionStarted()
        onTransferRequested: (paths, destinationPath, moveOperation) => root.transferRequested(paths, destinationPath, moveOperation)
    }

    // Empty-folder hero overlay (handoff §8). One instance covers whichever flat
    // view is active (grid / detailed / hybrid). Shown when the directory lists
    // zero visible items AND this is a normal, browsable local directory — so it
    // stays out of trash / remote mounts (where New folder makes no sense) and
    // out of Miller, whose multi-column navigator owns its own empty handling.
    // Non-button areas are click-through: the underlying view still gets
    // empty-space right-click (context menu) and drop targeting.
    readonly property bool _dirEmpty: root.fileModel
        && (root.fileModel.fileCount + root.fileModel.folderCount) === 0
    readonly property bool _canCreate: root.currentPath.length > 0
        && !fileOps.isRemotePath(root.currentPath)
        && !fileOps.isTrashPath(root.currentPath)
        && root.currentPath.indexOf("://") < 0

    EmptyState {
        anchors.fill: parent
        visible: root.viewMode !== "miller" && root._dirEmpty && root._canCreate
        hiddenShown: root.fileModel ? root.fileModel.showHidden : false
        onNewFolderClicked: root.createItemRequested("folder", root.currentPath)
        onNewFileClicked: root.createItemRequested("file", root.currentPath)
        // Toggle: reveal dot-files, or hide them again if already shown.
        onShowHiddenClicked: { if (root.fileModel) root.fileModel.showHidden = !root.fileModel.showHidden }
    }
}
