# P3 M1 — Cleanup hardcoded shortcuts + canonical naming

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove dead Ctrl+M / Ctrl+Shift+M shortcut blocks, rename action `split_view` → `toggle_merge` with config migration, and add rebindable `context_menu_alt` action (default Menu key) — without touching user-visible behavior of F3 toggle or the Menu key context-menu trigger.

**Architecture:** Two surfaces change. C++ side (`src/services/configmanager.cpp` + `.h`): registry entries renamed/added, load-path gains a silent one-shot key migration `split_view → toggle_merge`. QML side (`src/qml/Main.qml`): two legacy `Shortcut {}` blocks deleted, one rename of the shortcutMap key, one hardcoded `"Menu"` sequence replaced with a config-driven binding. TDD on the C++ side (`tests/tst_configmanager.cpp` already exists), build + qmllint + visual-OK on the QML side per [[feedback-verify-before-commit]].

**Tech Stack:** Qt6 / QML, C++23, CMake, Qt6::Test (QCOMPARE / QTemporaryDir / QFile), toml++ (header-only via `third_party/toml.hpp`).

**Spec reference:** `docs/superpowers/specs/2026-05-29-settings-shortcuts-polish-design.md` Chapter B → M1.

---

### Task 1: Rename action `split_view` → `toggle_merge` in the registry (TDD)

**Files:**
- Modify: `src/services/configmanager.cpp:21-62` (`kShortcutSpecs[]`), `src/services/configmanager.cpp:85-126` (`s_defaultShortcuts`)
- Test: `tests/tst_configmanager.cpp` (append new test slot before the closing `};`)

- [ ] **Step 1.1: Read the current state of the registry**

Confirm exact lines for the `split_view` entry in both `kShortcutSpecs` (currently around line 49: `{"split_view", "Toggle Split View"},`) and `s_defaultShortcuts` (currently around line 113: `{"split_view", "F3"},`). If line numbers have drifted, locate with `grep -n '"split_view"' src/services/configmanager.cpp`.

- [ ] **Step 1.2: Write failing test for the renamed action**

Append the following private slot to `tests/tst_configmanager.cpp`, just before the final `};` that closes `class TestConfigManager`:

```cpp
    void testToggleMergeActionRegistered()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        const QVariantMap shortcutMap = mgr.shortcutMap();
        QVERIFY2(shortcutMap.contains("toggle_merge"),
                 "Action 'toggle_merge' must be registered (renamed from split_view in P3 M1).");
        QCOMPARE(shortcutMap.value("toggle_merge").toString(), QString("F3"));

        QVERIFY2(!shortcutMap.contains("split_view"),
                 "Old action key 'split_view' must be gone from the registry.");

        const QVariantList defs = mgr.shortcutDefinitions();
        bool foundToggleMerge = false;
        for (const QVariant &v : defs) {
            const QVariantMap def = v.toMap();
            if (def.value("action").toString() == QLatin1String("toggle_merge")) {
                foundToggleMerge = true;
                QCOMPARE(def.value("label").toString(), QString("Merge / Unmerge Panes"));
                QCOMPARE(def.value("defaultSequence").toString(), QString("F3"));
                break;
            }
        }
        QVERIFY2(foundToggleMerge,
                 "shortcutDefinitions() must expose toggle_merge with label 'Merge / Unmerge Panes'.");
    }
```

- [ ] **Step 1.3: Build and run the test to confirm RED**

Run:

```bash
cmake --build build && ctest --test-dir build -R tst_configmanager --output-on-failure
```

Expected: `testToggleMergeActionRegistered` fails because the registry still contains `split_view`, not `toggle_merge`. The other tests in the suite still pass.

- [ ] **Step 1.4: Rename the registry entry in `kShortcutSpecs`**

In `src/services/configmanager.cpp` change the `split_view` row in `kShortcutSpecs[]` (around line 49) from:

```cpp
    {"split_view", "Toggle Split View"},
```

to:

```cpp
    {"toggle_merge", "Merge / Unmerge Panes"},
```

- [ ] **Step 1.5: Rename the default entry in `s_defaultShortcuts`**

In the same file, change the `split_view` row in `s_defaultShortcuts` (around line 113) from:

```cpp
    {"split_view", "F3"},
```

to:

```cpp
    {"toggle_merge", "F3"},
```

- [ ] **Step 1.6: Build and run the test to confirm GREEN**

Run:

```bash
cmake --build build && ctest --test-dir build -R tst_configmanager --output-on-failure
```

Expected: `testToggleMergeActionRegistered` passes. The full `tst_configmanager` suite is green.

**Do not commit yet — Tasks 2-4 are part of the same M1 milestone and ship as one atomic commit.**

---

### Task 2: One-shot migration of pre-existing TOML `split_view` key (TDD)

