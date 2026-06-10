# W7 — Sidebar Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the Wayfile sidebar to the handoff structure (Favorites · Places-with-XDG-tree · Devices · Network · Trash-at-bottom), unify the gallery + normal sidebars into one, add a 56px compact rail and per-entry hide-via-context-menu — without losing any current entry.

**Architecture:** A single `Sidebar.qml` renders an ordered section stack filtered against a persisted hidden-entry set; the curated-XDG folder tree lives in a new `SidebarPlacesTree.qml` reusing the existing C++ `FolderTreeModel` + the `GalleryFolderNav` TreeView delegate; `SidebarPane.qml` loses its gallery special-case and drives a Full↔Compact width from a new `config.sidebarCompact`.

**Tech Stack:** Qt 6.11 QML (TreeView, Loader, ColumnLayout), C++ (QFileSystemModel subclass, ConfigManager/toml++), Qt6::Test.

**Spec:** `docs/superpowers/specs/2026-06-10-wayfile-w7-sidebar-rework-design.md`.
**Reference (existing, to reuse):** `src/qml/components/GalleryFolderNav.qml` (working folder tree), `src/qml/components/Sidebar.qml` (current sections), `src/models/foldertreemodel.{h,cpp}`.

**Build/verify recipe (MANDATORY after every change — `cmake --build` alone does NOT regenerate the compiled-QML qrc):**
```bash
cmake -B build && cmake --build build -j$(nproc)
ctest --test-dir build            # full suite (or -R <name> for one)
mkdir -p /tmp/wf-tmp && timeout 8 env TMPDIR=/tmp/wf-tmp QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 ./build/src/wayfile 2>/tmp/w.log; echo $?
# exit 124 = loads OK; 255 = QML failure → read /tmp/w.log
# TMPDIR isolation REQUIRED: the user's running instance owns the /tmp single-instance socket.
```
**Commit rule:** NO Co-Authored-By / attribution lines (project CLAUDE.md). Use `/usr/bin/grep`, not bare grep (the shell wrapper silently skips files).

**File structure:**

| File | Responsibility | Task |
|---|---|---|
| `src/services/configmanager.{h,cpp}` | + `sidebarCompact` bool, `hiddenSidebarEntries` QStringList, save/hide/show invokables | 1 |
| `tests/tst_configmanager.cpp` | round-trip tests for the two new keys | 1 |
| `src/qml/components/SidebarPlacesTree.qml` (new) | Curated-XDG forest: fixed rows + per-XDG expandable subtree | 2 |
| `src/qml/components/Sidebar.qml` | Section stack reorder, fold in tree, polish, hide-filter, compact render | 3,4,5 |
| `src/qml/components/SidebarPane.qml` | Remove gallery special-case; Full↔Compact width | 5,6 |
| `src/qml/components/GalleryFolderNav.qml` | Deleted (absorbed into SidebarPlacesTree) | 6 |
| `src/CMakeLists.txt` | register new QML, drop deleted | 2,6 |
| `src/qml/Main.qml` | toolbar toggle → compact; pass config to sidebar | 5 |

---

### Task 1: ConfigManager — `sidebarCompact` + `hiddenSidebarEntries`

**Files:**
- Modify: `src/services/configmanager.h`, `src/services/configmanager.cpp`
- Test: `tests/tst_configmanager.cpp`

- [ ] **Step 1: Write the failing tests**

Append to `tests/tst_configmanager.cpp` (inside the test class — mirror existing test methods; find an existing `void someTest();` slot declaration and an existing `void ConfigManager...` usage to match the harness):

```cpp
void TestConfigManager::sidebarCompactPersists()
{
    QTemporaryDir dir;
    const QString path = dir.path() + "/config.toml";
    {
        ConfigManager cfg(path);
        QCOMPARE(cfg.sidebarCompact(), false);            // default
        cfg.saveSidebarCompact(true);
        QCOMPARE(cfg.sidebarCompact(), true);
    }
    ConfigManager reloaded(path);                          // fresh load from disk
    QCOMPARE(reloaded.sidebarCompact(), true);
}

void TestConfigManager::hiddenSidebarEntriesPersist()
{
    QTemporaryDir dir;
    const QString path = dir.path() + "/config.toml";
    {
        ConfigManager cfg(path);
        QVERIFY(cfg.hiddenSidebarEntries().isEmpty());
        cfg.hideSidebarEntry("places.recents");
        cfg.hideSidebarEntry("network");
        cfg.hideSidebarEntry("places.recents");           // dup is a no-op
        QCOMPARE(cfg.hiddenSidebarEntries().size(), 2);
        cfg.showSidebarEntry("network");
        QCOMPARE(cfg.hiddenSidebarEntries(), QStringList{"places.recents"});
    }
    ConfigManager reloaded(path);
    QCOMPARE(reloaded.hiddenSidebarEntries(), QStringList{"places.recents"});
}
```

