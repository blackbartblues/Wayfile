# W7 — Sidebar Rework (handoff alignment) — Design

> Part of the Wayfile 1.0.0 visual-system effort (branch `handoff-1.0.0`). Follows W1–W6.
> Source of truth for the target look: `docs/design-handoff/design_handoff_wayfile/`
> (`README.md` §Sidebar, `wayfile-components.jsx` `Sidebar`/`SBSection`/`SBItem`/`CompactSidebar`).

## Goal

Rework the sidebar to the handoff's section structure and visual detail **without losing any
current entry or feature**, add an expandable curated-XDG folder tree, a 56px compact icon
rail, and per-entry hide-via-context-menu. Unify the gallery-mode and normal sidebars into one.

## Background (current state)

- `src/qml/components/Sidebar.qml` — the normal sidebar: a `ColumnLayout` with hand-rolled
  sections **PLACES** (flat Repeater: Home, Hidden, Recents, Trash, Network, Pictures,
  Downloads), **FAVORITES** (drag-to-add/reorder bookmarks), **DEVICES** (`SidebarDeviceRow`
  with a real storage-usage bar + free/total caption — richer than the handoff's "84%" chip).
- `src/qml/components/SidebarPane.qml` — the host wrapper. Holds the **gallery special-case**:
  in Gallery mode it hides `Sidebar` and shows `GalleryFolderNav` (a real expandable folder
  tree) behind a **Places/Folders segmented toggle** (`host.galleryFolderNavActive`). Also owns
  the **drag-to-resize splitter** (`sidebarResizeHandle`, `Qt.SizeHorCursor`, persists
  `config.sidebarWidth`) added in the W7-evening fixes.
- `src/qml/components/GalleryFolderNav.qml` — a working folder tree: Qt `TreeView` over the C++
  `FolderTreeModel` (folders-only `QFileSystemModel`, lazy, `indexForPath`/`pathAt`), chevron
  expand/collapse (rotate 90°), current-folder gold highlight + auto-reveal.
- `src/models/foldertreemodel.{h,cpp}` — single-root folders-only tree model.
- `SidebarDeviceRow.qml` — device row with usage bar + tooltip.
- Collapse today = the toolbar sidebar-toggle drives `sidebarVisible` → `Layout.preferredWidth`
  animates to **0** (fully hidden).

## Decisions (locked in brainstorm 2026-06-10)

1. **Unify** — drop the gallery special-case entirely: remove `galleryActive`/`showFolderNav`,
   the Places/Folders toggle, `host.galleryFolderNavActive`, and the standalone
   `GalleryFolderNav` swap. One sidebar in every view. The folder tree moves into **Places**.
   `GalleryFolderNav.qml` is superseded; its TreeView + delegate logic is reused inside the
   new Places tree.
2. **Places structure** — **curated XDG forest**: fixed quick rows at top (Home mono, Recents,
   Hidden), then the XDG roots **Desktop, Documents, Downloads, Pictures, Music, Videos**, each
   an expandable tree node (chevron → its child folders, recursively). NOT the full Home tree.
3. **No loss** — every current entry stays (Home, Hidden, Recents, Trash, Network, Pictures,
   Downloads, Favorites/bookmarks, Devices). **Hidden stays.**
4. **Hide-via-context-menu** — right-click any sidebar entry → "Hide from sidebar"; persisted as
   a set of entry IDs in config; a "Show hidden" affordance restores them.
5. **Section order (top → bottom):** Favorites · Places · Devices · Network · (spacer) · Trash.
6. **Network** — its own section: the existing browse entry (`network:///`) plus any mounted
   network shares if a clean source exists; otherwise just the browse entry (never empty).
7. **Trash** — pinned at the bottom (after a flex spacer) with a **mono count chip** = number of
   items in Trash.
8. **Compact rail** — the toolbar sidebar-toggle switches **Full ↔ Compact (56px icon rail)**
   (no more hide-to-0). Persisted via `config.sidebarCompact`.
9. **Detail polish** — hover-reveal `+` add button on section headers (≥ Favorites); mono count
   chips; mono font on path-like labels (Home, drives, network hosts); colored star favorites
   (start gold, optional per-bookmark tint later); active left-rail **3px → 2px** with the
   existing glow.

## Architecture

### Components

| File | Responsibility | Change |
|---|---|---|
| `Sidebar.qml` | The single unified sidebar: section stack, hide-filter, full+compact render | Rewritten section model; folds in the tree; ~split if it grows past ~800 lines |
| `SidebarSectionHeader.qml` (new) | Uppercase header + hover-reveal `+`; restore-hidden menu | New small component |
| `SidebarPlacesTree.qml` (new) | The curated-XDG forest: fixed rows + per-XDG expandable subtrees | New; reuses `FolderTreeModel` + GalleryFolderNav's TreeView delegate |
| `SidebarPane.qml` | Host wrapper: resize splitter (kept), full/compact width | Remove gallery special-case + toggle |
| `GalleryFolderNav.qml` | — | Deleted (logic absorbed into `SidebarPlacesTree`) |
| `SidebarDeviceRow.qml` | Device row | Unchanged (compact variant added) |
| `foldertreemodel.{h,cpp}` | Folders-only tree | Unchanged (used per-XDG via `rootIndex`/`indexForPath`) |
| `configmanager.{h,cpp}` | Config | Add `sidebarCompact` + `hiddenSidebarEntries` (persist) |

### Forest tree (Places)

One shared `FolderTreeModel` instance. The curated XDG rows are a fixed list. Each XDG row is a
header row + a `Loader`-activated subtree that instantiates a `TreeView` rooted at that XDG dir
(`rootIndex: model.indexForPath(xdgDir)`), `interactive: false`, `implicitHeight` bound to the
TreeView's `contentHeight`, so the **outer sidebar Flickable owns all scrolling** (no nested
flickable conflict). The subtree delegate is the GalleryFolderNav delegate (chevron rotate,
indent by depth, click name → `host.navigateActivePaneTo` + expand, current-folder gold
highlight + auto-reveal). Expansion state of an XDG root is local UI state (collapsed by
default; Home/active path auto-reveals).

