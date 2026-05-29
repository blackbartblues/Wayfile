# P3 M2 — Shortcut Registry Hardening (group + rebindable + grouped dialog + Reset All)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `group` and `rebindable` fields to the shortcut registry, expose them via `shortcutDefinitions()`, render the Keyboard Shortcuts dialog as grouped sections (Tabs / Navigation / Panes / View / Selection / File / Application), mark the `open` action as view-local non-rebindable, and add a "Reset all to defaults" footer button with two-click confirm.

**Architecture:** Two surfaces change. C++ side (`src/services/configmanager.cpp` + `.h`): `ShortcutSpec` struct gains two fields, all 41 entries get populated, `kShortcutSpecs[]` is reordered to be group-contiguous in the target display order, and `shortcutDefinitions()` surfaces the new fields. QML side (`src/qml/components/KeyboardShortcutsDialog.qml`): flat Repeater is replaced with a group-aware delegate that emits a section header on group transitions, the `open` row gets a non-rebindable visual variant, and the footer gains a "Reset all to defaults" button with a 2-click confirm idiom. TDD on the C++ side, build + qmllint + user visual-OK on the QML side per [[feedback-verify-before-commit]].

**Tech Stack:** Qt6 / QML, C++23, CMake, Qt6::Test (QCOMPARE / QVERIFY / QSet), Quill component library.

**Spec reference:** `docs/superpowers/specs/2026-05-29-settings-shortcuts-polish-design.md` Chapter B → M2. The `open` action disposition reverses the spec's default of "ADD_REBIND" because Qt's Shortcut binding is global and `open` is fundamentally view-local — making `Return` global would fire fileActivated from any focused view including text inputs (path bar, rename dialog). KEEP_FILE_LOCAL with a non-rebindable registry entry that documents the view-local behavior is the correct decision; see Plan §Task 2 for the rendering treatment.

---

### Task 1: Extend `ShortcutSpec` with `group` field, populate, expose (TDD)

**Files:**
- Modify: `src/services/configmanager.cpp` (struct `ShortcutSpec` at line 16-19, `kShortcutSpecs[]` at lines 21-62, `shortcutDefinitions()` at lines 401-417)
- Test: `tests/tst_configmanager.cpp` (append before the closing `};`)

- [ ] **Step 1.1: Read the current ShortcutSpec and registry order**

Confirm with `grep -nA3 "struct ShortcutSpec" src/services/configmanager.cpp` that the struct still has the form:

```cpp
struct ShortcutSpec {
    const char *action;
    const char *label;
};
```

Confirm with `grep -nB1 -A1 "kShortcutSpecs\[\]" src/services/configmanager.cpp` that the array literal is in the legacy "by-feature" order (open, back, forward, ...).

- [ ] **Step 1.2: Write the failing test for `group` field exposure**

Append the following private slot to `tests/tst_configmanager.cpp` just before the closing `};` of class `TestConfigManager`:

```cpp
    // --- P3 M2: registry group field ---

    void testEveryActionHasGroup()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        const QSet<QString> kAllowedGroups = {
            QStringLiteral("Tabs"),
            QStringLiteral("Navigation"),
            QStringLiteral("Panes"),
            QStringLiteral("View"),
            QStringLiteral("Selection"),
            QStringLiteral("File"),
            QStringLiteral("Application")
        };

        const QVariantList defs = mgr.shortcutDefinitions();
        QVERIFY(!defs.isEmpty());

        for (const QVariant &v : defs) {
            const QVariantMap def = v.toMap();
            const QString action = def.value("action").toString();
            const QString group = def.value("group").toString();
            QVERIFY2(!group.isEmpty(),
                     qPrintable(QStringLiteral("Action '%1' must have a non-empty group").arg(action)));
            QVERIFY2(kAllowedGroups.contains(group),
                     qPrintable(QStringLiteral("Action '%1' has unexpected group '%2'").arg(action, group)));
        }
    }

    void testKnownActionsHaveExpectedGroups()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        const QMap<QString, QString> expected = {
            // Tabs
            {QStringLiteral("new_tab"), QStringLiteral("Tabs")},
            {QStringLiteral("close_tab"), QStringLiteral("Tabs")},
            {QStringLiteral("reopen_tab"), QStringLiteral("Tabs")},
            {QStringLiteral("open_in_new_tab"), QStringLiteral("Tabs")},
            {QStringLiteral("open_in_split"), QStringLiteral("Tabs")},
            // Navigation
            {QStringLiteral("back"), QStringLiteral("Navigation")},
            {QStringLiteral("forward"), QStringLiteral("Navigation")},
            {QStringLiteral("parent"), QStringLiteral("Navigation")},
            {QStringLiteral("home"), QStringLiteral("Navigation")},
            {QStringLiteral("refresh"), QStringLiteral("Navigation")},
            {QStringLiteral("path_bar"), QStringLiteral("Navigation")},
            // Panes
            {QStringLiteral("toggle_merge"), QStringLiteral("Panes")},
            {QStringLiteral("focus_left_pane"), QStringLiteral("Panes")},
            {QStringLiteral("focus_right_pane"), QStringLiteral("Panes")},
            {QStringLiteral("focus_next_pane"), QStringLiteral("Panes")},
            {QStringLiteral("focus_previous_pane"), QStringLiteral("Panes")},
            {QStringLiteral("toggle_sidebar"), QStringLiteral("Panes")},
            // View
            {QStringLiteral("grid_view"), QStringLiteral("View")},
            {QStringLiteral("miller_view"), QStringLiteral("View")},
            {QStringLiteral("detailed_view"), QStringLiteral("View")},
            {QStringLiteral("toggle_hidden"), QStringLiteral("View")},
            {QStringLiteral("quick_preview"), QStringLiteral("View")},
            // Selection
            {QStringLiteral("select_all"), QStringLiteral("Selection")},
            {QStringLiteral("context_menu"), QStringLiteral("Selection")},
            {QStringLiteral("context_menu_alt"), QStringLiteral("Selection")},
            // File
            {QStringLiteral("open"), QStringLiteral("File")},
            {QStringLiteral("copy"), QStringLiteral("File")},
            {QStringLiteral("cut"), QStringLiteral("File")},
            {QStringLiteral("paste"), QStringLiteral("File")},
            {QStringLiteral("trash"), QStringLiteral("File")},
            {QStringLiteral("permanent_delete"), QStringLiteral("File")},
            {QStringLiteral("undo"), QStringLiteral("File")},
            {QStringLiteral("redo"), QStringLiteral("File")},
            {QStringLiteral("rename"), QStringLiteral("File")},
            {QStringLiteral("new_folder"), QStringLiteral("File")},
            {QStringLiteral("new_file"), QStringLiteral("File")},
            {QStringLiteral("properties"), QStringLiteral("File")},
            {QStringLiteral("open_terminal"), QStringLiteral("File")},
            // Application
            {QStringLiteral("search"), QStringLiteral("Application")},
            {QStringLiteral("settings"), QStringLiteral("Application")},
            {QStringLiteral("keyboard_shortcuts"), QStringLiteral("Application")}
        };

        const QVariantList defs = mgr.shortcutDefinitions();
        QMap<QString, QString> actual;
        for (const QVariant &v : defs) {
            const QVariantMap def = v.toMap();
            actual.insert(def.value("action").toString(), def.value("group").toString());
        }

        for (auto it = expected.cbegin(); it != expected.cend(); ++it) {
            QVERIFY2(actual.contains(it.key()),
                     qPrintable(QStringLiteral("Expected action '%1' is missing from shortcutDefinitions()")
                                .arg(it.key())));
            QCOMPARE(actual.value(it.key()), it.value());
        }
        QCOMPARE(actual.size(), expected.size());
    }

    void testRegistryIsGroupContiguous()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        const QVariantList defs = mgr.shortcutDefinitions();
        QVERIFY(!defs.isEmpty());

        QSet<QString> seenGroups;
        QString currentGroup;
        for (const QVariant &v : defs) {
            const QString group = v.toMap().value("group").toString();
            if (group != currentGroup) {
                QVERIFY2(!seenGroups.contains(group),
                         qPrintable(QStringLiteral("Group '%1' is non-contiguous in kShortcutSpecs — "
                                                   "the dialog renders groups in registry order so "
                                                   "all entries of one group must sit together")
                                    .arg(group)));
                seenGroups.insert(group);
                currentGroup = group;
            }
        }
    }
```

- [ ] **Step 1.3: Build and confirm the new tests are RED**

Run:

```bash
cmake --build build && ctest --test-dir build -R tst_configmanager --output-on-failure
```

Expected: the three new tests (`testEveryActionHasGroup`, `testKnownActionsHaveExpectedGroups`, `testRegistryIsGroupContiguous`) all fail. Existing M1 tests stay green. Failures are along the lines of "group is empty" or "expected action missing".

- [ ] **Step 1.4: Extend `ShortcutSpec` with the `group` field**

Replace the struct definition in `src/services/configmanager.cpp` (around line 16):

```cpp
struct ShortcutSpec {
    const char *action;
    const char *label;
    const char *group;
};
```

- [ ] **Step 1.5: Reorder `kShortcutSpecs[]` to be group-contiguous and populate the new field**

Replace the entire `kShortcutSpecs[]` array (around lines 21-62) with:

```cpp
const ShortcutSpec kShortcutSpecs[] = {
    // Tabs
    {"new_tab", "New Tab", "Tabs"},
    {"close_tab", "Close Tab", "Tabs"},
    {"reopen_tab", "Reopen Closed Tab", "Tabs"},
    {"open_in_new_tab", "Open in New Tab", "Tabs"},
    {"open_in_split", "Open in Split View", "Tabs"},

    // Navigation
    {"back", "Back", "Navigation"},
    {"forward", "Forward", "Navigation"},
    {"parent", "Go to Parent", "Navigation"},
    {"home", "Home", "Navigation"},
    {"refresh", "Refresh", "Navigation"},
    {"path_bar", "Focus Path Bar", "Navigation"},

    // Panes
    {"toggle_merge", "Merge / Unmerge Panes", "Panes"},
    {"focus_left_pane", "Focus Left Pane", "Panes"},
    {"focus_right_pane", "Focus Right Pane", "Panes"},
    {"focus_next_pane", "Focus Next Pane", "Panes"},
    {"focus_previous_pane", "Focus Previous Pane", "Panes"},
    {"toggle_sidebar", "Toggle Sidebar", "Panes"},

    // View
    {"grid_view", "Grid View", "View"},
    {"miller_view", "Miller View", "View"},
    {"detailed_view", "Detailed View", "View"},
    {"toggle_hidden", "Toggle Hidden Files", "View"},
    {"quick_preview", "Quick Preview", "View"},

    // Selection
    {"select_all", "Select All", "Selection"},
    {"context_menu", "Show Context Menu", "Selection"},
    {"context_menu_alt", "Show Context Menu (Menu key)", "Selection"},

    // File
    {"open", "Open", "File"},
    {"copy", "Copy", "File"},
    {"cut", "Cut", "File"},
    {"paste", "Paste", "File"},
    {"trash", "Move to Trash", "File"},
    {"permanent_delete", "Permanent Delete", "File"},
    {"undo", "Undo", "File"},
    {"redo", "Redo", "File"},
    {"rename", "Rename", "File"},
    {"new_folder", "New Folder", "File"},
    {"new_file", "New File", "File"},
    {"properties", "Properties", "File"},
    {"open_terminal", "Open in Terminal", "File"},

    // Application
    {"search", "Search", "Application"},
    {"settings", "Open Settings", "Application"},
    {"keyboard_shortcuts", "Open Keyboard Shortcuts", "Application"},
};
```

All 41 actions are present in the new order. Compare counts via `grep -c '^\s*{"' src/services/configmanager.cpp` once edited — should still be 41 ShortcutSpec entries before the other-purpose `s_defaultShortcuts` map.

- [ ] **Step 1.6: Surface `group` in `shortcutDefinitions()`**

In `src/services/configmanager.cpp` around line 408 (inside the for-loop in `shortcutDefinitions()`), add the line marked `+` below to the existing block. The function should read:

```cpp
QVariantList ConfigManager::shortcutDefinitions() const
{
    QVariantList definitions;
    definitions.reserve(static_cast<qsizetype>(sizeof(kShortcutSpecs) / sizeof(kShortcutSpecs[0])));

    for (const auto &spec : kShortcutSpecs) {
        const QString action = QString::fromUtf8(spec.action);
        QVariantMap definition;
        definition.insert("action", action);
        definition.insert("label", QString::fromUtf8(spec.label));
        definition.insert("group", QString::fromUtf8(spec.group));
        definition.insert("defaultSequence", s_defaultShortcuts.value(action));
        definition.insert("sequence", m_shortcuts.value(action, s_defaultShortcuts.value(action)));
        definitions.append(definition);
    }

    return definitions;
}
```

- [ ] **Step 1.7: Build and confirm the tests pass**

Run:

```bash
cmake --build build && ctest --test-dir build -R tst_configmanager --output-on-failure
```

Expected: the three Task 1 tests pass. All M1 tests stay green. Full `tst_configmanager` suite green.

**Do not commit yet — M2 is one milestone, one commit. Tasks 2-6 follow.**

---

### Task 2: Add `rebindable` field, mark `open` as non-rebindable (TDD)

**Files:**
- Modify: `src/services/configmanager.cpp` (struct `ShortcutSpec`, `kShortcutSpecs[]`, `shortcutDefinitions()`)
- Test: `tests/tst_configmanager.cpp`

- [ ] **Step 2.1: Write the failing test for `rebindable`**

Append the following two slots to `tests/tst_configmanager.cpp`:

```cpp
    void testOpenActionIsNonRebindable()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        const QVariantList defs = mgr.shortcutDefinitions();
        bool foundOpen = false;
        for (const QVariant &v : defs) {
            const QVariantMap def = v.toMap();
            if (def.value("action").toString() == QLatin1String("open")) {
                foundOpen = true;
                QVERIFY2(def.contains("rebindable"),
                         "shortcutDefinitions() must expose a 'rebindable' field on every row.");
                QCOMPARE(def.value("rebindable").toBool(), false);
                break;
            }
        }
        QVERIFY(foundOpen);
    }

    void testNonOpenActionsAreRebindable()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        const QVariantList defs = mgr.shortcutDefinitions();
        int checked = 0;
        for (const QVariant &v : defs) {
            const QVariantMap def = v.toMap();
            const QString action = def.value("action").toString();
            if (action == QLatin1String("open"))
                continue;
            QVERIFY2(def.contains("rebindable"),
                     qPrintable(QStringLiteral("Action '%1' is missing the 'rebindable' field").arg(action)));
            QVERIFY2(def.value("rebindable").toBool(),
                     qPrintable(QStringLiteral("Action '%1' must be rebindable (only 'open' is view-local)").arg(action)));
            ++checked;
        }
        QVERIFY2(checked >= 40,
                 qPrintable(QStringLiteral("Expected at least 40 rebindable actions, only saw %1").arg(checked)));
    }
```

- [ ] **Step 2.2: Build and confirm RED**

Run:

```bash
cmake --build build && ctest --test-dir build -R tst_configmanager --output-on-failure
```

Expected: the two new tests fail with "must expose a 'rebindable' field" or similar. Task 1 tests still pass.

- [ ] **Step 2.3: Extend `ShortcutSpec` with `rebindable`**

Replace the struct definition (it currently has three fields after Task 1):

```cpp
struct ShortcutSpec {
    const char *action;
    const char *label;
    const char *group;
    bool rebindable;
};
```

- [ ] **Step 2.4: Populate `rebindable` on every entry**

For all 41 entries in `kShortcutSpecs[]`, add `, true` at the end of every row except the `open` row, which gets `, false`. The full block from Task 1 Step 1.5 should now read (showing only the changed format — every row gets the trailing bool):

```cpp
const ShortcutSpec kShortcutSpecs[] = {
    // Tabs
    {"new_tab", "New Tab", "Tabs", true},
    {"close_tab", "Close Tab", "Tabs", true},
    {"reopen_tab", "Reopen Closed Tab", "Tabs", true},
    {"open_in_new_tab", "Open in New Tab", "Tabs", true},
    {"open_in_split", "Open in Split View", "Tabs", true},

    // Navigation
    {"back", "Back", "Navigation", true},
    {"forward", "Forward", "Navigation", true},
    {"parent", "Go to Parent", "Navigation", true},
    {"home", "Home", "Navigation", true},
    {"refresh", "Refresh", "Navigation", true},
    {"path_bar", "Focus Path Bar", "Navigation", true},

    // Panes
    {"toggle_merge", "Merge / Unmerge Panes", "Panes", true},
    {"focus_left_pane", "Focus Left Pane", "Panes", true},
    {"focus_right_pane", "Focus Right Pane", "Panes", true},
    {"focus_next_pane", "Focus Next Pane", "Panes", true},
    {"focus_previous_pane", "Focus Previous Pane", "Panes", true},
    {"toggle_sidebar", "Toggle Sidebar", "Panes", true},

    // View
    {"grid_view", "Grid View", "View", true},
    {"miller_view", "Miller View", "View", true},
    {"detailed_view", "Detailed View", "View", true},
    {"toggle_hidden", "Toggle Hidden Files", "View", true},
    {"quick_preview", "Quick Preview", "View", true},

    // Selection
    {"select_all", "Select All", "Selection", true},
    {"context_menu", "Show Context Menu", "Selection", true},
    {"context_menu_alt", "Show Context Menu (Menu key)", "Selection", true},

    // File
    {"open", "Open", "File", false},
    {"copy", "Copy", "File", true},
    {"cut", "Cut", "File", true},
    {"paste", "Paste", "File", true},
    {"trash", "Move to Trash", "File", true},
    {"permanent_delete", "Permanent Delete", "File", true},
    {"undo", "Undo", "File", true},
    {"redo", "Redo", "File", true},
    {"rename", "Rename", "File", true},
    {"new_folder", "New Folder", "File", true},
    {"new_file", "New File", "File", true},
    {"properties", "Properties", "File", true},
    {"open_terminal", "Open in Terminal", "File", true},

    // Application
    {"search", "Search", "Application", true},
    {"settings", "Open Settings", "Application", true},
    {"keyboard_shortcuts", "Open Keyboard Shortcuts", "Application", true},
};
```

