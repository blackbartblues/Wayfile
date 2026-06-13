# Wayfile — Per-pane independent view + per-folder view memory (WS2)

**Date:** 2026-06-13
**Status:** Design approved (pending written-spec review)
**Scope:** View mode (`grid`/`list`/`detailed`/`miller`/`hybrid`) only. Sort order is out of scope.

## Problem

Two related gaps in how the active view mode is owned:

1. **All panes in a split tab share one view.** A tab carries a single
   `viewMode`; `TabModel::setViewMode()` mirror-loops it onto every pane
   (`tabmodel.cpp:114-123`), and QML reads tab-level `viewMode` rather than the
   per-pane value. You cannot have, e.g., a grid pane next to a detailed pane in
   the same split. The infrastructure for per-pane view already exists
   (`PaneState::viewMode` at `panestate.h:29`; `TabModel::paneViewMode(idx)`
   getter at `tabmodel.cpp:357`) but is unused — the mirror loop and tab-level
   QML bindings defeat it.

2. **No folder remembers how you like to view it.** Whatever view a pane is in
   stays until you change it, regardless of which folder you navigate to. There
   is no way to say "Downloads should always open in detailed view."

## Goal

- Each pane owns its own view mode. The footer view-switch cluster reflects and
  drives the **focused** pane only. Split panes can show different views. View
  is sticky per pane across navigation.
- Optionally (setting-gated, default ON), a folder remembers the view you last
  set for it and re-applies it when any pane navigates back to it.

## Decisions (locked during brainstorming)

- **Per-folder memory is setting-gated, default ON** — a `rememberFolderView`
  flag in `ConfigManager` plus one toggle in Settings. Per-pane independence
  works regardless of this flag.
- **View mode only** is remembered per folder (not sort column/direction).
- **Sticky-on-unremembered semantics** (not snap-to-default): navigating to a
  folder with no stored view leaves the pane's current view unchanged; the store
  only ever holds folders the user explicitly customized.
- **Standalone `FolderViewStore` service** for the store (approach A), modeled
  on the existing `RecentFilesModel` (`main.cpp:391`) — its own JSON file under
  `~/.config/wayfile/`, `load()` on construct, `save()` on mutation, LRU cap.
- **No "Forget all" button in Settings** now. Backend `clear()`/`forget()` are
  still implemented (for tests and a future WS3 settings rework), just not
  surfaced in the UI.

## Design

### Mechanic 1 — Per-pane independent view

#### C++ — `TabModel`

**Drop the mirror loop** in `setViewMode()` (`tabmodel.cpp:114-123`). It keeps
its existing meaning — "set the *primary* pane's view" (writes `m_panes[0]`,
emits `viewModeChanged()`) — but no longer overwrites the other panes.

**New setter + signal** (`tabmodel.h` / `tabmodel.cpp`):

```cpp
Q_INVOKABLE void setPaneViewMode(int idx, const QString &mode); // tabmodel.h
void paneViewModeChanged(int idx);                              // signals
```

```cpp
void TabModel::setPaneViewMode(int idx, const QString &mode)
{
    if (idx < 0 || idx >= m_panes.size())
        return;
    if (m_panes[idx].viewMode == mode)
        return;
    m_panes[idx].viewMode = mode;
    emit paneViewModeChanged(idx);
    if (idx == 0)
        emit viewModeChanged();   // keep tab-level consumers (session save) live
}
```

`paneViewMode(idx)` getter is unchanged (`tabmodel.cpp:357`).

`TabListModel` already connects `viewModeChanged → sessionChanged`
(`tablistmodel.cpp:90`). Add a parallel connection so per-pane changes also mark
the session dirty:

```cpp
connect(tab, &TabModel::paneViewModeChanged, this, &TabListModel::sessionChanged);
```

#### QML — `Main.qml`

Rewire every tab-level `viewMode` read/write to be pane-indexed:

- **PaneFrame delegate** (`:1636`): `paneViewMode: tabModel.activeTab ? tabModel.activeTab.paneViewMode(index) : "hybrid"`.
  Because `paneViewMode(idx)` is a `Q_INVOKABLE` (not a notifying property),
  bind it through a small reactive mirror keyed on `paneViewModeChanged` — the
  same pattern already used for `panePath`/`activePanePath` (`:306-331`). Add a
  `paneViewModes` JS array (length = pane count) refreshed in a
  `Connections { target: tabModel.activeTab; function onPaneViewModeChanged(idx){…} }`
  handler, and have the delegate read `root.paneViewModes[index]`.
- **Footer StatusBar** (`:1690-1692`): drive the **focused** pane.
  - `viewMode: root.paneViewModes[root.activePaneIndex] ?? "hybrid"`
  - `onViewModeRequested: (m) => root.applyViewToActivePane(m)` (see below).
- **`subViewFor` / `activeFileView`** (`:585`, `:575`): resolve view from
  `paneViewMode(pane)` instead of `tabModel.activeTab.viewMode`.
