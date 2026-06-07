# Gallery View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 5th "Gallery" view mode — a vertical thumbnail filmstrip + a large preview of the selected media + a metadata bar — for browsing photos, videos, PDFs and audio without leaving the file manager.

**Architecture:** Gallery is a new pluggable view (`GalleryView.qml`) alongside hybrid/grid/detailed/miller. It reuses the existing `FileGridView` (narrow, single-column) as the filmstrip over a new `media` mode of `DirFilterProxyModel`, and reuses the shared `PreviewState` engine for the big preview + metadata. Video plays in-pane via Qt Multimedia (`MediaPlayer`/`VideoOutput`), started on click. Selection is exposed in source-model index space, exactly like `HybridView`, so Main.qml's existing plumbing is unchanged.

**Tech Stack:** Qt6 (Quick, Qml, **Multimedia** [new]), QML, C++ `QSortFilterProxyModel`, CMake, Qt6::Test + CTest.

**Spec:** `docs/superpowers/specs/2026-06-07-gallery-view-design.md`

**Branch:** `rebrand-wayfile` (builds on the Wayfile rebrand). Implement after the rebrand is merged/settled.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `src/models/dirfilterproxymodel.h` / `.cpp` | Add a `Media` filter mode (image/video/audio/pdf, no folders) | Modify |
| `tests/tst_dirfilterproxymodel.cpp` | Unit test for the `Media` mode | Modify |
| `src/qml/views/GalleryView.qml` | The Gallery view: filmstrip + preview + metadata | Create |
| `src/qml/views/FileViewContainer.qml` | Host `GalleryView`, expose `galleryViewItem`, route `selectAll`/`focusPath`, exclude gallery from the new-folder empty hero | Modify |
| `src/qml/components/StatusBar.qml` | 5th footer switcher icon → `"gallery"` | Modify |
| `src/qml/Main.qml` | `subViewFor` returns `galleryViewItem` for `"gallery"` | Modify |
| `CMakeLists.txt` | `find_package(Qt6 ... Multimedia)` | Modify |
| `src/CMakeLists.txt` | Link `Qt6::Multimedia`; add `GalleryView.qml` to QML_FILES | Modify |
| `PKGBUILD` | `qt6-multimedia` runtime dependency | Modify |
| `README.md`, `CLAUDE.md` | Dependency lists | Modify |

---

## Task 1: `Media` filter mode in DirFilterProxyModel (TDD)

**Files:**
- Modify: `src/models/dirfilterproxymodel.h:23` (enum), `src/models/dirfilterproxymodel.cpp:89-96` (`filterAcceptsRow`)
- Test: `tests/tst_dirfilterproxymodel.cpp`

- [ ] **Step 1: Write the failing test**

Add this slot to `tests/tst_dirfilterproxymodel.cpp` (after `testFilesOnlyKeepsOnlyFiles`, before the closing `};`/`QTEST_MAIN`). It builds a fixture with one of each media type plus non-media files and a folder, then asserts the `Media` mode keeps exactly the four media files:

```cpp
    void testMediaKeepsOnlyPreviewableMedia()
    {
        TestDir dir;
        dir.createDir("sub");
        dir.createFile("pic.png",   "d");   // image
        dir.createFile("clip.mp4",  "d");   // video
        dir.createFile("song.mp3",  "d");   // audio
        dir.createFile("doc.pdf",   "d");   // pdf (category "document", matched by extension)
        dir.createFile("notes.txt", "aaa"); // document → excluded
        dir.createFile("arch.zip",  "bb");  // archive → excluded

        FileSystemModel model; model.setSynchronousReload(true);
        model.setRootPath(dir.path());

        DirFilterProxyModel proxy;
        proxy.setMode(DirFilterProxyModel::Media);
        proxy.setSourceModel(&model);

        QCOMPARE(proxy.rowCount(), 4);
        QVERIFY(rowForName(proxy, "pic.png")  >= 0);
        QVERIFY(rowForName(proxy, "doc.pdf")  >= 0);
        QVERIFY(rowForName(proxy, "clip.mp4") >= 0);
        QVERIFY(rowForName(proxy, "song.mp3") >= 0);
        QCOMPARE(rowForName(proxy, "notes.txt"), -1);
        QCOMPARE(rowForName(proxy, "arch.zip"),  -1);
        QCOMPARE(rowForName(proxy, "sub"),       -1);
        for (int r = 0; r < proxy.rowCount(); ++r)
            QVERIFY(!proxy.isDir(r));
    }
```

