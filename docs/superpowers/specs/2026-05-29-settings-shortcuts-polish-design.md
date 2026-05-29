# Heimdall P3 — Settings + Keyboard Shortcuts Polish Pass

**Status:** Spec approved, ready for `writing-plans`.
**Date:** 2026-05-29
**Branch base:** `main` HEAD `a1de6d4` (P2 fully shipped + visually confirmed)
**Author intent:** *"Chce poprawic settings i keyboard shortcuts aby zawsze wszystko bylo dzialajace i dobrze opisane."*

This spec is the single source of truth for Phase 3. It contains:
- **Chapter A — Audit** of the two user-facing customization surfaces (keyboard shortcuts + settings panel + persistence layer).
- **Chapter B — Milestones** (M1–M6) derived from the audit, each shippable as one commit with explicit verify gates.

Background, naming history, and architectural conventions live in the memory store
([[project-heimdall-p3-polish]], [[project-helm-file-manager]], [[reference-hyprfm-as-stack-mirror]],
[[lessons-qt6-qml-wiring]], [[feedback-customization-first]], [[feedback-ux-mouse-windows-like]],
[[feedback-verify-before-commit]], [[feedback-dry-no-duplicate-systems]]).

---

## Status taxonomy

Each audit row carries exactly one status. The status drives which milestone (if any) picks it up.

| Status | Meaning | Disposition |
|---|---|---|
| `OK` | Works, has label/UI, round-trips correctly. | none |
| `RENAME_NEEDED` | Exists but name/label is misleading. | M1 |
| `MISSING_LABEL` | Action registered, no human label in KB dialog. | M2 |
| `MISSING_BINDING` | Action registered, no `Shortcut {}` block driving it (or scope unclear). | M2 |
| `HARDCODED_INTENTIONAL` | Sequence bypasses config — by design. | none (documented) |
| `HARDCODED_LEGACY` | Sequence bypasses config — duplicate / superseded. | M1 (delete) |
| `NEEDS_REBIND` | Sequence hardcoded today but should be user-rebindable. | M1 |
| `NO_UI` | TOML key read by ConfigManager, no control in `SettingsPanel.qml`. | M3 (with per-row `ADD_UI` / `KEEP_FILE_ONLY` decision) |
| `NOT_PERSISTED` | UI control writes value but ConfigManager doesn't persist it. | M3 |
| `NO_DESCRIPTION` | Control exists in Settings but has no visible description line. | M4 |
| `NO_ROUND_TRIP` | Saves on disk, fails to restore on launch. | M6 |
| `BEHAVIOR_BUG` | Wires up correctly but handler logic is wrong / too narrow. | M5 |

---

## Chapter A — Audit

### A.1 Keyboard shortcut audit

**Method:** every `Shortcut {}` block in `src/qml/Main.qml` (counted: 44) is paired against the action registry in `src/services/configmanager.cpp` (`kShortcutSpecs[]`, 41 entries; `s_defaultShortcuts`, 41 entries — counts match). Status decided by: (a) does the sequence reference `config.shortcutMap[...]`? (b) does the action have a registry entry with a label? (c) does the handler do what the action name suggests?

#### A.1.1 Shortcut bindings in `Main.qml`