**Files:**
- Modify: `src/services/configmanager.cpp` (the load path, currently around lines 338-350)
- Test: `tests/tst_configmanager.cpp`

- [ ] **Step 2.1: Locate the load path that fills `m_shortcuts`**

The current shortcut load block lives around `src/services/configmanager.cpp:338-350`:

```cpp
if (auto tbl = config["shortcuts"].as_table()) {
    for (const auto &[key, val] : *tbl) {
        if (auto v = val.value<std::string>()) {
            m_shortcuts[QString::fromStdString(std::string(key))] =
                QString::fromStdString(*v);
        }
    }

    // Migrate the old default new-file shortcut so existing configs
    // pick up Ctrl+N unless the user chose a different custom binding.
    if (m_shortcuts.value(QStringLiteral("new_file")) == QStringLiteral("Ctrl+Alt+N"))
        m_shortcuts[QStringLiteral("new_file")] = s_defaultShortcuts.value(QStringLiteral("new_file"));
}
```

The new migration belongs right after the existing `new_file` migration (same idiom: silent, one-shot, gated on a precondition).

- [ ] **Step 2.2: Write failing test for the migration**

Append this private slot to `tests/tst_configmanager.cpp`:

```cpp
    void testMigrateSplitViewToToggleMerge_customValue()
    {
        QTemporaryDir dir;
        const QString cfgPath = dir.path() + "/config.toml";

        // Seed a config that pre-dates the rename: only the old key, with a
        // user-customized value (so the migration must preserve the value,
        // not just substitute the default).
        QFile f(cfgPath);
        QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Text));
        f.write("[shortcuts]\nsplit_view = \"Ctrl+J\"\n");
        f.close();

        ConfigManager mgr(cfgPath);

        const QVariantMap shortcutMap = mgr.shortcutMap();
        QCOMPARE(shortcutMap.value("toggle_merge").toString(), QString("Ctrl+J"));
        QVERIFY2(!shortcutMap.contains("split_view"),
                 "After migration, the old action key must not surface via shortcutMap().");
    }

    void testMigrateSplitViewToToggleMerge_doesNotOverwriteNewKey()
    {
        QTemporaryDir dir;
        const QString cfgPath = dir.path() + "/config.toml";

        // If a user has BOTH keys (e.g. partial manual edit), the new key
        // wins — migration must not clobber it.
        QFile f(cfgPath);
        QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Text));
        f.write("[shortcuts]\nsplit_view = \"Ctrl+J\"\ntoggle_merge = \"Ctrl+K\"\n");
        f.close();

        ConfigManager mgr(cfgPath);

        const QVariantMap shortcutMap = mgr.shortcutMap();
        QCOMPARE(shortcutMap.value("toggle_merge").toString(), QString("Ctrl+K"));
    }
```

- [ ] **Step 2.3: Build and run the new tests to confirm RED**

Run:

```bash
cmake --build build && ctest --test-dir build -R tst_configmanager --output-on-failure
```

Expected: both `testMigrateSplitViewToToggleMerge_*` tests fail (the first because `toggle_merge` is empty / falls back to default `F3`; the second similarly). The Task 1 test stays green; all other tests stay green.

- [ ] **Step 2.4: Implement the migration**

In `src/services/configmanager.cpp`, inside the `if (auto tbl = config["shortcuts"].as_table())` block, immediately after the existing `new_file` migration, add:

```cpp
        // P3 M1: rename action 'split_view' → 'toggle_merge'. Existing
        // configs that referenced the old key keep their custom value
        // under the new key. If the user already has 'toggle_merge'
        // (manual edit, partial state), we leave it alone. One-shot,
        // silent, idempotent: the next saveShortcuts() rewrites the
        // [shortcuts] table and drops 'split_view' on disk too.
        if (m_shortcuts.contains(QStringLiteral("split_view"))
            && !m_shortcuts.contains(QStringLiteral("toggle_merge"))) {
            m_shortcuts[QStringLiteral("toggle_merge")] =
                m_shortcuts.take(QStringLiteral("split_view"));
        } else {
            m_shortcuts.remove(QStringLiteral("split_view"));
        }
```

The `else` branch handles the "both keys present" case from the second test: drop the legacy key, keep the new one.

- [ ] **Step 2.5: Build and run the tests to confirm GREEN**

Run:

```bash
cmake --build build && ctest --test-dir build -R tst_configmanager --output-on-failure
```

Expected: both Task 2 tests pass. Task 1 test still passes. Full suite green.

---

### Task 3: Add new rebindable action `context_menu_alt` (TDD)

**Files:**
- Modify: `src/services/configmanager.cpp` (`kShortcutSpecs[]` and `s_defaultShortcuts`)
- Test: `tests/tst_configmanager.cpp`