- **Miller parent-model sync** (`:407`, `:421`): the `viewMode !== "miller"`
  guard becomes `paneViewMode(idx) !== "miller"`.
- **Default-view seed** (`:745`, currently `tabModel.activeTab.viewMode = config.defaultView`):
  unchanged — `config.defaultView` keeps seeding pane 0 of a brand-new tab via
  the existing tab-level setter. Newly split panes already inherit pane 0's view
  at creation (`addPane`, `tabmodel.cpp:207-215`), so a split still looks
  identical to start; folder memory may then override a pane's view by path.

New helper consolidating the footer action + folder-memory write:

```qml
function applyViewToActivePane(mode) {
    if (!tabModel.activeTab) return
    var idx = root.activePaneIndex
    tabModel.activeTab.setPaneViewMode(idx, mode)
    // record per-folder override (Mechanic 2), guarded
    if (config.rememberFolderView && root.isRealFolderPane(idx))
        folderViewStore.rememberView(root.panePath(idx), mode)
}
```

#### Session schema — `tablistmodel.cpp`

Today `panes` is a JSON array of path strings and the view is a single
top-level `"viewMode"` (`:701-739`). Change `panes` to an array of objects so
each pane carries its own view:

```json
{
  "viewMode": "grid",                         // = pane 0's view (back-compat write)
  "panes": [
    { "path": "/home/me",      "viewMode": "grid" },
    { "path": "/home/me/dev",  "viewMode": "detailed" }
  ]
}
```

- **Write** (`saveSession`, ~`:701-710`): emit `{path, viewMode}` per pane; keep
  writing top-level `"viewMode"` = pane 0's view so older builds still restore
  something.
- **Read** (`restoreSession`, ~`:730-747`): for each pane element —
  - object → use `viewMode` (fall back to top-level legacy / `"grid"`),
  - **string** (legacy session) → treat as `{path, <top-level viewMode>}`.

  After recreating panes via `addPane(...)`, apply each pane's view with the new
  `setPaneViewMode(i, mode)`. Pane 0's view continues to flow through the
  existing `tab->setViewMode(...)` call.

### Mechanic 2 — Per-folder view memory

#### New service — `FolderViewStore` (`src/models/folderviewstore.{h,cpp}`)

A plain `QObject` (not a list model — never displayed), modeled on
`RecentFilesModel`:

```cpp
class FolderViewStore : public QObject {
    Q_OBJECT
public:
    explicit FolderViewStore(const QString &storagePath, QObject *parent = nullptr);

    Q_INVOKABLE QString viewForFolder(const QString &path) const; // "" if none
    Q_INVOKABLE void rememberView(const QString &path, const QString &mode);
    Q_INVOKABLE void forget(const QString &path);
    Q_INVOKABLE void clear();

private:
    void load();
    void save() const;

    struct Entry { QString path; QString viewMode; };
    QList<Entry> m_entries;     // most-recently-written at front (LRU order)
    QString m_storagePath;
    int m_maxEntries = 500;
};
```

- **`rememberView`**: normalize path (strip trailing slash); if present, update
  in place and move to front; else prepend; cap to `m_maxEntries` via
  `resize()`; `save()`. (Empty `mode` is ignored.)
- **`viewForFolder`**: lookup only — does **not** reorder or save (avoids a disk
  write on every navigation). Returns `""` when absent → caller leaves the pane's
  view unchanged.
- **`forget`/`clear`**: mutate + `save()`. Not surfaced in UI yet.
- **Storage**: `~/.config/wayfile/folder-views.json`, a JSON array of
  `{ "path": "...", "viewMode": "..." }`. Constructed in `main.cpp` beside
  `RecentFilesModel`:

  ```cpp
  FolderViewStore *folderViewStore =
      new FolderViewStore(configDir + "/folder-views.json", &app);
  engine.rootContext()->setContextProperty("folderViewStore", folderViewStore);
  ```

#### `ConfigManager` flag

Follow the existing `sidebarCompact` bool pattern:

- `configmanager.h`: `Q_PROPERTY(bool rememberFolderView READ rememberFolderView NOTIFY configChanged)` + getter.
- `configmanager.cpp`: default `m_rememberFolderView = true;`; parse
  `config["general"]["remember_folder_view"]`; persist via
  `general.insert_or_assign("remember_folder_view", …)` in the save path, and
  handle the `rememberFolderView` key in `saveSettings(QVariantMap)`.

#### Navigation hooks — `Main.qml`

On a pane settling into a new path, **apply** any stored view. The two existing
hooks are `onCurrentPathChanged` (pane 0, `:129`) and `onPanePathChanged(idx)`
(`:142`). Route both through one guarded helper:

```qml
function maybeApplyFolderView(idx) {
    if (!config.rememberFolderView) return
    if (!isRealFolderPane(idx)) return          // skip special/remote/search
    var saved = folderViewStore.viewForFolder(panePath(idx))
    if (saved.length > 0)
        tabModel.activeTab.setPaneViewMode(idx, saved)
    // saved === "" → leave the pane's current view untouched (sticky)
}
```

`isRealFolderPane(idx)` returns false for Recents, Hidden, Trash, remote/gvfs,
and active-search panes, reusing the existing predicates
(`paneIsRecents`/`paneIsHidden`/`isTrashView`/`isRemoteView`/`searchMode`,
`Main.qml:42-51,340`). In those states the store is neither read nor written.

The **write** side lives in `applyViewToActivePane` (Mechanic 1) — i.e. a folder
is recorded only when the user explicitly changes the focused pane's view, and
only for real folders with the setting ON.

#### Settings UI

One `Quill` toggle "Remember view per folder" in the existing Settings → Layout
section (`SettingsSectionLayout.qml`, near the default-view control), wired through the
standard edit-copy + `saveSettings()` flow used by the other Layout switches.
(The broader Layout/Settings regroup is WS3 and out of scope here.)

## Interaction summary

| Event | Setting OFF | Setting ON |
|---|---|---|
| New tab/pane | seeded at `config.defaultView` | seeded at `config.defaultView` |
| Navigate focused pane to folder F | pane keeps current view | F in store → apply stored view; else keep current view |
| Footer view-switch on focused pane | set that pane's view | set that pane's view **and** record `F → mode` (real folders only) |
| Navigate to Recents/Trash/remote/search | pane keeps current view | store untouched (neither read nor written) |
| Toggle setting OFF | — | JSON file left intact; simply stops being read/written |

## Error handling & edge cases

- `setPaneViewMode(idx, …)` bounds-checks `idx` against `m_panes.size()`.
- `FolderViewStore` load tolerates a missing/corrupt JSON file (start empty,
  matching `RecentFilesModel::load()`); save failures are non-fatal.
- Paths are normalized before store keys to avoid `/x` vs `/x/` duplicates.
- Legacy `session.json` (string `panes` array, single top-level `viewMode`)
  restores without loss.
- Closing/merging supertabs: per-pane views travel with their panes (the merge
  paths in `tablistmodel.cpp:309-432` operate on `PaneState`, which already
  carries `viewMode`).

## Testing

Per the repo convention (`tests/tst_*.cpp`, one per backend class, Qt6::Test):

- **`tst_folderviewstore`** (new): round-trip save/load; `rememberView`
  insert/update/move-to-front; LRU eviction at the cap; `viewForFolder` miss
  returns `""` and does not write; `forget`/`clear`; path normalization;
  tolerance of a missing/garbage file.
- **`tst_tabmodel`** (extend): `setPaneViewMode` writes only the target pane (no
  mirror); `paneViewMode` reflects it; out-of-range `idx` is a no-op;
  `paneViewModeChanged(idx)` fires (QSignalSpy); `setViewMode` still updates
  pane 0 + emits `viewModeChanged`.
- **`tst_tablistmodel`** (extend): session round-trip preserves divergent
  per-pane views; legacy string-array `panes` restores (pane 0 = legacy
  top-level `viewMode`).
- **`tst_configmanager`** (extend): `rememberFolderView` defaults true, parses
  from TOML, and round-trips through `saveSettings`.

Plus the standard manual gate: `cmake -B build && cmake --build build`,
`tst_qml_smoke`, `ctest`, and user GUI-verify on Wayland (split a tab → give
each pane a different view; set a folder's view, navigate away and back, confirm
restore; toggle the setting off and confirm memory stops; relaunch and confirm
per-pane views persist). Reminder: `cmake --build` alone does not regenerate the
qrc — reconfigure with `cmake -B build` before smoke-testing QML.

## Files touched

- `src/models/tabmodel.{h,cpp}` — drop mirror loop; `setPaneViewMode` + signal.
- `src/models/tablistmodel.cpp` — per-pane session schema; new signal connection.
- `src/models/folderviewstore.{h,cpp}` — **new** service.
- `src/services/configmanager.{h,cpp}` — `rememberFolderView` flag + persistence.
- `src/main.cpp` — construct `FolderViewStore`, expose as context property.
- `src/qml/Main.qml` — pane-indexed view bindings, `paneViewModes` mirror,
  `applyViewToActivePane`, `maybeApplyFolderView`, `isRealFolderPane`.
- `src/qml/components/SettingsSectionLayout.qml` (Settings) — one toggle.
- `src/CMakeLists.txt` / `tests/CMakeLists.txt` — register new source + test.
- `tests/tst_folderviewstore.cpp` (new); extend `tst_tabmodel`,
  `tst_tablistmodel`, `tst_configmanager`.

## Out of scope

- Remembering sort column/direction per folder (view mode only).
- The broader Settings/Layout regroup (WS3).
- Custom context actions (WS4).
- Any "Forget all remembered views" UI.