| # | Sequence source | Action key (if any) | Default | Handler | Status | Notes |
|---|---|---|---|---|---|---|
| 1 | `config.shortcutMap["new_tab"]` | `new_tab` | Ctrl+T | `tabModel.addTab()` | `OK` | |
| 2 | `config.shortcutMap["close_tab"]` | `close_tab` | Ctrl+W | `root.closePaneAt(activePaneIndex)` | `OK` | P2-M9 contextual close (pane vs tab) |
| 3 | `"Ctrl+M"` | — | — | `tabModel.mergeSelected()` | `HARDCODED_LEGACY` | Duplicate of F3 (`toggle_merge`). P2-M4 leftover; toolbar button shipped in M5. Delete. |
| 4 | `"Ctrl+Shift+M"` | — | — | `tabModel.unmergeActive()` | `HARDCODED_LEGACY` | Duplicate of F3 (`toggle_merge`). P2-M8 leftover. Delete. |
| 5 | `config.shortcutMap["reopen_tab"]` | `reopen_tab` | Ctrl+Shift+T | `tabModel.reopenClosedTab()` | `OK` | |
| 6 | `config.shortcutMap["open_in_new_tab"]` | `open_in_new_tab` | Ctrl+Return | `root.openPathInNewTab(...)` | `OK` | |
| 7 | `config.shortcutMap["open_in_split"]` | `open_in_split` | Ctrl+Shift+Return | `root.openPathInSplitView(...)` | `OK` | |
| 8 | `config.shortcutMap["back"]` | `back` | Alt+Left | `goActivePaneBack()` | `OK` | |
| 9 | `"Backspace"` | — | — | `goActivePaneUp()` | `HARDCODED_INTENTIONAL` | Windows-Explorer convention alias of `parent`. Per code comment + user policy 2026-05-29. Keep. |
| 10 | `config.shortcutMap["forward"]` | `forward` | Alt+Right | `goActivePaneForward()` | `OK` | |
| 11 | `config.shortcutMap["parent"]` | `parent` | Alt+Up | `goActivePaneUp()` | `OK` | |
| 12 | `config.shortcutMap["home"]` | `home` | Alt+Home | `navigateActivePaneTo(homePath)` | `OK` | |
| 13 | `config.shortcutMap["refresh"]` | `refresh` | F5 | `fsModel.refresh(); splitFsModel.refresh()` | `OK` | |
| 14 | `config.shortcutMap["toggle_hidden"]` | `toggle_hidden` | Ctrl+H | `fsModel.showHidden = !fsModel.showHidden` | `OK` | |
| 15 | `config.shortcutMap["path_bar"]` | `path_bar` | Ctrl+L | `toolbar.startEditing()` | `OK` | |
| 16 | `config.shortcutMap["toggle_sidebar"]` | `toggle_sidebar` | F9 | `root.sidebarVisible = !root.sidebarVisible` | `OK` | |
| 17 | `config.shortcutMap["split_view"]` | `split_view` | F3 | `root.toggleMergeOrUnmerge()` | `RENAME_NEEDED` | Handler is merge/unmerge toggle, name says "split view". M1: rename action to `toggle_merge`, label "Merge / Unmerge Panes", migrate old config key. |
| 18 | `config.shortcutMap["focus_left_pane"]` | `focus_left_pane` | Ctrl+Alt+Left | `setActivePane(0)` | `OK` | |
| 19 | `config.shortcutMap["focus_right_pane"]` | `focus_right_pane` | Ctrl+Alt+Right | `setActivePane(1)` | `OK` | |
| 20 | `config.shortcutMap["focus_next_pane"]` | `focus_next_pane` | F6 | `focusNextPane()` | `OK` | |
| 21 | `config.shortcutMap["focus_previous_pane"]` | `focus_previous_pane` | Shift+F6 | `focusNextPane()` ← **same fn** | `BEHAVIOR_BUG` | `focusPreviousPane()` does not exist. Currently both keys do the same toggle. Harmless for 2-pane, broken for 3+ pane supertabs. M5: add `focusPreviousPane()` that rotates in reverse. |
| 22 | `config.shortcutMap["grid_view"]` | `grid_view` | Ctrl+1 | sets `viewMode = "grid"` | `OK` | |
| 23 | `config.shortcutMap["miller_view"]` | `miller_view` | Ctrl+2 | sets `viewMode = "miller"` | `OK` | |
| 24 | `config.shortcutMap["detailed_view"]` | `detailed_view` | Ctrl+3 | sets `viewMode = "detailed"` | `OK` | |
| 25 | `config.shortcutMap["copy"]` | `copy` | Ctrl+C | `clipboard.copy(paths)` | `OK` | |
| 26 | `config.shortcutMap["cut"]` | `cut` | Ctrl+X | `clipboard.cut(paths)` | `OK` | |
| 27 | `config.shortcutMap["paste"]` | `paste` | Ctrl+V | `pasteIntoDirectory(dest)` | `OK` | |
| 28 | `config.shortcutMap["trash"]` | `trash` | Delete | trash flow w/ undo | `OK` | |
| 29 | `config.shortcutMap["permanent_delete"]` | `permanent_delete` | Shift+Delete | `deleteConfirmDialog` | `OK` | |
| 30 | `config.shortcutMap["undo"]` | `undo` | Ctrl+Z | `undoManager.undo()` | `OK` | |
| 31 | `config.shortcutMap["redo"]` | `redo` | Ctrl+Shift+Z | `undoManager.redo()` | `OK` | |
| 32 | `config.shortcutMap["select_all"]` | `select_all` | Ctrl+A | `view.selectAll()` | `OK` | |
| 33 | `config.shortcutMap["context_menu"]` | `context_menu` | Shift+F10 | `showContextMenuForActiveSelection()` | `OK` | |
| 34 | `"Menu"` | — | — | `showContextMenuForActiveSelection()` | `NEEDS_REBIND` | Per user policy 2026-05-29. M1: add action `context_menu_alt` with default `Menu`; or extend existing block to `sequences: [...]`. |
| 35 | `config.shortcutMap["open_terminal"]` | `open_terminal` | Ctrl+Alt+T | `fileOps.openInTerminal(path)` | `OK` | |
| 36 | `config.shortcutMap["properties"]` | `properties` | Alt+Return | `propertiesDialog.showProperties(path)` | `OK` | |
| 37 | `config.shortcutMap["rename"]` | `rename` | F2 | `toggleRenameWorkflow(paths)` | `OK` | |
| 38 | `config.shortcutMap["new_folder"]` | `new_folder` | Ctrl+Shift+N | `toggleNewFolderDialog(dest)` | `OK` | |
| 39 | `config.shortcutMap["new_file"]` | `new_file` | Ctrl+N | `toggleNewFileDialog(dest)` | `OK` | |
| 40 | `config.shortcutMap["quick_preview"]` | `quick_preview` | Space | `quickPreview.active = ...` | `OK` | |
| 41 | `config.shortcutMap["search"]` | `search` | Ctrl+F | `toggleSearch()` | `OK` | |
| 42 | `config.shortcutMap["settings"]` | `settings` | Ctrl+, | `openSettingsPanel()` | `OK` | |
| 43 | `config.shortcutMap["keyboard_shortcuts"]` | `keyboard_shortcuts` | Ctrl+? | `openKeyboardShortcutsDialog()` | `OK` | |
| 44 | `"Escape"` | — | — | `closeSearch()` (only when `searchMode` true and no dialog visible) | `BEHAVIOR_BUG` + `HARDCODED_INTENTIONAL` | Sequence stays hardcoded (universal cancel). Handler too narrow — should chain-close: quickPreview → context menu → settings/KB/properties/new-folder/new-file/rename dialogs → search. M5. |