Declare the two slots next to the other `private slots:` test declarations in the file, and register nothing else (Qt auto-runs them). Match the existing class name in the file — open the file and use whatever the test class is actually called (it is NOT necessarily `TestConfigManager`; adapt the two method definitions + declarations to the real class name).

- [ ] **Step 2: Run to verify failure**

```bash
cmake -B build && cmake --build build -j$(nproc) 2>&1 | tail -20
```
Expected: COMPILE FAIL — `sidebarCompact`/`saveSidebarCompact`/`hiddenSidebarEntries`/`hideSidebarEntry`/`showSidebarEntry` not members of ConfigManager.

- [ ] **Step 3: Add the header API**

In `src/services/configmanager.h`, add Q_PROPERTYs near the other sidebar ones (after line 27 `sidebarVisible`):

```cpp
    Q_PROPERTY(bool sidebarCompact READ sidebarCompact NOTIFY configChanged)
    Q_PROPERTY(QStringList hiddenSidebarEntries READ hiddenSidebarEntries NOTIFY configChanged)
```

Add getters near `bool sidebarVisible() const;` (line 80):

```cpp
    bool sidebarCompact() const;
    QStringList hiddenSidebarEntries() const;
```

Add invokables near `saveSidebarWidth` (line 106):

```cpp
    Q_INVOKABLE void saveSidebarCompact(bool compact);
    Q_INVOKABLE void hideSidebarEntry(const QString &id);
    Q_INVOKABLE void showSidebarEntry(const QString &id);
    Q_INVOKABLE void clearHiddenSidebarEntries();
```

Add members near `m_sidebarWidth` (find it ~ the private members block):

```cpp
    bool m_sidebarCompact = false;
    QStringList m_hiddenSidebarEntries;
```

- [ ] **Step 4: Implement in the .cpp**

In `src/services/configmanager.cpp`:

(a) Defaults — near line 391 `m_sidebarWidth = 236;` add `m_sidebarCompact = false;` and `m_hiddenSidebarEntries.clear();`.

(b) Load — in the parse block, near where `config["sidebar"]["width"]` is read (~line 447), add:

```cpp
        if (auto v = config["sidebar"]["compact"].value<bool>())
            m_sidebarCompact = *v;
        m_hiddenSidebarEntries.clear();
        if (auto arr = config["sidebar"]["hidden_entries"].as_array()) {
            for (const auto &item : *arr) {
                if (auto v = item.value<std::string>())
                    m_hiddenSidebarEntries.append(QString::fromStdString(*v));
            }
        }
```

(c) Getters — near line 578 `int ConfigManager::sidebarWidth()...`:

```cpp
bool ConfigManager::sidebarCompact() const { return m_sidebarCompact; }
QStringList ConfigManager::hiddenSidebarEntries() const { return m_hiddenSidebarEntries; }
```

(d) saveSettings sidebar table — in the block that writes `sidebar.insert_or_assign("width", ...)` (~line 737), add a `sidebarCompact` branch:

```cpp
    if (settings.contains("sidebarCompact")) {
        m_sidebarCompact = settings.value("sidebarCompact").toBool();
        sidebar.insert_or_assign("compact", m_sidebarCompact);
    }
```

