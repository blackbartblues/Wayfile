# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

```bash
# Build
cmake -B build && cmake --build build

# Run
./build/src/wayfile

# Run all tests
ctest --test-dir build

# Run a single test
./build/tests/tst_configmanager
```

Tests use Qt6::Test (QCOMPARE, QSignalSpy). Test sources are in `tests/tst_*.cpp` — one per backend class.

## Architecture

Wayfile is a Qt6/QML file manager with three layers:

**QML Frontend** (`src/qml/`) — All rendering. `Main.qml` is the root that wires tab state, selection, and keyboard shortcuts. `FileViewContainer.qml` switches between grid/list/detailed views. `Theme.qml` is a QML singleton providing colors from the active TOML theme.

**C++ Backend** (`src/models/`, `src/services/`, `src/providers/`) — Exposed to QML as context properties set in `main.cpp`. Models (FileSystemModel, TabListModel, BookmarkModel, DeviceModel) are all QAbstractListModel subclasses with custom roles. Services (ConfigManager, ThemeLoader, FileOperations, ClipboardManager) manage state and async operations.

**System Layer** — FileOperations spawns rsync/gio/xdg-open via QProcess. DeviceModel monitors UDisks2 over DBus. Assumes Wayland (wl-copy for clipboard).

### Data flow

QML action → Q_INVOKABLE C++ method → model property change → QML property binding re-renders view. FileSystemModel watches directories via QFileSystemWatcher for automatic reload.

### Key conventions

- Models expose data via `roleNames()` mapping enums to QML-accessible names (e.g., `FileNameRole` → `"fileName"`)
- QML components communicate upward via signals (fileActivated, contextMenuRequested), downward via property bindings
- Config lives at `~/.config/wayfile/config.toml` (TOML format); theme files in `themes/`
- All async file I/O through QProcess to avoid blocking the GUI thread

## Commit Rules

Never add Co-Authored-By lines to commits.

## Shared Submodules & Vendored Libraries

- `src/qml/icons/` → [quill-icons](https://github.com/soyeb-jim285/quill-icons) **submodule** — 60 PathSvg icons (Lucide-derived, ISC/MIT). No push access; do not edit in place (inline glyphs in the main repo instead — see GitBadge.qml).
- `src/qml/Quill/` → **vendored** (forked) from [quill](https://github.com/soyeb-jim285/quill) @ `e3a7d99` — Themed QML component library (Button, TextField, Card, Tabs, Dropdown, etc.). Un-submoduled so its components can be re-skinned (obsidian+gold) directly in this repo. Edit these files freely.

Quill's `Theme.qml` singleton is bridged from Wayfile's theme in `Main.qml` `Component.onCompleted`. The directory must be uppercase `Quill/` to match the QML module name. Quill is loaded from disk at runtime via `engine.addImportPath(.../src/qml)` (not the rcc resource), so edits to Quill components take effect on relaunch without a rebuild.

## Packaging & Distribution

- **AUR**: `PKGBUILD` in repo root, also maintained at `~/wayfile-aur/` (ssh://aur@aur.archlinux.org/wayfile-git.git)
- **AppImage**: not currently published — there is no CI workflow yet. A `.github/workflows/build.yml` would be needed to build AppImages on `v*` tags. (`scripts/build-appimage-local.sh` builds one locally.)
- **Flatpak**: manifest `io.github.blackbartblues.Wayfile.yml` in repo root (org.kde.Platform 6.9), pins a release tag for Flathub submission.
- **Desktop entry, icon & metainfo**: `dist/io.github.blackbartblues.Wayfile.{desktop,svg,metainfo.xml}` (named to the app-id)

### AUR vs GitHub repo

The AUR repo (`~/wayfile-aur/`) only contains `PKGBUILD` + `.SRCINFO` — build instructions, not source code. The PKGBUILD clones from GitHub at build time, so `yay -S wayfile-git` always gets the latest `main`. Only update the AUR repo when dependencies, build steps, or install paths change — not for code changes.

### WAYFILE_DATA_DIR

`WAYFILE_DATA_DIR` (CMake cache var) controls where the binary finds themes and QML at runtime. Defaults to `CMAKE_SOURCE_DIR` for dev. PKGBUILD sets it to `/usr/share/wayfile`. Separate from `WAYFILE_SOURCE_DIR` which is always the build source dir (needed for `loadFromModule`).

## Dependencies

Qt6 modules: Core, Gui, Qml, Quick, QuickControls2, DBus, Widgets, Svg, SvgWidgets, Multimedia (`qt6-multimedia` — in-app video playback in the Gallery view). TOML parsing via header-only `third_party/toml.hpp`. Runtime CLI tools: rsync, gio, xdg-open, wl-copy (optional; warns if missing).