**Counts:** 35 `OK` · 2 `HARDCODED_LEGACY` (delete) · 2 `HARDCODED_INTENTIONAL` (keep, document) · 1 `NEEDS_REBIND` (Menu) · 1 `RENAME_NEEDED` (`split_view`→`toggle_merge`) · 2 `BEHAVIOR_BUG` (focus_previous_pane, Escape) · 1 row (`Escape`) doubly tagged.

#### A.1.2 Registered actions vs bindings (registry inventory)

The 41 entries in `kShortcutSpecs[]` are all reachable through `Main.qml` Shortcut blocks **except one**:

| Action | Label | Default | Binding in Main.qml? | Status |
|---|---|---|---|---|
| `open` | Open | Return | **no global `Shortcut {}` block** | `MISSING_BINDING` (verify scope) — Return-on-selected-file is handled per-view in `FileViewContainer.qml` / list/grid delegates. Decision in M2: either (a) keep registry entry as documentation of an unreboundable view-local key, OR (b) actually plumb it through `config.shortcutMap["open"]` in the file-view delegates. Default to (b) since user expects everything in dialog to be rebindable. |

Everything else in `kShortcutSpecs` has a 1:1 Main.qml `Shortcut {}` block — no orphan registry rows.

#### A.1.3 KeyboardShortcutsDialog feature audit

| Feature | Status | Notes |
|---|---|---|
| Per-row label + group heading | partial | `KeyboardShortcutsDialog.qml` reads `config.shortcutDefinitions()` (action, label, sequence). Grouping currently not present in registry — labels are flat. **M2: add group field to `ShortcutSpec` struct + render grouped sections in dialog ("Tabs" / "Navigation" / "Panes" / "View" / "Selection" / "File operations" / "Application").** |
| Click row → press combo → rebind | OK | `setShortcutValue(action, sequence)` writes through ConfigManager. Verified via grep. |
| Reset single row to default | OK | Per-row button exists. |
| Reset all to defaults | TBD-during-audit | Verify presence during M2 execution; add if missing. |
| Conflict detection (combo already taken) | unknown | Not verified by grep. Low-priority backlog — note in M2, ship only if cheap. |
| Visible description (one line under combo) | missing | Labels are short noun phrases ("Open", "Back"). M4 considers adding sentence-form descriptions to the registry. |

### A.2 Settings / config audit

