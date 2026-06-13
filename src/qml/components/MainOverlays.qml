import QtQuick
import Wayfile

// Modal overlays for Wayfile's main window — extracted from Main.qml (Faza 5,
// B7). Holds the 13 dialog instances + the file and sidebar context menus as
// one cohesive unit so the orchestrator no longer carries them inline.
//
// `host` is the root ApplicationWindow: used for imperative method calls inside
// handlers and as transientParent for the Window-based dialogs. Reactive root
// state that dialog *bindings* read is passed as TYPED properties
// (sidebarVisible/sidebarWidth/activePaneIndex/transferMoveOperation/
// deleteConfirmPaths/isTrashView) — reading those through `host` (a var) inside
// a binding would evaluate once and never re-fire when the source changes.
//
// Most child dialogs are in-scene overlays (anchors.fill: parent, z 1000–9999);
// this Item fills the window and carries a high z so the whole group renders
// above mainContent / QuickPreview / tooltips / toasts, exactly as when the
// dialogs were direct children of root. SettingsPanel + PropertiesDialog are
// separate Windows (z-independent) anchored via transientParent.
Item {
    id: overlays
    anchors.fill: parent
    z: 9999

    // Root ApplicationWindow — imperative method calls + transientParent.
    property var host
    // = mainContent (the file context menu's blur source). Set once; not reactive.
    property Item blurTarget
    // = root-level Toast (sidebar context menu mount/unmount hints).
    property var toast

    // Reactive root state read inside dialog *bindings* — must be typed props
    // (see header note). Bound from root at the call site.
    property bool sidebarVisible
    property int sidebarWidth
    property int activePaneIndex
    property bool transferMoveOperation
    property var deleteConfirmPaths: []
    property bool isTrashView

    // Expose every instance so Main.qml + AppShortcuts can reach them.
    property alias bulkRenameDialog: bulkRenameDialog
    property alias remoteConnectDialog: remoteConnectDialog
    property alias settingsPanel: settingsPanel
    property alias shortcutsDialog: shortcutsDialog
    property alias missingDependenciesDialog: missingDependenciesDialog
    property alias renameDialog: renameDialog
    property alias newFolderDialog: newFolderDialog
    property alias newFileDialog: newFileDialog
    property alias appChooserDialog: appChooserDialog
    property alias propertiesDialog: propertiesDialog
    property alias conflictDialog: conflictDialog
    property alias deleteConfirmDialog: deleteConfirmDialog
    property alias emptyTrashConfirmDialog: emptyTrashConfirmDialog
    property alias contextMenu: contextMenu
    property alias sidebarContextMenu: sidebarContextMenu

    BulkRenameDialog {
        id: bulkRenameDialog
        onRenameApplied: (paths) => host.handleBulkRenameApplied(paths)
    }

    RemoteConnectDialog {
        id: remoteConnectDialog
        onConnected: (uri) => host.navigateActivePaneTo(uri)
    }

    SettingsPanel {
        id: settingsPanel
        transientParent: overlays.host
        currentShowHidden: fsModel.showHidden
        currentSidebarVisible: sidebarVisible
        currentSidebarWidth: sidebarWidth
        onRemoteConnectRequested: host.openRemoteConnectDialog()
        onKeyboardShortcutsRequested: host.openKeyboardShortcutsDialog()
        onDependencyCheckRequested: missingDependenciesDialog.openDialog()
        onClosed: host.scheduleActivePaneFocus()
    }

    KeyboardShortcutsDialog {
        id: shortcutsDialog
        onClosed: host.scheduleActivePaneFocus()
    }

    MissingDependenciesDialog {
        id: missingDependenciesDialog
        onClosed: host.scheduleActivePaneFocus()
    }

    // (Wayfile: the startup auto-popup was removed. Trigger via Settings ->
    // "Check Optional Dependencies" instead.)

    // ── Rename dialog ───────────────────────────────────────────────────────
    AnimatedInputDialog {
        id: renameDialog
        title: "Rename"
        placeholder: "Enter new name"
        confirmText: "Rename"
        selectAllOnOpen: true
        onSubmitted: (name) => {
            if (host.renameTargetPath === "")
                return
            var parentDir = fileOps.parentPath(host.renameTargetPath)
            var targetPath = parentDir + "/" + name
            if (fileOps.pathExists(targetPath)) {
                showError("\"" + name + "\" already exists")
                return
            }
            if (fileOps.isRemotePath(host.renameTargetPath)) {
                var result = fileOps.renameResolvedItems([{ sourcePath: host.renameTargetPath, targetPath: targetPath }])
                if (!result.success) {
                    showError(result.error || "Rename failed")
                    return
                }
                host.refreshAllPanes()
            } else {
                undoManager.rename(host.renameTargetPath, name)
            }
            closeDialog()
        }
    }

    // ── New Folder / New File dialogs ───────────────────────────────────────
    AnimatedInputDialog {
        id: newFolderDialog
        title: "New Folder"
        placeholder: "Folder name"
        confirmText: "Create"
        onSubmitted: (name) => {
            if (host.newItemParentPath === "")
                return
            var createdPath = host.newItemParentPath + "/" + name
            if (fileOps.pathExists(createdPath)) {
                showError("\"" + name + "\" already exists")
                return
            }
            if (fileOps.isRemotePath(host.newItemParentPath)) {
                fileOps.createFolder(host.newItemParentPath, name)
                host.refreshAllPanes()
            } else {
                undoManager.createFolder(host.newItemParentPath, name)
            }
            if (fileOps.pathExists(createdPath))
                host.focusPathInPane(activePaneIndex, createdPath, true)
            closeDialog()
        }
    }

    AnimatedInputDialog {
        id: newFileDialog
        title: "New File"
        placeholder: "File name"
        confirmText: "Create"
        onSubmitted: (name) => {
            if (host.newItemParentPath === "")
                return
            var createdPath = host.newItemParentPath + "/" + name
            if (fileOps.pathExists(createdPath)) {
                showError("\"" + name + "\" already exists")
                return
            }
            if (fileOps.isRemotePath(host.newItemParentPath)) {
                fileOps.createFile(host.newItemParentPath, name)
                host.refreshAllPanes()
            } else {
                undoManager.createFile(host.newItemParentPath, name)
            }
            if (fileOps.pathExists(createdPath))
                host.focusPathInPane(activePaneIndex, createdPath, true)
            closeDialog()
        }
    }


    // ── App Chooser dialog ──────────────────────────
    AppChooserDialog {
        id: appChooserDialog
        fileModel: host.paneBaseModel(activePaneIndex)
        onUsedAndClosed: {
            if (propertiesDialog.visible && propertiesDialog.props.mimeType) {
                propertiesDialog._appsMime = propertiesDialog.props.mimeType
                propertiesDialog.fileModelRef.requestAvailableApps(propertiesDialog.props.mimeType)
            }
        }
    }

    // Open "just works": when a host-local file has no working default handler,
    // FileOperations.openFile emits openFileFailed → surface the App Chooser
    // (with the MIME set, so "Set Default" is available) plus an info toast.
    Connections {
        target: fileOps
        function onOpenFileFailed(path, mimeType) {
            toast.show("No default app for \"" + fileOps.displayNameForPath(path) + "\" — choose one", "info")
            appChooserDialog.filePath = path
            appChooserDialog.mimeType = mimeType
            appChooserDialog.open()
        }
    }

    // ── Properties dialog ──────────────────────────────────────────────────
    PropertiesDialog {
        id: propertiesDialog
        host: overlays.host
        transientParent: overlays.host
        onChooseAppRequested: (path, mimeType) => {
            appChooserDialog.filePath = path
            appChooserDialog.mimeType = mimeType
            appChooserDialog.open()
        }
        onClosed: host.scheduleActivePaneFocus()
    }

    TransferConflictDialog {
        id: conflictDialog
        isMoveOperation: transferMoveOperation
        onResolveRequested: (action) => host.resolveTransferConflict(action)
        onRejected: {
            host.resetTransferConflictState()
            host.scheduleActivePaneFocus()
        }
    }

    // ── Permanent Delete Confirmation Dialog ───────────────────────────────
    ConfirmActionDialog {
        id: deleteConfirmDialog
        title: "Permanently Delete?"
        confirmLabel: "Delete"
        bodyText: deleteConfirmPaths.length === 1
            ? "\"" + deleteConfirmPaths[0].substring(deleteConfirmPaths[0].lastIndexOf("/") + 1) + "\" will be permanently deleted. This cannot be undone."
            : deleteConfirmPaths.length + " items will be permanently deleted. This cannot be undone."
        onConfirmed: fileOps.deleteFiles(deleteConfirmPaths)
    }

    // ── Empty Trash Confirmation Dialog ──────────────────────────────────────
    ConfirmActionDialog {
        id: emptyTrashConfirmDialog
        title: "Empty Trash?"
        confirmLabel: "Empty Trash"
        bodyText: "All items in the Trash will be permanently deleted. This cannot be undone."
        onConfirmed: fileOps.emptyTrash()
    }

    // ── Context Menu ────────────────────────────────────────────────────────
    ContextMenu {
        id: contextMenu
        blurSource: blurTarget

        fileModel: host.paneBaseModel(activePaneIndex)
        isTrashView: overlays.isTrashView
        currentViewMode: tabModel.activeTab ? tabModel.activeTab.viewMode : "grid"
        currentSortBy: tabModel.activeTab ? tabModel.activeTab.sortBy : "name"
        currentSortAscending: tabModel.activeTab ? tabModel.activeTab.sortAscending : true

        onOpenRequested: (path, isDir) => {
            if (isDir)
                host.navigateActivePaneTo(path)
            else
                fileOps.openFile(path)
        }
        onOpenInNewTabRequested: (path) => host.openPathInNewTab(path)
        onOpenWithRequested: (path, desktopFile) => fileOps.openFileWith(path, desktopFile)
        onSetDefaultAppRequested: (mimeType, desktopFile) => {
            host.paneBaseModel(activePaneIndex).setDefaultApp(mimeType, desktopFile)
        }
        onChooseAppRequested: (path, mimeType) => {
            appChooserDialog.filePath = path
            appChooserDialog.mimeType = mimeType
            appChooserDialog.open()
        }

        onCutRequested: (paths) => clipboard.cut(paths)

        onCopyRequested: (paths) => clipboard.copy(paths)

        onPasteRequested: (destPath) => {
            host.pasteIntoDirectory(destPath)
        }

        onCopyPathRequested: (path) => fileOps.copyPathToClipboard(path)

        onRenameRequested: (path) => host.openRenameDialogForPath(path)
        onBulkRenameRequested: (paths) => host.openBulkRenameDialog(paths)

        onTrashRequested: (paths) => {
            var hasRemotePath = false
            for (var i = 0; i < paths.length; ++i) {
                if (fileOps.isRemotePath(paths[i])) {
                    hasRemotePath = true
                    break
                }
            }

            if (hasRemotePath)
                fileOps.trashFiles(paths)
            else
                undoManager.trashFiles(paths)
        }
        onRestoreRequested: (paths) => fileOps.restoreFromTrash(paths)
        onEmptyTrashRequested: emptyTrashConfirmDialog.open()

        onDeleteRequested: (paths) => {
            host.deleteConfirmPaths = paths
            deleteConfirmDialog.open()
        }

        onOpenInTerminalRequested: (path) => {
            fileOps.openInTerminal(path)
        }

        onNewFolderRequested: (parentPath) => {
            host.showNewFolderDialog(parentPath)
        }

        onNewFileRequested: (parentPath) => {
            host.showNewFileDialog(parentPath)
        }

        onSelectAllRequested: {
            var view = host.activeFileView()
            if (view) view.selectAll()
        }

        onPropertiesRequested: (path) => {
            propertiesDialog.showProperties(path)
        }

        onViewModeRequested: (mode) => {
            if (tabModel.activeTab) tabModel.activeTab.viewMode = mode
        }

        onSortRequested: (column, ascending) => host.applySortFromUi(column, ascending)
    }

    ContextMenu {
        id: sidebarContextMenu
        menuWidth: 220

        property var sidebarItem: ({})

        onOpenRequested: (path) => {
            if (sidebarItem.isRecents) {
                host.setPaneRecents(activePaneIndex, true)
                return
            }

            if (sidebarItem.isHidden) {
                host.setPaneHidden(activePaneIndex, true)
                return
            }

            host.navigateActivePaneTo(path)
        }

        onOpenInNewTabRequested: (path) => {
            if (path)
                host.openPathInNewTab(path)
        }

        onPropertiesRequested: (path) => {
            if (path)
                propertiesDialog.showProperties(path)
        }

        onOpenInTerminalRequested: (path) => {
            if (path)
                fileOps.openInTerminal(path)
        }

        // ContextMenu.executeAction routes the "emptytrash" action through the
        // dedicated emptyTrashRequested() signal (not customActionRequested), so
        // the sidebar needs this handler — mirroring the main file-view menu.
        onEmptyTrashRequested: emptyTrashConfirmDialog.open()

        onCustomActionRequested: (action) => {
            if (action === "hide-entry") {
                // W7 per-entry hide — persisted via ConfigManager (toml).
                if (sidebarItem.entryId)
                    config.hideSidebarEntry(sidebarItem.entryId)
            } else if (action === "show-hidden") {
                // Restore every hidden sidebar entry at once (persisted).
                config.clearHiddenSidebarEntries()
            } else if (action === "removebookmark") {
                if (sidebarItem.kind === "bookmark" && sidebarItem.index >= 0)
                    bookmarks.removeBookmark(sidebarItem.index)
            } else if (action.indexOf("bookmark-color:") === 0) {
                // W8: per-favorite star color. "bookmark-color:<hex>"; an empty
                // hex clears the override back to the default gold. Persisted
                // via the model → ConfigManager.saveBookmarkColor wiring.
                if (sidebarItem.kind === "bookmark" && sidebarItem.index >= 0) {
                    var hex = action.substring("bookmark-color:".length)
                    bookmarks.setBookmarkColor(sidebarItem.index, hex)
                }
            } else if (action === "mountdevice") {
                if (sidebarItem.backend === "udisks2" && !runtimeFeatures.udisksctlAvailable) {
                    toast.show(runtimeFeatures.installHint("deviceMount"), "info")
                } else if (sidebarItem.kind === "device" && sidebarItem.index >= 0) {
                    devices.mount(sidebarItem.index)
                }
            } else if (action === "unmountdevice") {
                if (sidebarItem.backend === "udisks2" && !runtimeFeatures.udisksctlAvailable) {
                    toast.show(runtimeFeatures.installHint("deviceMount"), "info")
                } else if (sidebarItem.kind === "device" && sidebarItem.index >= 0) {
                    devices.unmount(sidebarItem.index)
                }
            }
        }

        onVisibleChanged: {
            if (!visible)
                sidebarItem = ({})
        }
    }
}