- [ ] **Step 3.1: Write failing test for the new action**

Append this private slot to `tests/tst_configmanager.cpp`:

```cpp
    void testContextMenuAltActionRegistered()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        const QVariantMap shortcutMap = mgr.shortcutMap();
        QCOMPARE(shortcutMap.value("context_menu_alt").toString(), QString("Menu"));

        const QVariantList defs = mgr.shortcutDefinitions();
        bool found = false;
        for (const QVariant &v : defs) {
            const QVariantMap def = v.toMap();
            if (def.value("action").toString() == QLatin1String("context_menu_alt")) {
                found = true;
                QCOMPARE(def.value("label").toString(),
                         QString("Show Context Menu (Menu key)"));
                QCOMPARE(def.value("defaultSequence").toString(), QString("Menu"));
                break;
            }
        }
        QVERIFY2(found,
                 "shortcutDefinitions() must expose context_menu_alt with the Menu-key label.");
    }
```

- [ ] **Step 3.2: Build and run to confirm RED**

Run:

```bash
cmake --build build && ctest --test-dir build -R tst_configmanager --output-on-failure
```

Expected: `testContextMenuAltActionRegistered` fails because the action isn't registered. Tasks 1 + 2 tests stay green.

- [ ] **Step 3.3: Register the new action**

In `src/services/configmanager.cpp`, append the new spec to `kShortcutSpecs[]` (immediately after the existing `{"context_menu", "Show Context Menu"},` row, around line 44):

```cpp
    {"context_menu_alt", "Show Context Menu (Menu key)"},
```

Append the new default to `s_defaultShortcuts` (immediately after `{"context_menu", "Shift+F10"},` around line 108):

```cpp
    {"context_menu_alt", "Menu"},
```

- [ ] **Step 3.4: Build and run to confirm GREEN**

Run:

```bash
cmake --build build && ctest --test-dir build -R tst_configmanager --output-on-failure
```

Expected: all Task 1 / 2 / 3 tests pass. Full `tst_configmanager` suite green.

- [ ] **Step 3.5: Run the full test suite**

Run:

```bash
ctest --test-dir build --output-on-failure
```

Expected: every test in every `tst_*` binary passes. If anything outside `tst_configmanager` breaks, investigate before continuing — the C++ changes so far are additive + renamings; nothing should regress.

---

### Task 4: Update `Main.qml` to match the new registry (no TDD — build + qmllint + visual-OK)

**Files:**
- Modify: `src/qml/Main.qml`

QML changes have no automated test harness in this repo (per CLAUDE.md the Qt6::Test suites are C++-only). Verification is build + qmllint + the user's visual-OK gate at Task 5.

- [ ] **Step 4.1: Delete the legacy Ctrl+M block**

In `src/qml/Main.qml`, locate (around lines 2947-2953):

```qml
    // Phase 2 P2-M4 temporary trigger: Ctrl+M collapses the current Ctrl-
    // click selection into a supertab.  P2-M5 will replace this with a
    // chain-link merge button in the toolbar.
    Shortcut {
        sequence: "Ctrl+M"
        onActivated: tabModel.mergeSelected()
    }
```

Delete the entire block including the three-line preamble comment (the comment refers to a since-shipped P2-M5 milestone and would rot in place).

- [ ] **Step 4.2: Delete the legacy Ctrl+Shift+M block**

Immediately below the just-deleted block, locate (was around lines 2955-2961):

```qml
    // Phase 2 P2-M8 temporary trigger: Ctrl+Shift+M dissolves the active
    // supertab back into its constituent tabs.  Same toolbar button as
    // merge will likely host this too (chain-link toggle).
    Shortcut {
        sequence: "Ctrl+Shift+M"
        onActivated: tabModel.unmergeActive()
    }
```

Delete the entire block including the three-line preamble comment.

- [ ] **Step 4.3: Rename the `split_view` shortcutMap key in Main.qml**

Locate the F3 binding (was around line 3034). Change:

```qml
    Shortcut {
        sequence: config.shortcutMap["split_view"]
        onActivated: root.toggleMergeOrUnmerge()
    }
```

to:

```qml
    Shortcut {
        sequence: config.shortcutMap["toggle_merge"]
        onActivated: root.toggleMergeOrUnmerge()
    }
```

Sanity grep after the edit: `grep -n '"split_view"' src/qml/Main.qml` must return no matches.

- [ ] **Step 4.4: Replace the hardcoded Menu-key block**

Locate (was around lines 3161-3164):

```qml
    Shortcut {
        sequence: "Menu"
        onActivated: root.showContextMenuForActiveSelection()
    }
```

Replace with:

```qml
    Shortcut {
        sequence: config.shortcutMap["context_menu_alt"]
        onActivated: root.showContextMenuForActiveSelection()
    }
```

