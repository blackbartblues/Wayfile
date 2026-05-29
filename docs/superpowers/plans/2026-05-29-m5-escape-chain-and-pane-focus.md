# P3 M5 — Escape closes context menu + focusPreviousPane

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two pre-existing pane/keyboard behavior bugs: (1) `Shift+F6` (`focus_previous_pane`) currently calls the same `focusNextPane()` as `F6`, and `focusNextPane()` only toggles panes 0↔1 instead of rotating through all supertab panes; (2) `Escape` does nothing when a context menu is open (the menu has no Escape handling and the global Escape shortcut is disabled outside search mode).

**Architecture:** Both changes are in `src/qml/Main.qml`. Generalize `focusNextPane()` to rotate forward by `paneCount` and add `focusPreviousPane()` rotating backward, both guarded on `paneCount > 1` (covers split *and* supertab; the old `splitViewEnabled()` gate missed supertabs). Wire the `focus_previous_pane` Shortcut to the new function. Extend the existing global `Escape` Shortcut into a small priority chain: close the file/sidebar context menu first, otherwise fall back to closing search — while keeping its `enabled` guard so modal dialogs and QuickPreview continue to self-handle Escape (verified: `QuickPreview.qml:296` `Keys.onEscapePressed`; `Q.Dialog`/`SettingsPanel` have their own Escape close).

**Tech Stack:** Qt6 / QML. No C++, no test harness (QML behavior) — verified by build + qmllint + user visual-OK.

**Spec reference:** `docs/superpowers/specs/2026-05-29-settings-shortcuts-polish-design.md` Chapter B → M5. Note: the Escape chain here also delivers the "dismiss context menu" behavior that an earlier window-deactivation approach was rejected for (it fought Hyprland focus-follows-mouse). Escape is the correct, compositor-agnostic dismiss.

---

### Task 1: Generalize pane focus rotation + add `focusPreviousPane()`

**Files:**
- Modify: `src/qml/Main.qml` (`focusNextPane()` at lines ~583-588; the `focus_previous_pane` Shortcut at ~3070-3072)

- [ ] **Step 1.1: Replace `focusNextPane()` and add `focusPreviousPane()`**

Current (`src/qml/Main.qml:583-588`):

```qml
    function focusNextPane() {
        if (!splitViewEnabled())
            return

        root.setActivePane(activePaneIndex === 0 ? 1 : 0)
    }
```

Replace with:

```qml
    function focusNextPane() {
        var count = tabModel.activeTab ? tabModel.activeTab.paneCount : 1
        if (count <= 1)
            return
        root.setActivePane((activePaneIndex + 1) % count)
    }

    function focusPreviousPane() {
        var count = tabModel.activeTab ? tabModel.activeTab.paneCount : 1
        if (count <= 1)
            return
        root.setActivePane((activePaneIndex - 1 + count) % count)
    }
```

Rationale: `setActivePane()` already clamps out-of-range indices, so modular arithmetic is safe. For a 2-pane tab both functions reduce to the old 0↔1 toggle; for 3+ pane supertabs they rotate through every pane. The `paneCount > 1` guard replaces `splitViewEnabled()` so the keys also work in merged supertabs (where `splitViewEnabled` may be false).

- [ ] **Step 1.2: Wire `focus_previous_pane` to the new function**

Current (`src/qml/Main.qml:3070-3072`):

```qml
        sequence: config.shortcutMap["focus_previous_pane"]
        onActivated: root.focusNextPane()
```

Change to:

```qml
        sequence: config.shortcutMap["focus_previous_pane"]
        onActivated: root.focusPreviousPane()
```

- [ ] **Step 1.3: Build + qmllint**

Run:

```bash
cmake --build build && qmllint src/qml/Main.qml
```

Expected: clean build, no qmllint output.

**Do not commit yet — Task 2 is part of the same milestone/commit.**

---

### Task 2: Escape closes the context menu (priority over search)

**Files:**
- Modify: `src/qml/Main.qml` (the `Escape` Shortcut at lines ~3262-3274)

- [ ] **Step 2.1: Extend the Escape Shortcut into a priority chain**

Current (`src/qml/Main.qml:3262-3274`):

```qml
        sequence: "Escape"
        enabled: root.searchMode
                 && !quickPreview.active
                 && !bulkRenameDialog.visible
                 && !settingsPanel.visible
                 && !shortcutsDialog.visible
                 && !renameDialog.visible
                 && !newFolderDialog.visible
                 && !newFileDialog.visible
                 && !deleteConfirmDialog.visible
                 && !emptyTrashConfirmDialog.visible
        onActivated: root.closeSearch()
    }
```

