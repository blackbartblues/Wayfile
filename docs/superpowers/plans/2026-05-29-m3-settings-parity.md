# P3 M3 — Settings Parity (wire dead keys + builtinIcons UI + bookmarks hint + reset confirm)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Settings control map to a config key that actually works: persist `default_view`/`sort_by`/`sort_ascending`, make new tabs honor them, add a `builtinIcons` toggle, surface the three new defaults + builtin-icons in the panel, add a bookmarks-managed-from-sidebar hint, and gate "Reset to Defaults" behind a two-click confirm (covering the newly added keys).

**Architecture:** Three layers. **C++ (`configmanager.cpp`)**: `saveSettings()` learns to persist `default_view`/`sort_by`/`sort_ascending` in the `[general]` table (loadConfig already reads them; only the write path is missing). **QML wiring (`Main.qml`)**: a new `createTabWithDefaults()` helper seeds each new tab's `viewMode`/`sortBy`/`sortAscending` from `config`, routed through all four `addTab()` call sites — without it the three keys are dead (nothing consumes them). **QML UI (`SettingsPanel.qml`)**: draft properties + `currentSettings()` + `syncFromCurrentState()` + `resetToDefaults()` gain the four keys (`builtinIcons` + the three sort/view defaults), three new Layout-section controls, a `builtinIcons` toggle in Look & Feel, a bookmarks hint in Tools, and a two-click confirm on the Reset button.

**Tech Stack:** Qt6 / QML, C++23, CMake, Qt6::Test, Quill (`Q.Dropdown` takes a plain string array + emits `selected(index, value)`; `Q.Toggle`/`Q.Checkbox`/`Q.Button`).

**Spec reference:** `docs/superpowers/specs/2026-05-29-settings-shortcuts-polish-design.md` Chapter B → M3. **Audit corrections discovered during planning (recorded here so the spec's A.2.1 row notes don't mislead):**
- `builtinIcons` is **not** an empty-label toggle (audit said line 422 — that's the *Dark Mode* toggle). It has **no UI at all**. C++ persists+reads it and it is consumed widely (icon URLs). → genuine `ADD_UI`.
- `animationsEnabled` is **fine** — its toggle (line ~745) has a sibling "Animations" `Text` label (same Row-label idiom as Dark Mode). No label fix needed; **dropped from M3**.
- `default_view`/`sort_by`/`sort_ascending` are **dead keys**: `loadConfig` reads them, Q_PROPERTYs expose them, but **nothing consumes them** and `TabListModel` has no `ConfigManager`. New tabs use hardcoded `TabModel` struct defaults. Per user decision (2026-05-29) M3 **wires them for real** via a QML new-tab seeder, then adds UI.
- Apply model is **live-apply** (every change → immediate `saveSettings`; no Apply/Cancel buttons). The spec's "Cancel discards edits" item is **N/A** — there is no Cancel, by design. We do **not** invent one ([[feedback-dry-no-duplicate-systems]]: don't add a parallel apply model).

---

### Task 1: Persist `default_view` / `sort_by` / `sort_ascending` in `saveSettings()` (TDD)

**Files:**
- Modify: `src/services/configmanager.cpp` (`saveSettings`, the `[general]` block around lines 487-516)
- Test: `tests/tst_configmanager.cpp`

- [ ] **Step 1.1: Write the failing round-trip test**

Append this slot to `tests/tst_configmanager.cpp` before the closing `};`:

```cpp
    // --- P3 M3: persist default_view / sort_by / sort_ascending ---

    void testSaveViewAndSortDefaults()
    {
        QTemporaryDir dir;
        const QString path = dir.path() + "/config.toml";

        ConfigManager mgr(path);
        mgr.saveSettings(QVariantMap{
            {"defaultView", "detailed"},
            {"sortBy", "size"},
            {"sortAscending", false}
        });

        // Fresh instance against the same file must restore the values.
        ConfigManager mgr2(path);
        QCOMPARE(mgr2.defaultView(), QString("detailed"));
        QCOMPARE(mgr2.sortBy(), QString("size"));
        QCOMPARE(mgr2.sortAscending(), false);
    }

    void testSaveViewDefaultsRejectsEmptyStrings()
    {
        QTemporaryDir dir;
        const QString path = dir.path() + "/config.toml";

        ConfigManager mgr(path);
        // Empty strings must not overwrite the sensible defaults.
        mgr.saveSettings(QVariantMap{
            {"defaultView", ""},
            {"sortBy", ""}
        });

        ConfigManager mgr2(path);
        QCOMPARE(mgr2.defaultView(), QString("grid"));
        QCOMPARE(mgr2.sortBy(), QString("name"));
    }
```

