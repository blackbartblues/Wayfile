# Wayfile — "Open just works": App Chooser fallback (WS1)

**Date:** 2026-06-13
**Status:** Design approved (pending written-spec review)
**Scope:** Host-local file opens only.

## Problem

Activating *Open* on a local file whose MIME type has no working default
application fails badly:

- `FileOperations::openFile` (host-local branch, `fileoperations_desktop.cpp`)
  calls `QDesktopServices::openUrl`, which on Linux routes through `xdg-open`.
- `xdg-open` has a **browser fallback** (`open_generic` → `$BROWSER` →
  firefox/chromium/…). For an unhandled file it launches the browser with the
  `file://` URL, so the user gets the browser's useless *"You have chosen to
  open … Would you like to save this file?"* dialog instead of opening the file.
- Because the browser fallback "succeeds", `openUrl` returns `true`. There is no
  reliable signal to detect "no real handler", so the file manager can't react.

Empirically verified 2026-06-13: opening an `application/octet-stream` file in
Wayfile pops Firefox's save-file dialog; `openUrl` returns `true`.

## Goal

When a host-local file has no working default handler, stop deferring to the
browser. Instead surface Wayfile's existing **App Chooser** so the user can pick
an application (and optionally *Set Default*, permanently fixing the
association).

## Key findings (live testing, 2026-06-13)

1. **`QDesktopServices::openUrl()==false` is not a usable trigger** — the
   xdg-open browser fallback makes it almost always return `true`.
2. **`xdg-mime query default <mime>` (the model's `defaultApp`) is too naive** —
   it queries the *exact* type only and misses the MIME subclass hierarchy.
   Example measured: `text/x-python3` → empty via `xdg-mime`, but the file
   really opens (resolves to `micro.desktop` via hierarchy). Using this check
   would wrongly pop the chooser for files that open fine today.
3. **`gio open <path>` is the correct mechanism:**
   - Honors the user's default app **and** the MIME subclass hierarchy
     (`text/x-python3` → launches `micro`, no false chooser).
   - Has **no browser fallback**.
   - On a genuinely unhandled file it **exits non-zero cleanly with no GUI**
     (`gio open <octet-stream file>` → exit `2`, prints "Failed to find default
     application for content type …").
   - `gio` is already a hard runtime dependency, and the existing remote-URI
     branch of `openFile` already uses `gio open`.

## Design

### C++ — `FileOperations`

**New signal** (`fileoperations.h`, signals block):

```cpp
void openFileFailed(const QString &path, const QString &mimeType);
```

**`openFile()` host-local branch** (`fileoperations_desktop.cpp`): replace the
`QDesktopServices::openUrl` call with a `gio open <normalized>` `QProcess`
(mirroring the existing remote branch). Detect failure on completion:

- On `finished`: if `exitStatus != NormalExit || exitCode != 0`, compute the
  MIME lazily with a function-local `QMimeDatabase`
  (`db.mimeTypeForFile(normalized).name()` — content-sniffed) and
  `emit openFileFailed(normalized, mime)`.
- On `errorOccurred` (e.g. `gio` failed to start): same emit, so failure is
  never silent.
- A small one-shot guard (e.g. a captured `std::shared_ptr<bool>`) prevents a
  double emit in the rare `finished`+`errorOccurred` (crash) overlap.

Add `#include <QMimeDatabase>` to `fileoperations_desktop.cpp`.

Branches **left unchanged** (out of scope per decision): remote URIs
(`gio open` fire-and-forget) and Flatpak local (`flatpak-spawn --host xdg-open`
fire-and-forget).

### QML — `MainOverlays.qml`

**New `Connections` block** beside the existing `appChooserDialog` instance:

```qml
Connections {
    target: fileOps
    function onOpenFileFailed(path, mimeType) {
        toast.show("No default app for \"" + fileOps.displayNameForPath(path) + "\" — choose one", "info")
        appChooserDialog.filePath = path
        appChooserDialog.mimeType = mimeType
        appChooserDialog.open()
    }
}
```

This reuses the exact logic of the existing `onChooseAppRequested` handler
(filePath + mimeType + open) plus an info toast naming the file. `toast` is
already a property of `MainOverlays`; `toast.show(message, "info")` is the
established helper.

## Data flow

`Open file` → `fileOps.openFile(path)` → host-local branch → `gio open <path>`
(QProcess) → exit ≠ 0 → `emit openFileFailed(path, mime)` → QML
`onOpenFileFailed` → info toast + App Chooser opens (lists all installed apps;
*Set Default* available because `mimeType` is set) → user picks → `openFileWith`
launches it; *Set Default* permanently fixes the association.

## Edge cases

- **Empty `mimeType`** (unknown type): chooser still works, just no *Set
  Default* button — matches the existing `mimeType==""` behavior.
- **`gio` missing**: `errorOccurred` → chooser still pops (not silent). The
  runtime-features dependency check already warns about a missing `gio`.
- **No double-launch**: a non-zero exit means nothing was launched.
- **Successful open**: `finished` with exit 0 → nothing further happens; no toast.
- **Chooser is the existing singleton** in `MainOverlays`; its
  `usedAndClosed` → Properties-dialog refresh path is untouched.

## Trade-off (accepted)

Host-local files now launch via `gio open` instead of `QDesktopServices` /
`xdg-open`. This removes the browser-dump misbehavior and makes failure
deterministic and hierarchy-correct. It drops `QDesktopServices`' KDE-specific
`kde-open` path — acceptable because `gio` is a hard runtime dependency, the
remote branch already relies on it, and `gio`-based resolution is how GTK file
managers (Nautilus/Nemo) open files.

## Testing / verification

- Build: `cmake -B build && cmake --build build` (⚠ `cmake --build` alone may
  not regenerate the qrc — reconfigure with `cmake -B build` and relaunch the
  app for the smoke check).
- `tst_qml_smoke` (QML still loads) + `ctest` (expect 24/24 regression-green).
- The failure path depends on an environment with no handler for a given MIME,
  so it is not cleanly unit-testable through the process layer — the
  `openFileFailed` signal is the contract.
- **Manual GUI-verify on Wayland** with the prepared test file
  `~/Downloads/wayfile-open-test.bin` (`application/octet-stream`, no default):
  open it in Wayfile → confirm the info toast + App Chooser appear → pick an app
  (confirms launch) → *Set Default*, then re-open opens it directly.
- Regression spot-check: a normally-associated file (e.g. an image, a `.txt`,
  and a `.py`/`text/x-python3`) still opens directly with no chooser.

## Footprint

~20 lines across three files:

- `src/services/fileoperations.h` — `+1` signal.
- `src/services/fileoperations_desktop.cpp` — host-local branch rewrite +
  `#include <QMimeDatabase>`.
- `src/qml/components/MainOverlays.qml` — `+1` `Connections` block.

One commit: `feat(open): fall back to the app chooser when no default handler`.
