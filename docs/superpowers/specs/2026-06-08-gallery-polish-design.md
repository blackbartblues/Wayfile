# Gallery Polish — Design Spec

**Date:** 2026-06-08
**Branch:** `gallery-polish` (off `main`, which already carries the merged Gallery view)
**Status:** Design approved by user; ready for implementation plan.

## Goal

Three refinements to the existing Gallery view (the 5th view mode), driven by user
feedback after the first GUI pass:

1. **Sidebar background** — the gallery sidebar (folder navigator + Places/Folders
   toggle) is fully transparent. Give it the same obsidian background as the
   normal sidebar.
2. **Resizable filmstrip + thumbnail scaling** — the thumbnail strip is too narrow
   and the thumbnails too small. Widen it, add a drag-to-resize splitter, and make
   the thumbnails scale with the strip width.
3. **Real folder tree** — replace the current flat folder navigator (".." + a flat
   list of immediate subfolders) with a genuine, expandable filesystem tree.

These are refinements to a shipped feature, not a rewrite. The Gallery's selection
plumbing, preview engine, video playback, and metadata bar are unchanged.

---

## 1. Sidebar background (transparency fix)

**Problem:** In Gallery mode, `SidebarPane.qml` swaps the normal `Sidebar` (a
`Rectangle` painting an obsidian gradient `Theme.panel`→`Theme.mantle` + right
hairline) for `GalleryFolderNav` — a bare `Item` with no background. The
Places/Folders toggle strip above it is also background-less. Result: the whole
sidebar region is transparent in Gallery mode.

**Design:** Add a background `Rectangle` behind `sidebarStack` in `SidebarPane.qml`,
with the same obsidian vertical gradient and right-edge hairline as the normal
`Sidebar`, visible only when `galleryActive`. Outside Gallery the normal `Sidebar`
paints its own background, so the new rectangle stays hidden and nothing
double-paints.

---

## 2. Resizable filmstrip + thumbnail scaling

**Current:** `GalleryView.qml` hosts the filmstrip as a `FileGridView` with a fixed
`Layout.preferredWidth: 96` and `cellSize: 84`. `FileGridView` computes
`columnsPerRow = max(1, floor(width / cellSize))` and
`iconSize = min(cellSize, cellWidth) − padding`, so at width 96 / cellSize 84 it is
one column with a small (~70px) icon. There is a static 1px `Theme.line` divider
between the strip and the preview.

**Design:**
- New `property real stripWidth` on `GalleryView` (default **200**, clamped
  ~**120–480**). The strip's `Layout.preferredWidth` binds to it.
- Replace the static 1px divider with a **drag-to-resize splitter**: a 10px hit
  area with an accent line shown on hover/drag, mirroring the `sidebarResizeHandle`
  pattern in `SidebarPane.qml`. Dragging updates `stripWidth` (clamped).
- Bind the strip's `cellSize` to `stripWidth` (with a sane min so it never hits 0),
  keeping the strip a single column whose `iconSize` grows with the bar. Thumbnails
  scale live while dragging.
- **Persistence:** out of scope for this pass — `stripWidth` lives in memory and
  resets to the default on relaunch. A `config.galleryStripWidth` key (mirroring the
  existing `gridCellSize` persistence) is an optional follow-up, not part of this
  spec.

---

## 3. Real folder tree

**Current:** `GalleryFolderNav.qml` is a flat list — a ".." parent row plus the
immediate subfolders of the active pane's directory (a `DirFilterProxyModel` in
`FoldersOnly` mode over `fsModel`). It is a folder *entry point*, not a tree.

**Decisions (user-approved):**
- **Root:** Home (`~`). The tree starts at the home directory and expands downward.
  Navigation above Home via the tree is intentionally not offered.
- **Scope:** folders only; hidden folders excluded.
- **Interaction:** a **chevron** expands/collapses a node without navigating;
  clicking the folder **name** navigates the active pane there (the gallery's
  thumbnails + preview refresh) and expands that node. The folder currently shown in
  the gallery is **highlighted gold with a gold left-bar**, and the tree
  auto-expands and scrolls to reveal it.

**Architecture — Approach A (battle-tested):** Qt's built-in filesystem tree model
plus Qt Quick Controls `TreeView`, with a thin C++ wrapper and a themed delegate.