**Method:** every TOML key read by `src/services/configmanager.cpp` is paired with: (a) does ConfigManager expose it as `Q_PROPERTY`? (b) does `SettingsPanel.qml::currentSettings()` write it back? (c) does any visible Quill control toggle / set it?

#### A.2.1 Config key inventory

| TOML key | Q_PROPERTY | In `currentSettings()` | UI control | Visible description? | Status | Notes |
|---|---|---|---|---|---|---|
| `[general] theme` | `theme` | yes | `Q.Dropdown` "Theme" | no | `NO_DESCRIPTION` | M4. |
| `[general] icon_theme` | `iconTheme` | yes | `Q.Dropdown` "Icon Pack" | no | `NO_DESCRIPTION` | M4. |
| `[general] builtin_icons` | `builtinIcons` | **no** | `Q.Toggle` (label `""`, line 422) | no | `NOT_PERSISTED` + `NO_DESCRIPTION` | Toggle exists but value never flows into `currentSettings()`. M3: add to `currentSettings()`, label "Use built-in icon set", description. |
| `[general] font_family` | `fontFamily` | yes | `Q.Dropdown` "Font" | no | `NO_DESCRIPTION` | M4. |
| `[general] default_view` | `defaultView` | no | none | n/a | `NO_UI` | Decide M3: `ADD_UI` (Dropdown grid/miller/detailed in Layout section, default view for new tabs) or `KEEP_FILE_ONLY`. Recommend `ADD_UI` — visible UX. |
| `[general] show_hidden` | `showHidden` | yes | `Q.Toggle` "Show hidden files" | no | `NO_DESCRIPTION` | M4. |
| `[general] sort_by` | `sortBy` | no | none | n/a | `NO_UI` | Currently set per-tab via detailed-view column click. Decide M3: `ADD_UI` (default sort for new tabs, Dropdown name/size/modified/type) or `KEEP_FILE_ONLY`. Recommend `ADD_UI`. |
| `[general] sort_ascending` | `sortAscending` | no | none | n/a | `NO_UI` | Pair with `sort_by`. Recommend `ADD_UI` (Toggle "Sort ascending" right next to sort dropdown). |
| `[sidebar] visible` | `sidebarVisible` | yes | `Q.Toggle` "Show sidebar" | no | `NO_DESCRIPTION` | M4. |
| `[sidebar] width` | `sidebarWidth` | yes | `Q.Slider` "Sidebar width" | no | `NO_DESCRIPTION` | M4. |
| `[sidebar] position` | `sidebarPosition` | yes | `Q.Toggle` "Sidebar on right" | no | `NO_DESCRIPTION` | M4. Description should clarify "left" vs "right" semantics. |
| `[sidebar] bookmarks` | `bookmarks` | no | sidebar pin-from-context-menu only | n/a | `NO_UI` (`KEEP_FILE_ONLY`) | Per [[feedback-dry-no-duplicate-systems]]: bookmark editor inside Settings would be a second model on the same data. **Decision M3: KEEP_FILE_ONLY for editing; add a read-only "Manage from sidebar context menu" hint line in Tools section.** Audit confirms sidebar pin is the canonical edit point — no parallel system to build. |
| `[appearance] radius_small` | `radiusSmall` | yes | `Q.Slider` "Small radius" | no | `NO_DESCRIPTION` | M4. |
| `[appearance] radius_medium` | `radiusMedium` | yes | `Q.Slider` "Medium radius" | no | `NO_DESCRIPTION` | M4. Note clamp `radiusMedium ≥ radiusSmall` from configmanager.cpp — describe. |
| `[appearance] radius_large` | `radiusLarge` | yes | `Q.Slider` "Large radius" | no | `NO_DESCRIPTION` | M4. Note clamp `radiusLarge ≥ radiusMedium` — describe. |
| `[appearance] transparency_enabled` | `transparencyEnabled` | yes | `Q.Toggle` "Transparent containers" | no | `NO_DESCRIPTION` | M4. |
| `[appearance] transparency_level` | `transparencyLevel` | yes | `Q.Slider` "Transparency" | no | `NO_DESCRIPTION` | M4. |
| `[appearance] animations_enabled` | `animationsEnabled` | yes | `Q.Toggle` (label `""`, line 745) | no | `NOT_PERSISTED`? | Verify in M3 — label is empty; if the Toggle is correctly wired to draft, only `NO_DESCRIPTION` + `MISSING_LABEL` apply. Add label "Enable animations" and description. |
| `[appearance] anim_duration_fast` | `animDurationFast` | yes | `Q.Slider` "Fast" | no | `NO_DESCRIPTION` | M4. Description should give use-case examples ("hovers, ripples"). |
| `[appearance] anim_duration` | `animDuration` | yes | `Q.Slider` "Normal" | no | `NO_DESCRIPTION` | M4. ("panel slides, dialogs"). |
| `[appearance] anim_duration_slow` | `animDurationSlow` | yes | `Q.Slider` "Slow" | no | `NO_DESCRIPTION` | M4. ("layout/split transitions"). |
| `[appearance] anim_curve_enter` | `animCurveEnter` | yes | `Q.Dropdown` "Enter" | no | `NO_DESCRIPTION` | M4. |
| `[appearance] anim_curve_exit` | `animCurveExit` | yes | `Q.Dropdown` "Exit" | no | `NO_DESCRIPTION` | M4. |
| `[appearance] anim_curve_transition` | `animCurveTransition` | yes | `Q.Dropdown` "Transition" | no | `NO_DESCRIPTION` | M4. |
| `[window] show_controls` | `showWindowControls` | yes | `Q.Toggle` "Show window controls" | no | `NO_DESCRIPTION` | M4. |
| `[window] button_layout` | `windowButtonLayout` | yes | `Q.Toggle` "Buttons on left" + per-button toggles (close/minimize/maximize) | no | `NO_DESCRIPTION` | M4. Single composite control surface — describe how the toggles compose. |
| `[shortcuts] *` | `shortcutMap` + `shortcutDefinitions` | n/a | KeyboardShortcutsDialog | n/a | `OK` | Managed separately. See A.1. |
| `[custom_context_actions]` and subkeys (`actions`, `command`, `types`, `name`, `context_menu`) | `customContextActions` | no | none | n/a | `NO_UI` (`KEEP_FILE_ONLY`) | Power-user feature. Out of P3 scope per spec section 1. Document in Tools section as "Edit `~/.config/heimdall/config.toml` to add" with a "Show config in editor" button (optional, M3 stretch). |
| `[remote] paths` | (via `remoteModel`?) | no | none | n/a | `NO_UI` | "Connect to Network Location" Tools button exists. Verify in M3 that this is the canonical edit point. |