Note: `open` is the only entry with `false`. This is the C-level documentation that `open` is view-local and the dialog must not let the user rebind it (Enter on file = activate; rebinding to e.g. `Ctrl+Q` would NOT actually change the view's keyboard handler — that's per-view `Keys.onPressed` in `FileGridView.qml:179` and `FileDetailedView.qml:546`, both hardcoded to `Qt.Key_Return | Qt.Key_Enter`).

- [ ] **Step 2.5: Surface `rebindable` in `shortcutDefinitions()`**

In `shortcutDefinitions()`, add the `rebindable` insert next to the existing `group` insert. The function body should read:

```cpp
for (const auto &spec : kShortcutSpecs) {
    const QString action = QString::fromUtf8(spec.action);
    QVariantMap definition;
    definition.insert("action", action);
    definition.insert("label", QString::fromUtf8(spec.label));
    definition.insert("group", QString::fromUtf8(spec.group));
    definition.insert("rebindable", spec.rebindable);
    definition.insert("defaultSequence", s_defaultShortcuts.value(action));
    definition.insert("sequence", m_shortcuts.value(action, s_defaultShortcuts.value(action)));
    definitions.append(definition);
}
```

- [ ] **Step 2.6: Build and confirm GREEN**

Run:

```bash
cmake --build build && ctest --test-dir build -R tst_configmanager --output-on-failure
```

Expected: all Task 1 + Task 2 tests pass. Full `tst_configmanager` suite green.

- [ ] **Step 2.7: Run the broader non-flaky test set**

Run:

```bash
ctest --test-dir build -R "tst_configmanager|tst_themeloader|tst_tabmodel|tst_filesystemmodel|tst_bookmarkmodel|tst_clipboardmanager|tst_undomanager|tst_iconprovider|tst_devicemodel" --output-on-failure
```

Expected: 9/9 pass. (`tst_fileoperations` is a known pre-existing flake — exclude. `tst_giotransferworker` is flaky-when-co-run — exclude here, will rerun standalone in Task 6.)

---

### Task 3: Grouped rendering in `KeyboardShortcutsDialog.qml` (no TDD — build + visual-OK)

**Files:**
- Modify: `src/qml/components/KeyboardShortcutsDialog.qml`

- [ ] **Step 3.1: Locate the flat Repeater that renders rows**

The dialog renders a single flat list at `src/qml/components/KeyboardShortcutsDialog.qml:256` (`Repeater { model: root.shortcutEntries; delegate: Rectangle { id: shortcutRow ... }`). The header row above it (line 224-254) renders "Action | Shortcut | (reset spacer)".

The replacement strategy is: keep the header row, replace the flat Repeater with a Repeater whose delegate emits a small group-header band whenever `modelData.group !== prevGroup`. Track previous group via a property on the outer ColumnLayout that gets reset each rebuild.

- [ ] **Step 3.2: Replace the flat Repeater with a group-aware delegate**

Replace the existing block at `src/qml/components/KeyboardShortcutsDialog.qml:256-384` (from `Repeater { model: root.shortcutEntries` through the closing `}` of the delegate Rectangle) with:

```qml
                Repeater {
                    model: root.shortcutEntries

                    delegate: Column {
                        id: shortcutRowContainer
                        required property var modelData
                        required property int index

                        readonly property bool isRecording: root.recordingAction === modelData.action
                        readonly property bool isModified: modelData.sequence !== modelData.defaultSequence
                        readonly property bool isRebindable: modelData.rebindable === undefined
                            ? true
                            : modelData.rebindable
                        readonly property bool showGroupHeader: shortcutRowContainer.index === 0
                            || root.shortcutEntries[shortcutRowContainer.index - 1].group !== modelData.group

                        width: parent ? parent.width : 0
                        spacing: 0

                        // Group header band (only on group transitions)
                        Rectangle {
                            visible: shortcutRowContainer.showGroupHeader
                            width: parent.width
                            implicitHeight: visible ? 32 : 0
                            color: "transparent"

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 4
                                text: shortcutRowContainer.modelData.group
                                color: Theme.accent
                                font.pointSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                height: 1
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                            }
                        }

                        Rectangle {
                            id: shortcutRow
                            width: parent.width
                            implicitHeight: 44
                            color: {
                                if (shortcutRowContainer.isRecording)
                                    return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                                if (rowHover.hovered && shortcutRowContainer.isRebindable)
                                    return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
                                return "transparent"
                            }
                            Behavior on color { ColorAnimation { duration: Theme.animDuration } }

                            // Bottom separator (last row in group gets no separator)
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                height: 1
                                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
                                visible: shortcutRowContainer.index < root.shortcutEntries.length - 1
                                    && root.shortcutEntries[shortcutRowContainer.index + 1].group === shortcutRowContainer.modelData.group
                            }

                            HoverHandler {
                                id: rowHover
                                enabled: shortcutRowContainer.isRebindable
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 8

                                // Action label
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        Layout.fillWidth: true
                                        text: shortcutRowContainer.modelData.label
                                        color: shortcutRowContainer.isRebindable ? Theme.text : Theme.subtext
                                        font.pointSize: Theme.fontNormal
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: !shortcutRowContainer.isRebindable
                                        text: "View-local — fires from the active file view (Enter on selection)."
                                        color: Theme.subtext
                                        font.pointSize: Theme.fontSmall
                                        font.italic: true
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                // Shortcut badge / recording indicator
                                Rectangle {
                                    Layout.preferredWidth: 180
                                    Layout.preferredHeight: 30
                                    radius: Theme.radiusSmall
                                    color: {
                                        if (shortcutRowContainer.isRecording)
                                            return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                                        if (!shortcutRowContainer.isRebindable)
                                            return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.03)
                                        return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
                                    }
                                    border.width: shortcutRowContainer.isRecording ? 1 : 0
                                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
                                    opacity: shortcutRowContainer.isRebindable ? 1.0 : 0.6

                                    Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                                    Behavior on border.width { NumberAnimation { duration: Theme.animDuration } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 4

                                        Text {
                                            Layout.fillWidth: true
                                            text: shortcutRowContainer.isRecording
                                                ? "Press keys..."
                                                : shortcutRowContainer.modelData.sequence
                                            color: shortcutRowContainer.isRecording ? Theme.accent : Theme.text
                                            font.pointSize: Theme.fontNormal
                                            font.weight: Font.Medium
                                            font.italic: shortcutRowContainer.isRecording
                                            elide: Text.ElideRight

                                            SequentialAnimation on opacity {
                                                running: shortcutRowContainer.isRecording
                                                loops: Animation.Infinite
                                                NumberAnimation { to: 0.4; duration: 600; easing.type: Easing.InOutSine }
                                                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: shortcutRowContainer.isRebindable
                                            ? Qt.PointingHandCursor
                                            : Qt.ArrowCursor
                                        enabled: shortcutRowContainer.isRebindable
                                        onClicked: {
                                            if (shortcutRowContainer.isRecording)
                                                root.stopRecording()
                                            else
                                                root.startRecording(shortcutRowContainer.modelData.action)
                                        }
                                    }
                                }

                                // Reset button (visible when modified AND rebindable)
                                HoverRect {
                                    width: 28; height: 28
                                    visible: shortcutRowContainer.isModified
                                        && !shortcutRowContainer.isRecording
                                        && shortcutRowContainer.isRebindable
                                    opacity: visible ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.animDuration } }
                                    onClicked: root.resetToDefault(shortcutRowContainer.modelData.action)

                                    IconUndo {
                                        anchors.centerIn: parent
                                        size: 14
                                        color: Theme.subtext
                                    }
                                }

                                // Spacer when reset button is hidden
                                Item {
                                    width: 28
                                    visible: !(shortcutRowContainer.isModified
                                        && !shortcutRowContainer.isRecording
                                        && shortcutRowContainer.isRebindable)
                                }
                            }
                        }
                    }
                }
```