- [ ] **Step 2: Build and confirm it fails to compile**

Run: `cmake --build build --target tst_dirfilterproxymodel`
Expected: **compile error** — `DirFilterProxyModel::Media` is not a member of the enum yet. (This is the red state for a compiled language.)

- [ ] **Step 3: Add `Media` to the enum**

In `src/models/dirfilterproxymodel.h`, change line 23:

```cpp
    enum Mode { FoldersOnly, FilesOnly, Media };
```

- [ ] **Step 4: Implement the predicate**

In `src/models/dirfilterproxymodel.cpp`, replace the whole `filterAcceptsRow` body (lines 89-96) with:

```cpp
bool DirFilterProxyModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    if (!sourceModel())
        return false;
    const QModelIndex idx = sourceModel()->index(sourceRow, 0, sourceParent);
    const bool isDirectory = sourceModel()->data(idx, FileSystemModel::IsDirRole).toBool();
    switch (m_mode) {
    case FoldersOnly:
        return isDirectory;
    case FilesOnly:
        return !isDirectory;
    case Media: {
        if (isDirectory)
            return false;
        const QString cat =
            sourceModel()->data(idx, FileSystemModel::FileCategoryRole).toString();
        if (cat == QLatin1String("image") || cat == QLatin1String("video")
            || cat == QLatin1String("audio"))
            return true;
        // PDFs are categorised as "document"; match them by extension instead.
        const QString ext =
            sourceModel()->data(idx, FileSystemModel::FileExtensionRole).toString();
        return ext.compare(QLatin1String("pdf"), Qt::CaseInsensitive) == 0;
    }
    }
    return false;
}
```

- [ ] **Step 5: Build and run the test — expect PASS**

Run: `cmake --build build --target tst_dirfilterproxymodel && ./build/tests/tst_dirfilterproxymodel`
Expected: PASS — all slots including `testMediaKeepsOnlyPreviewableMedia` pass.

- [ ] **Step 6: Run the full proxy suite to confirm no regression**

