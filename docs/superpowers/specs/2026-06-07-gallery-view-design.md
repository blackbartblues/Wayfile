# Gallery View — Design Spec

**Date:** 2026-06-07
**Status:** Approved (brainstorm), ready for implementation plan
**Branch:** `rebrand-wayfile` (builds on the Wayfile rebrand)

## Goal

A new **Gallery** view mode for browsing photos and videos (and other previewable
media) without leaving the file manager. It pairs a narrow thumbnail strip with a
large preview of the selected item and a full metadata bar, so the user can flip
through media quickly and watch videos in place.

## Locked decisions

1. **Mode shape:** a 5th *view mode* (alongside `hybrid | grid | detailed | miller`),
   selectable from the footer view switcher. It keeps the app chrome (tabs,
   sidebar, toolbar/breadcrumb) and renders inside the content area — it is **not**
   a fullscreen overlay.
2. **Layout:** vertical thumbnail strip on the **left**, large preview filling the
   rest on the **right**, full metadata in a bar along the **bottom**.
3. **File scope:** all *previewable media* — images, videos, PDFs, audio. Folders
   are excluded from the strip; directory navigation uses the breadcrumb/sidebar
   (which mode C keeps visible).
4. **Video:** in-app playback, **click-to-start** — the preview shows the poster
   frame with a ▶ overlay; clicking plays the video in the preview pane with
   controls (play/pause, seek, volume). Requires the `qt6-multimedia` dependency.

## UX & layout

- **Thumbnail strip (left, ~84 px wide):** square, cropped thumbnails of every
  previewable-media item in the current directory. The selected item shows a gold
  ring + glow. Video items carry a small ▶ badge. Scrolls vertically.
- **Preview pane (right, fills remaining space):** the full-size rendering of the
  current item, `object-fit: contain` (whole item, no cropping). Per type:
  - **Image** → full-resolution `Image`.
  - **Video** → poster frame + large ▶; click starts in-pane playback with
    controls.
  - **PDF** → rendered page image (reuse the existing PDF preview source).
  - **Audio** → cover art / metadata card (reuse existing audio handling).
- **Metadata bar (bottom):** comprehensive details for the current item — name,
  dimensions, file size, date; EXIF (aperture / shutter / ISO) for photos;
  codec / duration / resolution for video. Laid out horizontally.
- **Footer switcher:** gains a 5th icon (gold when active) next to the existing
  grid / detailed / miller / hybrid icons.
- **Empty state:** a folder with no previewable media shows a "No photos or
  videos here" message.

## Interaction & keyboard

- **Click** a thumbnail → selects it and updates the preview + metadata.
- **↑ / ↓** → move to the previous / next item in the strip.
- **Enter / double-click** → open the current item in the system default app.
- **Selection semantics match the other views:** single click selects; Ctrl /
  Shift extend a multi-selection, so file operations (copy / cut / delete, context
  menu) and the status-bar count work as everywhere else. The large preview always
  follows the *current* (last-clicked) item.
- **Folders are not shown** in the strip; the user changes directory via the
  breadcrumb or sidebar.
- **On entering the view or changing directory**, the first media item is selected
  by default (the strip is never blank when media exists).

## Architecture & components

Slots into the existing pluggable-view system; no new app-level concepts.

- **`FileViewContainer.qml`** — add a `GalleryView` instance,
  `visible: viewMode === "gallery"`, wired with the same signals as the other
  views (`fileActivated`, `contextMenuRequested`, `selectionChanged`,
  `interactionStarted`, `transferRequested`) and exposed via a `galleryViewItem`
  alias for Main.qml's selection plumbing.
- **`StatusBar.qml`** — add a 5th view-switcher icon and route it through the
  existing `viewMode` / `viewModeRequested` mechanism.
- **`Main.qml`** — include `"gallery"` in view routing (`subViewFor`) and the
  per-pane selection plumbing. Per-tab persistence via `panestate` /
  `ConfigManager` as for the other modes; the default view stays `hybrid`.