- **`FolderTreeModel : QFileSystemModel`** (`src/models/foldertreemodel.{h,cpp}`):
  - Constructor sets a folders-only filter (`QDir::AllDirs | QDir::NoDotAndDotDot`,
    no `QDir::Hidden`).
  - `Q_PROPERTY(QString rootPath)` (writable) → `setRootPath`, with change signal.
  - `Q_INVOKABLE QModelIndex indexForPath(const QString&)` and
    `Q_INVOKABLE QString pathAt(const QModelIndex&)` for path↔index mapping (the
    base `index(path)` / `filePath(index)` are not invokable from QML).
  - Registered via `qmlRegisterType` in `main.cpp` (like `DirFilterProxyModel`),
    **not** `QML_ELEMENT`, to keep the QtQml-free test targets building. QML then
    instantiates `FolderTreeModel {}` directly — no context property needed.
  - **No new dependency:** `QFileSystemModel` lives in the already-linked Qt6 Gui
    module; `TreeView` is in the already-used Qt Quick Controls.

- **`GalleryFolderNav.qml` rewritten on `TreeView`:**
  - `rootIndex` = the model's index for Home, so the visible tree is rooted at `~`.
  - Custom themed delegate: indentation by `depth`, a chevron glyph (rotates when
    expanded) on a MouseArea that toggles expand/collapse, a gold `IconFolder` glyph,
    and an elided name. Hover background as today. When the row's path equals the
    active pane path: gold fill highlight + gold left-bar.
  - Name MouseArea → `host.navigateActivePaneTo(path)` + expand the node.
  - **Auto-reveal:** when `host.activePanePath` changes and is under Home, expand the
    chain of ancestor nodes down to it and scroll it into view. `QFileSystemModel`
    populates directories asynchronously, so reveal is driven incrementally off the
    `directoryLoaded` signal (expand the next level as each loads).
  - Keeps the `host` property and `navigateActivePaneTo` contract; the ".." row and
    the flat `FoldersOnly` proxy are removed.

- **`SidebarPane.qml`:** the Places/Folders toggle is unchanged; it simply swaps in
  the new tree-based `GalleryFolderNav`. (Background handled in §1.)

**Version note:** `TreeView.rootIndex` requires Qt ≥ 6.6. The target is a rolling
distro with newer Qt; this is verified at build time. Fallback if ever needed: root
the model at `/` and auto-expand to Home on load.

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `src/models/foldertreemodel.h` / `.cpp` | Create | Folders-only `QFileSystemModel` subclass + path↔index invokables |
| `tests/tst_foldertreemodel.cpp` | Create | Unit tests (folders-only, hidden excluded, `indexForPath`/`pathAt` round-trip) |
| `src/qml/components/GalleryFolderNav.qml` | Rewrite | Themed `TreeView` folder tree rooted at Home |
| `src/qml/components/SidebarPane.qml` | Modify | Gallery sidebar background + hairline |
| `src/qml/views/GalleryView.qml` | Modify | `stripWidth`, drag-to-resize splitter, `cellSize` bound to width |
| `src/main.cpp` | Modify | `qmlRegisterType<FolderTreeModel>` |
| `src/CMakeLists.txt` | Modify | Add `foldertreemodel.cpp` to sources |
| `tests/CMakeLists.txt` | Modify | Register `tst_foldertreemodel` |

`GalleryFolderNav.qml` is already in `QML_FILES`; no QML_FILES change needed.

---

## Testing

- **Unit (`tst_foldertreemodel`, Qt6::Test):** build a temp directory tree with
  nested folders, files, and a hidden folder; assert the model exposes only
  (non-hidden) folders, that `indexForPath` round-trips with `pathAt`, and that an
  unknown path returns an invalid index.
- **Smoke (`tst_qml_smoke`):** the rewritten `GalleryFolderNav` (now a `TreeView`)
  instantiates within the Wayfile module.
- **Full suite:** `ctest --test-dir build -j1` stays green (23 tests + the new one).
- **Manual GUI verify (Wayland):** sidebar has a solid obsidian background in Gallery
  mode; the strip drags wider/narrower and thumbnails scale with it; the tree is
  rooted at Home, chevrons expand/collapse, clicking a name navigates the pane and
  the gallery refreshes, the current folder is gold and auto-revealed.

---

## Out of scope

- Persisting `stripWidth` across restarts (optional config follow-up).
- Showing hidden folders in the tree (could be a later toggle).
- Navigating above Home via the tree.
- Any change to the gallery preview, video playback, metadata bar, or selection.