**Counts:** 4 `OK` · 19 `NO_DESCRIPTION` (M4) · 4 `NO_UI` decisions (M3: 3× `ADD_UI` + 1× `KEEP_FILE_ONLY`) · 1 `NOT_PERSISTED` (`builtinIcons`, M3) · 1 `MISSING_LABEL` + `NO_DESCRIPTION` (`animationsEnabled` toggle, M3+M4) · 2 power-user keys deferred.

#### A.2.2 Apply / Cancel / Restore semantics audit

| Action | Current behavior | Status | Disposition |
|---|---|---|---|
| Apply (auto-debounce via `settingsApplyTimer`) | `currentSettings()` → `config.saveSettings(...)` writes TOML, emits `configChanged`, live bindings repaint. | `OK` | none |
| Cancel | Settings has `flushPendingChanges()` and `syncFromCurrentState()`. Verify in M3 execution that closing the panel without explicit Apply discards drafts and re-syncs from disk. | TBD-during-audit | M3 |
| Restore defaults | Function `resetToDefaults()` exists at line 226. Verify it covers all keys + has confirm prompt. | TBD-during-audit | M3 (extend if gaps) |
| Theme hot-swap | Draft theme preview wired via `bindAppearancePreview()` / `setDraftTheme()`. Verify that Apply causes a no-restart full reload. | TBD-during-audit | M6 |

### A.3 Cross-cutting findings (not in original audit scope, surfaced during recon)

| Finding | Status | Disposition |
|---|---|---|
| `focusPreviousPane()` does not exist (line 565: only `focusNextPane`). Both F6 and Shift+F6 invoke the same toggle. | `BEHAVIOR_BUG` | **M5** (was M2 candidate but Escape + this are both pure behavior fixes → grouped). |
| `builtinIcons` Toggle has empty label and isn't persisted via `currentSettings()`. | `NOT_PERSISTED` + `MISSING_LABEL` | **M3**. |
| `animationsEnabled` Toggle has empty label. | `MISSING_LABEL` | **M3** (label addition co-occurs with description in M4 — keep tag fresh). |
| Only 4 of ~24 controls use `description:` or `subtitle:`. | `NO_DESCRIPTION` (×19) | **M4** (single sweep). |
| Bookmark editing has one canonical entry point (sidebar context-menu pin), no parallel UI to build. | DRY check passed | document in Tools section only |

