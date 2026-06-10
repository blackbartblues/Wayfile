# W8 — Handoff Fidelity Pass (post-W7 design corrections)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (implementer → spec review → code-quality review → fix loop → one commit per task, like W7). Steps use `- [ ]`.

**Origin:** After W7 (sidebar rework, code-complete at `d803fba`), the user audited our build against the design handoff and gave 10 correction points + "check absolutely every aspect." A full 5-surface audit (tokens/typography, sidebar, chrome, context menus, views/icons) was done 2026-06-10. This plan implements the corrections.

**Handoff = ground truth:** `docs/design-handoff/design_handoff_wayfile/` — `tokens.css` (exact values), `wayfile-components.jsx` (structure/toolbar order/sidebar), `wayfile-icons.jsx` (glyphs), `README.md` (spec). Token prefix `--h-` maps to our `Theme.*`/`themeloader.cpp`.

**Branch:** `handoff-1.0.0` (continue). **Nothing pushed.**

**Build/verify recipe (MANDATORY per change — `cmake -B build` regenerates the compiled-QML qrc; `cmake --build` alone does NOT):**
```bash
cmake -B build && cmake --build build -j$(nproc)
ctest --test-dir build
mkdir -p /tmp/wf-tmp && timeout 8 env TMPDIR=/tmp/wf-tmp QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 ./build/src/wayfile 2>/tmp/w.log; echo $?  # 124=ok
/usr/bin/grep -iE "error|is not a type|cannot|binding loop|ReferenceError|TypeError" /tmp/w.log | /usr/bin/grep -v -iE "spaVisitChoice|vdpau|vulkan|pipewire" || echo clean
```
Ignore PipeWire/VDPAU/Vulkan log noise. Use `/usr/bin/grep`. NO Co-Authored-By lines. **Every task = USER Wayland GUI-verify** (visual fidelity needs the user's eyes).

## LOCKED DECISIONS (from user, 2026-06-10)
- **Toolbar:** match handoff order; Settings + sidebar-collapse(W7 compact) move into a new **⋯ More** overflow menu; **Search always-visible** (not a toggle).
- **Favorites:** per-bookmark **color** stored in config; set via a **right-click "Color" swatch submenu**; rendered as a filled star in that color (full sidebar + compact rail).
- **Network:** new model enumerating **live gio/gvfs network mounts + saved RemoteConnect hosts**; one row each; **hide the whole section when empty**.
- **Icon glow:** **light touch** — file glow uses the file's **type color** (not gold) with rest→hover→select intensity steps; folder glow = accent; **skip** interior bloom + rim lip-light.

## Handoff reference values (exact)
- **Type:** UI items 12.5px, list rows 12.5px, tabs 12.5px, context-menu items 12.5px; section header 10.5px uppercase 0.08em weight 600; meta 11.5px; size/count mono 11px (sidebar count 10.5px). Fonts Inter/JetBrains Mono/Cormorant (already correct).
- **Radii:** sm 4, md 6, lg 10, xl(window) 14. Tab 8, iconbtn 6, row-selected 4.
- **Dividers:** all hairline 1px. `--h-divider #1A1D21`, `--h-border-soft #2A2E33`, `--h-border #353B42`.
- **Sidebar:** width 220; item min-height 28, font 12.5, padding 5/14/5/16, gap 10, icon 16(render 14); section header padding 12/14/4; active = 90° gradient rgba(accent,.10→.02@70%) + 2px left rail + `0 0 8px accent-glow`; count mono 10.5 text-3; child indent 32/48.
- **Toolbar:** Back·Fwd·Up·Refresh ∣sep∣ NewFolder·Merge ∣sep∣ [crumbs flex] ∣sep∣ Search(240×30) ∣ More. iconbtn 28px r6; sep 1px×18 #353B42 m0/4; padding 8/12; gap 6. Back/Fwd/Up = **arrows** (not chevrons); More = 3 horizontal dots.
- **Context menu:** bg gradient #2A2E33→#24272C, border #353B42, radius 10, pad 5, min-w 220; item pad 6/10 r5 font 12.5 gap 10; icon 14 text-2→accent on hover; **hover = `linear-gradient(90deg, rgba(accent,.12), rgba(accent,.04))`**; shortcut mono 10.5 text-3; danger red + red-tinted hover; sep 1px border-soft + sheen.
- **List:** cols 1fr/140/110/80 gap12 pad16; header 11px w500 text-3; row 28 min, 12.5, icon 18 gap10; hover rgba(255,255,255,.025); selected accent-grad .10→.04 + inset 1px accent.18 + r4 + trailing accent chevron; meta 11.5 text-2; size 11 mono right.
- **Status:** h26 pad0/14 gap14 bg #1A1D21→#15181C border-top 1px divider, 11px text-2; "N items"; selected accent; mono path 10.5 text-3; viewmode group (we keep our 5 views) active = surface-hi bg + accent.
- **Grid:** tiles minmax120 gap4 pad14; tile pad12/8/10 r8 11.5; hover rgba(255,255,255,.025); selected accent .10 + inset 1px accent.30.

---

### Task 1 — Foundational tokens: typography + radii + sizing  (`src/qml/theme/Theme.qml`, `src/services/configmanager.cpp` radius defaults)
Addresses user #2 + #10 (everything smaller). FOUNDATIONAL — do first; affects whole app; USER must GUI-verify nothing overflows.
- [ ] `fontNormal`: drop ~1pt so primary UI ≈ 12.5px (audit: `max(10,round(base))`→`max(9,round(base-1))`). `fontSmall`: drop ~1pt to ≈11px (`max(9,base-1)`→`max(8,base-2)`). Verify section-header (`fontSmall-1`) stays ≈10.5px (may need a dedicated token so it doesn't go to 7pt).
- [ ] Radii: `radiusMedium` default 8→6, `radiusLarge` 12→10 (configmanager.cpp defaults), `radiusTab` 9→8, `radiusButton` 8→6, `radiusRow` 8→4 (Theme.qml). Add `radiusWindow/xl: 14` if window uses 12.
- [ ] Row-height constants down to handoff: sidebar bookmark/quick rows 32→28, places-tree `_rowHeight` 30→28, tab strip 44→40, status bar 28→26. (Coordinate with the font drop so rows don't look loose.)
- [ ] Default sidebar width 236→220 (configmanager.cpp + SettingsPanel reset 200→220).
- [ ] Build + ctest + offscreen + **USER GUI-verify** (no clipping/overflow anywhere; fonts visibly smaller). Commit `fix(theme): handoff typography + radii + base sizing (smaller UI) (W8)`.

### Task 2 — Chrome dividers #5 #6  (`src/qml/components/TabBar.qml`, `Toolbar.qml`)
- [ ] #5 tab-strip↔toolbar: `TabBar.qml:~59` `height:2; color:Theme.divider(#454C54)` → `height:1` + near-black `#1A1D21` (add `Theme.chromeHair` token or inline). Active tab bg already = toolbar bg so seam vanishes.
- [ ] #6 toolbar↔content: `Toolbar.qml:~123` `height:2; Theme.divider` → `height:1` + `Theme.lineSoft` (#2A2E33). Verify `Theme.lineSoft`=#2A2E33.
- [ ] Build/verify + **USER GUI-verify**. Commit `fix(chrome): 1px hairline dividers tab↔toolbar (subtle) + toolbar↔content (W8)`.

### Task 3 — Toolbar rework #7  (`src/qml/components/Toolbar.qml`, new `IconMore.qml`, arrow icons, a ⋯More popup)
Order → **Back·Fwd·Up·Refresh ∣ NewFolder·Merge ∣ [breadcrumb flex] ∣ Search(always-visible) ∣ ⋯More**. iconbtn 28 r6, sep 1px×18 #353B42, gap 6, pad 8/12.
- [ ] Replace Back/Fwd/Up chevrons with **arrow** glyphs (IcArrowL/R/U: `M19 12H5M12 5l-7 7 7 7` etc.) — add IconArrowLeft/Right/Up or inline; add **Refresh** (IconRefreshCw exists). New-folder + Merge kept (Merge = chain-link, W4 binary armed/disabled).
- [ ] Make Search an **always-visible** box (240×30, bg #15181C, r8, inset shadow, trailing kbd chip mono 10.5) sitting after the breadcrumb — not a toggle that replaces the crumb.
- [ ] New **⋯ More** button (IconMore = 3 horizontal dots) at far right → popup menu (reuse ContextMenu infra) holding **Settings** + **Collapse sidebar (compact toggle, W7)** + any overflow. Remove the standalone Settings + sidebar-toggle buttons from the bar.
- [ ] Keep trash-view Restore/EmptyTrash affordances working.
- [ ] Build/verify + **USER GUI-verify**. Commit `feat(toolbar): handoff order (arrows, Refresh, always-on Search, ⋯More) + Settings/compact in overflow (W8)`.

### Task 4 — Sidebar unified Places tree + unique icons + metrics  (`src/qml/components/SidebarPlacesTree.qml`, `Sidebar.qml`)
Addresses #1, #3, #10. The biggest sidebar task.
- [ ] **Unify Places into one tree:** Home as the first top-level row of the tree (mono label), then Desktop/Documents/Downloads/Pictures/Music/Videos as peer expandable rows (existing tree). Decide Recents/Hidden: keep them as two rows directly under Home (our additions, retain) but inside the same Places block so it reads as one list. Remove the visual split between "quick rows" and "the tree".
- [ ] **Unique per-XDG icons (full + compact):** map label→icon: Home→IconHome, Desktop→IconMonitor, Documents→IconFileText, Downloads→IconDownload, Pictures→IconImage, Music→IconMusic, Videos→IconVideo; generic subfolders→IconFolder. Replace the generic `FileIcon{isDir}` at XDG ROOT rows. In the compact rail (`Sidebar.qml` compact Repeater) replace `iconKind="folder"` with the per-label glyph so they're distinguishable. (Subfolders deeper in the tree keep the folder glyph — fine.)
- [ ] **Metrics:** sidebar icons 18→14/16, item gap 8→10, left inset →16, section header padding →12/14/4 + weight DemiBold(600), count chip →10.5 mono, places row height 28, active-rail glow already present. Sidebar width handled in T1.
- [ ] Compact Trash pinned to bottom (compact Column needs a fillHeight spacer before Trash).
- [ ] Build/verify + **USER GUI-verify** (one cohesive expandable Places list, distinct icons, distinguishable compact rail). Commit `feat(sidebar): unified Places tree w/ Home + unique per-place icons + handoff metrics (W8)`.

### Task 5 — Favorites per-bookmark color #8  (`src/models/bookmarkmodel.{h,cpp}`, `Sidebar.qml`, sidebar context menu)
- [ ] Add `color` (QString hex, default "") to the `Bookmark` struct + `ColorRole` + persist in config (mirror existing bookmark persistence) + a `Q_INVOKABLE setBookmarkColor(index,color)`.
- [ ] Render the favorite's LEADING icon as a **filled IconStar (14px) in its color** (default = accent gold) instead of the folder glyph — in both full sidebar and compact rail. Keep the trailing pin star.
- [ ] Add a **"Color" submenu of swatches** to the bookmark right-click menu (handoff palette: gold #D4AA6A, rose #D4A6A6, image-green #8FC380, aqua #57C7BF, violet #B292E8, coral #E68B5C, +"Default") → calls `setBookmarkColor`.
- [ ] Tests: bookmark color round-trips (tst for bookmarkmodel if one exists; else config round-trip). Build/verify + **USER GUI-verify**. Commit `feat(sidebar): per-favorite star colors (right-click swatch), persisted (W8)`.

### Task 6 — Network enumeration #4  (new `NetworkLocationModel` C++, `Sidebar.qml`, new `IconNetwork.qml`)
- [ ] New model listing **live gio/gvfs network mounts** (`gio mount -l` / GVfs, filter sftp/smb/nfs/davs URIs) **+ saved RemoteConnect hosts**. Expose as a ListModel (name + uri). Refresh on mount changes.
- [ ] Sidebar Network section: render one row per host (IconNetwork glyph + mono label, navigates to the uri). **Hide the entire section (header included) when the list is empty.**
- [ ] Add `IconNetwork.qml` (Lucide `network`/`share-2`), replace `IconGlobe` in the Network section.
- [ ] Tests for the model if feasible. Build/verify + **USER GUI-verify** (with and without a mounted remote). Commit `feat(sidebar): enumerate network mounts + saved hosts; hide section when none (W8)`.

### Task 7 — Sidebar tree context menu #9  (`src/qml/components/SidebarPlacesTree.qml`, `Sidebar.qml`)
- [ ] Add `acceptedButtons: LeftButton|RightButton` + right-click handling to BOTH the XDG header rows and the inner TreeView delegate rows; emit a `contextMenuRequested(item, pos)` signal (mirror SidebarDeviceRow); `Sidebar.qml` forwards to `sidebarContextMenuRequested`. Payload `kind:"quickAccess", path:fullPath, entryId:fullPath` — reuses `SidebarPane.sidebarMenuItems` (Open / Open in new tab / Open in split / Open in terminal / Properties / Add to favorites).
- [ ] Build/verify + **USER GUI-verify** (right-click a tree folder → menu; actions work). Commit `feat(sidebar): context menu on Places tree rows (W8)`.

### Task 8 — Context menu restyle  (`src/qml/components/ContextMenu.qml`, `ContextMenuRow.qml`)
- [ ] **Hover = accent gradient** `linear-gradient(90deg, rgba(gold,.12), rgba(gold,.04))` (was flat raise2). Icons **text-2 normally → accent on hover** (was always gold), size 16→14. Menu radius 12→10; item radius →5; item h-padding 12→10, gap 8→10, row height →~28 (6px v-pad). Separator color line→lineSoft + 1px warm sheen. Danger rows: red label + **red-tinted hover bg** + icon red only on hover.
- [ ] Fix "Open in New Tab" icon (Folder→a tab/window glyph); Rename icon (FolderPen→pencil). (Keep our extra items: Open With/Terminal/Copy Path/Extract/Wallpaper/View/Sort — they're good UX.)
- [ ] Build/verify + **USER GUI-verify**. Commit `fix(menu): accent-gradient hover, grey→accent icons, radius/padding, danger hover (handoff) (W8)`.

### Task 9 — View metrics  (`FileDetailedView.qml`, `FileDetailedRow.qml`, `FileGridView.qml`, `StatusBar.qml`)
- [ ] Detailed rows: hover bg 0.05→0.025; name icon 16→18; icon→text gap 6→10; h-padding 8→16; size column add `Fonts.mono`; selected bg accent .10→.04 (from gold .18) + inset 1px accent.18 + r4. Header weight 500 + text-3.
- [ ] Grid: hover 0.07→0.025; add 14px grid padding + 12/8/10 tile padding; selected fill .20→.10.
- [ ] Status bar: height 28→26; bg flat→gradient #1A1D21→#15181C; add 1px top divider; padding 8→14, gap 8→14; selected-count always accent when >0; path mono 10.5 text-3; keep our 5 view buttons but give active a surface-hi bg pill + accent.
- [ ] Build/verify + **USER GUI-verify**. Commit `fix(views): handoff list/grid/status metrics (hover, padding, icon sizes, status gradient) (W8)`.

### Task 10 — Icon glow light-touch  (`src/qml/views/FileIcon.qml`, `WayFile.qml`, `WayFolder.qml`)
- [ ] **File glow uses the file's TYPE color** (FileTypeColors) for the shadow, not `Theme.goldGlow`; folders keep accent. Add rest→hover→select **intensity steps** (e.g. shadowBlur/opacity ramp) so selection reads stronger than hover. Skip interior radial bloom + rim lip-light (out of scope per decision).
- [ ] Build/verify + **USER GUI-verify** (a selected .pdf glows red, .ts teal; folders gold). Commit `feat(icons): type-tinted file glow + rest/hover/select steps (light-touch) (W8)`.

### Task 11 — Final verification
- [ ] Clean-from-scratch rebuild + full ctest + offscreen (full + compact) launches exit 124 clean.
- [ ] Holistic GUI-verify checklist for the user covering all 10 points + the additional fidelity items.

**Out of scope (confirmed):** interior icon bloom + rim lip-light (light-touch glow only); converting our 5 views down to the handoff's 3; replacing our richer Device usage-bar rows with the handoff's compact %; Mac-style shortcut glyphs (keep Linux Ctrl/Del). Keep our extra context-menu actions.