(e) New invokables — add near `saveSidebarWidth` definition. `saveSidebarCompact` reuses `saveSettings`; the hidden-entry ops mutate the list and persist the array directly (mirror `saveBookmarks`'s toml-array write so the whole list round-trips):

```cpp
void ConfigManager::saveSidebarCompact(bool compact)
{
    saveSettings(QVariantMap{{"sidebarCompact", compact}});
}

void ConfigManager::clearHiddenSidebarEntries()
{
    m_hiddenSidebarEntries.clear();
    persistHiddenSidebarEntries();
}

void ConfigManager::hideSidebarEntry(const QString &id)
{
    if (id.isEmpty() || m_hiddenSidebarEntries.contains(id))
        return;
    m_hiddenSidebarEntries.append(id);
    persistHiddenSidebarEntries();
}

void ConfigManager::showSidebarEntry(const QString &id)
{
    if (m_hiddenSidebarEntries.removeAll(id) > 0)
        persistHiddenSidebarEntries();
}
```

Add a private helper `persistHiddenSidebarEntries()` (declare it `private:` in the header) that writes the array under `[sidebar].hidden_entries`, mirroring `saveBookmarks` exactly but into the `sidebar` table and emitting `configChanged`:

```cpp
void ConfigManager::persistHiddenSidebarEntries()
{
    const bool wasWatching = m_watcher.files().contains(m_configPath);
    if (wasWatching)
        m_watcher.removePath(m_configPath);

    toml::table config;
    if (QFile::exists(m_configPath)) {
        try { config = toml::parse_file(m_configPath.toStdString()); } catch (...) {}
    }
    toml::array arr;
    for (const auto &e : m_hiddenSidebarEntries)
        arr.push_back(e.toStdString());
    auto sidebar = config["sidebar"].as_table() ? *config["sidebar"].as_table() : toml::table{};
    sidebar.insert_or_assign("hidden_entries", std::move(arr));
    config.insert_or_assign("sidebar", std::move(sidebar));
    writeTomlAtomic(m_configPath, config);

    if (QFile::exists(m_configPath))
        m_watcher.addPath(m_configPath);
    emit configChanged();
}
```

- [ ] **Step 5: Build + run the two tests**

```bash
cmake -B build && cmake --build build -j$(nproc)
ctest --test-dir build -R tst_configmanager
```
Expected: PASS (incl. the two new cases). Then full `ctest --test-dir build` → all green.

- [ ] **Step 6: Commit**

```bash
git add src/services/configmanager.h src/services/configmanager.cpp tests/tst_configmanager.cpp
git commit -m "feat(config): sidebarCompact + hiddenSidebarEntries (persist) for W7 sidebar"
```

---

### Task 2: `SidebarPlacesTree.qml` — curated-XDG forest

**Files:**
- Create: `src/qml/components/SidebarPlacesTree.qml`
- Modify: `src/CMakeLists.txt` (QML_FILES list — add near the other `qml/components/*.qml`)

This is a self-contained component: a Column of curated XDG roots, each an expandable subtree over a single shared `FolderTreeModel`. It does not yet replace anything (Task 3 wires it into Sidebar).

- [ ] **Step 1: Create the component**

```qml
import QtQuick
import QtQuick.Layouts
import Wayfile

// Curated-XDG folder forest for the sidebar's Places section. A fixed list of
// XDG roots (Desktop/Documents/Downloads/Pictures/Music/Videos); each row has a
// chevron that expands an embedded TreeView rooted at that dir over the shared
// FolderTreeModel. The outer sidebar Flickable owns scrolling (inner TreeViews
// are interactive:false, height-bound to contentHeight). Clicking a folder name
// navigates the active pane + expands. Reuses the GalleryFolderNav delegate.
Column {
    id: root
    property var host: null                         // Main.qml: navigateActivePaneTo + activePanePath
    readonly property string homeDir: fsModel.homePath()
    readonly property string currentDir: host ? host.activePanePath : ""
    readonly property int _indent: Math.round(14 * Theme.uiScale)
    readonly property int _rowHeight: Math.round(30 * Theme.uiScale)
    spacing: 0

    // One shared folders-only FS model for every subtree.
    FolderTreeModel { id: folderTree; rootPath: root.homeDir }

    // The curated roots. `label` is shown; `dir` resolves under Home. A root
    // whose directory does not exist is omitted (visible:false collapses it).
    readonly property var xdgRoots: [
        { label: "Desktop",   dir: homeDir + "/Desktop" },
        { label: "Documents", dir: homeDir + "/Documents" },
        { label: "Downloads", dir: homeDir + "/Downloads" },
        { label: "Pictures",  dir: homeDir + "/Pictures" },
        { label: "Music",     dir: homeDir + "/Music" },
        { label: "Videos",    dir: homeDir + "/Videos" }
    ]

    Repeater {
        model: root.xdgRoots
        delegate: Column {
            id: xdgItem
            width: root.width
            required property var modelData
            // QFileSystemModel returns an invalid index for a missing dir.
            readonly property bool dirExists: folderTree.indexForPath(modelData.dir).valid
            visible: dirExists
            height: visible ? implicitHeight : 0
            property bool expanded: false

            // The XDG header row (chevron + folder glyph + label). Clicking the
            // name navigates + expands; the chevron only toggles.
            Rectangle {
                width: parent.width
                height: root._rowHeight
                color: xdgHeaderHover.hovered
                       ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
                       : "transparent"
                HoverHandler { id: xdgHeaderHover }

                Item {
                    id: xdgChev
                    x: 4; width: 16; height: parent.height
                    IconChevronRight {
                        anchors.centerIn: parent
                        size: 13
                        color: Theme.subtext
                        rotation: xdgItem.expanded ? 90 : 0
                        Behavior on rotation { NumberAnimation { duration: Theme.animDurationFast } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: xdgItem.expanded = !xdgItem.expanded
                    }
                }
                Row {
                    anchors.left: xdgChev.right; anchors.right: parent.right
                    anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    FileIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        isDir: true; size: 15
                        hovered: xdgHeaderHover.hovered
                        selected: xdgItem.modelData.dir === root.currentDir
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 15 - 6
                        text: xdgItem.modelData.label
                        color: xdgItem.modelData.dir === root.currentDir ? Theme.gold : Theme.text
                        font.pointSize: Theme.fontNormal
                        elide: Text.ElideRight
                    }
                }
                MouseArea {
                    anchors.left: xdgChev.right; anchors.right: parent.right
                    anchors.top: parent.top; anchors.bottom: parent.bottom
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.host) root.host.navigateActivePaneTo(xdgItem.modelData.dir)
                        xdgItem.expanded = true
                    }
                }
            }

            // Lazy subtree, only built when expanded.
            Loader {
                width: parent.width
                active: xdgItem.expanded
                visible: active
                sourceComponent: subtreeComp
                property string subtreeDir: xdgItem.modelData.dir
            }
        }
    }

    // A TreeView rooted at one XDG dir. interactive:false so the sidebar scroll
    // owns it; height follows contentHeight. Delegate mirrors GalleryFolderNav.
    Component {
        id: subtreeComp
        TreeView {
            id: subtree
            readonly property string rootDir: parent.subtreeDir
            width: parent.width
            height: contentHeight
            interactive: false
            clip: false
            model: folderTree
            columnWidthProvider: function (column) { return subtree.width }
            onWidthChanged: forceLayout()
            Component.onCompleted: subtree.rootIndex = folderTree.indexForPath(rootDir)
            Connections {
                target: folderTree
                function onDirectoryLoaded(p) {
                    if (p === subtree.rootDir)
                        subtree.rootIndex = folderTree.indexForPath(subtree.rootDir)
                }
            }
            delegate: Item {
                id: rowItem
                implicitHeight: root._rowHeight
                implicitWidth: subtree.width
                required property int row
                required property string display
                required property var treeView
                required property int depth
                required property bool expanded
                required property bool hasChildren
                readonly property string fullPath: folderTree.pathAt(subtree.index(rowItem.row, 0))
                readonly property bool isCurrent: rowItem.fullPath === root.currentDir
                // +1 so an XDG child indents past the XDG header's glyph.
                readonly property int _leftPad: 4 + (rowItem.depth + 1) * root._indent

                Rectangle {
                    anchors.fill: parent
                    color: rowItem.isCurrent ? Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.18)
                         : (rowHover.hovered ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04) : "transparent")
                }
                Rectangle {
                    visible: rowItem.isCurrent
                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    width: 2; color: Theme.gold
                }
                HoverHandler { id: rowHover }
                Item {
                    id: chev
                    x: rowItem._leftPad; width: 16; height: parent.height
                    IconChevronRight {
                        anchors.centerIn: parent; visible: rowItem.hasChildren; size: 13
                        color: Theme.subtext; rotation: rowItem.expanded ? 90 : 0
                        Behavior on rotation { NumberAnimation { duration: Theme.animDurationFast } }
                    }
                    MouseArea {
                        anchors.fill: parent; enabled: rowItem.hasChildren
                        cursorShape: Qt.PointingHandCursor
                        onClicked: rowItem.treeView.toggleExpanded(rowItem.row)
                    }
                }
                Row {
                    anchors.left: chev.right; anchors.right: parent.right
                    anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    FileIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        isDir: true; size: 15; hovered: rowHover.hovered; selected: rowItem.isCurrent
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 15 - 6
                        text: rowItem.display
                        color: rowItem.isCurrent ? Theme.gold : Theme.text
                        font.pointSize: Theme.fontNormal; elide: Text.ElideRight
                    }
                }
                MouseArea {
                    anchors.left: chev.right; anchors.right: parent.right
                    anchors.top: parent.top; anchors.bottom: parent.bottom
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.host) root.host.navigateActivePaneTo(rowItem.fullPath)
                        if (rowItem.hasChildren && !rowItem.expanded) subtree.expand(rowItem.row)
                    }
                }
            }
        }
    }
}
```

⚠ Notes:
- `folderTree.indexForPath(dir).valid` — `QModelIndex` exposes `valid` to QML. If a missing dir still returns a valid index in practice (QFileSystemModel quirk), fall back to a C++ `Q_INVOKABLE bool dirExists(path)` on FolderTreeModel; verify at runtime via /tmp/w.log + the GUI.
- `IconChevronRight`, `FileIcon`, `FolderTreeModel` are all existing `Wayfile`-module types (no new imports).
- `height: contentHeight` on a non-interactive TreeView: TableView exposes `contentHeight`; it updates as rows expand. If a binding-loop warning appears, bind `implicitHeight: contentHeight` instead.

- [ ] **Step 2: Register in CMake**

`src/CMakeLists.txt` QML_FILES list — add `qml/components/SidebarPlacesTree.qml` in the components group.

- [ ] **Step 3: Build + smoke + launch (full recipe)** — exit 124, no QML errors. (Nothing instantiates it yet; this proves it compiles in the module.)

- [ ] **Step 4: Commit**

```bash
git add src/qml/components/SidebarPlacesTree.qml src/CMakeLists.txt
git commit -m "feat(sidebar): SidebarPlacesTree — curated-XDG expandable folder forest (W7)"
```

---

### Task 3: Restructure `Sidebar.qml` — sections, tree, polish

**Files:**
- Modify: `src/qml/components/Sidebar.qml`

Reorder the `ColumnLayout` to: **Favorites · Places · Devices · Network · (spacer) · Trash**. Keep ALL existing entries and the existing bookmarks/devices machinery; only move/relabel and add. Places = Home (mono) + Recents + Hidden quick rows, then `SidebarPlacesTree`. Add a Network section (the existing Network quick-access entry) and a bottom-pinned Trash row with a mono count chip. Apply the polish (2px active rail, mono path labels, count chips).

- [ ] **Step 1: Split the current flat PLACES list into Places-quick + Network + Trash**

The current `Repeater` model (lines ~123-131) lists Home/Hidden/Recents/Trash/Network/Pictures/Downloads in one flat list. Replace with **Places quick rows** = Home (mono), Recents, Hidden only (Pictures/Downloads become tree children under the XDG forest; Trash + Network move to their own sections). Concretely, change that `ListModel` to:

```qml
                model: ListModel {
                    ListElement { name: "Home"; iconType: "home"; mono: true }
                    ListElement { name: "Recents"; iconType: "clock"; mono: false }
                    ListElement { name: "Hidden"; iconType: "eyeoff"; mono: false }
                }
```

Add `mono` handling to that delegate's label `Text` (the `font.family` toggles to `Fonts.mono` when `model.mono`):

```qml
                        Text {
                            text: model.name
                            color: quickAccessDelegate.isActive ? Theme.text : Theme.subtext
                            font.family: model.mono ? Fonts.mono : root.font.family
                            font.pointSize: Theme.fontNormal
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            width: parent.width - 32 - Theme.spacing
                        }
```

(`import Wayfile` already provides `Fonts`.)

Change the active left-rail width from `3` to `2` (find the `width: 3` rail Rectangle ~line 193) to match the handoff.

- [ ] **Step 2: Insert `SidebarPlacesTree` after the Places quick rows**

Immediately after the Places quick-access `Column` (the one holding the Repeater), add:

```qml
        // Expandable curated-XDG folder forest (Desktop/Documents/… each a tree).
        SidebarPlacesTree {
            Layout.fillWidth: true
            host: root.host ? root.host : null    // see Step 5 for host plumbing
        }
```

⚠ `Sidebar.qml`'s root needs access to Main.qml for `navigateActivePaneTo`/`activePanePath`. It currently emits `bookmarkClicked` etc. and the host wires those. Add a `property var host: null` to `Sidebar.qml`'s root and set it from `SidebarPane`/Main (Step 5). The tree calls `host.navigateActivePaneTo` directly.

- [ ] **Step 3: Add the Network section (existing Network entry, own header)**

After the Devices section (the `devicesSection` Column, ~line 698-713), add a Network header + a one-row Network entry that navigates to `network:///` (reuse the quick-access delegate styling; simplest is a small inline Repeater with a single `{ name: "Network"; iconType: "globe" }` element, `onClicked: root.bookmarkClicked("network:///")`). Header text `"NETWORK"`, same style as the other `Text` headers (muted, uppercase, `fontSmall-1`, bold, letterSpacing 1.3).

- [ ] **Step 4: Bottom-pinned Trash with a mono count chip**

Move Trash OUT of the top list. After the existing flex spacer `Item { Layout.fillHeight: true }` (lines ~716-719), add a Trash row pinned at the bottom:

```qml
        // Trash — pinned at the very bottom, with a mono item-count chip.
        Rectangle {
            id: trashRow
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing / 2
            Layout.rightMargin: Theme.spacing / 2
            Layout.bottomMargin: Theme.spacing / 2
            height: 32
            radius: Theme.radiusRow
            readonly property bool isActive: fileOps.isTrashPath(root.currentPath)
            color: trashHover.containsMouse && !isActive
                   ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.03) : "transparent"
            Row {
                anchors.left: parent.left; anchors.leftMargin: Theme.spacing
                anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spacing
                Loader { width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter
                         sourceComponent: iconTrash
                         onLoaded: item.color = Qt.binding(() => trashRow.isActive ? Theme.gold : Theme.muted) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Trash"
                       color: trashRow.isActive ? Theme.text : Theme.subtext; font.pointSize: Theme.fontNormal }
            }
            // mono count chip (right-aligned)
            Text {
                anchors.right: parent.right; anchors.rightMargin: Theme.spacing
                anchors.verticalCenter: parent.verticalCenter
                visible: fsModel.trashEntryCount() > 0
                text: fsModel.trashEntryCount()
                font.family: Fonts.mono; font.pointSize: Theme.fontSmall
                color: Theme.muted
            }
            MouseArea {
                id: trashHover; anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (m) => {
                    if (m.button === Qt.RightButton) {
                        var p = trashHover.mapToItem(null, m.x, m.y)
                        root.sidebarContextMenuRequested({ kind: "quickAccess", name: "Trash",
                            path: root.trashPath, isRecents: false, isHidden: false }, Qt.point(p.x, p.y))
                        return
                    }
                    root.bookmarkClicked(root.trashPath)
                }
            }
        }
```

⚠ `fsModel.trashEntryCount()` — verify it is `Q_INVOKABLE` in `filesystemmodel.h`; if not, add `Q_INVOKABLE` to its declaration (line ~ the public `int trashEntryCount() const;`) so QML can call it, rebuild. The count is static at construction; a fully-live chip is out of scope (acceptable: it refreshes on reload).

- [ ] **Step 4b: Hover-reveal `+` add button on the FAVORITES header**

The handoff section headers reveal a `+` on hover. Wire it on the Favorites header to bookmark the active folder. The FAVORITES header is the `Text { text: "FAVORITES" }` (~line 288). Wrap it in a `RowLayout` (header text + a trailing `+` button) and add:

```qml
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing
            Layout.rightMargin: Theme.spacing
            Layout.topMargin: Theme.spacing / 2
            Text {
                Layout.fillWidth: true
                text: "FAVORITES"
                color: Theme.muted
                font.pointSize: Theme.fontSmall - 1
                font.bold: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.3
            }
            // Reveal on header hover; appends the active folder to bookmarks.
            IconPlus {
                id: favAdd
                size: 13
                color: favAddHover.containsMouse ? Theme.gold : Theme.muted
                opacity: favHeaderHover.hovered ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: Theme.animDurationFast } }
                MouseArea {
                    id: favAddHover
                    anchors.fill: parent; anchors.margins: -6
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var p = root.host ? root.host.activePanePath : ""
                        if (p && config.bookmarks.indexOf(p) < 0)
                            config.saveBookmarks(config.bookmarks.concat([p]))
                    }
                }
            }
        }
```

Add a `HoverHandler { id: favHeaderHover }` to the RowLayout so the `+` only shows on header hover. `IconPlus` is an existing `Wayfile` icon; `config.bookmarks`/`config.saveBookmarks` already exist. (`config` is the existing context property.) Replace the old standalone FAVORITES `Text` with this RowLayout.

- [ ] **Step 5: Plumb `host` into Sidebar**

Add `property var host: null` to `Sidebar.qml` root. In `SidebarPane.qml` where it instantiates `Sidebar { ... }`, pass `host: sidebarPane.host`. (Main.qml already passes `host: root` to `SidebarPane` — line ~1701.)

- [ ] **Step 6: Build + smoke + launch (full recipe)**

Expected exit 124, no QML errors. GUI (user) will verify ordering/tree later; for now confirm it loads.

- [ ] **Step 7: Commit**

```bash
git add src/qml/components/Sidebar.qml src/qml/components/SidebarPane.qml src/models/filesystemmodel.h
git commit -m "feat(sidebar): handoff section order + XDG tree in Places + bottom Trash w/ count chip + mono labels + 2px rail (W7)"
```

---

### Task 4: Hide-via-context-menu

**Files:**
- Modify: `src/qml/components/Sidebar.qml`, and the sidebar context-menu handler in `src/qml/Main.qml` (where `sidebarContextMenuRequested` is handled — find it).

- [ ] **Step 1: Filter every hideable entry against `config.hiddenSidebarEntries`**

Give each hideable row a stable `entryId` (e.g. `"places.recents"`, `"places.hidden"`, `"network"`, bookmark path, `"trash"`). Add `visible: config.hiddenSidebarEntries.indexOf(entryId) < 0` to each such row (Recents, Hidden, Network, Trash, each bookmark). Home is NOT hideable (no filter). `config` is the existing context property.

- [ ] **Step 2: Add a "Hide from sidebar" action to the sidebar context menu**

Find the menu opened by `sidebarContextMenuRequested` in Main.qml (the `mainOverlays.sidebarContextMenu` model). Add a `{ "label": "Hide from sidebar", "action": "hide-entry" }` item, and in its `onTriggered` call `config.hideSidebarEntry(item.entryId)`. Pass `entryId` through the `sidebarContextMenuRequested({...})` payload (add `entryId` to each row's payload object).

- [ ] **Step 3: Add a "Show hidden entries (N)" restore affordance**

In the sidebar context menu, when `config.hiddenSidebarEntries.length > 0`, add `{ "label": "Show hidden entries (" + config.hiddenSidebarEntries.length + ")", "action": "show-hidden" }` → `config.clearHiddenSidebarEntries()`.

- [ ] **Step 4: Build + smoke + launch (full recipe)** — exit 124, no errors.

- [ ] **Step 5: Commit**

```bash
git add src/qml/components/Sidebar.qml src/qml/Main.qml
git commit -m "feat(sidebar): hide entries via context menu + restore-all, persisted (W7)"
```

---

### Task 5: Compact rail (Full ↔ 56px) + toggle rewire

**Files:**
- Modify: `src/qml/components/SidebarPane.qml`, `src/qml/components/Sidebar.qml`, `src/qml/Main.qml`, `src/qml/components/Toolbar.qml` (toggle handler only)

- [ ] **Step 1: Drive width from `sidebarCompact`**

In `SidebarPane.qml`, the `Layout.preferredWidth` currently animates between `sidebarWidth` and 0 on `sidebarVisible`. Change so the toolbar toggle flips `config.sidebarCompact` instead of hiding:

```qml
    Layout.preferredWidth: host ? (host.sidebarCompact ? 56 : host.sidebarWidth) : 0
```

Add `property bool sidebarCompact: config.sidebarCompact` mirror to Main.qml (next to `sidebarWidth`/`sidebarVisible`, ~line 290), seeded in `Component.onCompleted` (~line 188) and toggled by the toolbar button. Disable the resize splitter when compact (`sidebarResizeHandle.enabled: host && !host.sidebarCompact`).

- [ ] **Step 2: Rewire the toolbar sidebar-toggle**

Find the toolbar `sidebarToggleBtn` `onClicked` (it currently flips `sidebarVisible`). Change it to toggle compact and persist:

```qml
                    onClicked: {
                        root.sidebarCompact = !root.sidebarCompact
                        config.saveSidebarCompact(root.sidebarCompact)
                    }
```

(Route via the existing signal the toolbar emits to Main; set `root.sidebarCompact` in Main's handler. Match the existing `sbHidden`-style plumbing — rename the toolbar's `sbHidden` read to `sidebarCompact` for the gold-highlight state.)

- [ ] **Step 3: Compact render in Sidebar**

In `Sidebar.qml`, wrap the full `ColumnLayout` in a `visible: !host.sidebarCompact` and add a sibling compact rail `Column` (`visible: host && host.sidebarCompact`, width 56) that renders the top-level visible entries as 36×32 centred icons (Favorites star, Home, Recents, Hidden, each XDG root, each device, Network, Trash). Active entry: `Qt.rgba(Theme.accent,0.10)` bg + 2px accent left-rail + glow; `Q.Tooltip`/existing tooltip layer on hover; click navigates (same handlers). Keep it simple — icons + tooltips, no expansion in compact.

- [ ] **Step 4: Build + smoke + launch (full recipe)** — exit 124, no errors.

- [ ] **Step 5: Commit**

```bash
git add src/qml/components/SidebarPane.qml src/qml/components/Sidebar.qml src/qml/Main.qml src/qml/components/Toolbar.qml
git commit -m "feat(sidebar): Full↔Compact 56px icon rail toggle, persisted (W7)"
```

---

### Task 6: Unify — remove the gallery special-case

**Files:**
- Modify: `src/qml/components/SidebarPane.qml`
- Delete: `src/qml/components/GalleryFolderNav.qml`
- Modify: `src/CMakeLists.txt`, and any `galleryFolderNavActive` references in `src/qml/Main.qml`

- [ ] **Step 1: Strip the gallery toggle from SidebarPane**

Remove `galleryActive`/`showFolderNav` properties (lines ~99-104), the gallery-only background Rectangle + Places/Folders segmented toggle (lines ~111-220), and the `GalleryFolderNav` instance (~222-225). The normal `Sidebar` now renders in every view (including Gallery). Keep the resize splitter and the obsidian gradient (the `Sidebar` already paints its own gradient; ensure no double-paint — the gallery-only background was a workaround now obsolete).

- [ ] **Step 2: Remove `galleryFolderNavActive` plumbing**

`/usr/bin/grep -rn "galleryFolderNavActive\|GalleryFolderNav\|showFolderNav\|galleryActive" src/qml` → remove every reference (Main.qml property + any bindings). 

- [ ] **Step 3: Delete the component + deregister**

```bash
git rm src/qml/components/GalleryFolderNav.qml
```
Remove `qml/components/GalleryFolderNav.qml` from `src/CMakeLists.txt` QML_FILES.

- [ ] **Step 4: Build + smoke + launch (full recipe)**

Expected exit 124, no "GalleryFolderNav is not a type" / unresolved-reference errors. `/usr/bin/grep -rn "GalleryFolderNav\|galleryFolderNav" src/` → zero hits.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(sidebar): drop gallery folder-nav special-case — unified sidebar with the Places tree everywhere (W7)"
```

---

### Task 7: Final verification

- [ ] **Step 1: Clean rebuild + full suite**

```bash
cmake -B build && cmake --build build -j$(nproc)
ctest --test-dir build
```
Expected: all tests PASS (incl. the 2 new config tests).

- [ ] **Step 2: Offscreen launch (recipe)** — exit 124, zero QML errors.

- [ ] **Step 3: Report for user GUI-verify (list explicitly):**
  - Section order Favorites · Places · Devices · Network · Trash(bottom)
  - Places: Home(mono)/Recents/Hidden quick rows + XDG roots expand to children; current folder gold + auto-revealed
  - Trash pinned at bottom with mono count chip
  - Right-click entry → "Hide from sidebar" → gone; "Show hidden (N)" restores; persists across restart
  - Toolbar toggle → Full ↔ Compact 56px icon rail (tooltips, active accent); resize splitter works in Full only
  - Gallery view now uses the same sidebar (tree in Places) — no missing folder-nav
  - No regression: bookmarks drag-add/reorder, device usage bars, context menus, keyboard nav, sidebar position left/right

**Out of scope (do not implement):** per-bookmark custom star colors UI; network mounted-share enumeration (browse entry only); user reordering of XDG roots.