---

## Chapter B — Milestones

Each milestone = one commit. Commit message format: `feat(p3,MN-...): <subject>` or `fix(p3,MN-...)`. Sequence is `M1 → M2 → M3 → M4 → M5 → M6` (sequential — per Section 3 of the approved design, parallel execution would make visual-OK noisy). `cmake --build build` + `qmllint` self-checked before asking for visual-OK.

### M1 — Cleanup hardcoded shortcuts + canonical naming

**Scope:**
1. Delete `Shortcut { sequence: "Ctrl+M" }` and `Shortcut { sequence: "Ctrl+Shift+M" }` blocks (Main.qml lines ~2950–2961). Remove their explanatory comments since they reference shipped milestones.
2. Rename action `split_view` → `toggle_merge`:
   - `kShortcutSpecs[]`: action `"toggle_merge"`, label `"Merge / Unmerge Panes"`.
   - `s_defaultShortcuts`: `{"toggle_merge", "F3"}`.
   - `Main.qml`: `config.shortcutMap["split_view"]` → `config.shortcutMap["toggle_merge"]`.
3. Add config migration shim in `ConfigManager::loadShortcuts()` (or equivalent load path): if `[shortcuts] split_view` exists and `[shortcuts] toggle_merge` does not, copy value under the new key, drop the old key, mark config dirty so it persists on the next save. Silent — no log, no prompt, one-time migration.
4. Add new action `context_menu_alt` (label `"Show Context Menu (Menu key)"`, default `"Menu"`). Replace the hardcoded `Shortcut { sequence: "Menu" }` block with `Shortcut { sequence: config.shortcutMap["context_menu_alt"] }`. Handler stays `showContextMenuForActiveSelection()`.

**Files touched:** `src/services/configmanager.cpp`, `src/services/configmanager.h` (only if migration logic needs a new private method declaration), `src/qml/Main.qml`. **Not touched:** `KeyboardShortcutsDialog.qml` (reads through the registry, picks up changes automatically).

**Verify gate:**
- [ ] `cmake --build build` succeeds.
- [ ] `qmllint src/qml/Main.qml` clean (no new warnings).
- [ ] **User visual-OK** in running app:
  - F3 still toggles merge ↔ unmerge.
  - Ctrl+M does nothing (legacy gone).
  - Pressing the dedicated Menu key opens the context menu.
  - KB dialog shows row "Merge / Unmerge Panes" with combo "F3" and a row "Show Context Menu (Menu key)" with combo "Menu".
  - With a pre-existing config that has `[shortcuts] split_view = "Ctrl+J"`: launch Heimdall, confirm KB dialog shows "Ctrl+J" for the renamed action and that the old key has been removed from `~/.config/heimdall/config.toml`.

### M2 — Shortcut registry hardening

**Scope:**
1. Add `group` field to `ShortcutSpec` (`const char *group`). Populate for every action: `"Tabs"`, `"Navigation"`, `"Panes"`, `"View"`, `"Selection"`, `"File"`, `"Application"`. Surface in `shortcutDefinitions()`.
2. `KeyboardShortcutsDialog.qml`: render rows grouped by `group` with section headers (collapsed alphabetically inside group).
3. Decide `open` action scope (per A.1.2): plumb `config.shortcutMap["open"]` into the file-view delegates so Enter-on-file is rebindable. If the cost balloons (signal plumbing across grid/miller/detailed views), drop back to keeping the registry entry as documentation only and tag the row `view-local` in the dialog.
4. Verify (and add if missing) "Reset all to defaults" button in `KeyboardShortcutsDialog`.

**Files touched:** `src/services/configmanager.cpp`, `src/services/configmanager.h`, `src/qml/components/KeyboardShortcutsDialog.qml`, possibly file-view delegates (`src/qml/components/FileGridView.qml`, `FileListView.qml`, `FileDetailedView.qml` — verify file names during execution).

**Verify gate:**
- [ ] Build + qmllint clean.
- [ ] **User visual-OK**: every action lives in exactly one group section in the KB dialog; default reset works per-row and globally.
- [ ] `open` decision: either Enter-on-file uses the rebindable shortcut, OR the registry row clearly indicates view-local non-rebindable.

### M3 — Settings parity (UI for missing keys + persistence fixes)

