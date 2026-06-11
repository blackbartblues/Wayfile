<div align="center">

<img src="docs/screenshots/wayfile-banner.png" alt="Wayfile — an obsidian-and-gold file manager for Hyprland and Wayland" width="100%"/>

[![License](https://img.shields.io/github/license/blackbartblues/Wayfile?style=flat-square&color=D4AA6A)](LICENSE)
[![Release](https://img.shields.io/github/v/release/blackbartblues/Wayfile?style=flat-square&color=D4AA6A)](https://github.com/blackbartblues/Wayfile/releases)
[![AUR](https://img.shields.io/aur/version/wayfile-git?style=flat-square&logo=arch-linux&color=D4AA6A)](https://aur.archlinux.org/packages/wayfile-git)

</div>

> **Wayfile is a fork of [HyprFM](https://github.com/soyeb-jim285/hyprfm)** by Soyeb Pervez Jim — re-skinned with the obsidian-and-gold *Bifröst* design system and substantially extended. The **1.0.0** release rebuilds the entire visual layer — thin-frame type-coloured icons, glowing tabs, a unified Places sidebar, a compass-folder logo, an *Inter · Cormorant · JetBrains Mono* type stack, and five live accent presets — on top of HyprFM, and adds a hybrid view, merged tabs, network locations, and a token-driven theme system. All credit for the original file manager goes to the upstream project.

---

Wayfile is a Qt6/QML file manager built to feel native on Hyprland: lightweight, fast, and unapologetically keyboard-driven. Its signature look is **Bifröst** — a deep obsidian surface with a warm gate-glow gold accent — and its default layout is the **hybrid view**: a folder grid stacked over a sortable file list with one shared selection. Underneath the polish sit the features power users actually reach for: Miller columns, split panes, merged tabs, async file operations, rich previews, git status, and a live theme system with five accent presets.

<div align="center">

![Hybrid view](docs/screenshots/hybrid-view.png)
*The default **hybrid** view — a folder grid over a sortable file list, the unified Places sidebar with a live disk meter, and the obsidian + gold Bifröst skin.*

</div>

### The whole UI retints, live

Bifröst ships with five accent presets. Pick one in **Settings → Colours** and the entire interface — folders, tabs, sidebar, breadcrumb, meters — recolours instantly, while file-type colours stay fixed so files remain recognisable.

<div align="center">

![Theme presets cycling](docs/screenshots/theming.gif)

![The five accent presets](docs/screenshots/theming-presets.png)
*Bifröst · Aurora · Nebula · Ember · Verdant — obsidian base, one accent swap.*

</div>

---

## ✨ Features

### Views

- **Hybrid** (default) — a folder grid stacked over a sortable file list, with one unified selection across both halves; the file list sorts independently.
- **Grid** (`Ctrl+1`) — `Ctrl+Scroll` to zoom; the icon size stays constant while columns reflow to fill the width.
- **Detailed** (`Ctrl+3`) — sortable `Name · Modified · Type · Size` columns, folder item counts, image/video thumbnails.
- **Miller columns** (`Ctrl+2`) — parent · current · live preview, with a metadata panel for the focused item.
- **Quick preview** (`Space`) — a full-screen overlay for images, video, PDFs, and text with a rich metadata sidebar; `←/→` browse neighbours.
- **Split panes / merged tabs** (`F3`) — up to four directories side by side, each with its own path strip and item count.

<div align="center">

![Grid view](docs/screenshots/grid-view.png)
*Grid view — thin-frame, type-coloured file glyphs (PDF, code, archive, config…), gold folders, and inline image/video thumbnails.*

![Miller view](docs/screenshots/miller-view.png)
*Miller columns with a live preview column and a per-item metadata panel.*

![View modes](docs/screenshots/views.gif)
*Switching between grid, detailed, and Miller columns.*

</div>

### Navigation & input

- **Full keyboard navigation** — arrows, history, type-ahead jump-to-file
- **Tabs** with independent per-pane history; **merge tabs** into a split "supertab" (the merge button joins the active tab with its right-hand neighbour, badged `×N`)
- **Breadcrumb path bar** with inline editing (`Ctrl+L`) and suggestions
- **Unified sidebar** — Favorites with per-bookmark colour tags, an expandable **Places** tree of your XDG folders, mounted **devices** with live capacity meters, **network** locations, and Trash; collapsible to a compact icon rail
- **Kinetic wheel scrolling** with momentum and rubber-band overscroll
- **Rubber-band selection**; contiguous selections render as one rounded gold outline

<div align="center">

![Merged tabs / split panes](docs/screenshots/supertab.png)
*Two tabs merged into a split "supertab" — each pane keeps its own path and the tab is badged `×2`.*

</div>

### File operations

- **Async copy / move** via `rsync` and `gio` with live progress, speed, ETA, and pause
- **Drag & drop** between panes, tabs, and external apps (Wayland-native)
- **Trash** with restore (XDG-compliant) · **Bulk rename** with regex find/replace
- **Compress / extract** archives · **Open With** from `.desktop` entries · **Undo / redo**

<div align="center">

![Quick preview](docs/screenshots/quick-preview.png)
*Quick preview (`Space`) — image preview with a full metadata sidebar; `←/→` step through neighbours.*

</div>

### Look & feel

- **Bifröst**, the signature obsidian + gold theme, plus four more live accent presets — **Aurora** (teal), **Nebula** (violet), **Ember** (coral), and **Verdant** (green)
- **Colours settings page** — pick a preset and the whole UI retints live, fine-tune any palette token (swatch + hex), and save your own palette as a named theme; a contrast warning flags an accent that's too dark against the background
- **TOML themes with live reload** — drop a file in `themes/`, pick it in Settings, no restart
- **Thin-frame SVG icon set** — type-coloured file glyphs and accent-coloured folders, rendered via Qt Shapes, with a soft gold bloom on hover and selection
- **Type stack** — *Inter* (UI), *Cormorant Garamond* (display), and *JetBrains Mono* (mono), all bundled
- **Configurable** corner radius, fonts, animation timing, and transparency
- **Compositor blur** on Hyprland, plus native KWin blur on KDE Plasma

<div align="center">

![Settings — Look & Feel](docs/screenshots/settings.png)
*The Settings panel — fonts, icon pack, transparency, corner radii, and the live Colours picker.*

</div>

### Integrations

- **udisks2** mount/unmount of removable drives · **gvfs / gio** for SFTP, SMB, MTP, trash
- **Git status overlays** in every view (modified, staged, untracked, …)
- **wl-clipboard** clipboard · **bat** syntax highlighting · **ffmpeg** video posters · **Poppler** PDF previews

---

## 📦 Installation

### Arch Linux (AUR)

```bash
yay -S wayfile-git
```

The PKGBUILD clones the latest `main`, builds with Ninja, and installs to `/usr/bin/wayfile`.

### Build from source

```bash
git clone --recursive https://github.com/blackbartblues/Wayfile.git
cd Wayfile
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF
cmake --build build --parallel
./build/src/wayfile
```

> **Note:** `--recursive` pulls the [quill-icons](https://github.com/soyeb-jim285/quill-icons) icon submodule. (The Quill control library is vendored directly in `src/qml/Quill/`, so it is not a submodule.)

#### Dependencies

| | Packages |
|---|---|
| **Required (build)** | `cmake`, `ninja`, `qt6-base`, `qt6-declarative`, `qt6-svg` |
| **Required (runtime)** | `qt6-base`, `qt6-declarative`, `qt6-svg`, `qt6-multimedia`, `qt6-wayland`, `glib2`, `fd`, `rsync`, `xdg-utils` |
| **Optional** | `kwindowsystem` (native KDE blur), `wl-clipboard` (clipboard), `bat` (syntax highlighting), `gvfs` / `gvfs-smb` (remote filesystems), `ffmpeg` (video thumbnails), `udisks2` (device mounting), `poppler-qt6` (PDF previews) |

---

## ⌨️ Keyboard shortcuts

### Navigation
| Shortcut | Action |
|----------|--------|
| `Return` / `Double-click` | Open file or directory |
| `Backspace` / `Alt+Up` | Parent directory |
| `Alt+Left` / `Alt+Right` | Back / Forward in history |
| `Ctrl+L` | Focus path bar |
| `Ctrl+F` | Search |
| `Type any letter` | Type-ahead jump to file |

### Views
| Shortcut | Action |
|----------|--------|
| `Ctrl+1` | Grid view |
| `Ctrl+2` | Miller column view |
| `Ctrl+3` | Detailed view |
| `Ctrl+Scroll` | Zoom |
| `Space` | Quick preview |
| `F3` | Merge / split panes |
| `F9` | Toggle sidebar |
| `Ctrl+H` | Toggle hidden files |

> The **hybrid** view is the default and is reachable from the view switcher in the status bar.

### Tabs
| Shortcut | Action |
|----------|--------|
| `Ctrl+T` / `Ctrl+W` | New / Close tab |
| `Ctrl+Shift+T` | Reopen closed tab |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Cycle tabs |

### File operations
| Shortcut | Action |
|----------|--------|
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | Copy / Cut / Paste |
| `Ctrl+A` | Select all |
| `Ctrl+Z` / `Ctrl+Shift+Z` | Undo / Redo |
| `F2` | Rename |
| `Delete` / `Shift+Delete` | Trash / Permanent delete |
| `Ctrl+Shift+N` / `Ctrl+N` | New folder / New file |
| `Ctrl+,` | Open Settings |

All shortcuts can be remapped in `~/.config/wayfile/config.toml` under `[shortcuts]`.

---

## ⚙️ Configuration

Config lives at `~/.config/wayfile/config.toml`, created with sensible defaults on first run.

```toml
[general]
theme = "bifrost"              # filename in themes/ without .toml
icon_theme = "Adwaita"         # system icon theme fallback
builtin_icons = true           # use the bundled SVG icons
default_view = "hybrid"        # hybrid | grid | detailed | miller
show_hidden = false
sort_by = "name"               # name | size | modified | type
sort_ascending = true
grid_cell_size = 150           # grid zoom (110–320), persisted across restarts

[appearance]
radius_small = 4
radius_medium = 6
radius_large = 10
transparency_enabled = true
transparency_level = 0.5       # 0 = fully transparent, 1 = opaque
animations_enabled = true

[sidebar]
position = "left"
width = 270
visible = true
compact = false                # collapse to a 56px icon rail
hidden_entries = ["places.recents"]   # sidebar rows hidden via right-click

[bookmarks]
paths = ["~/Documents", "~/Downloads", "~/Pictures", "~/Projects"]

[shortcuts]
# Override any shortcut, e.g.:
# rename      = "F2"
# miller_view = "Ctrl+2"
```

---

## 🎨 Theming

Wayfile is built on a **shared obsidian base** plus a **single accent**. The five shipped presets — Bifröst, Aurora, Nebula, Ember, and Verdant — each change just one value, the `accent`; the gold/accent ramp, glows, and chrome tints are derived from it live, so the whole UI retints from one colour. File-type and git-status colours are deliberately fixed so files stay recognisable across themes.

A theme is a TOML file with a `[colors]` table. The minimal form is a single accent:

```toml
# themes/aurora.toml — a preset is a one-line accent swap on the obsidian base
[colors]
accent = "#57C7BF"
```

You can override more of the palette in the same table if you want a fuller re-skin:

```toml
[colors]
base = "#1E2126"; mantle = "#15181C"; crust = "#0D0F13"; surface = "#25292E"
text = "#ECE7DC"; subtext = "#9CA0A8"; muted = "#787E85"
accent = "#D4AA6A"; success = "#84C98A"; warning = "#E68B5C"; error = "#C97070"
```

**Don't want to hand-edit TOML?** The **Settings → Colours** page has a swatch picker for the five presets that applies live, plus token-by-token editing (swatch + hex field) and a **Save** action that writes your palette to `~/.config/wayfile/themes/<name>.toml` as a new selectable theme. A live warning flags an accent that's too low-contrast against the background. Drop any TOML file into `themes/` (or your config folder) and it shows up in the picker — no restart.

---

## 🧱 Architecture

Wayfile is a three-layer Qt6 application:

- **QML frontend** (`src/qml/`) — all rendering. `Main.qml` wires tab state, selection, and shortcuts. `FileViewContainer` switches between `HybridView`, `FileGridView`, `FileDetailedView`, and `FileMillerView`. Theme tokens come from the `Theme` / `Fonts` / `FileTypeColors` / `GitColors` QML singletons; the vendored [Quill](https://github.com/soyeb-jim285/quill) library (in `src/qml/Quill/`) provides themed controls, bridged onto Wayfile's tokens in `Main.qml`.
- **C++ backend** (`src/models/`, `src/services/`, `src/providers/`) — `QAbstractListModel` subclasses for files, tabs, bookmarks, devices, and network locations; async services for config, theming, clipboard, file operations, search, disk usage, and previews. `ThemeLoader` parses the active TOML into the live `Theme` singleton, deriving the accent ramp. Exposed to QML via `setContextProperty`.
- **System layer** — `rsync` / `gio` via `QProcess`, UDisks2 over DBus, `wl-copy` for the clipboard.

See [`CLAUDE.md`](CLAUDE.md) for the full architecture notes.

---

## 🤝 Contributing

Issues and PRs welcome. A few notes:

- Run the tests with `ctest --test-dir build` after changes (Qt6::Test).
- Match the existing 4-space-indent style for QML and C++.
- Initialise submodules after pulling: `git submodule update --init --recursive`.

---

## 📜 License & credits

[MIT](LICENSE). Wayfile is a fork maintained by **blackbartblues**, building on the original **[HyprFM](https://github.com/soyeb-jim285/hyprfm)** by **Soyeb Pervez Jim**.

Built with [Qt 6](https://www.qt.io/) · icons inspired by [Lucide](https://lucide.dev/) · type by [Inter](https://rsms.me/inter/) (OFL), [Cormorant Garamond](https://github.com/CatharsisFonts/Cormorant) (OFL) & [JetBrains Mono](https://www.jetbrains.com/lp/mono/) (OFL) · inspired by macOS Finder, Nautilus, and Dolphin.
</content>
</invoke>