### Hide-via-context-menu

`ConfigManager` gains `hiddenSidebarEntries` (a `QStringList` of stable entry IDs, e.g.
`"places.recents"`, `"places.hidden"`, `"network"`, a bookmark path, a device id) serialized to
`[sidebar] hidden_entries` in `config.toml`, with `Q_INVOKABLE hideSidebarEntry(id)` /
`showSidebarEntry(id)` / `clearHiddenSidebarEntries()`. The sidebar filters every entry against
this set. A "Show hidden entries (N)" item appears in section-header / sidebar context menus when
the set is non-empty. Essential structural rows (Home) are not hideable.

### Compact rail (56px)

`ConfigManager.sidebarCompact` (bool, persisted, default false). The toolbar toggle flips it.
`SidebarPane` width = `sidebarCompact ? 56 : sidebarWidth`. In compact mode `Sidebar` renders an
icon-only vertical rail: each visible top-level entry as a 36×32 centred icon, active entry gets
`rgba(accent,0.10)` bg + 2px accent left-rail + glow, tooltip on hover (reusing the existing
tooltip layer). Favorites/Places-roots/Devices/Trash collapse to their icons; the XDG subtrees
are not expandable in compact (click navigates to the XDG dir). The resize splitter is disabled
in compact (fixed 56px).

## Data flow

Unchanged contracts: `bookmarkClicked(path)`, `recentsClicked()`, `hiddenClicked()`,
`sidebarContextMenuRequested(item, pos)`, `host.navigateActivePaneTo(path)`,
`host.activePanePath`. New: `host`/config reads for `sidebarCompact` + `hiddenSidebarEntries`;
Trash count from a lightweight count of the trash dir (reuse existing trash plumbing if present,
else a small `Q_INVOKABLE` count).

## Error handling / edge cases

- XDG dir missing (e.g. no `~/Music`) → that root row is hidden (don't show dead entries).
- FolderTreeModel async load → subtree `implicitHeight` updates on `directoryLoaded`; auto-reveal
  is best-effort (re-runs on load), same as GalleryFolderNav today.
- All entries hidden in a section → the section header hides too (no empty header).
- Compact + resize: splitter disabled; toggling back to Full restores the persisted width.
- Network with no mounts → the browse entry alone (section never empty).

## Testing

- **Unit (Qt6::Test):** `ConfigManager` round-trips `sidebarCompact` + `hiddenSidebarEntries`
  (add/remove/clear, TOML persistence); `FolderTreeModel` `indexForPath` for each XDG root.
- **tst_qml_smoke:** loads the rewritten tree headless (catches QML/binding errors).
- **Offscreen launch** (`TMPDIR=/tmp/wf-tmp`, exit 124) after every QML change.
- **User GUI-verify:** sections in handoff order; XDG rows expand to children; current folder
  highlighted/revealed; Trash at bottom with count; right-click → hide → persists across
  restart; show-hidden restores; toggle Full↔Compact 56px with tooltips + active accent;
  resize splitter still works in Full; no gallery regression (tree now in Places everywhere).

## Out of scope

- Per-bookmark custom star colors UI (start gold; auto/explicit tint is a later polish).
- Network share enumeration if no clean existing source (then: browse entry only).
- Re-ordering Places XDG roots by the user; multi-select in the tree.

## Open items (resolve in the plan, pragmatic defaults noted)

- **Trash count source:** prefer an existing count if the trash backend exposes one; else a
  cheap `QDir` entry count behind a `Q_INVOKABLE`.
- **Network mounts source:** check whether `DeviceModel`/remote infra surfaces mounted shares;
  if not, ship the browse entry only and note it.
