import QtQuick

// All application-level keyboard shortcuts, extracted from Main.qml. Non-visual
// Item. `host` is the root window (provides the action functions + state);
// toolbar/quickPreview/the dialog+menu ids are injected so the few direct
// references and the Escape guard keep working. Globals (config, tabModel,
// fsModel, clipboard, fileOps, undoManager) are context properties used directly.
Item {
    id: appShortcuts

    property var host: null
    property var toolbar: null
    property var quickPreview: null
    property var propertiesDialog: null
    property var deleteConfirmDialog: null
    property var emptyTrashConfirmDialog: null
    property var contextMenu: null
    property var sidebarContextMenu: null
    property var bulkRenameDialog: null
    property var settingsPanel: null
    property var shortcutsDialog: null
    property var renameDialog: null
    property var newFolderDialog: null
    property var newFileDialog: null

    // Tab management
    Shortcut {
        sequence: config.shortcutMap["new_tab"]
        onActivated: host.createTabWithDefaults()
    }

    Shortcut {
        sequence: config.shortcutMap["close_tab"]
        onActivated: {
            host.closePaneAt(host.activePaneIndex)
        }
    }

    Shortcut {
        sequence: config.shortcutMap["reopen_tab"]
        onActivated: tabModel.reopenClosedTab()
    }

    Shortcut {
        sequence: config.shortcutMap["open_in_new_tab"]
        onActivated: host.openPathInNewTab(host.currentOrSelectedDirectoryPath())
    }

    Shortcut {
        sequence: config.shortcutMap["open_in_split"]
        onActivated: host.toggleMergeOrUnmerge()
    }

    // Navigation
    Shortcut {
        sequence: config.shortcutMap["back"]
        onActivated: host.goActivePaneBack()
    }

    Shortcut {
        sequence: "Backspace"
        onActivated: host.goActivePaneUp()
    }

    Shortcut {
        sequence: config.shortcutMap["forward"]
        onActivated: host.goActivePaneForward()
    }

    Shortcut {
        sequence: config.shortcutMap["parent"]
        onActivated: host.goActivePaneUp()
    }

    Shortcut {
        sequence: config.shortcutMap["home"]
        onActivated: host.navigateActivePaneTo(fsModel.homePath())
    }

    Shortcut {
        sequence: config.shortcutMap["refresh"]
        onActivated: host.refreshAllPanes()
    }

    Shortcut {
        sequence: config.shortcutMap["toggle_hidden"]
        onActivated: {
            var show = !host.paneBaseModel(host.activePaneIndex).showHidden
            host.forEachLivePaneModel(function(mdl) { mdl.showHidden = show })
        }
    }

    Shortcut {
        sequence: config.shortcutMap["path_bar"]
        onActivated: appShortcuts.toolbar.startEditing()
    }

    Shortcut {
        sequence: config.shortcutMap["toggle_sidebar"]
        onActivated: host.sidebarVisible = !host.sidebarVisible
    }

    Shortcut {
        sequence: config.shortcutMap["toggle_merge"]
        onActivated: host.toggleMergeOrUnmerge()
    }

    Shortcut {
        sequence: config.shortcutMap["focus_left_pane"]
        onActivated: host.setActivePane(0)
    }

    Shortcut {
        sequence: config.shortcutMap["focus_right_pane"]
        onActivated: host.setActivePane((tabModel.activeTab ? tabModel.activeTab.paneCount : 1) - 1)
    }

    Shortcut {
        sequence: config.shortcutMap["focus_next_pane"]
        onActivated: host.focusNextPane()
    }

    Shortcut {
        sequence: config.shortcutMap["focus_previous_pane"]
        onActivated: host.focusPreviousPane()
    }

    // View mode switching
    Shortcut {
        sequence: config.shortcutMap["grid_view"]
        onActivated: { if (tabModel.activeTab) tabModel.activeTab.viewMode = "grid" }
    }

    Shortcut {
        sequence: config.shortcutMap["miller_view"]
        onActivated: { if (tabModel.activeTab) tabModel.activeTab.viewMode = "miller" }
    }

    Shortcut {
        sequence: config.shortcutMap["detailed_view"]
        onActivated: { if (tabModel.activeTab) tabModel.activeTab.viewMode = "detailed" }
    }

    // File operations
    Shortcut {
        sequence: config.shortcutMap["copy"]
        onActivated: {
            var paths = host.getSelectedPaths()
            if (paths.length > 0) clipboard.copy(paths)
        }
    }

    Shortcut {
        sequence: config.shortcutMap["cut"]
        onActivated: {
            var paths = host.getSelectedPaths()
            if (paths.length > 0) clipboard.cut(paths)
        }
    }

    Shortcut {
        sequence: config.shortcutMap["paste"]
        onActivated: {
            if (!clipboard.hasContent && !fileOps.hasClipboardImage()) return
            if (host.paneIsRecents(host.activePaneIndex)) return
            var dest = host.panePath(host.activePaneIndex)
            if (dest === "") return
            host.pasteIntoDirectory(dest)
        }
    }

    Shortcut {
        sequence: config.shortcutMap["trash"]
        onActivated: {
            var paths = host.getSelectedPaths()
            if (paths.length === 0) return
            if (host.isTrashView) {
                host.deleteConfirmPaths = paths
                appShortcuts.deleteConfirmDialog.open()
            } else {
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
        }
    }

    Shortcut {
        sequence: config.shortcutMap["permanent_delete"]
        onActivated: {
            var paths = host.getSelectedPaths()
            if (paths.length > 0) {
                host.deleteConfirmPaths = paths
                appShortcuts.deleteConfirmDialog.open()
            }
        }
    }

    Shortcut {
        sequence: config.shortcutMap["undo"]
        onActivated: { if (undoManager.canUndo) undoManager.undo() }
    }

    Shortcut {
        sequence: config.shortcutMap["redo"]
        onActivated: { if (undoManager.canRedo) undoManager.redo() }
    }

    Shortcut {
        sequence: config.shortcutMap["select_all"]
        onActivated: {
            var view = host.activeFileView()
            if (view) view.selectAll()
        }
    }

    Shortcut {
        sequence: config.shortcutMap["context_menu"]
        onActivated: host.showContextMenuForActiveSelection()
    }

    Shortcut {
        sequence: config.shortcutMap["context_menu_alt"]
        onActivated: host.showContextMenuForActiveSelection()
    }

    Shortcut {
        sequence: config.shortcutMap["open_terminal"]
        onActivated: {
            var path = host.selectedOrCurrentTerminalPath()
            if (host.isLocalPath(path))
                fileOps.openInTerminal(path)
        }
    }

    Shortcut {
        sequence: config.shortcutMap["properties"]
        onActivated: {
            var path = host.selectedOrCurrentPropertiesPath()
            if (path)
                appShortcuts.propertiesDialog.showProperties(path)
        }
    }

    Shortcut {
        sequence: config.shortcutMap["rename"]
        onActivated: {
            var paths = host.getSelectedPaths()
            host.toggleRenameWorkflow(paths)
        }
    }

    Shortcut {
        sequence: config.shortcutMap["new_folder"]
        onActivated: {
            var dest = host.isRecentsView ? "" : host.panePath(host.activePaneIndex)
            host.toggleNewFolderDialog(dest)
        }
    }

    Shortcut {
        sequence: config.shortcutMap["new_file"]
        onActivated: {
            var dest = host.isRecentsView ? "" : host.panePath(host.activePaneIndex)
            host.toggleNewFileDialog(dest)
        }
    }

    // Quick preview (spacebar)
    Shortcut {
        sequence: config.shortcutMap["quick_preview"]
        onActivated: {
            if (appShortcuts.quickPreview.active) {
                appShortcuts.quickPreview.active = false
                return
            }
            var paths = host.getSelectedPaths()
            if (paths.length === 0) return
            appShortcuts.quickPreview.fileModel = host.paneBaseModel(host.activePaneIndex)
            appShortcuts.quickPreview.filePath = paths[0]
            appShortcuts.quickPreview.directoryFiles = host.getDirectoryFiles()
            appShortcuts.quickPreview.active = true
            appShortcuts.quickPreview.forceActiveFocus()
        }
    }

    // Search
    Shortcut {
        sequence: config.shortcutMap["search"]
        onActivated: {
            if (host.searchMode) host.closeSearch()
            else host.openSearch()
        }
    }

    Shortcut {
        sequence: config.shortcutMap["settings"]
        onActivated: host.openSettingsPanel()
    }

    Shortcut {
        sequence: config.shortcutMap["keyboard_shortcuts"]
        onActivated: host.openKeyboardShortcutsDialog()
    }

    Shortcut {
        sequence: "Escape"
        // Context menus are in-scene overlays with no Escape handling of their
        // own, so the global shortcut closes them (highest priority). Otherwise
        // it closes search. Modal dialogs + QuickPreview self-handle Escape, so
        // the shortcut stays disabled while one of those is open. Guards are
        // null-safe because the injected ids are var properties.
        enabled: (appShortcuts.contextMenu && appShortcuts.contextMenu.visible)
                 || (appShortcuts.sidebarContextMenu && appShortcuts.sidebarContextMenu.visible)
                 || (host && host.searchMode
                     && !(appShortcuts.quickPreview && appShortcuts.quickPreview.active)
                     && !(appShortcuts.propertiesDialog && appShortcuts.propertiesDialog.visible)
                     && !(appShortcuts.bulkRenameDialog && appShortcuts.bulkRenameDialog.visible)
                     && !(appShortcuts.settingsPanel && appShortcuts.settingsPanel.visible)
                     && !(appShortcuts.shortcutsDialog && appShortcuts.shortcutsDialog.visible)
                     && !(appShortcuts.renameDialog && appShortcuts.renameDialog.visible)
                     && !(appShortcuts.newFolderDialog && appShortcuts.newFolderDialog.visible)
                     && !(appShortcuts.newFileDialog && appShortcuts.newFileDialog.visible)
                     && !(appShortcuts.deleteConfirmDialog && appShortcuts.deleteConfirmDialog.visible)
                     && !(appShortcuts.emptyTrashConfirmDialog && appShortcuts.emptyTrashConfirmDialog.visible))
        onActivated: {
            if (appShortcuts.contextMenu.visible) {
                appShortcuts.contextMenu.close()
                return
            }
            if (appShortcuts.sidebarContextMenu.visible) {
                appShortcuts.sidebarContextMenu.close()
                return
            }
            host.closeSearch()
        }
    }
}