**Scope:**
1. **`builtinIcons` fix:** add to `currentSettings()`; set the existing empty-label Toggle's `label: "Use built-in icon set"`. (Description added in M4.)
2. **`animationsEnabled` label fix:** Toggle at line 745 gets `label: "Enable animations"`. (Description in M4.)
3. **Add UI controls** (Layout section unless noted):
   - `default_view`: `Q.Dropdown` "Default view for new tabs", values grid / miller / detailed.
   - `sort_by`: `Q.Dropdown` "Default sort", values name / size / modified / type.
   - `sort_ascending`: `Q.Toggle` "Sort ascending" alongside the sort dropdown.
4. **Tools section additions:**
   - Read-only hint row: "Bookmarks are managed from the sidebar (right-click → Pin)" with an icon. No editor UI. Confirms DRY by being explicit about where the canonical UI lives.
   - (Optional stretch) "Open config file in editor" button that runs `xdg-open ~/.config/heimdall/config.toml`. Drop if the additional `Process` plumbing is non-trivial.
5. **Apply / Cancel / Restore audit fixes:**
   - Verify `syncFromCurrentState()` is called on panel-close-without-Apply. Patch if missing.
   - Verify `resetToDefaults()` covers all keys in `currentSettings()` (including new ones from steps 1–3). Patch if missing.
   - Wrap `resetToDefaults()` in a confirm prompt if absent.

**Files touched:** `src/qml/components/SettingsPanel.qml` (primary), possibly `src/services/configmanager.cpp` if the persistence path for `builtinIcons` is missing.

**Verify gate:**
- [ ] Build + qmllint clean.
- [ ] **User visual-OK**:
  - `builtinIcons` toggle has visible label, toggling + Apply writes `builtin_icons = true/false` to TOML and survives restart.
  - `animationsEnabled` toggle has visible label.
  - New controls (`default_view`, `sort_by`, `sort_ascending`) appear in Layout section, change values, Apply persists.
  - Opening a new tab respects `default_view` setting.
  - New tabs respect default `sort_by` + `sort_ascending`.
  - Tools section shows the bookmarks hint.
  - Cancel discards uncommitted drafts; Restore-defaults confirms before wiping.

### M4 — Descriptions everywhere

**Scope:** add visible `description:` (or equivalent — confirm Quill control prop name during execution) to every Settings control identified `NO_DESCRIPTION` in audit A.2.1 (19 rows + the 3 new controls from M3 = ~22 descriptions to author). Descriptions are one sentence, plain English, ≤ ~80 chars where possible. Examples:

- `theme` → "Color palette for the whole application."
- `iconTheme` → "External icon pack used for files and folders."
- `builtinIcons` → "Fall back to the icons shipped with Heimdall when the chosen pack is missing entries."
- `radiusMedium` → "Corner radius of buttons, cards, and toggles. Clamped to be at least as large as Small."
- `transparencyLevel` → "0 = fully opaque, 1 = maximally transparent. Compositor support required."
- `animDurationFast` → "Hover, ripple, and other under-200 ms motions."
- `windowButtonLayout` (composite) → "Choose which window controls show and which side they sit on. Toggles below compose the layout string."
- (full list authored during execution; spec ships the policy + examples, not all 22 verbatim — that would be busywork better done with the actual UI open.)

**Files touched:** `src/qml/components/SettingsPanel.qml` only.

**Verify gate:**
- [ ] Build + qmllint clean.
- [ ] **User visual-OK**: every control visible in the panel has a one-line description directly under it (not tooltip). Per-section visually scanned for completeness. Description text reads cleanly at default font size and theme.

### M5 — Behavior bug fixes

**Scope:**
1. **Implement `focusPreviousPane()`** in Main.qml that rotates active pane index in reverse direction across all panes of the active supertab (handles 2-pane and 3+ pane cases consistently with `focusNextPane`). Wire the `focus_previous_pane` shortcut to the new function.
2. **Expand `Escape` handler** to a priority chain — top-most overlay closes first regardless of category:
   1. If a context menu is open → close it. (Menus sit above everything, including dialogs.)
   2. Else if `quickPreview.active` → close quickPreview.
   3. Else if any modal dialog visible (`renameDialog`, `newFolderDialog`, `newFileDialog`, `bulkRenameDialog`, `deleteConfirmDialog`, `emptyTrashConfirmDialog`, `propertiesDialog`) → close it.
   4. Else if `shortcutsDialog.visible` → close it.
   5. Else if `settingsPanel.visible` → close it.
   6. Else if `root.searchMode` → close search.
   7. Else → no-op.
   Remove the long `enabled:` guard now that the handler self-checks; Escape always fires globally, the handler decides what to close.

