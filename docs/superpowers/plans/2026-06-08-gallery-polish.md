# Gallery Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three refinements to the shipped Gallery view — give the gallery sidebar a real background, make the thumbnail filmstrip drag-resizable with width-scaled thumbnails, and replace the flat folder navigator with a genuine expandable folder tree.

**Architecture:** A new thin C++ `FolderTreeModel : QFileSystemModel` (folders-only, Qt's built-in lazy filesystem tree) is rendered by a themed Qt Quick Controls `TreeView` in a rewritten `GalleryFolderNav.qml`, rooted at Home. `SidebarPane.qml` gains an obsidian background behind the gallery sidebar. `GalleryView.qml` gains a `stripWidth` property, a drag-to-resize splitter, and a `cellSize` bound to the strip width so thumbnails scale.

**Tech Stack:** Qt6 (QFileSystemModel in Qt6::Gui — no new dependency), Qt Quick Controls `TreeView` (≥ 6.6), QML, CMake, Qt6::Test + CTest.

**Spec:** `docs/superpowers/specs/2026-06-08-gallery-polish-design.md`

**Branch:** `gallery-polish` (off `main`).

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `src/models/foldertreemodel.h` / `.cpp` | Folders-only `QFileSystemModel` + path↔index invokables | Create |
| `tests/tst_foldertreemodel.cpp` | Unit tests (folders-only, hidden excluded, round-trip) | Create |
| `tests/CMakeLists.txt` | Register `tst_foldertreemodel` target | Modify |
| `src/CMakeLists.txt` | Add `models/foldertreemodel.cpp` to sources | Modify |
| `src/main.cpp` | `qmlRegisterType<FolderTreeModel>` | Modify |
| `src/qml/components/GalleryFolderNav.qml` | Themed `TreeView` folder tree rooted at Home | Rewrite |
| `src/qml/components/SidebarPane.qml` | Obsidian background for the gallery sidebar | Modify |
| `src/qml/views/GalleryView.qml` | `stripWidth`, resize splitter, width-scaled `cellSize` | Modify |

`GalleryFolderNav.qml` is already in `QML_FILES` — no QML_FILES edit needed.

---

## Task 1: `FolderTreeModel` — folders-only QFileSystemModel (TDD)

**Files:**
- Create: `src/models/foldertreemodel.h`, `src/models/foldertreemodel.cpp`
- Test: `tests/tst_foldertreemodel.cpp`
- Modify: `tests/CMakeLists.txt`, `src/CMakeLists.txt`, `src/main.cpp`

- [ ] **Step 1: Write the failing test**

Create `tests/tst_foldertreemodel.cpp`:

```cpp
#include <QTest>
#include <QStandardPaths>
#include <QFileSystemModel>
#include "models/foldertreemodel.h"
#include "testdir.h"

// Unit tests for FolderTreeModel — the folders-only QFileSystemModel that backs
// the Gallery sidebar's folder tree. QFileSystemModel populates directories
// asynchronously, so QTRY_* is used to wait for the watched dir to load.
class TestFolderTreeModel : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
    }

    void testListsOnlyFolders()
    {
        TestDir dir;
        dir.createDir("alpha");
        dir.createDir("beta");
        dir.createFile("note.txt", "x");   // file → excluded

        FolderTreeModel model;
        const QModelIndex root = model.setRootPath(dir.path());
        QTRY_COMPARE(model.rowCount(root), 2);

        QStringList names;
        for (int r = 0; r < model.rowCount(root); ++r)
            names << model.index(r, 0, root).data(QFileSystemModel::FileNameRole).toString();
        names.sort();
        QCOMPARE(names, (QStringList{"alpha", "beta"}));
    }

    void testExcludesHiddenFolders()
    {
        TestDir dir;
        dir.createDir("visible");
        dir.createDir(".secret");          // hidden folder → excluded

        FolderTreeModel model;
        const QModelIndex root = model.setRootPath(dir.path());
        QTRY_COMPARE(model.rowCount(root), 1);
        QCOMPARE(model.index(0, 0, root).data(QFileSystemModel::FileNameRole).toString(),
                 QString("visible"));
    }

    void testIndexForPathRoundTrips()
    {
        TestDir dir;
        dir.createDir("alpha");

        FolderTreeModel model;
        const QModelIndex root = model.setRootPath(dir.path());
        QTRY_COMPARE(model.rowCount(root), 1);

        const QString alphaPath = dir.path() + "/alpha";
        const QModelIndex idx = model.indexForPath(alphaPath);
        QVERIFY(idx.isValid());
        QCOMPARE(model.pathAt(idx), alphaPath);

        QVERIFY(!model.indexForPath(dir.path() + "/does-not-exist").isValid());
    }
};

QTEST_MAIN(TestFolderTreeModel)
#include "tst_foldertreemodel.moc"
```

- [ ] **Step 2: Register the test target**

In `tests/CMakeLists.txt`, add after the `tst_dirfilterproxymodel` block (the `add_test(NAME tst_dirfilterproxymodel ...)` line, ~line 210):

```cmake
add_executable(tst_foldertreemodel tst_foldertreemodel.cpp
    ${CMAKE_SOURCE_DIR}/src/models/foldertreemodel.cpp
)
target_include_directories(tst_foldertreemodel PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_SOURCE_DIR}/src/third_party
)
target_link_libraries(tst_foldertreemodel PRIVATE Qt6::Test Qt6::Core Qt6::Gui Qt6::Widgets)
add_test(NAME tst_foldertreemodel COMMAND tst_foldertreemodel)
```

- [ ] **Step 3: Build and confirm it fails to compile**

Run: `cmake -B build && cmake --build build --target tst_foldertreemodel`
Expected: **compile error** — `foldertreemodel.h` does not exist / `FolderTreeModel` undeclared. (Red state for a compiled language.)

- [ ] **Step 4: Create the header**

Create `src/models/foldertreemodel.h`:

```cpp
#pragma once

#include <QFileSystemModel>

// Folders-only filesystem tree model for the Gallery sidebar's folder tree.
// Subclasses QFileSystemModel (Qt's built-in, lazily-populated FS tree) and:
//   - filters to directories only, excluding hidden ones,
//   - exposes rootPath as a QML-writable property (the base setRootPath()
//     returns a QModelIndex, so a void wrapper `setRootDir` backs the WRITE),
//   - adds indexForPath()/pathAt() invokables to bridge QML <-> QModelIndex,
//     used to root the TreeView at Home and to auto-reveal the active folder.
//
// Registered as a creatable QML type in main.cpp (qmlRegisterType into the
// "Wayfile" module). Kept Qt6::Qml-free so the unit test can link it alone.
class FolderTreeModel : public QFileSystemModel
{
    Q_OBJECT
    Q_PROPERTY(QString rootPath READ rootPath WRITE setRootDir NOTIFY rootPathChanged)

public:
    explicit FolderTreeModel(QObject *parent = nullptr);

    // QML-writable wrapper around the base setRootPath() (which returns an index).
    void setRootDir(const QString &path);

    Q_INVOKABLE QModelIndex indexForPath(const QString &path) const;
    Q_INVOKABLE QString pathAt(const QModelIndex &index) const;
};
```

> Note: `NOTIFY rootPathChanged` reuses QFileSystemModel's own `rootPathChanged(const QString&)` signal; `READ rootPath` reuses its inherited getter. We only add the `setRootDir` write wrapper because the base `setRootPath` returns `QModelIndex` and cannot back a Q_PROPERTY WRITE.

- [ ] **Step 5: Create the implementation**

Create `src/models/foldertreemodel.cpp`:

```cpp
#include "models/foldertreemodel.h"

#include <QDir>

FolderTreeModel::FolderTreeModel(QObject *parent)
    : QFileSystemModel(parent)
{
    // Directories only (no files): QDir::AllDirs lists directories and, with no
    // QDir::Files flag, files are omitted; QDir::NoDotAndDotDot drops "."/".."
    // and, with no QDir::Hidden, hidden folders are excluded.
    setFilter(QDir::AllDirs | QDir::NoDotAndDotDot);
    setReadOnly(true);
}

void FolderTreeModel::setRootDir(const QString &path)
{
    if (path == rootPath())
        return;
    QFileSystemModel::setRootPath(path);  // emits the base rootPathChanged()
}

QModelIndex FolderTreeModel::indexForPath(const QString &path) const
{
    return index(path);   // QFileSystemModel::index(const QString&)
}

QString FolderTreeModel::pathAt(const QModelIndex &idx) const
{
    return filePath(idx); // QFileSystemModel::filePath(const QModelIndex&)
}
```

- [ ] **Step 6: Build and run the test — expect PASS**

Run: `cmake -B build && cmake --build build --target tst_foldertreemodel && ./build/tests/tst_foldertreemodel`
Expected: PASS — all three slots pass.

> If the build cannot find `<QFileSystemModel>`, confirm it resolves via Qt6::Gui (Qt 6 ships QFileSystemModel in the Gui module). The test target already links Qt6::Gui and Qt6::Widgets.

- [ ] **Step 7: Add the model to the app's sources**

In `src/CMakeLists.txt`, add to `WAYFILE_SOURCES` right after line 30 (`models/dirfilterproxymodel.cpp`):

```cmake
    models/foldertreemodel.cpp
```

- [ ] **Step 8: Register the QML type**

In `src/main.cpp`, add the include after line 43 (`#include "models/dirfilterproxymodel.h"`):

```cpp
#include "models/foldertreemodel.h"
```

And add the registration after line 406 (`qmlRegisterType<DirFilterProxyModel>(...)`):

```cpp
    qmlRegisterType<FolderTreeModel>("Wayfile", 1, 0, "FolderTreeModel");
```

- [ ] **Step 9: Build the whole app**

Run: `cmake --build build`
Expected: build succeeds (the type is registered but not yet used).

- [ ] **Step 10: Commit**

```bash
git add src/models/foldertreemodel.h src/models/foldertreemodel.cpp tests/tst_foldertreemodel.cpp tests/CMakeLists.txt src/CMakeLists.txt src/main.cpp
git commit -m "feat(gallery): FolderTreeModel — folders-only QFileSystemModel for the tree"
```

---

## Task 2: Real folder tree in the gallery sidebar (`TreeView`)

**Files:**
- Rewrite: `src/qml/components/GalleryFolderNav.qml`

- [ ] **Step 1: Rewrite `GalleryFolderNav.qml` as a themed TreeView**

Replace the entire contents of `src/qml/components/GalleryFolderNav.qml` with:

```qml
import QtQuick
import QtQuick.Controls
import Wayfile

// Folder TREE shown in the sidebar while the Gallery view is active (SidebarPane
// swaps it in for the normal Sidebar). A real, expandable filesystem tree rooted
// at Home over FolderTreeModel (a folders-only QFileSystemModel). A chevron
// expands/collapses a node without navigating; clicking a folder NAME navigates
// the active pane there (the gallery's thumbnails + preview refresh) and expands
// that node. The folder currently shown is highlighted gold and auto-revealed.
Item {
    id: root
    Accessible.role: Accessible.Pane
    Accessible.name: "Folder tree"

    // Main.qml root — provides activePanePath + navigateActivePaneTo.
    property var host: null

    readonly property string homeDir: fsModel.homePath()
    readonly property string currentDir: host ? host.activePanePath : ""
    readonly property color _hoverBg: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
    readonly property color _currentBg: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.18)
    readonly property int _indent: 14
    readonly property int _rowHeight: 30

    FolderTreeModel {
        id: folderTree
        rootPath: root.homeDir
    }

    TreeView {
        id: tree
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: folderTree

        // One column that always fills the sidebar width.
        columnWidthProvider: function (column) { return tree.width }
        onWidthChanged: forceLayout()

        // Root the visible tree at Home. QFileSystemModel populates dirs
        // asynchronously, so (re)assign once Home's node is ready, then reveal.
        Component.onCompleted: tree.rootIndex = folderTree.indexForPath(root.homeDir)
        Connections {
            target: folderTree
            function onDirectoryLoaded(loadedPath) {
                if (loadedPath === root.homeDir)
                    tree.rootIndex = folderTree.indexForPath(root.homeDir)
                root._revealCurrent()
            }
        }

        delegate: Item {
            id: rowItem
            implicitHeight: root._rowHeight
            implicitWidth: tree.width

            // TableView/TreeView delegate context.
            required property int row
            required property string display          // DisplayRole = file name

            // TreeView attached state.
            readonly property var _view: TreeView.view
            readonly property int _depth: TreeView.depth
            readonly property bool _expanded: TreeView.expanded
            readonly property bool _hasKids: TreeView.hasChildren

            readonly property string fullPath: folderTree.pathAt(tree.modelIndex(rowItem.row, 0))
            readonly property bool isCurrent: rowItem.fullPath === root.currentDir
            readonly property int _leftPad: 4 + rowItem._depth * root._indent

            // Background: gold for the current folder, faint hover otherwise.
            Rectangle {
                anchors.fill: parent
                color: rowItem.isCurrent ? root._currentBg
                       : (rowHover.hovered ? root._hoverBg : "transparent")
            }
            Rectangle {                       // gold left-bar for the current folder
                visible: rowItem.isCurrent
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 3
                color: Theme.gold
            }
            HoverHandler { id: rowHover }

            // Chevron (expand/collapse, no navigation) — only when the node has children.
            Item {
                id: chevron
                x: rowItem._leftPad
                width: 16
                height: parent.height
                IconChevronRight {
                    anchors.centerIn: parent
                    visible: rowItem._hasKids
                    size: 13
                    color: Theme.subtext
                    rotation: rowItem._expanded ? 90 : 0
                    Behavior on rotation { NumberAnimation { duration: 120 } }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: rowItem._hasKids
                    cursorShape: Qt.PointingHandCursor
                    onClicked: rowItem._view.toggleExpanded(rowItem.row)
                }
            }

            // Folder glyph + name — clicking navigates the active pane + expands.
            Row {
                anchors.left: chevron.right
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                IconFolder {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 15
                    color: Theme.gold
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 15 - 6
                    text: rowItem.display
                    color: Theme.text
                    font.pointSize: Theme.fontNormal
                    elide: Text.ElideRight
                }
            }
            MouseArea {
                anchors.left: chevron.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.host)
                        root.host.navigateActivePaneTo(rowItem.fullPath)
                    if (rowItem._hasKids && !rowItem._expanded)
                        tree.expand(rowItem.row)
                }
            }
        }
    }

    onCurrentDirChanged: _revealCurrent()

    // Expand the ancestor chain down to the active folder and scroll it into
    // view. Best-effort: if the path's node is not loaded yet, expandToIndex is
    // a no-op and this re-runs on the next directoryLoaded.
    function _revealCurrent() {
        if (!root.currentDir)
            return
        var idx = folderTree.indexForPath(root.currentDir)
        tree.expandToIndex(idx)
        Qt.callLater(function () {
            var r = tree.rowAtIndex(idx)
            if (r >= 0)
                tree.positionViewAtRow(r, TableView.Contain)
        })
    }
}
```

> API notes (all Qt Quick Controls ≥ 6.6): `tree.modelIndex(row, 0)` maps a flattened row to its `QModelIndex`; `TreeView.view.toggleExpanded(row)` / `tree.expand(row)` change expansion; `tree.expandToIndex(index)` expands all ancestors of `index`; `tree.rowAtIndex(index)` returns the visible row (or -1); `positionViewAtRow(row, TableView.Contain)` is inherited from TableView. `display` is `Qt::DisplayRole` (the file name); QFileSystemModel does not expose custom QML role names, so the path comes from `folderTree.pathAt(...)`.

- [ ] **Step 2: Rebuild (QML is rcc'd into the binary)**

Run: `cmake --build build`
Expected: build succeeds; qmllint/cachegen run clean.

- [ ] **Step 3: Smoke test**

Run: `ctest --test-dir build -R tst_qml_smoke --output-on-failure`
Expected: PASS — the Wayfile module (now with the TreeView-based GalleryFolderNav) instantiates.

> If smoke fails with "TreeView is not a type", confirm `import QtQuick.Controls` resolves (the module is already used elsewhere in the project). If it fails on `modelIndex`/`expandToIndex`, the installed Qt Quick Controls is < 6.6 — fall back to `tree.index(row, 0)` and manual ancestor expansion; record the Qt version in the commit body.

- [ ] **Step 4: Commit**

```bash
git add src/qml/components/GalleryFolderNav.qml
git commit -m "feat(gallery): real folder tree (TreeView) in the gallery sidebar"
```

---

## Task 3: Obsidian background for the gallery sidebar

**Files:**
- Modify: `src/qml/components/SidebarPane.qml`

- [ ] **Step 1: Add the background rectangle**

In `src/qml/components/SidebarPane.qml`, immediately AFTER the `readonly property bool showFolderNav:` block (it ends at the line `galleryActive && (host ? host.galleryFolderNavActive : false)`) and BEFORE `Column { id: sidebarStack`, insert:

```qml
    // Obsidian background for the Gallery sidebar. In Gallery mode the normal
    // Sidebar (which paints its own gradient) is hidden and replaced by the
    // background-less folder tree + toggle, so paint the same obsidian gradient
    // and right hairline here. Outside Gallery this stays hidden and the normal
    // Sidebar paints itself, so nothing double-paints.
    Rectangle {
        anchors.fill: parent
        visible: sidebarPane.galleryActive
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.panel }
            GradientStop { position: 1.0; color: Theme.mantle }
        }
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Theme.hair
        }
    }
```

> It is declared before `sidebarStack`, so it renders behind the toggle + tree. The resize handle `MouseArea` (declared later with `z: 10`) still sits on top.

- [ ] **Step 2: Rebuild + smoke**

Run: `cmake --build build && ctest --test-dir build -R tst_qml_smoke --output-on-failure`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add src/qml/components/SidebarPane.qml
git commit -m "fix(gallery): give the gallery sidebar an obsidian background"
```

---

## Task 4: Drag-to-resize filmstrip with width-scaled thumbnails

**Files:**
- Modify: `src/qml/views/GalleryView.qml`

- [ ] **Step 1: Add the strip-width properties**

In `src/qml/views/GalleryView.qml`, add these properties right after `property string currentPath: ""` (line 20):

```qml
    // Resizable filmstrip width (drag the splitter). In-memory only — resets to
    // the default on relaunch (persistence is an optional config follow-up).
    property real stripWidth: 200
    readonly property real minStripWidth: 120
    readonly property real maxStripWidth: 480
```

- [ ] **Step 2: Bind the strip width + thumbnail size to `stripWidth`**

In the `FileGridView { id: strip ... }` block, change the fixed width and cell size.

Replace:

```qml
            Layout.preferredWidth: 96
```

with:

```qml
            Layout.preferredWidth: root.stripWidth
```

Replace:

```qml
            cellSize: 84
```

with:

```qml
            // One column that fills the strip; iconSize = cellSize − padding, so
            // thumbnails grow with the bar. Min keeps cellSize sane at narrow widths.
            cellSize: Math.max(96, Math.round(root.stripWidth))
```

- [ ] **Step 3: Replace the static divider with a drag-to-resize splitter**

Replace the 1px divider block between the strip and the preview column:

```qml
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: Theme.line
        }
```

with:

```qml
        // Drag-to-resize splitter between the filmstrip and the preview.
        Item {
            Layout.fillHeight: true
            Layout.preferredWidth: 6
            Rectangle {
                anchors.centerIn: parent
                width: (splitterHandle.containsMouse || splitterHandle.pressed) ? 2 : 1
                height: parent.height
                color: (splitterHandle.containsMouse || splitterHandle.pressed)
                       ? Theme.accent : Theme.line
                opacity: splitterHandle.pressed ? 0.9
                         : (splitterHandle.containsMouse ? 0.6 : 1.0)
            }
            MouseArea {
                id: splitterHandle
                anchors.fill: parent
                anchors.margins: -3                  // ~12px hit area
                hoverEnabled: true
                cursorShape: Qt.SizeHorCursor
                preventStealing: true
                property real startX: 0
                property real startW: 0
                onPressed: (mouse) => {
                    startX = mapToItem(root, mouse.x, 0).x
                    startW = root.stripWidth
                }
                onPositionChanged: (mouse) => {
                    if (!pressed)
                        return
                    var dx = mapToItem(root, mouse.x, 0).x - startX
                    root.stripWidth = Math.max(root.minStripWidth,
                                      Math.min(root.maxStripWidth, startW + dx))
                }
            }
        }
```

> Deltas are measured against `root` (GalleryView), a stable coordinate space that does not move while the strip grows, so the drag tracks the cursor 1:1.

- [ ] **Step 4: Rebuild + smoke**

Run: `cmake --build build && ctest --test-dir build -R tst_qml_smoke --output-on-failure`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/qml/views/GalleryView.qml
git commit -m "feat(gallery): drag-to-resize filmstrip with width-scaled thumbnails"
```

---

## Task 5: Full build + test suite + manual GUI verification (Wayland)

> Not a code change — verification against the built binary on the user's Hyprland session.

- [ ] **Step 1: Full build + test suite**

```bash
cmake --build build
rm -rf ~/.local/share/Trash/* ; ctest --test-dir build -j1
```
Expected: all green (the prior 23 tests + `tst_foldertreemodel`). Run `-j1` — parallel runs flake the gio-trash tests.

- [ ] **Step 2: Launch and verify**

Launch `build/src/wayfile`, switch to Gallery (footer image icon), and confirm:
- The sidebar has a solid obsidian background (no transparency) behind both the Places/Folders toggle and the folder area.
- **Folder tree:** the Folders tab shows a real tree rooted at Home. Chevrons expand/collapse nodes without navigating. Clicking a folder name navigates the active pane there (thumbnails + preview refresh) and expands that node. The current folder is highlighted gold with a gold left-bar, and the tree auto-expands/scrolls to reveal it when you navigate from elsewhere.
- **Filmstrip:** dragging the splitter between the strip and the preview widens/narrows the strip; the thumbnails scale up/down with the width; the strip clamps between ~120 and ~480px.
- Toggling back to Places restores the normal sidebar; leaving Gallery restores Places automatically (unchanged behaviour).

- [ ] **Step 3: Confirm with the user** before considering the work done.

---

## Self-Review

- **Spec coverage:** §1 sidebar background → Task 3 ✓ · §2 resizable filmstrip + thumbnail scaling → Task 4 (`stripWidth`, splitter, `cellSize` bound to width) ✓ · §3 real folder tree → Task 1 (`FolderTreeModel`) + Task 2 (`TreeView`, Home root, chevron-expands/name-navigates, gold current + auto-reveal) ✓ · testing (unit + smoke + manual) → Task 1 test, Tasks 2-4 smoke, Task 5 ✓ · out-of-scope (stripWidth persistence, hidden folders, preview/video/selection untouched) honoured ✓.
- **Placeholder scan:** no TBD/TODO; every code step shows complete code. The two "if it fails …" notes are fallback guidance, not placeholders.
- **Type consistency:** `FolderTreeModel` with `setRootDir`, `indexForPath`, `pathAt` (Task 1) is exactly what Task 2 uses (`folderTree.rootPath`, `folderTree.indexForPath`, `folderTree.pathAt`) ✓ · `qmlRegisterType<FolderTreeModel>("Wayfile", …)` (Task 1) matches `FolderTreeModel {}` in QML (Task 2) ✓ · `stripWidth`/`minStripWidth`/`maxStripWidth` defined (Task 4 Step 1) and used (Steps 2-3) ✓ · `host.activePanePath` / `host.navigateActivePaneTo` / `fsModel.homePath()` verified against Main.qml:304/718 and filesystemmodel.h:100 ✓ · `IconChevronRight`, `IconFolder` exist in QML_FILES ✓ · `Theme.panel/mantle/hair/gold/accent/line/subtext/text/fontNormal` all already used in Sidebar.qml/GalleryFolderNav.qml ✓.

## Execution notes

- Each task is independently buildable + committable. Task 1 is backend/build (TDD); Tasks 2-4 are the three UI changes; Task 5 is verification.
- QML changes require `cmake --build build` before any smoke test (QML is rcc'd into the binary).
- `TreeView` API used (`modelIndex`, `expandToIndex`, `rowAtIndex`) needs Qt Quick Controls ≥ 6.6; verify at build time (Task 2 Step 3 note).