Key changes vs the original delegate:
- Outer container is now a `Column` so the group header band + row body stack vertically.
- `showGroupHeader` peeks at `root.shortcutEntries[index - 1].group` to detect group transitions (first row always shows).
- Bottom-separator now hides on the last row of each group (looks at the next row's group).
- Every interactive surface (HoverHandler, MouseArea, reset button) gates on `isRebindable`.
- Non-rebindable rows render label in subtext color + an italic explainer line ("View-local — fires from the active file view (Enter on selection).").
- Badge rendering uses lower opacity + a softer background for non-rebindable rows.

- [ ] **Step 3.3: Build and confirm QML compiles cleanly**

Run:

```bash
cmake --build build
```

Expected: full build succeeds, no new warnings, no QML compilation errors.

- [ ] **Step 3.4: qmllint the dialog file**

Run:

```bash
qmllint src/qml/components/KeyboardShortcutsDialog.qml
```

Expected: no output (clean). If any new warnings appear, fix before continuing — the rendering rewrite is the riskiest QML change in M2 and warnings here often indicate property-binding issues.

---

### Task 4: "Reset all to defaults" footer button with two-click confirm (no TDD — build + visual-OK)

**Files:**
- Modify: `src/qml/components/KeyboardShortcutsDialog.qml`

- [ ] **Step 4.1: Add `resetAllToDefaults()` function near `resetToDefault()`**

Just after `resetToDefault(action)` at `src/qml/components/KeyboardShortcutsDialog.qml:98-106`, add:

```qml
    function resetAllToDefaults() {
        var nextShortcuts = ({})
        var nextEntries = []
        for (var i = 0; i < shortcutEntries.length; ++i) {
            var entry = shortcutEntries[i]
            var defaultSeq = entry.defaultSequence
            nextShortcuts[entry.action] = defaultSeq

            var updatedEntry = ({})
            for (var field in entry)
                updatedEntry[field] = entry[field]
            updatedEntry.sequence = defaultSeq
            nextEntries.push(updatedEntry)
        }
        draftShortcuts = nextShortcuts
        shortcutEntries = nextEntries
        queueShortcutApply()
    }
```

This walks every entry, copies it with `sequence = defaultSequence`, replaces both `draftShortcuts` and `shortcutEntries` in one paint, and schedules the save through the existing debounce timer.

- [ ] **Step 4.2: Add a `confirmResetAll` property on `root`**

Just below the existing property declarations near the top of `Q.Dialog { id: root ... }` (around line 19, next to `property string recordingAction: ""`), add:

```qml
    property bool confirmResetAll: false
```

This is the two-click state: first click flips it to true and shows a "Click again to confirm" label; second click invokes `resetAllToDefaults()` and resets it. Any other interaction (clicking another row, closing the dialog) resets it without action.

- [ ] **Step 4.3: Add a Timer that auto-cancels the confirm state**

Just after the existing `Timer { id: shortcutApplyTimer ... }` block (search for `shortcutApplyTimer` in the file), add:

```qml
    Timer {
        id: resetConfirmTimer
        interval: 3000
        repeat: false
        onTriggered: root.confirmResetAll = false
    }
```

This avoids the confirm state persisting forever if the user wanders off — after 3 s without a second click, it cancels.

- [ ] **Step 4.4: Wire `closeDialog()` to clear the confirm state**

Replace the existing `closeDialog()` function at `src/qml/components/KeyboardShortcutsDialog.qml:83-87`:

```qml
    function closeDialog() {
        recordingAction = ""
        confirmResetAll = false
        resetConfirmTimer.stop()
        applyPendingShortcuts()
        close()
    }
```

- [ ] **Step 4.5: Add the "Reset all to defaults" button to the footer**

The current footer is at lines 401-419 (the `RowLayout` containing the `Text` hint + `Q.Button { text: "Done" }`). Replace it with:

```qml
    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Text {
            Layout.fillWidth: true
            text: root.recordingAction !== ""
                ? "Press Escape to cancel recording."
                : root.confirmResetAll
                    ? "Click again to confirm — every binding goes back to its factory default."
                    : "Click a shortcut to change it. Changes save automatically."
            color: root.confirmResetAll ? Theme.accent : Theme.subtext
            font.pointSize: Theme.fontSmall
            wrapMode: Text.WordWrap
        }

        Q.Button {
            text: root.confirmResetAll ? "Confirm reset" : "Reset all to defaults"
            variant: "ghost"
            onClicked: {
                if (root.confirmResetAll) {
                    root.confirmResetAll = false
                    resetConfirmTimer.stop()
                    root.resetAllToDefaults()
                } else {
                    root.confirmResetAll = true
                    resetConfirmTimer.restart()
                }
            }
        }

        Q.Button {
            text: "Done"
            onClicked: root.closeDialog()
        }
    }
```

The label color flips to accent + the hint text changes the moment confirm is armed, so the state is obvious. `Q.Button` `variant: "ghost"` keeps the reset-all button secondary — primary CTA stays "Done".

- [ ] **Step 4.6: Build and qmllint**

Run:

```bash
cmake --build build && qmllint src/qml/components/KeyboardShortcutsDialog.qml
```

Expected: clean build, no qmllint output.

---

### Task 5: Confirm `open` is not bound to a `Shortcut {}` block in Main.qml (sanity check, no edit)

**Files:** none.

The audit already confirmed `open` has no global `Shortcut { sequence: config.shortcutMap["open"] }` block in `Main.qml` (it's view-local via `Keys.onPressed` in `FileGridView.qml:179` and `FileDetailedView.qml:546`). Task 2 codified that fact in the registry by setting `rebindable: false`. There is no QML change required for `open` — the dialog renders it as non-rebindable, the per-view handlers stay hardcoded to `Qt.Key_Return | Qt.Key_Enter`, and the registry entry exists purely as documentation.

- [ ] **Step 5.1: Sanity-grep that no Main.qml block references `config.shortcutMap["open"]`**

Run:

```bash
grep -n 'shortcutMap\["open"\]' src/qml/Main.qml
```

Expected: no matches. If a match exists, it would mean someone snuck in a global Shortcut for `open` — delete it before continuing (would crash hover-state in path bar / rename dialog because Return would steal the binding).

---

### Task 6: Visual-OK gate + commit

**Files:** none (verify + commit step).

- [ ] **Step 6.1: Run the full sanity suite one more time**

```bash
ctest --test-dir build -R "tst_configmanager|tst_themeloader|tst_tabmodel|tst_filesystemmodel|tst_bookmarkmodel|tst_clipboardmanager|tst_undomanager|tst_iconprovider|tst_devicemodel" --output-on-failure
```

Expected: 9/9 pass. (`tst_fileoperations` pre-existing flake, `tst_giotransferworker` flaky in long suites — excluded.)

- [ ] **Step 6.2: Hand the visual-OK checklist to the user**

Present, verbatim:

> Launch Heimdall and confirm the following before I commit:
>
> 1. Open the Keyboard Shortcuts dialog (`Ctrl+?` by default).
> 2. The list is split into seven sections — section headers in accent color in this order: **Tabs**, **Navigation**, **Panes**, **View**, **Selection**, **File**, **Application**.
> 3. No section is empty. Counts visually look like ~5 / ~6 / ~6 / ~5 / ~3 / ~13 / ~3 rows.
> 4. The `open` row (in the **File** group, label "Open") looks visually different from the others: greyed label, italic note "View-local — fires from the active file view (Enter on selection).", combo "Return" rendered with reduced opacity. Clicking the row does nothing — no recording cursor, no rebinding. (Inside an active grid view, Enter on a focused file still activates that file — handler unchanged.)
> 5. Every other row is still clickable and recordable. Rebinding a sample one (e.g. `toggle_hidden` → `Ctrl+Shift+H`) still works; the per-row reset undo button still works after the rebind.
> 6. Footer has two buttons: **"Reset all to defaults"** (ghost / secondary) and **"Done"** (primary). Click "Reset all to defaults" once — the button label flips to "Confirm reset" and the hint text underneath flips to accent color "Click again to confirm — every binding goes back to its factory default." Wait 3+ seconds without clicking — button + hint revert silently.
> 7. Rebind something, then click "Reset all to defaults" → "Confirm reset" → after the second click, every row's combo reverts to its default and the per-row reset buttons hide.
> 8. After "Reset all" fires, close the dialog with Done, relaunch Heimdall, reopen the dialog — all defaults still there (the save went through `config.saveShortcuts`, not just in-memory).

Wait for the user to explicitly confirm. Do not move to Step 6.3 on assumption.

- [ ] **Step 6.3: Stage the changes**

```bash
git add src/services/configmanager.cpp tests/tst_configmanager.cpp src/qml/components/KeyboardShortcutsDialog.qml
git diff --cached --stat
```

Expected: exactly 3 files modified, no untracked files staged. Spec / plan files stay out of this commit. `configmanager.h` stays unchanged — adding fields to `ShortcutSpec` doesn't change the public API.

- [ ] **Step 6.4: Create the commit**

```bash
git commit -m "$(cat <<'EOF'
feat(p3,M2): grouped shortcuts dialog + 'open' marked view-local + Reset All

- Extend ShortcutSpec with 'group' and 'rebindable' fields. Populate
  every action with one of seven groups (Tabs, Navigation, Panes, View,
  Selection, File, Application). Reorder kShortcutSpecs[] so groups are
  registry-contiguous.
- Mark 'open' as rebindable=false: Qt's Shortcut is global, but Enter
  on a focused file is fundamentally view-local (FileGridView /
  FileDetailedView Keys.onPressed). A global binding would steal Return
  from text inputs. Registry row stays as documentation.
- KeyboardShortcutsDialog: render rows split by section headers; the
  'open' row gets a non-rebindable visual variant with an explainer
  line; per-row reset still works on rebindable entries.
- Add a "Reset all to defaults" footer button with a two-click confirm
  (3 s timeout to auto-cancel). Hint label flips to accent color +
  changes text while the confirm is armed.

Tests cover the new fields (presence + values), per-action group
assignments (all 41), group-contiguous ordering, 'open' non-rebindable,
all others rebindable. QML changes verified by build + qmllint + user
visual-OK against the 8-step checklist.

Spec: docs/superpowers/specs/2026-05-29-settings-shortcuts-polish-design.md (M2)
EOF
)"
```

- [ ] **Step 6.5: Confirm working tree is clean**

```bash
git log --oneline -3 && git status
```

Expected: new M2 commit at HEAD; working tree clean.

- [ ] **Step 6.6: Hand off**

Tell the user:

> M2 shipped on commit `<hash>`. Spec milestone M3 is next (Settings parity UI for `builtinIcons` / `animationsEnabled` labels + new controls for `default_view` / `sort_by` / `sort_ascending` + bookmarks hint + Apply/Cancel/Restore audit). Want me to write the M3 plan now, or pause here?
