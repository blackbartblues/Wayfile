# Wayfile — Custom theme presets + pinned picker (design)

**Date:** 2026-06-09
**Branch:** `handoff-1.0.0` (follows W2 theming; same single-branch effort)
**Status:** design — awaiting user review before writing the implementation plan.

## Goal

Let the user **save the current palette as a named preset**, manage those presets as **deletable swatches** alongside the 5 built-ins, and **pin the preset picker** at the top of the Colours settings page so only the token editor scrolls.

This builds directly on W2 (obsidian base + 5 accent presets + the swatch picker + the live token editor that forks an unsaved `custom` draft).

## Locked decisions (brainstorm 2026-06-09)

- **Preset scope:** a saved preset captures the **full current palette** (a complete, self-contained theme file), not just the accent.
- **Appearance/management:** saved presets appear as **extra swatches** in the same picker row (after the 5 built-ins), each with a hover **×** to delete. The **5 built-ins cannot be deleted or overwritten** (reserved names).
- **Active indicator:** **swatch highlight only** (gold border on the active swatch; none highlighted while on the unsaved `custom` draft). No extra "editing custom" hint line.
- **Duplicate user name:** **confirm-then-overwrite** for an existing *user* preset (lets you update in place). A reserved built-in name is always **rejected**.
- **Layout:** the preset row (header + swatches + Save control) is **pinned**; only the token editor below scrolls.
- **Tabs:** the Ctrl+LMB multi-select **ring stays as-is** — its replacement with the handoff glowing top-bar is **deferred to W4** (Tabs + merge). No tab work here.

## Architecture

### Storage

- **User themes dir:** `~/.config/wayfile/themes/` (the install `themes/` dir is read-only in packaged builds, so user presets need a writable home next to `config.toml`). Created on first save.
- A saved preset is `~/.config/wayfile/themes/<name>.toml` holding the **full palette** (every token, via the existing `ThemeLoader::saveThemeFile`). The theme **name == the file's complete base name** (matches how `availableThemes()` derives names today). Names may contain spaces.
- The unsaved working draft remains `custom.toml` in the config dir (unchanged W2 behavior): editing a token still applies live and forks `custom`. `+ Save as preset` promotes that draft into a named file.
- A saved preset's gold ramp is still **derived from its `accent`** at load time (W2 `Theme.qml`), so saved files are forward-compatible even if the ramp formula changes.

### ConfigManager (`src/services/configmanager.{h,cpp}`)

New surface (mirrors the existing `customThemePath()` pattern; `m_configPath` already gives the config dir):

- `QString userThemesDir() const` → `<configDir>/themes`.
- `Q_INVOKABLE QString userThemePath(const QString &name) const` → `<userThemesDir>/<sanitizedName>.toml`, **creating `userThemesDir` if missing**. Returns empty string if the name is invalid/reserved.
- `Q_INVOKABLE QString themeNameError(const QString &name) const` → `""` if the name is saveable, else a short reason (`"empty"` / `"reserved"` / `"invalid"`). Reserved = the 5 built-ins + `custom`, case-insensitive; invalid = contains `/ \ .`-leading or path separators / over a length cap.
- `Q_INVOKABLE bool userThemeExists(const QString &name) const` → true if `<userThemesDir>/<name>.toml` exists (drives the overwrite confirm).
- `Q_INVOKABLE bool deleteUserTheme(const QString &name)` → deletes the user file; **refuses reserved/built-in names and install-dir themes**; emits `userThemesChanged()`. Returns success.
- `Q_INVOKABLE QVariantList userThemes() const` → `[{ "name": "...", "accent": "#rrggbb" }, ...]` for each `*.toml` in `userThemesDir` (parse only the `accent` token via the existing `toml.hpp`; fall back to the default accent if absent). Drives the custom swatches.
- `Q_INVOKABLE QString themePath(const QString &name) const` → resolves a theme name to a load path: `custom` → `customThemePath()`; else user file if it exists; else `<installThemesDir>/<name>.toml`. Centralizes the lookup.
- `availableThemes()` also scans `userThemesDir` (dedup with install names; built-in names win). Still appends `custom` when `custom.toml` exists.
- Add signal `void userThemesChanged()` (emitted after save/delete) for the picker to refresh.

### ThemeLoader

No interface change. The picker saves via the existing `theme.saveThemeFile(config.userThemePath(name))` (full-palette serialization). `userThemePath` guarantees the directory exists first.

### main.cpp load path

Replace the two `loadTheme(...)` call sites (startup `:230` and the `configChanged` reload `:343-346`) with the resolver:
```cpp
theme->loadTheme(config->themePath(config->theme()), QString());
```
`themePath` already handles `custom` / user / built-in, so the inline `== "custom" ? customThemePath() : ...` branch is removed (cleaner). The path is absolute, so the `themesDir` arg is unused.

