import QtQuick

// Shared selection / type-ahead / focus logic for the three file views
// (FileGridView, FileDetailedView, FileMillerView). Non-visual: it owns the
// selection STATE and the model-driven functions all three duplicated almost
// verbatim. View-specific geometry stays in each view and talks to this
// controller through the injected `fileModel` / `itemCount` inputs and the
// `ensureIndexVisible` / `requestFocus` signals — that keeps the controller
// free of GridView/ListView positioning enums and of which concrete item holds
// keyboard focus.
//
// Mirrors the PreviewState extraction: consumers forward state via
// `property alias`, so external callers (Main.qml, FileViewContainer) keep
// reading/writing `selectedIndices` and calling `selectAll()` / `focusPath()`
// exactly as before.
Item {
    id: controller

    // ── Injected by the host view ──────────────────────────────────────────
    property var fileModel: null          // model exposing filePath/fileName/isDir(row)
    property int itemCount: 0             // host binds this to its view's `count`
    property bool autoSelectFirst: false  // Miller auto-selects row 0 after a load

    // ── Shared selection state ─────────────────────────────────────────────
    property var selectedIndices: []
    property int lastSelectedIndex: -1    // anchor for shift-selection
    property int cursorIndex: -1          // moving end for keyboard navigation
    property string typeAheadBuffer: ""
    property string pendingFocusPath: ""
    property bool pendingFocusReveal: true
    property bool focusScheduled: false

    // ── Positioning modes passed through ensureIndexVisible ────────────────
    // The host maps these to its own GridView/ListView enum (Contain vs
    // Beginning) so the controller stays view-agnostic.
    readonly property int positionContain: 0
    readonly property int positionBeginning: 1

    // ── Signals the host view wires to its concrete view object ────────────
    signal selectionChanged()
    signal ensureIndexVisible(int index, int mode)
    signal requestFocus()

    Timer {
        id: typeAheadTimer
        interval: 1000
        repeat: false
        onTriggered: controller.typeAheadBuffer = ""
    }

    // Called by the host on directory change / Escape to drop any in-flight
    // type-ahead (the timer lives here now, so the host can't stop it directly).
    function resetTypeAhead() {
        typeAheadBuffer = ""
        typeAheadTimer.stop()
    }

    function selectIndex(idx, ctrl, shift) {
        if (shift && lastSelectedIndex >= 0) {
            var lo = Math.min(idx, lastSelectedIndex)
            var hi = Math.max(idx, lastSelectedIndex)
            var newSel = ctrl ? selectedIndices.slice() : []
            for (var i = lo; i <= hi; i++) {
                if (newSel.indexOf(i) < 0) newSel.push(i)
            }
            selectedIndices = newSel
        } else if (ctrl) {
            var newSel2 = selectedIndices.slice()
            var pos = newSel2.indexOf(idx)
            if (pos >= 0)
                newSel2.splice(pos, 1)
            else
                newSel2.push(idx)
            selectedIndices = newSel2
            lastSelectedIndex = idx
        } else {
            selectedIndices = [idx]
            lastSelectedIndex = idx
        }
        cursorIndex = idx
        selectionChanged()
    }

    function clearSelection() {
        selectedIndices = []
        lastSelectedIndex = -1
        cursorIndex = -1
        selectionChanged()
    }

    function pathForRow(row) {
        if (!fileModel || row < 0)
            return ""

        if (fileModel.filePath)
            return fileModel.filePath(row)

        return fileModel.data(fileModel.index(row, 0), 258 /* FilePathRole */) || ""
    }

    function fileNameForRow(row) {
        if (!fileModel || row < 0)
            return ""

        if (fileModel.fileName)
            return fileModel.fileName(row)

        return fileModel.data(fileModel.index(row, 0), 257 /* FileNameRole */) || ""
    }

    function isDirForRow(row) {
        if (!fileModel || row < 0)
            return false

        if (fileModel.isDir)
            return fileModel.isDir(row)

        return fileModel.data(fileModel.index(row, 0), 265 /* IsDirRole */) || false
    }

    function rowForPath(path) {
        if (!path)
            return -1

        for (var i = 0; i < itemCount; ++i) {
            if (pathForRow(i) === path)
                return i
        }

        return -1
    }

    function isPrintableTypeAheadText(text) {
        return typeof text === "string" && text.length === 1 && /[^\x00-\x1f\x7f]/.test(text)
    }

    function findTypeAheadMatch(query, keepCurrentMatch) {
        if (!query || itemCount <= 0)
            return -1

        var needle = query.toLocaleLowerCase()
        var current = cursorIndex >= 0 ? cursorIndex : (selectedIndices.length > 0 ? selectedIndices[selectedIndices.length - 1] : -1)
        if (keepCurrentMatch && current >= 0 && fileNameForRow(current).toLocaleLowerCase().startsWith(needle))
            return current

        for (var step = 1; step <= itemCount; ++step) {
            var idx = current >= 0 ? (current + step) % itemCount : step - 1
            if (fileNameForRow(idx).toLocaleLowerCase().startsWith(needle))
                return idx
        }

        return -1
    }

    function handleTypeAhead(event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return

        if (event.key === Qt.Key_Backspace) {
            if (typeAheadBuffer.length === 0)
                return

            typeAheadBuffer = typeAheadBuffer.slice(0, -1)
            if (typeAheadBuffer.length > 0) {
                typeAheadTimer.restart()
                var backspaceMatch = findTypeAheadMatch(typeAheadBuffer, true)
                if (backspaceMatch >= 0) {
                    selectIndex(backspaceMatch, false, false)
                    ensureIndexVisible(backspaceMatch, positionContain)
                }
            } else {
                typeAheadTimer.stop()
            }
            event.accepted = true
            return
        }

        if (!isPrintableTypeAheadText(event.text))
            return

        var nextBuffer = typeAheadBuffer + event.text
        var keepCurrentMatch = typeAheadBuffer.length > 0 && nextBuffer.startsWith(typeAheadBuffer)
        var match = findTypeAheadMatch(nextBuffer, keepCurrentMatch)
        if (match < 0) {
            nextBuffer = event.text
            match = findTypeAheadMatch(nextBuffer, false)
        }

        typeAheadBuffer = nextBuffer
        typeAheadTimer.restart()
        if (match >= 0) {
            selectIndex(match, false, false)
            ensureIndexVisible(match, positionContain)
        }
        event.accepted = true
    }

    // Home / End. The host calls wheelScroller.stopAndSettle() itself before
    // invoking this where it did so before (grid/detailed); Miller did not, so
    // the stop stays out of here to keep each view byte-faithful.
    function moveSelectionTo(index, extend) {
        if (itemCount <= 0)
            return

        var next = Math.max(0, Math.min(itemCount - 1, index))
        if (extend && lastSelectedIndex >= 0) {
            var lo = Math.min(next, lastSelectedIndex)
            var hi = Math.max(next, lastSelectedIndex)
            var newSel = []
            for (var i = lo; i <= hi; i++) newSel.push(i)
            selectedIndices = newSel
        } else {
            selectedIndices = [next]
            lastSelectedIndex = next
        }

        cursorIndex = next
        ensureIndexVisible(next, positionContain)
        selectionChanged()
    }

    function selectAll() {
        var all = []
        for (var i = 0; i < itemCount; i++) all.push(i)
        selectedIndices = all
        selectionChanged()
    }

    function schedulePendingFocus() {
        if (focusScheduled)
            return

        focusScheduled = true
        Qt.callLater(function() {
            focusScheduled = false
            if (pendingFocusPath !== "") {
                focusPath(pendingFocusPath, pendingFocusReveal)
            } else if (autoSelectFirst && itemCount > 0) {
                autoSelectFirst = false
                selectIndex(0, false, false)
                ensureIndexVisible(0, positionBeginning)
                requestFocus()
            }
        })
    }

    function focusPath(path, reveal) {
        if (!path || !fileModel)
            return false

        var idx = rowForPath(path)
        if (idx < 0) {
            pendingFocusPath = path
            pendingFocusReveal = (reveal !== false)
            return false
        }

        pendingFocusPath = ""
        pendingFocusReveal = true
        requestFocus()
        selectIndex(idx, false, false)
        if (reveal !== false)
            ensureIndexVisible(idx, positionContain)
        return true
    }

    // Pure geometry for rubber-band hit-testing (host iterates its own items).
    function rectsIntersect(a, b) {
        return a.x < b.x + b.width  &&
               a.x + a.width  > b.x &&
               a.y < b.y + b.height &&
               a.y + a.height > b.y
    }

    // Viewport-clamped rubber-band hit-test for the ROW-based views (detailed /
    // miller), which had a byte-near-identical copy. `flickable` is the row
    // ListView (exposes count/contentY/height/itemAtIndex/mapFromItem),
    // `rubberBand` exposes selectionRect. Only realized rows can intersect a
    // viewport-bound band, so the scan is clamped to the visible range (a ±2
    // row pad) — huge folders otherwise scanned every row per mouse-move. The
    // grid keeps its own 2D-geometry variant (cellHeight × columnsPerRow).
    function selectRowsIntersecting(flickable, rubberBand, rowHeight) {
        var rb = rubberBand.selectionRect
        if (rb.width < 4 && rb.height < 4)
            return

        var newSel = []
        var rh = Math.max(1, rowHeight)
        var first = Math.max(0, Math.floor(flickable.contentY / rh) - 2)
        var last = Math.min(flickable.count - 1,
                            Math.ceil((flickable.contentY + flickable.height) / rh) + 2)
        for (var i = first; i <= last; i++) {
            var item = flickable.itemAtIndex(i)
            if (!item)
                continue
            var itemPos = flickable.mapFromItem(item, 0, 0)
            var itemRect = Qt.rect(itemPos.x, itemPos.y, item.width, item.height)
            if (rectsIntersect(rb, itemRect))
                newSel.push(i)
        }
        selectedIndices = newSel
    }
}
