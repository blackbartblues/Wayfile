import QtQuick

// Copy/move transfer engine + per-item conflict resolution — extracted from
// Main.qml (Phase 4). Non-visual: it owns the transfer STATE and the conflict
// state machine that walks the user through each name collision before handing
// the resolved batch to fileOps/undoManager.
//
// fileOps / undoManager / clipboard are global context properties (set in
// main.cpp), so this controller reaches them directly. The one host coupling is
// the conflict dialog, injected as `conflictDialog`, plus a request back to the
// host to re-focus the active pane (the controller has no pane concept).
//
// Mirrors the SelectionController extraction: Main.qml forwards the two
// dialog-driven entry points (resolveTransferConflict / resetTransferConflictState)
// as thin delegations so MainOverlays keeps calling them through `host` exactly
// as before, and reads `transferMoveOperation` straight off this controller.
Item {
    id: controller

    // ── Injected by the host ───────────────────────────────────────────────
    // = mainOverlays.conflictDialog (the TransferConflictDialog instance).
    property var conflictDialog: null

    // ── Signals the host wires ─────────────────────────────────────────────
    // The host re-focuses the active pane (controller is pane-agnostic).
    signal activePaneFocusRequested()

    // ── Transfer / conflict state ──────────────────────────────────────────
    property var transferConflictItems: []
    property var transferResolvedItems: []
    property int transferConflictIndex: -1
    property bool transferMoveOperation: false
    property bool transferClearClipboardOnSuccess: false
    property string transferDestinationPath: ""
    property var transferReservedTargets: ({})

    function reservedTargetNames() {
        return namesFromReserved(transferReservedTargets)
    }

    // Extract the basenames of the truthy keys of a {targetPath: bool} map, so a
    // batch transfer can block names already claimed within the same batch when
    // generating the next unique "(copy)" name.
    function namesFromReserved(reservedMap) {
        var names = []
        for (var path in reservedMap) {
            if (!reservedMap[path])
                continue
            var slashIndex = path.lastIndexOf("/")
            names.push(slashIndex >= 0 ? path.substring(slashIndex + 1) : path)
        }
        return names
    }

    function resetTransferConflictState() {
        transferConflictItems = []
        transferResolvedItems = []
        transferConflictIndex = -1
        transferMoveOperation = false
        transferClearClipboardOnSuccess = false
        transferDestinationPath = ""
        transferReservedTargets = ({})
    }

    function executeTransferOperation(items, moveOperation, clearClipboardOnSuccess) {
        if (!items || items.length === 0)
            return

        var usesRemotePath = false
        for (var i = 0; i < items.length; ++i) {
            if (fileOps.isRemotePath(items[i].sourcePath) || fileOps.isRemotePath(items[i].targetPath)) {
                usesRemotePath = true
                break
            }
        }

        if (clearClipboardOnSuccess) {
            // Named one-shot rather than arguments.callee (which breaks under
            // JS strict mode and is hard to debug): disconnect by reference.
            var onClipboardTransferFinished = function(success) {
                fileOps.operationFinished.disconnect(onClipboardTransferFinished)
                if (success)
                    clipboard.clear()
            }
            fileOps.operationFinished.connect(onClipboardTransferFinished)
        }

        if (usesRemotePath) {
            if (moveOperation)
                fileOps.moveResolvedItems(items)
            else
                fileOps.copyResolvedItems(items)
            return
        }

        if (moveOperation)
            undoManager.moveResolvedItems(items)
        else
            undoManager.copyResolvedItems(items)
    }

    function openTransferConflict(index) {
        if (index < 0 || index >= transferConflictItems.length) {
            var items = transferResolvedItems.slice()
            var moveOperation = transferMoveOperation
            var clearClipboard = transferClearClipboardOnSuccess
            resetTransferConflictState()
            conflictDialog.close()
            executeTransferOperation(items, moveOperation, clearClipboard)
            return
        }

        transferConflictIndex = index
        var item = transferConflictItems[index]
        conflictDialog.renameText = fileOps.uniqueNameForDestination(
            transferDestinationPath,
            item.sourceName,
            reservedTargetNames()
        )
        conflictDialog.errorText = ""
        conflictDialog.currentItem = item
        conflictDialog.open()
    }

    function beginTransfer(paths, destinationPath, moveOperation, clearClipboardOnSuccess) {
        if (!paths || paths.length === 0 || !destinationPath)
            return

        var plan = fileOps.transferPlan(paths, destinationPath)
        if (!plan || plan.length === 0)
            return

        var resolved = []
        var conflicts = []
        var reserved = ({})

        for (var i = 0; i < plan.length; ++i) {
            var item = plan[i]
            if (item.samePath) {
                // A move onto an item's own location is meaningless — skip it.
                // It must never reach the overwrite/backup path, which would
                // move the file to a backup then fail to copy the now-missing
                // source, destroying it. (Also guards drag into source's dir.)
                if (moveOperation)
                    continue
                // A COPY into the source's own folder becomes "name (copy).ext"
                // (Windows/Nautilus behaviour) rather than a no-op. Reserve the
                // generated name so a multi-file batch doesn't collide.
                var copyName = fileOps.uniqueNameForDestination(
                    destinationPath, item.sourceName, namesFromReserved(reserved))
                var copyTarget = destinationPath + "/" + copyName
                reserved[copyTarget] = true
                resolved.push({
                    sourcePath: item.sourcePath,
                    targetPath: copyTarget,
                    overwrite: false
                })
                continue
            }
            var targetPath = item.targetPath
            var hasReservedConflict = reserved[targetPath] === true
            if (item.targetExists || hasReservedConflict) {
                conflicts.push(item)
                continue
            }

            reserved[targetPath] = true
            resolved.push({
                sourcePath: item.sourcePath,
                targetPath: item.targetPath,
                overwrite: false
            })
        }

        // Everything was a self-drop (or nothing actionable): do nothing.
        if (resolved.length === 0 && conflicts.length === 0)
            return

        if (conflicts.length === 0) {
            executeTransferOperation(resolved, moveOperation, clearClipboardOnSuccess)
            return
        }

        transferResolvedItems = resolved
        transferConflictItems = conflicts
        transferConflictIndex = -1
        transferMoveOperation = moveOperation
        transferClearClipboardOnSuccess = clearClipboardOnSuccess
        transferDestinationPath = destinationPath
        transferReservedTargets = reserved
        openTransferConflict(0)
    }

    function resolveTransferConflict(action) {
        if (transferConflictIndex < 0 || transferConflictIndex >= transferConflictItems.length)
            return

        var item = transferConflictItems[transferConflictIndex]
        if (action === "overwrite") {
            if (item.samePath) {
                conflictDialog.errorText = "Cannot overwrite an item with itself"
                return
            }

            transferReservedTargets[item.targetPath] = true
            transferResolvedItems = transferResolvedItems.concat([{ sourcePath: item.sourcePath, targetPath: item.targetPath, overwrite: true }])
        } else if (action === "rename") {
            var name = conflictDialog.renameText.trim()
            if (name === "" || name === "." || name === ".." || name.indexOf("/") >= 0) {
                conflictDialog.errorText = "Enter a valid file name"
                return
            }

            var targetPath = transferDestinationPath + "/" + name
            if (transferReservedTargets[targetPath] || fileOps.pathExists(targetPath) || targetPath === item.sourcePath) {
                conflictDialog.errorText = "That name already exists"
                return
            }

            transferReservedTargets[targetPath] = true
            transferResolvedItems = transferResolvedItems.concat([{ sourcePath: item.sourcePath, targetPath: targetPath, overwrite: false }])
        }

        var nextIndex = transferConflictIndex + 1
        if (nextIndex >= transferConflictItems.length) {
            openTransferConflict(nextIndex)
            return
        }

        transferConflictIndex = nextIndex
        var nextItem = transferConflictItems[nextIndex]
        conflictDialog.currentItem = nextItem
        conflictDialog.renameText = fileOps.uniqueNameForDestination(
            transferDestinationPath,
            nextItem.sourceName,
            reservedTargetNames()
        )
        conflictDialog.errorText = ""
        conflictDialog.focusRenameField()
    }

    function cancelTransferConflicts() {
        if (conflictDialog.visible)
            conflictDialog.close()
        else {
            resetTransferConflictState()
            activePaneFocusRequested()
        }
    }
}