### Pinned picker layout (`SettingsPanel.qml` + `SettingsSectionColors.qml`)

The Colours page currently lives inside the **shared** `contentFlick` Flickable, so the whole page scrolls. To pin the picker we let the Colours page **own its scroll**:

- A section page may expose `readonly property bool managesOwnScroll: true`. When set, `SettingsPanel` renders the page **directly in the content rect** (filling it) instead of inside `contentFlick`. Other pages are unchanged (still inside the shared Flickable).
- `SettingsSectionColors` becomes: a fixed top region (the **preset picker**: "Theme preset" header + swatch row + `+ Save` control + the existing low-contrast warning) and an inner `Flickable` containing the **token editor** (the Accent/Obsidian/Semantic/Text/Lines/Atmosphere/Status groups + tips). The picker and the token editor stay in one component, so they keep sharing `colorsRoot` state (`rev`, helpers).

This keeps the component cohesive and avoids fighting the shared Flickable; the contract (`managesOwnScroll`) is small and reusable.

### Picker UI (in `SettingsSectionColors.qml`)

- Row = 5 built-in swatches (from the hardcoded `presets` model) **+** custom swatches (from `config.userThemes()`, held in a local `userPresets` list refreshed on `Component.onCompleted` and on `config.userThemesChanged`) **+** a `+` "Save current as preset" control.
- A swatch's `active` = `config.theme === name` (gold border). Custom swatches show a hover **×**; built-ins don't.
- **Save flow:** `+` reveals an inline, Wayland-safe name `Q.TextField` + Save/Cancel (no native dialog, matching the hex-field pattern). On Save:
  1. `var err = config.themeNameError(name)` → if non-empty, show the reason inline; abort.
  2. If `config.userThemeExists(name)` → show inline "Overwrite “<name>”?" confirm (Cancel/Overwrite); proceed only on Overwrite.
  3. `theme.saveThemeFile(config.userThemePath(name))`; then `panel.setDraftTheme(name)` + `panel.applySettingsNow()` (active = the new preset); `config.userThemesChanged` refreshes the row.
- **Delete (×):** `config.deleteUserTheme(name)`; if it was the active theme, `panel.setDraftTheme("bifrost")` + `applySettingsNow()`; the row refreshes via the signal.
- Clicking any swatch bumps `colorsRoot.rev` so the granular rows re-seed (W2 behavior).

## Data flow

```
+ Save (name) -> config.themeNameError? -> [reserved/empty/invalid -> inline notice]
             -> config.userThemeExists? -> [yes -> inline overwrite confirm]
             -> theme.saveThemeFile(config.userThemePath(name))   (writes ~/.config/wayfile/themes/<name>.toml)
             -> panel.setDraftTheme(name) + applySettingsNow()    (config[general].theme = name)
             -> config emits userThemesChanged -> picker reloads userThemes -> new swatch (active)
Restart -> main.cpp loadTheme(config.themePath(name)) -> resolves to the user file -> Theme.qml derives ramp
Delete (x) -> config.deleteUserTheme(name) -> [if active -> setDraftTheme("bifrost")] -> userThemesChanged -> row refresh
```

## Edge cases

- Missing `userThemesDir` → created on first save.
- Empty name / reserved built-in name / path-separator chars → rejected with an inline reason (no file written).
- Duplicate user name → confirm-then-overwrite.
- Deleting the active preset → falls back to Bifröst.
- A user file that fails to parse / lacks `accent` → `userThemes()` falls back to the default accent for its dot (still listed; still loadable via s_defaults fallback).
- `availableThemes()` name collision (a user file named like a built-in) → can't happen for new saves (reserved), and built-in wins on scan dedup.

## Testing

- **ConfigManager unit tests** (`tst_configmanager.cpp`): `userThemesDir` path; `availableThemes()` includes user-dir themes; `themePath()` resolves user vs install vs custom; `themeNameError()` (empty/reserved/invalid/ok); `userThemeExists()`; `userThemes()` parses name+accent; `deleteUserTheme()` removes a user file and **refuses built-in/reserved names**; `userThemesChanged` emitted on save-path/delete. Use a `QTemporaryDir` config dir + a temp install themes dir.
- **QML**: `tst_qml_smoke` (both edited settings files parse/instantiate); user GUI-verify (save a preset → swatch appears + active; restart persists; delete → falls back; pinned picker stays put while the token list scrolls; built-ins have no ×).

## Out of scope

- Tabs / the Ctrl+LMB ring (W4).
- Renaming presets in place (delete + re-save covers it).
- Importing/exporting preset files, sharing, or a full theme-authoring UI beyond the existing token editor.
- Per-preset file-type/git colours (those stay fixed, as in W2).
