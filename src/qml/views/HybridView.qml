import QtQuick
import QtQuick.Layouts
import Heimdall

// Hybrid view (Phase 8 — the new default). A "Folders" grid on top + a "Files"
// detailed list below, in two stacked sections (handoff screenshots/01).
//
// The two sections are driven by a folders-only and a files-only proxy over the
// pane's shared source model, so the files list sorts independently (clicking a
// column header sorts files only; the folders grid keeps name order).
//
// Selection is UNIFIED across both sections: clicking in one section clears the
// other, and `selectedIndices` is exposed in SOURCE-model index space (mapped
// back from each proxy) so Main.qml's existing selection plumbing — which maps a
// sub-view's selectedIndices against the pane's source model — works unchanged.
FocusScope {
    id: root
    Accessible.role: Accessible.Pane
    Accessible.name: "Folders and files"
    focus: visible

    // The pane's source model (the same object Main.qml uses as paneModel, so
    // mapped source indices line up there).
    property var viewModel: null
    property string currentPath: ""

    signal fileActivated(string filePath, bool isDirectory)
    signal contextMenuRequested(string filePath, bool isDirectory, point position)
    signal selectionChanged()
    signal interactionStarted()
    signal transferRequested(var paths, string destinationPath, bool moveOperation)
    // No sortRequested: hybrid sorts the files section locally (folders keep name
    // order), so the request never bubbles up to re-sort the whole tab.

    // ── Folders / files split proxies over the shared source model ──────────
    DirFilterProxyModel {
        id: foldersProxy
        mode: DirFilterProxyModel.FoldersOnly
    }
    DirFilterProxyModel {
        id: filesProxy
        mode: DirFilterProxyModel.FilesOnly
    }
    onViewModelChanged: {
        foldersProxy.switchSourceModel(viewModel)
        filesProxy.switchSourceModel(viewModel)
    }
    Component.onCompleted: {
        foldersProxy.switchSourceModel(viewModel)
        filesProxy.switchSourceModel(viewModel)
    }

    // ── Unified selection (exposed in SOURCE index space) ───────────────────
    property var selectedIndices: []
    // Guards the cross-clear so clearing one section's selection doesn't recurse
    // back through the other section's change handler.
    property bool _crossClearing: false

    function _recomputeSelection() {
        var out = []
        var fSel = foldersGrid.selectedIndices
        for (var i = 0; i < fSel.length; ++i) {
            var sr = foldersProxy.mapRowToSource(fSel[i])
            if (sr >= 0) out.push(sr)
        }
        var gSel = filesList.selectedIndices
        for (var j = 0; j < gSel.length; ++j) {
            var sr2 = filesProxy.mapRowToSource(gSel[j])
            if (sr2 >= 0) out.push(sr2)
        }
        root.selectedIndices = out
        root.selectionChanged()
    }

    // Forwarders Main.qml / FileViewContainer call on the active sub-view.
    function selectAll() {
        foldersGrid.selectAll()
        filesList.selectAll()
    }
    function clearSelection() {
        root._crossClearing = true
        foldersGrid.clearSelection()
        filesList.clearSelection()
        root._crossClearing = false
        root._recomputeSelection()
    }
    function focusPath(path, reveal) {
        // Each call no-ops on the section that doesn't own the path (a path is
        // either a folder or a file, never both), so the matching section selects.
        foldersGrid.focusPath(path, reveal)
        filesList.focusPath(path, reveal)
    }

    // Cross-clear: a new selection in one section drops the other's, then the
    // unified set is recomputed. The guard short-circuits the clear-triggered
    // re-entry so it can't loop.
    Connections {
        target: foldersGrid
        function onSelectedIndicesChanged() {
            if (root._crossClearing) return
            if (foldersGrid.selectedIndices.length > 0 && filesList.selectedIndices.length > 0) {
                root._crossClearing = true
                filesList.clearSelection()
                root._crossClearing = false
            }
            root._recomputeSelection()
        }
    }
    Connections {
        target: filesList
        function onSelectedIndicesChanged() {
            if (root._crossClearing) return
            if (filesList.selectedIndices.length > 0 && foldersGrid.selectedIndices.length > 0) {
                root._crossClearing = true
                foldersGrid.clearSelection()
                root._crossClearing = false
            }
            root._recomputeSelection()
        }
    }

    // ── Section header: "Folders" + fading rule (handoff .sec-head). The item
    // count is intentionally omitted — the footer already shows folder/file
    // counts, so a per-section number here is redundant.
    component SectionHeader: Item {
        property string title: ""
        implicitHeight: 41

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 16
            anchors.bottomMargin: 9
            spacing: 10

            Text {
                text: title
                color: Theme.text
                font.pointSize: Theme.fontNormal
                font.weight: Font.DemiBold
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.alignment: Qt.AlignVCenter
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Theme.line }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }
    }

    // Full-area surface BEHIND the sections so the directory context menu and
    // click-to-deselect work in the empty area below the content too (e.g. a
    // folders-only directory, where the file list — which normally owns that
    // surface — is hidden). The sections render on top and capture their own
    // tile/row clicks; only the uncovered gaps fall through to here.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            root.interactionStarted()
            if (mouse.button === Qt.RightButton) {
                var mp = mapToItem(null, mouse.x, mouse.y)
                root.contextMenuRequested("", false, Qt.point(mp.x, mp.y))
            } else {
                root.clearSelection()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Folders section ─ tiles at a fixed compact size; the grid is capped at
        // ~half the view and only scrolls internally when it overflows. The
        // height carries a small bottom inset so a selected tile in the last row
        // renders its full rounded outline instead of being clipped at the grid
        // edge (and so "Files" sits a touch lower).
        SectionHeader {
            Layout.fillWidth: true
            visible: foldersProxy.count > 0
            title: "Folders"
        }
        FileGridView {
            id: foldersGrid
            readonly property int bottomInset: 14
            Layout.fillWidth: true
            Layout.preferredHeight: visible
                ? Math.min(contentHeight + bottomInset,
                           filesProxy.count > 0 ? root.height * 0.5 : root.height)
                : 0
            visible: foldersProxy.count > 0
            model: foldersProxy
            currentPath: root.currentPath
            cellSize: 118
            zoomEnabled: false
            interactive: contentHeight > height

            onFileActivated: (fp, isDir) => root.fileActivated(fp, isDir)
            onContextMenuRequested: (fp, isDir, pos) => root.contextMenuRequested(fp, isDir, pos)
            onInteractionStarted: root.interactionStarted()
            onTransferRequested: (paths, dst, move) => root.transferRequested(paths, dst, move)
        }

        // Files section ─ the detailed list; its column header sorts files only.
        SectionHeader {
            Layout.fillWidth: true
            visible: filesProxy.count > 0
            title: "Files"
        }
        FileDetailedView {
            id: filesList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: filesProxy.count > 0
            viewModel: filesProxy
            currentPath: root.currentPath

            onFileActivated: (fp, isDir) => root.fileActivated(fp, isDir)
            onContextMenuRequested: (fp, isDir, pos) => root.contextMenuRequested(fp, isDir, pos)
            onInteractionStarted: root.interactionStarted()
            onTransferRequested: (paths, dst, move) => root.transferRequested(paths, dst, move)
            // Files-only sort — applied to the files proxy, never bubbled up.
            onSortRequested: (col, asc) => filesProxy.sortByColumn(col, asc)
        }

        // When the file list is hidden (a folders-only directory) it can no
        // longer absorb the layout's leftover height, which would otherwise let
        // the folders grid drift off the top. This spacer takes the slack so the
        // folders stay pinned just under their header.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: filesProxy.count === 0
        }
    }
}