Replace the `enabled:` and `onActivated:` with:

```qml
        sequence: "Escape"
        // Context menus are in-scene overlays with no Escape handling of
        // their own, so the global shortcut closes them (highest priority).
        // Otherwise it closes search. Modal dialogs and QuickPreview keep
        // self-handling Escape, so the shortcut stays disabled while one of
        // those is open (it would otherwise swallow the key before them).
        enabled: contextMenu.visible
                 || sidebarContextMenu.visible
                 || (root.searchMode
                     && !quickPreview.active
                     && !bulkRenameDialog.visible
                     && !settingsPanel.visible
                     && !shortcutsDialog.visible
                     && !renameDialog.visible
                     && !newFolderDialog.visible
                     && !newFileDialog.visible
                     && !deleteConfirmDialog.visible
                     && !emptyTrashConfirmDialog.visible)
        onActivated: {
            if (contextMenu.visible) {
                contextMenu.close()
                return
            }
            if (sidebarContextMenu.visible) {
                sidebarContextMenu.close()
                return
            }
            root.closeSearch()
        }
    }
```

Note: when a context menu is open the shortcut is enabled regardless of dialog state, but in practice opening a modal dialog closes any open menu, so the context-menu branch and the dialog-self-handling never collide.

- [ ] **Step 2.2: Build + qmllint**

Run:

```bash
cmake --build build && qmllint src/qml/Main.qml
```

Expected: clean build, no qmllint output.

- [ ] **Step 2.3: Offscreen load sanity (broad error scan)**

Run:

```bash
QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 4 ./build/src/heimdall 2>&1 | grep -iE "fail|multiple|error|qrc:" | grep -v "kf.windowsystem" | head || echo "(clean load)"
```

Expected: `(clean load)` — no component-load errors. (The grep includes `fail|multiple` deliberately: a narrow `error`-only filter previously missed a "Property value set multiple times" load failure.)

---

### Task 3: Visual-OK gate + commit

**Files:** none.

- [ ] **Step 3.1: Hand the visual-OK checklist to the user**

Present, verbatim:

> Launch Heimdall and confirm before I commit:
>
> **Pane focus (needs a split/supertab — open a folder in split view, or merge 3 tabs):**
> 1. Two panes: F6 and Shift+F6 both move focus between the two panes (active-pane outline / sidebar+status path follow).
> 2. Three+ panes (supertab): F6 rotates focus forward (pane 0→1→2→0), Shift+F6 rotates backward (0→2→1→0). Previously both keys did the same thing and only toggled 0↔1.
> 3. Single pane: F6 / Shift+F6 do nothing (no crash).
>
> **Escape:**
> 4. Right-click a file → context menu opens → press **Escape** → menu closes. (Previously Escape did nothing for an open menu.)
> 5. Right-click a sidebar entry → its context menu opens → Escape closes it.
> 6. Open search (Ctrl+F), type something, no menu open → Escape still closes search (no regression).
> 7. Open a dialog (F2 rename, properties, settings, keyboard shortcuts) → Escape still closes that dialog (dialogs self-handle; the global shortcut stays out of the way). QuickPreview (Space) → Escape still closes it.

Wait for explicit confirmation. Do not commit on assumption.

- [ ] **Step 3.2: Stage and commit**

```bash
git add src/qml/Main.qml
git commit -m "$(cat <<'EOF'
fix(p3,M5): rotate pane focus both directions + Escape closes context menu

- focusNextPane() now rotates forward through all panes by paneCount
  (was hardcoded to toggle 0<->1) and focusPreviousPane() rotates
  backward; both guard on paneCount > 1 so they work in merged supertabs,
  not just split view. Wire Shift+F6 (focus_previous_pane) to the new
  function — previously it called focusNextPane(), so F6 and Shift+F6
  did the same thing.
- Escape now closes an open file/sidebar context menu (highest priority),
  otherwise closes search. Context menus are in-scene overlays with no
  Escape handling of their own; modal dialogs and QuickPreview keep
  self-handling Escape via the shortcut's enabled guard.

Verified by build + qmllint + offscreen load + user visual-OK.

Spec: docs/superpowers/specs/2026-05-29-settings-shortcuts-polish-design.md (M5)
EOF
)"
```

- [ ] **Step 3.3: Confirm clean tree + hand off**

```bash
git log --oneline -2 && git status
```

Then tell the user: M5 shipped; remaining P3 is M6 (round-trip backstop tests) and the deferred M4 (Settings descriptions).