- **`src/qml/views/GalleryView.qml` (new)** — a `FocusScope` composing:
  - **Filtered model:** a `DirFilterProxyModel` in a new **`media`** filter mode
    that keeps only rows whose `FileCategoryRole` is image / video / pdf / audio
    and drops folders. Selection is exposed in **source-index space**
    (`mapRowToSource`), matching `HybridView`, so upstream plumbing is unchanged.
  - **Strip:** a vertical `ListView` of thumbnail delegates using the existing
    async, cached `ThumbnailProvider` via the model's thumbnail/icon roles.
    ListView recycling keeps large directories light.
  - **Preview:** reuse the shared **`PreviewState.qml`** engine (the same one
    Quick Preview uses) bound to the current item's path, with `loadEnabled`
    gated to the current item only. Video uses a new `MediaPlayer` + `VideoOutput`.
  - **Metadata bar:** bound to `previewState.fileMetadata`
    (exiftool / ffprobe, already wired).
  - Public API mirroring the other views: `selectAll()`, `clearSelection()`,
    `focusPath(path, reveal)`, `selectedIndices` (source space).
- **`DirFilterProxyModel` (`src/models/dirfilterproxymodel.{h,cpp}`)** — add the
  `media` filter mode alongside the existing dirs-only / files-only modes used by
  Hybrid. Reactive `count`.

## Data flow

```
pane source model
   └─> DirFilterProxyModel(media)  ──> strip ListView
                                        │ click → currentIndex
                                        ▼
                          mapRowToSource → file path
                                        ▼
                       PreviewState.filePath (loadEnabled = current only)
                          ├─> preview pane (image / video / pdf / audio)
                          └─> metadata bar (fileMetadata)
   selection changes ──> source indices ──> Main.qml (file ops, status count)
```

## Video playback & dependency

- New dependency: **`qt6-multimedia`** (Qt6::Multimedia C++ module + the
  `QtMultimedia` QML import). On Linux it uses the system backend
  (GStreamer / ffmpeg).
- **CMake:** `find_package(Qt6 ... Multimedia)` and link `Qt6::Multimedia`.
- **Packaging:** add `qt6-multimedia` to PKGBUILD `depends`; it is already part of
  the Flatpak `org.kde.Platform 6.9` runtime (no manifest module needed, verify the
  QML import resolves); document it in README / CLAUDE dependency lists.
- **Fallback:** if Qt Multimedia is unavailable at runtime, the preview falls back
  to the poster frame + "open in external player" — the gallery still works for
  images, PDFs and audio.

## Files to create / change

**New**
- `src/qml/views/GalleryView.qml`
- (possibly) a gallery footer-switcher icon QML, if no existing icon fits.

**Changed**
- `src/qml/views/FileViewContainer.qml` — gallery case + alias.
- `src/qml/components/StatusBar.qml` — 5th switcher icon.
- `src/qml/Main.qml` — routing + selection plumbing.
- `src/models/dirfilterproxymodel.{h,cpp}` — `media` filter mode.
- `src/CMakeLists.txt` — add `GalleryView.qml` to QML_FILES; link `Qt6::Multimedia`.
- `CMakeLists.txt` — `find_package` Qt6 Multimedia component.
- `PKGBUILD` — `qt6-multimedia` dependency.
- `io.github.blackbartblues.Wayfile.yml` — verify QtMultimedia import resolves in
  the runtime; adjust if needed.
- `README.md`, `CLAUDE.md` — dependency lists.
- (`panestate.h` / `configmanager.cpp` only if view-mode values are enumerated
  rather than free strings.)

## Edge cases

- **Empty / no-media folder** → "No photos or videos here" message.
- **Large directories** → ListView delegate recycling + async cached thumbnails;
  the preview loads the full-size source only for the current item.
- **PDF / audio in the big pane** → reuse PreviewState's existing handling.
- **Remote / trash directories** → gallery still lists media; thumbnails may be
  limited for remote sources (same as elsewhere).
- **Missing Qt Multimedia at runtime** → poster + open-externally fallback.

## Testing

- **Unit:** extend the `DirFilterProxyModel` tests for the `media` mode — only
  image / video / pdf / audio rows survive, folders are dropped, `count` is
  reactive.
- **QML smoke (`tst_qml_smoke`):** the Wayfile module instantiates including
  `GalleryView`.
- **Manual / GUI (Wayland):** switch to gallery, navigate the strip with mouse and
  arrows, start video playback, confirm metadata fields, verify the empty state.

## Out of scope (future)

- Fullscreen / immersive variant (this is the chromed view-mode version).
- Slideshow / auto-advance.
- In-gallery editing, rating, or tagging.
- Grid-of-thumbnails gallery layout (this spec is strip + single large preview).
