#!/usr/bin/env bash
# QML load smoke test for Heimdall.
#
# Launches the built binary headless (offscreen Qt platform) in a throwaway
# XDG environment and fails if the QML engine reports any load or binding
# error on stderr. This is the automated form of the manual offscreen smoke
# used throughout the Faza 5 QML splits: it loads the WHOLE QML tree (Main +
# MainOverlays + every dialog/menu + the default Settings page and its
# dropdowns) with the real C++ context properties, so it catches regressions
# that compile cleanly but break the tree at load/bind time — a component
# dropped from the QML module, a stale context reference, or a self-
# referential binding that silently resolves to null.
#
# It is NOT an interaction test (it never clicks anything); pair it with a
# manual GUI pass for behaviour. A QtQuickTest harness was avoided on purpose:
# the components depend on many C++ context properties that would have to be
# mocked, which is far more brittle than running the real app headless.
#
# Usage: qml-smoke.sh <path-to-heimdall-binary>
set -u

BIN="${1:?usage: qml-smoke.sh <heimdall-binary>}"
if [ ! -x "$BIN" ]; then
    echo "qml-smoke: binary not found or not executable: $BIN" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the developer's running session: a private runtime dir gives
# the app its own single-instance socket (so it never attaches to a running
# instance), and private config/cache dirs keep the test from reading or
# writing real settings.
export XDG_RUNTIME_DIR="$TMP/run"
export XDG_CONFIG_HOME="$TMP/config"
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
chmod 700 "$XDG_RUNTIME_DIR"

export QT_QPA_PLATFORM=offscreen
export QT_FORCE_STDERR_LOGGING=1

LOG="$TMP/heimdall.log"
# The app runs until the timeout stops it; `timeout` returning non-zero
# (124 = stopped) is expected and not a failure — only QML errors are.
timeout 8 "$BIN" "$TMP" >"$LOG" 2>&1 || true

# QML-engine load/runtime error signatures only (NOT generic "warning"/"error",
# which would catch benign optional-tool notices like a missing udisksctl).
ERRORS="$(grep -nE '\.qml:[0-9]+|TypeError|ReferenceError|Cannot read property|Cannot assign|Unable to assign|is not a function|is not defined|Required property .* was not set|Binding loop detected' "$LOG" \
    | grep -viE 'qt\.qpa|libpng|EGL|Mesa|swrast' || true)"

if [ -n "$ERRORS" ]; then
    echo "QML smoke test FAILED — the QML engine reported errors:" >&2
    echo "$ERRORS" >&2
    exit 1
fi

echo "QML smoke test passed: no QML load/binding errors detected."
exit 0
