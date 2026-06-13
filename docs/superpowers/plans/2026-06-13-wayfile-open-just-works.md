# Open "just works" (App Chooser fallback) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a host-local file has no working default application, pop Wayfile's existing App Chooser (plus an info toast) instead of silently dumping the file into a web browser.

**Architecture:** Host-local `FileOperations::openFile` switches from `QDesktopServices::openUrl` (whose `xdg-open` backend has a browser fallback that masks "no handler") to `gio open` (honors the default app + MIME subclass hierarchy, no browser fallback, exits non-zero cleanly when unhandled). On non-zero exit (or failure to start) it emits a new `openFileFailed(path, mimeType)` signal; `MainOverlays.qml` listens and opens the existing `appChooserDialog`.

**Tech Stack:** Qt6 / C++ (`QProcess`, `QMimeDatabase`), QML (`Connections`), `gio` CLI (already a hard runtime dependency).

**Spec:** `docs/superpowers/specs/2026-06-13-wayfile-open-just-works-design.md`

**Branch:** `open-just-works` (already created, spec committed at `d9afb7d`).

---

## File Structure

- `src/services/fileoperations.h` — declares the new `openFileFailed` signal.
- `src/services/fileoperations_desktop.cpp` — rewrites the host-local branch of `openFile` to use `gio open` + exit-code/error detection; adjusts includes.
- `src/qml/components/MainOverlays.qml` — adds a `Connections` block that turns the signal into toast + App Chooser.

No new test file: the failure path shells out to the real `gio` binary and depends on the host's MIME associations, so it is not deterministically unit-testable. Verification is build + `tst_qml_smoke` + the full `ctest` regression suite (must stay 24/24) + manual Wayland GUI-verify. **Do not add a flaky `openFileFailed` unit test.**

---

### Task 1: C++ — emit `openFileFailed`; launch host-local files via `gio open`

**Files:**
- Modify: `src/services/fileoperations.h` (signals block, ~line 115)
- Modify: `src/services/fileoperations_desktop.cpp` (includes ~lines 5/10/18; `openFile` host-local branch lines 147-163)

- [ ] **Step 1: Declare the signal in the header**

In `src/services/fileoperations.h`, find the end of the `signals:` block:

```cpp
    void clipboardImageAvailableChanged();

private:
```

Replace it with:

```cpp
    void clipboardImageAvailableChanged();

    // Emitted when a host-local file has no working default handler, so the UI
    // can offer the App Chooser instead of failing silently. mimeType may be
    // empty for an unknown type.
    void openFileFailed(const QString &path, const QString &mimeType);

private:
```

- [ ] **Step 2: Fix includes in `fileoperations_desktop.cpp`**

Remove the now-unused `QDesktopServices` include. Find:

```cpp
#include <QDesktopServices>
#include <QDir>
```

Replace with:

```cpp
#include <QDir>
```

Add `QMimeDatabase` after the existing `QMimeData` include. Find:

```cpp
#include <QMimeData>
#include <QPixmap>
```

Replace with:

```cpp
#include <QMimeData>
#include <QMimeDatabase>
#include <QPixmap>
```

Add the `<memory>` std header for `std::make_shared`. Find:

```cpp
#include <QUuid>

using namespace FileOperationsHelpers;
```

Replace with:

```cpp
#include <QUuid>

#include <memory>

using namespace FileOperationsHelpers;
```

- [ ] **Step 3: Rewrite the host-local branch of `openFile`**

In `src/services/fileoperations_desktop.cpp`, find the block from the "Local files" comment through the end of `openFile` (lines ~147-163):