Run: `ctest --test-dir build -R tst_dirfilterproxymodel --output-on-failure`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/models/dirfilterproxymodel.h src/models/dirfilterproxymodel.cpp tests/tst_dirfilterproxymodel.cpp
git commit -m "feat(model): add Media filter mode to DirFilterProxyModel"
```

---

## Task 2: Add the Qt6 Multimedia dependency

**Files:**
- Modify: `CMakeLists.txt:12`, `src/CMakeLists.txt` (the `target_link_libraries(wayfile PRIVATE ...)` list, ~line 255)

- [ ] **Step 1: Add Multimedia to find_package**

In `CMakeLists.txt`, change line 12 to add `Multimedia`:

```cmake
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 DBus Widgets SvgWidgets Svg Network Concurrent Multimedia)
```

- [ ] **Step 2: Link Qt6::Multimedia into the target**

In `src/CMakeLists.txt`, find the `target_link_libraries(wayfile PRIVATE` block (~line 255) and add `Qt6::Multimedia` to the list of Qt6 libraries, e.g. on its own line alongside `Qt6::Quick`:

```cmake
    Qt6::Multimedia
```

- [ ] **Step 3: Reconfigure and build — expect success**

Run: `cmake -B build && cmake --build build`
Expected: configure finds Qt6 Multimedia; build succeeds (nothing uses it yet, so this only proves the dependency resolves). If configure fails with "Could not find Qt6Multimedia", install the package: `sudo pacman -S --needed qt6-multimedia`.

- [ ] **Step 4: Commit**

```bash
git add CMakeLists.txt src/CMakeLists.txt
git commit -m "build: add Qt6 Multimedia dependency for gallery video playback"
```

---

## Task 3: GalleryView.qml — filmstrip + image/PDF/audio preview + metadata

**Files:**
- Create: `src/qml/views/GalleryView.qml`
- Modify: `src/CMakeLists.txt` (QML_FILES list, ~line 126-139)

> Video playback is added in Task 4. This task gets the strip, the still-image / PDF / audio preview, the metadata bar, the empty state, and selection plumbing working. The `import QtMultimedia` line and the video layer come in Task 4.

- [ ] **Step 1: Register the new QML file**

In `src/CMakeLists.txt`, add to the `QML_FILES` list (right after `qml/views/HybridView.qml` on line 127):

```cmake
        qml/views/GalleryView.qml
```

- [ ] **Step 2: Create `src/qml/views/GalleryView.qml`**

```qml
import QtQuick
import QtQuick.Layouts
import Wayfile

// Gallery view (5th mode). A narrow vertical thumbnail filmstrip (a single-column
// FileGridView over a media-only proxy) on the left, a large preview of the
// selected item on the right, and a full metadata bar along the bottom.
//
// Selection is exposed in SOURCE-model index space (mapped back from the proxy),
// matching HybridView, so Main.qml's selection plumbing works unchanged.
FocusScope {
    id: root
    Accessible.role: Accessible.Pane
    Accessible.name: "Gallery"
    focus: visible

    // The pane's source model (same object Main.qml uses as paneModel).
    property var viewModel: null
    property string currentPath: ""

    signal fileActivated(string filePath, bool isDirectory)
    signal contextMenuRequested(string filePath, bool isDirectory, point position)
    signal selectionChanged()
    signal interactionStarted()
    signal transferRequested(var paths, string destinationPath, bool moveOperation)

    // ── Media-only proxy over the shared source model ───────────────────────
    DirFilterProxyModel {
        id: mediaProxy
        mode: DirFilterProxyModel.Media
    }
    onViewModelChanged: mediaProxy.switchSourceModel(viewModel)
    Component.onCompleted: {
        mediaProxy.switchSourceModel(viewModel)
        Qt.callLater(root._selectFirstIfNeeded)
    }

    // ── Selection (exposed in SOURCE index space) ───────────────────────────
    property var selectedIndices: []
    // Proxy row currently shown in the big preview (last-clicked); -1 if none.
    property int currentProxyRow: -1
    property string currentPreviewPath:
        currentProxyRow >= 0 ? mediaProxy.filePath(currentProxyRow) : ""

    function _sync() {
        var sel = strip.selectedIndices
        var out = []
        for (var i = 0; i < sel.length; ++i) {
            var sr = mediaProxy.mapRowToSource(sel[i])
            if (sr >= 0) out.push(sr)
        }
        root.selectedIndices = out
        root.currentProxyRow = sel.length > 0 ? sel[sel.length - 1] : -1
        root.selectionChanged()
    }

    // Auto-select the first media item when the list (re)populates and nothing is
    // selected, so the preview is never blank when media exists.
    function _selectFirstIfNeeded() {
        if (mediaProxy.count > 0 && strip.selectedIndices.length === 0)
            strip.focusPath(mediaProxy.filePath(0), false)
    }

    // Forwarders called by FileViewContainer / Main.qml on the active sub-view.
    function selectAll() { strip.selectAll() }
    function clearSelection() { strip.clearSelection() }
    function focusPath(path, reveal) { strip.focusPath(path, reveal) }

    Connections {
        target: strip
        function onSelectedIndicesChanged() { root._sync() }
    }
    Connections {
        target: mediaProxy
        function onCountChanged() { Qt.callLater(root._selectFirstIfNeeded) }
    }

    // ── Shared preview engine (same one Quick Preview uses) ─────────────────
    PreviewState {
        id: previewState
        filePath: root.currentPreviewPath
        isDir: false
        loadEnabled: root.visible
        fileModel: fsModel
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Filmstrip (left): a narrow, single-column FileGridView over the
        //    media proxy. Reuses its selection, context menu, drag & drop and
        //    keyboard nav; the narrow width forces one column (columnsPerRow =
        //    max(1, floor(width/cellSize))).
        FileGridView {
            id: strip
            Layout.fillHeight: true
            Layout.preferredWidth: 96
            model: mediaProxy
            currentPath: root.currentPath
            cellSize: 84
            zoomEnabled: false

            onFileActivated: (fp, isDir) => root.fileActivated(fp, isDir)
            onContextMenuRequested: (fp, isDir, pos) => root.contextMenuRequested(fp, isDir, pos)
            onInteractionStarted: root.interactionStarted()
            onTransferRequested: (paths, dst, move) => root.transferRequested(paths, dst, move)
        }

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: Theme.line
        }

        // ── Preview + metadata (right) ──────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Item {
                id: previewArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Empty state — no previewable media in this directory.
                Text {
                    anchors.centerIn: parent
                    visible: mediaProxy.count === 0
                    text: "No photos or videos here"
                    color: Theme.subtext
                    font.pointSize: Theme.fontNormal
                }

                // Still visual: image, PDF page, or video poster.
                Image {
                    id: stillImage
                    anchors.fill: parent
                    anchors.margins: 16
                    visible: previewState.isImage || previewState.isPdf
                             || (previewState.isVideo && previewState.hasVisualPreview)
                    source: previewState.isPdf ? previewState.pdfImageSource
                                               : previewState.visualSource
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                }

                // Audio / no-visual fallback card.
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: mediaProxy.count > 0 && !stillImage.visible
                    spacing: 8
                    IconImage {
                        Layout.alignment: Qt.AlignHCenter
                        size: 64
                        color: Theme.gold
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: previewState.fileName
                        color: Theme.text
                        font.pointSize: Theme.fontNormal
                    }
                }
            }

            // Metadata bar (bottom).
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                visible: mediaProxy.count > 0
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.raise }
                    GradientStop { position: 1.0; color: Theme.panel }
                }
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Theme.line
                }
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 18
                    Repeater {
                        model: previewState.metadataEntries
                        delegate: Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: modelData.label
                                color: Theme.muted
                                font.pixelSize: 9
                            }
                            Text {
                                text: modelData.value
                                color: Theme.text
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Rebuild (QML is compiled into the binary via rcc)**

Run: `cmake --build build`
Expected: build succeeds (QML_FILES picks up the new file; qmllint/cachegen run clean).

- [ ] **Step 4: Verify the module loads the new component**

Run: `ctest --test-dir build -R tst_qml_smoke --output-on-failure`
Expected: PASS — the Wayfile module (now including GalleryView) instantiates.

- [ ] **Step 5: Commit**

```bash
git add src/qml/views/GalleryView.qml src/CMakeLists.txt
git commit -m "feat(gallery): GalleryView with filmstrip, still/PDF/audio preview and metadata"
```

---

## Task 4: In-pane video playback (click-to-start)

**Files:**
- Modify: `src/qml/views/GalleryView.qml`

- [ ] **Step 1: Add the QtMultimedia import**

At the top of `src/qml/views/GalleryView.qml`, add the import after `import QtQuick.Layouts`:

```qml
import QtMultimedia
```

- [ ] **Step 2: Gate the still image and add the video layer + ▶ overlay**

In `previewArea`, change the `stillImage` `visible:` so the poster hides during playback, and add the play overlay + video layer **after** the audio fallback `ColumnLayout`. Replace the `stillImage` `visible:` line with:

```qml
                    visible: !videoLayer.playing
                             && (previewState.isImage || previewState.isPdf
                                 || (previewState.isVideo && previewState.hasVisualPreview))
```

Also change the audio fallback `ColumnLayout` `visible:` to also hide during playback:

```qml
                    visible: mediaProxy.count > 0 && !stillImage.visible && !videoLayer.playing
```

Then add, immediately before the closing `}` of `previewArea` (after the audio fallback `ColumnLayout`):

```qml
                // ▶ play overlay (click-to-start) for videos.
                Rectangle {
                    id: playOverlay
                    anchors.centerIn: parent
                    visible: previewState.isVideo && !videoLayer.playing
                    width: 72; height: 72; radius: 36
                    color: Qt.rgba(0, 0, 0, 0.45)
                    border.color: Theme.gold
                    border.width: 2
                    Text {
                        anchors.centerIn: parent
                        text: "▶"          // ▶
                        color: Theme.gold
                        font.pixelSize: 30
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: videoLayer.start()
                    }
                }

                // In-pane video playback (Qt Multimedia), started on demand.
                Item {
                    id: videoLayer
                    anchors.fill: parent
                    property bool playing: false
                    visible: playing

                    function start() {
                        mediaPlayer.source = "file://" + root.currentPreviewPath
                        mediaPlayer.play()
                        playing = true
                    }
                    function stop() {
                        mediaPlayer.stop()
                        mediaPlayer.source = ""
                        playing = false
                    }

                    VideoOutput {
                        id: videoOut
                        anchors.fill: parent
                        anchors.margins: 8
                        fillMode: VideoOutput.PreserveAspectFit
                    }
                    MediaPlayer {
                        id: mediaPlayer
                        videoOutput: videoOut
                        audioOutput: AudioOutput { id: audioOut }
                    }
                    // Click the video to toggle play/pause.
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mediaPlayer.playbackState === MediaPlayer.PlayingState
                                   ? mediaPlayer.pause() : mediaPlayer.play()
                    }
                }

                // Stop playback when the selected item changes.
                Connections {
                    target: root
                    function onCurrentPreviewPathChanged() {
                        if (videoLayer.playing) videoLayer.stop()
                    }
                }
```

- [ ] **Step 3: Rebuild**

Run: `cmake --build build`
Expected: build succeeds; the `QtMultimedia` import resolves (Task 2 added the dependency).

- [ ] **Step 4: Smoke test**

Run: `ctest --test-dir build -R tst_qml_smoke --output-on-failure`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/qml/views/GalleryView.qml
git commit -m "feat(gallery): in-pane video playback with click-to-start"
```

---

## Task 5: Wire GalleryView into FileViewContainer

**Files:**
- Modify: `src/qml/views/FileViewContainer.qml`

- [ ] **Step 1: Add the GalleryView instance**

In `src/qml/views/FileViewContainer.qml`, after the `FileMillerView { ... }` block (ends at line 100), add:

```qml
    GalleryView {
        id: galleryView
        anchors.fill: parent
        visible: root.viewMode === "gallery"
        viewModel: visible ? root.fileModel : null
        currentPath: root.currentPath

        onFileActivated: (fp, isDir) => root.fileActivated(fp, isDir)
        onContextMenuRequested: (fp, isDir, pos) => root.contextMenuRequested(fp, isDir, pos)
        onSelectionChanged: root.selectionChanged()
        onInteractionStarted: root.interactionStarted()
        onTransferRequested: (paths, destinationPath, moveOperation) => root.transferRequested(paths, destinationPath, moveOperation)
    }
```

- [ ] **Step 2: Expose the alias**

After line 43 (`property alias millerViewItem: millerView`), add:

```qml
    property alias galleryViewItem: galleryView
```

- [ ] **Step 3: Route `selectAll()` and `focusPath()`**

In `selectAll()` (lines 25-30), add a gallery branch:

```qml
        else if (viewMode === "gallery") galleryView.selectAll()
```

In `focusPath()` (lines 32-37), add the gallery view to the fan-out:

```qml
        galleryView.focusPath(path, reveal)
```

- [ ] **Step 4: Exclude gallery from the new-folder empty hero**

GalleryView shows its own "No photos or videos here" message, so the generic new-folder `EmptyState` must not also appear over it. Change the `EmptyState` `visible:` (line 118) to:

```qml
        visible: root.viewMode !== "miller" && root.viewMode !== "gallery"
                 && root._dirEmpty && root._canCreate
```

- [ ] **Step 5: Rebuild + smoke**

Run: `cmake --build build && ctest --test-dir build -R tst_qml_smoke --output-on-failure`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/qml/views/FileViewContainer.qml
git commit -m "feat(gallery): host GalleryView in FileViewContainer"
```

---

## Task 6: Footer switcher icon + Main.qml routing

**Files:**
- Modify: `src/qml/components/StatusBar.qml` (after the `detailedViewBtn` block, ~line 173-180), `src/qml/Main.qml` (`subViewFor`, line 552-556)

- [ ] **Step 1: Add the gallery switcher button**

In `src/qml/components/StatusBar.qml`, after the `detailedViewBtn` `HoverRect { ... }` block, add a matching button using `IconImage` (already registered in QML_FILES). Use the same structure as the sibling buttons:

```qml
            HoverRect {
                id: galleryViewBtn
                onClicked: statusBar.viewModeRequested("gallery")
                IconImage {
                    anchors.centerIn: parent
                    size: 16
                    color: statusBar.viewMode === "gallery" ? Theme.accent : Theme.subtext
                }
            }
```

> Match the exact width/height/anchoring of the existing `HoverRect` switcher buttons in this file (copy a sibling's property set). The icon `size: 16` and the `color:` ternary mirror `detailedViewBtn`.

- [ ] **Step 2: Route the view in Main.qml**

In `src/qml/Main.qml`, in `subViewFor` (lines 552-556), add a gallery branch before the final `return`:

```qml
        if (vm === "gallery") return view.galleryViewItem
```

So the function reads:

```qml
        var vm = tabModel.activeTab ? tabModel.activeTab.viewMode : "hybrid"
        if (vm === "hybrid") return view.hybridViewItem
        if (vm === "grid") return view.gridViewItem
        if (vm === "miller") return view.millerViewItem
        if (vm === "gallery") return view.galleryViewItem
        return view.detailedViewItem
```

- [ ] **Step 3: Rebuild + smoke**

Run: `cmake --build build && ctest --test-dir build -R tst_qml_smoke --output-on-failure`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/qml/components/StatusBar.qml src/qml/Main.qml
git commit -m "feat(gallery): footer view-switcher icon and Main routing"
```

---

## Task 7: Packaging & docs (qt6-multimedia dependency)

**Files:**
- Modify: `PKGBUILD` (depends), `README.md` (dependency table), `CLAUDE.md` (dependencies line), `io.github.blackbartblues.Wayfile.yml` (verify only)

- [ ] **Step 1: PKGBUILD runtime dependency**

In `PKGBUILD`, add `'qt6-multimedia'` to the `depends=( ... )` array (after `'qt6-svg'`):

```bash
    'qt6-multimedia'
```

- [ ] **Step 2: Regenerate `.SRCINFO`**

Run: `makepkg --printsrcinfo > .SRCINFO`
Expected: `.SRCINFO` now lists `depends = qt6-multimedia`.

- [ ] **Step 3: README dependency table**

In `README.md`, add `qt6-multimedia` to the **Required (runtime)** row of the dependencies table (it already lists `qt6-svg`, `qt6-wayland`, …):

```
qt6-multimedia (gallery video playback)
```

- [ ] **Step 4: CLAUDE.md dependencies line**

In `CLAUDE.md`, in the `## Dependencies` section, add `Multimedia` to the listed Qt6 modules and note `qt6-multimedia` provides in-app video playback for the gallery.

- [ ] **Step 5: Verify the Flatpak runtime ships QtMultimedia**

The Flatpak uses `org.kde.Platform 6.9`, which includes QtMultimedia — no manifest module is required. No edit needed; this step is a confirmation note in the commit body. (If a future `flatpak-builder` run reports the `QtMultimedia` QML import missing, add `qt6-multimedia` as a build module — out of scope here.)

- [ ] **Step 6: Commit**

```bash
git add PKGBUILD .SRCINFO README.md CLAUDE.md
git commit -m "docs(packaging): qt6-multimedia dependency for gallery video"
```

---

## Task 8: Manual GUI verification (Wayland)

> Not a code change — a verification checklist run against the built binary on the user's Hyprland session.

- [ ] **Step 1: Full build + test suite**

```bash
cmake --build build
rm -rf ~/.local/share/Trash/* ; ctest --test-dir build -j1 -E tst_giotransferworker
ctest --test-dir build -R tst_giotransferworker
```
Expected: all green.

- [ ] **Step 2: Launch and verify**

Launch `build/src/wayfile`, navigate to a folder with mixed media, and confirm:
- The footer switcher shows a 5th (image) icon; clicking it switches to Gallery and the icon goes gold.
- The left filmstrip lists only images/videos/PDFs/audio (no folders, no other files); the first item is auto-selected.
- Clicking / ↑↓ updates the big preview and the bottom metadata bar.
- A video shows its poster + ▶; clicking ▶ plays it in-pane with sound; clicking the video toggles pause; selecting another item stops playback.
- A PDF shows its first page; an audio file shows the fallback card; an image shows full-size, un-cropped.
- A folder with no media shows "No photos or videos here".
- Right-click on a thumbnail opens the context menu; copy/cut/delete operate on the strip selection.

- [ ] **Step 3: Confirm with the user** before considering the feature done.

---

## Self-Review

- **Spec coverage:** Mode shape (Task 5/6) ✓ · layout strip+preview+metadata (Task 3) ✓ · scope = previewable media (Task 1 predicate) ✓ · video click-to-start (Task 4) ✓ · qt6-multimedia dep + fallback (Task 2/7; fallback = poster shows when `hasVisualPreview`/`videoPreviewAvailable` is false, ▶ still attempts playback) ✓ · footer 5th icon (Task 6) ✓ · empty state (Task 3) ✓ · selection in source space / file ops (Task 3 `_sync`) ✓ · first-item-on-entry (Task 3 `_selectFirstIfNeeded`) ✓ · per-tab persistence (free — `viewMode` is a per-tab string; no enum to extend) ✓ · keyboard nav (free — reused FileGridView) ✓.
- **Placeholder scan:** no TBD/TODO; every code step shows complete code. Step 1 of Task 6 says "match the sibling HoverRect property set" — the engineer copies an adjacent button's exact geometry, which is shown in the same file (not a placeholder, a concrete instruction).
- **Type consistency:** `DirFilterProxyModel.Media` (enum, Task 1) used in `GalleryView` (Task 3) ✓ · `galleryViewItem` alias (Task 5) returned by `subViewFor` (Task 6) ✓ · `currentPreviewPath`, `_sync`, `_selectFirstIfNeeded`, `videoLayer.playing/start()/stop()` all defined and referenced within Task 3/4 ✓ · `mediaProxy.filePath/mapRowToSource/count` match the proxy's existing API ✓ · `previewState.metadataEntries` (array of `{label,value}`), `visualSource`, `pdfImageSource`, `isImage/isVideo/isPdf/hasVisualPreview` match PreviewState ✓.

## Execution notes

- Each task is independently buildable + committable. Tasks 1-2 are backend/build; 3-6 are the feature; 7 packaging; 8 verification.
- QML changes require `cmake --build build` before any smoke test (QML is rcc'd into the binary).
- Implement on `rebrand-wayfile` after the rebrand is merged, or rebase onto `main` once the rebrand lands.