- [ ] **Step 1.2: Build and confirm RED**

Run:

```bash
cmake --build build && ctest --test-dir build -R tst_configmanager --output-on-failure
```

Expected: `testSaveViewAndSortDefaults` fails (mgr2 still returns "grid"/"name"/true because saveSettings never wrote the keys). `testSaveViewDefaultsRejectsEmptyStrings` passes trivially (defaults unchanged) but stays as a guard. Existing tests green.

- [ ] **Step 1.3: Add the persistence to `saveSettings()`**

In `src/services/configmanager.cpp`, inside the `[general]` block, immediately after the `showHidden` handler (around line 516, before `if (!general.empty())`), add:

```cpp
    if (settings.contains("defaultView")) {
        const QString view = settings.value("defaultView").toString().trimmed();
        if (!view.isEmpty()) {
            m_defaultView = view;
            general.insert_or_assign("default_view", view.toStdString());
        }
    }

    if (settings.contains("sortBy")) {
        const QString sortBy = settings.value("sortBy").toString().trimmed();
        if (!sortBy.isEmpty()) {
            m_sortBy = sortBy;
            general.insert_or_assign("sort_by", sortBy.toStdString());
        }
    }

    if (settings.contains("sortAscending")) {
        m_sortAscending = settings.value("sortAscending").toBool();
        general.insert_or_assign("sort_ascending", m_sortAscending);
    }
```

- [ ] **Step 1.4: Build and confirm GREEN**

Run:

```bash
cmake --build build && ctest --test-dir build -R tst_configmanager --output-on-failure
```

Expected: both Task 1 tests pass. Full `tst_configmanager` suite green.

**Do not commit yet — M3 is one milestone, one commit. Tasks 2-6 follow.**

---

### Task 2: Seed new tabs from config defaults via a QML wrapper (`Main.qml`)

**Files:**
- Modify: `src/qml/Main.qml` (add helper near `openPathInNewTab` at line ~615; reroute four `addTab()` call sites: `Main.qml:620`, `Main.qml:880`, `Main.qml:2934`, `src/qml/components/TabBar.qml:742`)

This is what makes `default_view`/`sort_by`/`sort_ascending` real. No automated test (QML behavior, verified by visual-OK at Task 6: open a new tab → it uses the configured defaults). Session restore is unaffected — it goes through the restore path, not `addTab()`.

- [ ] **Step 2.1: Add the `createTabWithDefaults()` helper**

In `src/qml/Main.qml`, immediately before `function openPathInNewTab(path)` (line ~615), add:

```qml
    // Spawn a new tab and seed its view/sort from the configured defaults.
    // TabModel's own defaults are hardcoded (grid / name / ascending); this
    // is the single point where config.defaultView/sortBy/sortAscending
    // actually take effect. Session restore does NOT go through here, so
    // restored tabs keep their saved view/sort.
    function createTabWithDefaults() {
        tabModel.addTab()
        if (tabModel.activeTab) {
            tabModel.activeTab.viewMode = config.defaultView
            tabModel.activeTab.sortBy = config.sortBy
            tabModel.activeTab.sortAscending = config.sortAscending
        }
    }
```

- [ ] **Step 2.2: Route `openPathInNewTab` through the helper**

In `src/qml/Main.qml` (line ~620), change:

```qml
    function openPathInNewTab(path) {
        if (!path)
            return

        root.setPaneRecents(root.activePaneIndex, false)
        tabModel.addTab()
        if (tabModel.activeTab)
            tabModel.activeTab.navigateTo(path)
        root.scheduleActivePaneFocus()
    }
```