**Files touched:** `src/qml/Main.qml` (primary). Possibly individual dialog/panel QML files if they don't expose a `close()` method we can call.

**Verify gate:**
- [ ] Build + qmllint clean.
- [ ] **User visual-OK**:
  - In a 3-pane supertab, Shift+F6 rotates focus left-to-right while F6 rotates right-to-left (or the opposite — whichever feels natural; user picks during visual-OK).
  - Escape pressed in each scenario closes exactly the topmost overlay (quickPreview, dialog, settings, KB, context menu, search) in that priority order. Nothing closes when no overlay is open.

### M6 — Round-trip backstop + theme hot-swap verification

**Scope:**
1. **Round-trip smoke matrix:** for every key listed in audit A.2.1, manually mutate via UI → quit → relaunch → confirm value sticks. This is largely a user-driven test, but we automate where possible:
   - Add a new test file `tests/tst_configmanager_roundtrip.cpp`. For each Q_PROPERTY-backed key, set non-default value via `saveSettings()`, destroy ConfigManager, instantiate fresh against same TOML, assert getter returns the set value. Covers persistence-layer round-trip without launching QML.
   - Wire to CMake (`tests/CMakeLists.txt`).
2. **Theme hot-swap verification:** with the panel open, change `theme` dropdown → Apply → confirm the running UI repaints without restart (preview already shows, this confirms the final commit also reflows correctly). If hot-swap is missing on Apply (only preview works), patch by emitting `configChanged` and rebinding Quill `Q.Theme` getters. **Verify only — patch only if broken.**
3. **Settings reset visual flow:** trigger Restore Defaults from M3 → confirm prompt → all controls reset their visible values in one paint.

**Files touched:** `tests/tst_configmanager_roundtrip.cpp` (new), `tests/CMakeLists.txt`, possibly `src/services/configmanager.cpp` or `src/qml/Theme.qml` if hot-swap repair is needed.

**Verify gate:**
- [ ] `ctest --test-dir build --output-on-failure` passes (new round-trip suite green).
- [ ] Build + qmllint clean.
- [ ] **User visual-OK**: change every UI-exposed setting → restart → all values restored. Theme hot-swap on Apply visibly reflows the window. Restore Defaults asks for confirmation and resets cleanly.

---

## Workflow & gates

1. Spec → `superpowers:writing-plans` → per-milestone implementation plans.
2. Per-milestone: `superpowers:executing-plans` (or direct execution given milestone size).
3. After each milestone: `cmake --build build` + `qmllint` self-run → present visual-OK checklist to user → **wait for explicit OK** → commit ([[feedback-verify-before-commit]]). One commit per milestone.
4. Memory updated only on milestone-complete-and-pushed events. The audit doc is the running notebook.

## Non-goals (P3 closes when these stay untouched)

- Theme system internals (loader, hot-reload across multiple themes mid-session beyond the basic Apply case — out of scope).
- Custom context-actions editor UI (power-user TOML stays).
- Remote / network locations management UI beyond the existing "Connect" button.
- New shortcut conflict-detection UI (noted in A.1.3 as low-priority backlog — ship only if accidentally cheap during M2).
- Any new icons. If we need any UI icon we did not already have, register it in **both** `src/qml/icons/qmldir` AND `src/CMakeLists.txt` QML_FILES (per [[lessons-qt6-qml-wiring]] lesson 6). Do **not** import from Noctalia ([[feedback-no-noctalia-icons]]).

## Open questions / TBD-during-execution markers

These are the only items the audit could not pin from grep alone — each is resolved by inspecting the live app or running code during the milestone, not by additional brainstorming:

- KB dialog: presence of global "Reset all to defaults" button (verify in M2; add if missing).
- KB dialog: conflict detection on rebind (verify in M2; ship only if cheap).
- Settings: behavior of Cancel-without-Apply (verify in M3; fix if drafts leak).
- Settings: completeness of `resetToDefaults()` (verify in M3; extend if gaps).
- Settings: theme hot-swap on Apply, not only preview (verify in M6; fix if missing).
- M2: cost of plumbing `open` action through file-view delegates (decide during execution between `ADD_REBIND` and `LEAVE_VIEW_LOCAL`).
- M3: optional "Open config file in editor" button (ship only if Process plumbing is trivial).