```cpp
    // Local files. Outside a sandbox: hand off to Qt's QDesktopServices
    // (which uses xdg-open / kde-open / gio-launch under the hood and
    // honors the user's MIME associations). Inside a Flatpak: shell out
    // to `flatpak-spawn --host xdg-open` so the host opens the file with
    // the host's default app, completely bypassing the sandbox. This is
    // the same pattern Nautilus and Dolphin use when running as Flatpaks.
    if (runningInFlatpak()) {
        proc->start(QStringLiteral("flatpak-spawn"),
                    {QStringLiteral("--host"), QStringLiteral("xdg-open"), normalized});
        return;
    }

    proc->deleteLater();
    const QUrl url = QUrl::fromLocalFile(normalized);
    if (!QDesktopServices::openUrl(url))
        qWarning() << "FileOperations::openFile: failed to open" << normalized;
}
```

Replace it with:

```cpp
    // Flatpak local files: shell out to `flatpak-spawn --host xdg-open` so the
    // host opens the file with its default app, bypassing the sandbox. (Out of
    // scope for the App Chooser fallback — left as fire-and-forget.)
    if (runningInFlatpak()) {
        proc->start(QStringLiteral("flatpak-spawn"),
                    {QStringLiteral("--host"), QStringLiteral("xdg-open"), normalized});
        return;
    }

    // Host local files: launch via `gio open`, which honors the user's default
    // app AND the MIME subclass hierarchy and — unlike xdg-open / QDesktopServices
    // — has no web-browser fallback for unhandled types. When gio reports no
    // default handler (non-zero exit) or fails to start, emit openFileFailed so
    // the UI can offer the App Chooser. Reported at most once.
    auto reported = std::make_shared<bool>(false);
    auto reportFailure = [this, normalized, reported]() {
        if (*reported)
            return;
        *reported = true;
        QMimeDatabase mimeDb;
        emit openFileFailed(normalized, mimeDb.mimeTypeForFile(normalized).name());
    };
    connect(proc, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
            [reportFailure](int exitCode, QProcess::ExitStatus status) {
                if (status != QProcess::NormalExit || exitCode != 0)
                    reportFailure();
            });
    connect(proc, &QProcess::errorOccurred, this,
            [reportFailure](QProcess::ProcessError) { reportFailure(); });
    proc->start(QStringLiteral("gio"), {QStringLiteral("open"), normalized});
}
```

Note: the existing `connect(proc, finished, proc, &QProcess::deleteLater)` at the top of `openFile` still owns cleanup; the `reportFailure` lambda captures a `shared_ptr` so it stays valid after the proc is gone.

- [ ] **Step 4: Build**

Run: `cmake -B build && cmake --build build -j`
Expected: builds with no errors and no "unused include / undefined symbol" warnings for the touched files.

- [ ] **Step 5: Run the full test suite (regression)**

Run: `ctest --test-dir build --output-on-failure`
Expected: `100% tests passed, 0 tests failed out of 24`.

- [ ] **Step 6: Commit**

```bash
git add src/services/fileoperations.h src/services/fileoperations_desktop.cpp
git commit -m "feat(open): launch host-local files via gio and detect no-handler failures"
```

---

### Task 2: QML — turn `openFileFailed` into toast + App Chooser

**Files:**
- Modify: `src/qml/components/MainOverlays.qml` (after the `appChooserDialog` instance, ~line 185)

- [ ] **Step 1: Add the `Connections` block**

In `src/qml/components/MainOverlays.qml`, find the App Chooser instance:

```qml
    // ── App Chooser dialog ──────────────────────────
    AppChooserDialog {
        id: appChooserDialog
        fileModel: host.paneBaseModel(activePaneIndex)
        onUsedAndClosed: {
            if (propertiesDialog.visible && propertiesDialog.props.mimeType) {
                propertiesDialog._appsMime = propertiesDialog.props.mimeType
                propertiesDialog.fileModelRef.requestAvailableApps(propertiesDialog.props.mimeType)
            }
        }
    }
```

Insert immediately after its closing brace:

```qml

    // Open "just works": when a host-local file has no working default handler,
    // FileOperations.openFile emits openFileFailed → surface the App Chooser
    // (with the MIME set, so "Set Default" is available) plus an info toast.
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

(`fileOps` is a global context property already used throughout this file; `toast` is a property of `MainOverlays`; `appChooserDialog` is the sibling id above.)

- [ ] **Step 2: Reconfigure + build (regenerates the qrc so the QML change is bundled)**

Run: `cmake -B build && cmake --build build -j`
Expected: builds clean. ⚠ `cmake --build` alone does NOT regenerate the qrc — the `cmake -B build` reconfigure step is required or the smoke test runs stale QML.

- [ ] **Step 3: Run the QML smoke test**

Run: `ctest --test-dir build -R tst_qml_smoke --output-on-failure`
Expected: PASS (QML loads with no parse/binding errors for the new `Connections` block).

- [ ] **Step 4: Commit**

```bash
git add src/qml/components/MainOverlays.qml
git commit -m "feat(open): fall back to the app chooser when no default handler"
```

---

### Task 3: Manual GUI verification (Wayland) + cleanup

**Files:** none (verification only).

- [ ] **Step 1: Launch the app**

Run: `./build/src/wayfile`
Expected: app starts normally.

- [ ] **Step 2: Verify the fallback fires**

Navigate to `~/Downloads` and open `wayfile-open-test.bin` (double-click or context-menu → Open). This file is `application/octet-stream` with no default handler.
Expected: an info toast `No default app for "wayfile-open-test.bin" — choose one` appears AND the "Choose Application" dialog opens listing installed apps. **No** Firefox/browser save-file dialog.

- [ ] **Step 3: Verify launch + Set Default**

In the chooser, click a text editor to confirm it launches with the file. Re-open the file, hover an app, click **Set Default**. Re-open once more.
Expected: after Set Default, the file opens directly in that app with no chooser.

- [ ] **Step 4: Regression spot-check (normal files still open directly)**

Open a normally-associated file of each kind: an image, a `.txt`, and a `.py` (`text/x-python3` — the hierarchy case).
Expected: each opens directly in its default app; no chooser, no toast.

- [ ] **Step 5: Clean up the test artifacts (after the user confirms verification)**

```bash
rm -f ~/Downloads/wayfile-open-test.bin
```

Reset any default the verification set on `application/octet-stream` if undesired:

```bash
# Only if Step 3 set a default you don't want to keep:
# edit ~/.config/mimeapps.list and remove the application/octet-stream= line
```

---

## Self-Review

**Spec coverage:**
- `openFileFailed(path, mimeType)` signal → Task 1 Step 1 ✓
- Host-local launch via `gio open` + non-zero-exit detection → Task 1 Step 3 ✓
- Lazy `QMimeDatabase` MIME on failure → Task 1 Step 3 ✓
- `errorOccurred` handling + single-report guard → Task 1 Step 3 ✓
- Include changes (add `QMimeDatabase`/`memory`, drop `QDesktopServices`) → Task 1 Step 2 ✓
- QML `Connections` → toast + chooser with `mimeType` set → Task 2 Step 1 ✓
- Remote + Flatpak branches unchanged → preserved in Task 1 Step 3 ✓
- Verification: build + smoke + ctest 24/24 + GUI-verify with the prepared test file + regression spot-check → Tasks 1-3 ✓

**Placeholder scan:** none — every step has concrete code/commands.

**Type consistency:** signal `openFileFailed(QString path, QString mimeType)` ↔ QML handler `onOpenFileFailed(path, mimeType)`; APIs used (`toast.show(msg, "info")`, `fileOps.displayNameForPath`, `appChooserDialog.filePath`/`mimeType`/`open()`) all verified against current source. Consistent.

**Intermediate state note:** after Task 1 but before Task 2, opening an unhandled host-local file emits a signal with no listener → nothing happens (no browser dump, no chooser yet). Task 2 completes the behavior. Both commits build green.