- [ ] **Step 4.5: Confirm the build is clean**

Run:

```bash
cmake --build build
```

Expected: full build succeeds, no new warnings.

- [ ] **Step 4.6: Run qmllint on the changed file**

Run:

```bash
qmllint src/qml/Main.qml
```

Expected: no new warnings introduced by the edits. Pre-existing warnings (if any) stay the same. If a new warning appears, fix before continuing.

- [ ] **Step 4.7: Run the full test suite once more**

Run:

```bash
ctest --test-dir build --output-on-failure
```

Expected: all `tst_*` binaries pass. (The Main.qml changes don't touch C++ test paths but the cmake build needs to be clean end-to-end before handing off for visual-OK.)

---

### Task 5: User visual-OK gate + commit

**Files:** none (this is the verify + commit step).

- [ ] **Step 5.1: Hand the visual-OK checklist to the user**

Present, verbatim, the M1 verify-gate checklist from the spec:

> Please launch Heimdall and confirm the following before I commit:
>
> 1. F3 still toggles merge ↔ unmerge of panes (no regression).
> 2. Pressing Ctrl+M does nothing (legacy block gone).
> 3. Pressing Ctrl+Shift+M does nothing (legacy block gone).
> 4. Pressing the dedicated Menu key on the keyboard opens the context menu for the current selection (same behavior as before, now routed through `config.shortcutMap["context_menu_alt"]`).
> 5. Open the Keyboard Shortcuts dialog: there is a row labelled **"Merge / Unmerge Panes"** with combo `F3`, and a row labelled **"Show Context Menu (Menu key)"** with combo `Menu`. There is NO row labelled "Toggle Split View".
> 6. (Migration check, optional but valuable) Before launching, edit `~/.config/heimdall/config.toml` and add:
>
>    ```toml
>    [shortcuts]
>    split_view = "Ctrl+J"
>    ```
>
>    Launch Heimdall. Open KB dialog: row "Merge / Unmerge Panes" must show combo `Ctrl+J`. Press `Ctrl+J` in the file view — it should toggle merge/unmerge. F3 should NOT trigger merge in this session (the user-customized combo replaced the default).

**Wait for the user to explicitly confirm.** Do not move to Step 5.2 on assumption.

- [ ] **Step 5.2: Stage the changes**

Once the user has explicitly confirmed all visual-OK items, run:

```bash
git add src/services/configmanager.cpp tests/tst_configmanager.cpp src/qml/Main.qml
```

Tasks 1-3 only touch the `.cpp` file (kShortcutSpecs / s_defaultShortcuts edits and inline migration logic — no new methods). `configmanager.h` stays unchanged. Confirm the staged set with:

```bash
git diff --cached --stat
```

Expected: exactly 3 files modified, no untracked files staged. Spec / plan files stay out of this commit.

- [ ] **Step 5.3: Create the commit**

Run:

```bash
git commit -m "$(cat <<'EOF'
feat(p3,M1): cleanup hardcoded shortcuts + rename split_view->toggle_merge

- Delete legacy Ctrl+M and Ctrl+Shift+M Shortcut blocks (P2-M4/M8 temp
  triggers, superseded by the chain-link toolbar button + F3 toggle).
- Rename registry action 'split_view' to 'toggle_merge' with label
  'Merge / Unmerge Panes'. Default sequence stays F3.
- Migrate pre-existing user configs: on load, if [shortcuts] split_view
  exists and toggle_merge does not, move the value under the new key.
  Silent, one-shot, idempotent.
- Add new rebindable action 'context_menu_alt' (default Menu key) and
  replace the previously hardcoded 'Menu' Shortcut block with a
  config-driven binding.

Tests cover the rename, the migration (custom value preserved, new key
wins when both present), and the new action's registration. QML changes
verified by build + qmllint + user visual-OK.

Spec: docs/superpowers/specs/2026-05-29-settings-shortcuts-polish-design.md (M1)
EOF
)"
```

Expected: clean commit, no hook failures.

- [ ] **Step 5.4: Confirm the working tree is clean**

Run:

```bash
git log --oneline -3 && git status
```

Expected: the new M1 commit is at HEAD; working tree clean; no surprise untracked files.

- [ ] **Step 5.5: M1 done — hand off to the next milestone session**

M1 is complete. The next session writes the M2 plan (registry grouping + dialog UI + `open` action plumbing decision) from the same spec. Per the spec workflow, do not start M2 in this session — let the user decide whether to continue immediately or pause.

Tell the user:

> M1 shipped on commit `<hash>`. Spec milestone M2 is next (KB dialog grouping + "Reset all" verification + `open` action plumbing). Want me to write the M2 plan now, or pause here?