to:

```qml
    function openPathInNewTab(path) {
        if (!path)
            return

        root.setPaneRecents(root.activePaneIndex, false)
        root.createTabWithDefaults()
        if (tabModel.activeTab)
            tabModel.activeTab.navigateTo(path)
        root.scheduleActivePaneFocus()
    }
```

- [ ] **Step 2.3: Route the last-tab respawn (Main.qml ~880)**

Read the surrounding block first: `grep -n "addTab" src/qml/Main.qml` and open the line-880 site. It is inside the `onLastTabClosed`-style respawn ("Lone tab. Spawn a fresh one"). Change that single `tabModel.addTab()` to `root.createTabWithDefaults()`. (A freshly respawned tab should honor the user's defaults too.)

- [ ] **Step 2.4: Route the new_tab shortcut (Main.qml ~2934)**

Change:

```qml
        onActivated: tabModel.addTab()
```

to:

```qml
        onActivated: root.createTabWithDefaults()
```

(This is the `config.shortcutMap["new_tab"]` Shortcut block.)

- [ ] **Step 2.5: Route the TabBar "+" button**

In `src/qml/components/TabBar.qml` (line ~742), the "+" button does `onClicked: tabModel.addTab()`. TabBar does not have `root`-level access to `createTabWithDefaults`. Check how TabBar reaches Main — it likely emits a signal or has a `mainWindow`/callback property. Grep `grep -n "signal\|addTab\|tabModel" src/qml/components/TabBar.qml`. If TabBar already references `tabModel` directly (a context property), it cannot call the Main.qml helper. Two options, pick the one matching the existing pattern:
  - **Preferred:** add a signal to TabBar — `signal newTabRequested()` — change the "+" handler to `onClicked: root.newTabRequested()` (TabBar's own root), and in `Main.qml` where `TabBar { ... }` is instantiated, wire `onNewTabRequested: root.createTabWithDefaults()`.
  - **If TabBar already calls other Main functions via a property** (e.g. a `mainController`), follow that same channel.

Grep for the `TabBar {` instantiation in `Main.qml` (`grep -n "TabBar {" src/qml/Main.qml`) to add the handler. Implement the signal route, leaving `tabModel.addTab()` only inside the wrapper.

- [ ] **Step 2.6: Verify no `addTab()` call bypasses the seeder**

Run:

```bash
grep -rn "addTab()" src/qml/
```

Expected: the ONLY remaining `tabModel.addTab()` is inside `createTabWithDefaults()` in `Main.qml`. Every other site calls `createTabWithDefaults()` (or routes a signal to it). If any direct `addTab()` remains at a user-facing new-tab trigger, reroute it.

- [ ] **Step 2.7: Build + qmllint**

Run:

```bash
cmake --build build && qmllint src/qml/Main.qml src/qml/components/TabBar.qml
```

Expected: clean build, no qmllint output.

---

### Task 3: `builtinIcons` toggle in Look & Feel (`SettingsPanel.qml`)

**Files:**
- Modify: `src/qml/components/SettingsPanel.qml` (default props ~line 48; draft props ~line 84; `resetToDefaults` ~226; `syncFromCurrentState` ~280; `currentSettings` ~345; the Look & Feel "Icon Pack" dropdown region ~464)

- [ ] **Step 3.1: Add default + draft properties for builtinIcons**

In `src/qml/components/SettingsPanel.qml`, add a default near the other `readonly property ... default*` block (after line 49, `defaultWindowButtonLayout`):

```qml
    readonly property bool defaultBuiltinIcons: true
```

Add a draft property after `draftIconTheme` (line ~67):

```qml
    property bool draftBuiltinIcons: config.builtinIcons
```

- [ ] **Step 3.2: Include builtinIcons in `currentSettings()`**

In `currentSettings()` (line ~327), add `builtinIcons` next to `iconTheme`:

```qml
            iconTheme: draftIconTheme,
            builtinIcons: draftBuiltinIcons,
```

- [ ] **Step 3.3: Sync builtinIcons in `syncFromCurrentState()`**

After `draftIconTheme = config.iconTheme` (line ~262), add:

```qml
            draftBuiltinIcons = config.builtinIcons
```

- [ ] **Step 3.4: Reset builtinIcons in `resetToDefaults()`**

After `draftIconTheme = defaultIconThemeName` (line ~229), add:

```qml
        draftBuiltinIcons = defaultBuiltinIcons
```

- [ ] **Step 3.5: Add the toggle in Look & Feel after "Icon Pack"**

In the `lookPageComponent`, immediately after the "Icon Pack" `Q.Dropdown` (closes at line ~473), add:

```qml
            Q.Toggle {
                Layout.fillWidth: true
                label: "Use built-in icons as fallback"
                checked: root.draftBuiltinIcons
                onToggled: (value) => {
                    root.draftBuiltinIcons = value
                    root.applySettingsNow()
                }
            }
```

- [ ] **Step 3.6: Build + qmllint**

Run:

```bash
cmake --build build && qmllint src/qml/components/SettingsPanel.qml
```

Expected: clean build, no qmllint output.

---

### Task 4: `default_view` / `sort_by` / `sort_ascending` controls in Layout section (`SettingsPanel.qml`)

**Files:**
- Modify: `src/qml/components/SettingsPanel.qml` (default props ~48; draft props ~84; option arrays near `curveOptions` ~86; `resetToDefaults`; `syncFromCurrentState`; `currentSettings`; the `layoutPageComponent` "Browsing" section ~566-581)

- [ ] **Step 4.1: Add defaults + draft props + option arrays**

Add defaults near the other `default*` props (after `defaultBuiltinIcons` from Task 3):

```qml
    readonly property string defaultView: "grid"
    readonly property string defaultSortBy: "name"
    readonly property bool defaultSortAscending: true
```

Add draft props after `draftBuiltinIcons` (Task 3.1):

```qml
    property string draftDefaultView: config.defaultView
    property string draftSortBy: config.sortBy
    property bool draftSortAscending: config.sortAscending
```

Add label/value arrays near `curveOptions` (line ~86):

```qml
    readonly property var viewModeValues: ["grid", "miller", "detailed"]
    readonly property var viewModeLabels: ["Grid", "Miller columns", "Detailed list"]
    readonly property var sortByValues: ["name", "size", "modified", "type"]
    readonly property var sortByLabels: ["Name", "Size", "Date modified", "Type"]
```

- [ ] **Step 4.2: Include the three keys in `currentSettings()`**

In `currentSettings()`, add after `showHidden: draftShowHidden,`:

```qml
            defaultView: draftDefaultView,
            sortBy: draftSortBy,
            sortAscending: draftSortAscending,
```

- [ ] **Step 4.3: Sync in `syncFromCurrentState()`**

After `draftShowHidden = currentShowHidden` (line ~265), add:

```qml
            draftDefaultView = config.defaultView
            draftSortBy = config.sortBy
            draftSortAscending = config.sortAscending
```

- [ ] **Step 4.4: Reset in `resetToDefaults()`**

After `draftShowHidden = false` (line ~230), add:

```qml
        draftDefaultView = defaultView
        draftSortBy = defaultSortBy
        draftSortAscending = defaultSortAscending
```

- [ ] **Step 4.5: Add the three controls to the "Browsing" section**

In `layoutPageComponent`, immediately after the "Show hidden files" `Q.Checkbox` (closes at line ~581), add:

```qml
            Q.Dropdown {
                Layout.fillWidth: true
                label: "Default view for new tabs"
                model: root.viewModeLabels
                currentIndex: Math.max(0, root.viewModeValues.indexOf(root.draftDefaultView))
                onSelected: (index, _) => {
                    root.draftDefaultView = root.viewModeValues[index]
                    root.applySettingsNow()
                }
            }

            Q.Dropdown {
                Layout.fillWidth: true
                label: "Default sort for new tabs"
                model: root.sortByLabels
                currentIndex: Math.max(0, root.sortByValues.indexOf(root.draftSortBy))
                onSelected: (index, _) => {
                    root.draftSortBy = root.sortByValues[index]
                    root.applySettingsNow()
                }
            }

            Q.Toggle {
                Layout.fillWidth: true
                label: "Sort ascending by default"
                checked: root.draftSortAscending
                onToggled: (value) => {
                    root.draftSortAscending = value
                    root.applySettingsNow()
                }
            }
```

- [ ] **Step 4.6: Build + qmllint**

Run:

```bash
cmake --build build && qmllint src/qml/components/SettingsPanel.qml
```

Expected: clean build, no qmllint output.

---

### Task 5: Bookmarks hint in Tools + two-click confirm on "Reset to Defaults"

**Files:**
- Modify: `src/qml/components/SettingsPanel.qml` (Tools section `toolsPageComponent` ~857; the "Reset to Defaults" `Q.Button` ~997-1004; add a `confirmReset` property + timer)

- [ ] **Step 5.1: Add a bookmarks hint row to the Tools "Utilities" section**

In `toolsPageComponent` (the `ColumnLayout` starting line ~859), after the dependency-check `RowLayout` (closes ~902), add:

```qml
            Text {
                text: "Bookmarks"
                color: Theme.accent
                font.pointSize: Theme.fontSmall
                font.bold: true
                Layout.topMargin: 12
                Layout.bottomMargin: 4
            }

            Text {
                Layout.fillWidth: true
                text: "Pinned folders are managed from the sidebar — right-click a folder and choose Pin (or drag it onto the sidebar). They live in one place, so there is no separate editor here."
                color: Theme.subtext
                font.pointSize: Theme.fontSmall
                wrapMode: Text.WordWrap
            }
```

(This satisfies the spec's DRY requirement: the sidebar context-menu pin is the single canonical bookmark editor; Settings only points at it — [[feedback-dry-no-duplicate-systems]].)

- [ ] **Step 5.2: Add confirm state + auto-cancel timer**

Near the top-level property declarations (after the `pendingSettingsDirty` property, line ~63), add:

```qml
    property bool confirmReset: false
```

Find the `settingsApplyTimer` Timer (`grep -n "id: settingsApplyTimer" src/qml/components/SettingsPanel.qml`) and add a sibling timer right after it:

```qml
    Timer {
        id: resetConfirmTimer
        interval: 3000
        repeat: false
        onTriggered: root.confirmReset = false
    }
```

- [ ] **Step 5.3: Clear confirm state when the panel closes**

In `closePanel()` (line ~302), add `confirmReset = false` and stop the timer:

```qml
    function closePanel() {
        confirmReset = false
        resetConfirmTimer.stop()
        flushPendingChanges()
        root.hide()
        root.closed()
    }
```

- [ ] **Step 5.4: Convert the Reset button to two-click confirm**

Replace the "Reset to Defaults" `Q.Button` (lines ~997-1004):

```qml
                            Q.Button {
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                Layout.rightMargin: 12
                                Layout.topMargin: 8
                                text: "Reset to Defaults"
                                variant: "ghost"
                                onClicked: root.resetToDefaults()
                            }
```

with:

```qml
                            Q.Button {
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                Layout.rightMargin: 12
                                Layout.topMargin: 8
                                text: root.confirmReset
                                    ? "Click again to confirm reset"
                                    : "Reset to Defaults"
                                variant: "ghost"
                                onClicked: {
                                    if (root.confirmReset) {
                                        root.confirmReset = false
                                        resetConfirmTimer.stop()
                                        root.resetToDefaults()
                                    } else {
                                        root.confirmReset = true
                                        resetConfirmTimer.restart()
                                    }
                                }
                            }
```

- [ ] **Step 5.5: Build + qmllint**

Run:

```bash
cmake --build build && qmllint src/qml/components/SettingsPanel.qml
```

Expected: clean build, no qmllint output.

---

### Task 6: Full sanity suite, visual-OK gate, commit

**Files:** none.

- [ ] **Step 6.1: Run the non-flaky sanity suite**

```bash
ctest --test-dir build -R "tst_configmanager|tst_themeloader|tst_tabmodel|tst_filesystemmodel|tst_bookmarkmodel|tst_clipboardmanager|tst_undomanager|tst_iconprovider|tst_devicemodel" --output-on-failure
```

Expected: 9/9 pass (includes the two new Task 1 tests inside `tst_configmanager`).

- [ ] **Step 6.2: Hand the visual-OK checklist to the user**

Present, verbatim:

> Launch Heimdall and confirm before I commit:
>
> 1. **Settings → Look & Feel**: a new toggle "Use built-in icons as fallback" appears under Icon Pack. Toggle it off → some icons that relied on the built-in set change/disappear (or no visible change if your icon theme covers everything); toggle on → restored. Value survives restart.
> 2. **Settings → Layout → Browsing**: three new controls — "Default view for new tabs" (Grid / Miller columns / Detailed list), "Default sort for new tabs" (Name / Size / Date modified / Type), "Sort ascending by default" toggle.
> 3. Set Default view = **Detailed list**, Default sort = **Size**, ascending **off**. Close Settings.
> 4. Open a **new tab** (Ctrl+T, the + button, AND via "open in new tab" on a folder) → each new tab opens in **Detailed list**, sorted by **Size descending**. Existing/old tabs are unchanged.
> 5. Restart Heimdall → open a new tab → still Detailed/Size/descending (persisted).
> 6. **Settings → Tools**: a "Bookmarks" hint explains pinned folders are managed from the sidebar (no editor in Settings).
> 7. **Reset to Defaults** (Tools): first click changes the button to "Click again to confirm reset"; wait 3 s → reverts silently; click twice quickly → all settings (including the new view/sort/builtin-icons) snap back to defaults.
> 8. After reset, open a new tab → back to Grid / Name / ascending.

Wait for explicit confirmation. Do not commit on assumption.

- [ ] **Step 6.3: Stage and commit**

```bash
git add src/services/configmanager.cpp tests/tst_configmanager.cpp src/qml/Main.qml src/qml/components/TabBar.qml src/qml/components/SettingsPanel.qml
git diff --cached --stat
```

Expected: 5 files (configmanager.cpp, tst_configmanager.cpp, Main.qml, TabBar.qml, SettingsPanel.qml). If Task 2.5 didn't need a TabBar.qml change (TabBar reached Main differently), it's 4 files — adjust the `git add` accordingly.

```bash
git commit -m "$(cat <<'EOF'
feat(p3,M3): settings parity — wire view/sort defaults, builtin-icons toggle

- saveSettings now persists default_view / sort_by / sort_ascending in
  [general] (loadConfig already read them; the write path was missing).
- New tabs honor the configured defaults: createTabWithDefaults() in
  Main.qml seeds viewMode/sortBy/sortAscending from config and is routed
  through every new-tab trigger (shortcut, + button, open-in-new-tab,
  last-tab respawn). These three config keys were previously dead —
  read from TOML, exposed as Q_PROPERTYs, consumed by nothing.
- SettingsPanel: add "Use built-in icons as fallback" toggle (Look &
  Feel) and "Default view / Default sort / Sort ascending" controls
  (Layout → Browsing). All four wired through draft props,
  currentSettings(), syncFromCurrentState(), and resetToDefaults().
- Tools section gains a bookmarks hint pointing at the sidebar pin (the
  single canonical bookmark editor — no parallel UI).
- "Reset to Defaults" now needs a two-click confirm (3 s auto-cancel),
  matching the keyboard-shortcuts dialog idiom.

New saveSettings round-trip covered by tests. QML verified by build +
qmllint + user visual-OK (builtin-icons toggle, new-tab view/sort
defaults applied + persisted, bookmarks hint, reset confirm).

Spec: docs/superpowers/specs/2026-05-29-settings-shortcuts-polish-design.md (M3)
EOF
)"
```

- [ ] **Step 6.4: Confirm clean tree**

```bash
git log --oneline -3 && git status
```

Expected: M3 commit at HEAD, working tree clean.

- [ ] **Step 6.5: Hand off**

> M3 shipped on `<hash>`. Next is M4 (visible descriptions on every Settings control — ~22 one-line descriptions). Want the M4 plan now, or pause?
