# Custom Theme Presets + Pinned Picker — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user save the current palette as a named preset (full-palette TOML in a writable user dir), manage those presets as deletable swatches alongside the 5 read-only built-ins, and pin the preset picker at the top of the Colours settings page so only the token editor scrolls.

**Architecture:** `ConfigManager` gains a small user-theme API (resolve name→path, list user presets, validate/reserve names, delete) and `main.cpp` switches to that resolver. The Colours page (`SettingsSectionColors.qml`) exposes its preset picker as a `pinnedHeader` Component that `SettingsPanel.qml` renders fixed above the shared scroll Flickable — the Component resolves the page's state via its lexical creation context, so picker and token-editor stay one cohesive component while living in different scroll regions.

**Tech Stack:** Qt6/QML, C++ (ConfigManager), `third_party/toml.hpp`, Qt6::Test. Build: `cmake --build build`; tests: `ctest --test-dir build`.

**Spec:** `docs/superpowers/specs/2026-06-09-wayfile-custom-theme-presets-design.md`.

---

## Context (read before starting)

- Branch `handoff-1.0.0`; this follows the W2 theming work (obsidian base + 5 accent presets + a swatch picker + a live token editor that forks an unsaved `custom` draft).
- `ConfigManager` (`src/services/configmanager.{h,cpp}`) holds the config at `~/.config/wayfile/config.toml`; `customThemePath()` returns `<configDir>/custom.toml`; `availableThemes()` scans the read-only install themes dir (`m_themesDir`). `configmanager.cpp` already includes `third_party/toml.hpp`, `QDir`, `QFile`, `QFileInfo`.
- `main.cpp` loads the theme at startup (`:230`) and on `configChanged` (`:343-346`) via `theme->loadTheme(name-or-custompath, themesDir)`. `ThemeLoader::loadTheme(nameOrPath, themesDir)` uses `nameOrPath` directly if it's an existing file path, else `themesDir/<name>.toml`.
- `config` and `theme` are global QML context properties (set in `main.cpp`). `SettingsSectionColors.qml` already references both directly.
- `SettingsPanel.qml` renders each section page via a `Loader pageLoader` inside one shared `Flickable contentFlick`; the section title `Text` sits fixed above the Flickable.
- The W2 picker currently lives in the body of `SettingsSectionColors.qml` (lines ~212-278) and scrolls with everything else.

## File structure

| File | Responsibility | Task |
|---|---|---|
| `src/services/configmanager.h` / `.cpp` | user-theme API: `userThemesDir/userThemePath/themeNameError/userThemeExists/deleteUserTheme/userThemes/themePath`; `availableThemes` scans user dir | 1 |
| `tests/tst_configmanager.cpp` | unit tests for the new API | 1 |
| `src/main.cpp` | use `themePath()` resolver for both load sites | 2 |
| `src/qml/components/SettingsPanel.qml` | render a section page's optional `pinnedHeader` fixed above the scroll | 3 |
| `src/qml/components/SettingsSectionColors.qml` | move the picker into a `pinnedHeader` Component (T3); add custom swatches + save/delete (T4) | 3, 4 |

---

## Task 1: ConfigManager user-theme API (TDD)

**Files:**
- Modify: `src/services/configmanager.h` (declarations)
- Modify: `src/services/configmanager.cpp` (implementations + `availableThemes`)
- Test: `tests/tst_configmanager.cpp`

- [ ] **Step 1: Write the failing tests**

Add these test methods inside the `private slots:` section of `tests/tst_configmanager.cpp` (after the existing `testAvailableThemes`):

```cpp
    void testUserThemesDir()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");
        QCOMPARE(mgr.userThemesDir(), QDir(dir.path()).filePath("themes"));
    }

    void testThemeNameErrorValidation()
    {
        QTemporaryDir dir;
        QDir().mkpath(dir.path() + "/install");
        QFile bf(dir.path() + "/install/bifrost.toml");
        QVERIFY(bf.open(QIODevice::WriteOnly));
        bf.write("[colors]\naccent = \"#D4AA6A\"\n");
        bf.close();

        ConfigManager mgr(dir.path() + "/config.toml", nullptr, dir.path() + "/install");
        QCOMPARE(mgr.themeNameError(""), QString("empty"));
        QCOMPARE(mgr.themeNameError("   "), QString("empty"));
        QCOMPARE(mgr.themeNameError("bifrost"), QString("reserved"));
        QCOMPARE(mgr.themeNameError("BIFROST"), QString("reserved"));
        QCOMPARE(mgr.themeNameError("custom"), QString("reserved"));
        QCOMPARE(mgr.themeNameError("a/b"), QString("invalid"));
        QCOMPARE(mgr.themeNameError(".hidden"), QString("invalid"));
        QCOMPARE(mgr.themeNameError("My Cool Theme"), QString(""));
    }

    void testUserThemePathCreatesDir()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");
        const QString p = mgr.userThemePath("Cool");
        QCOMPARE(p, QDir(dir.path() + "/themes").filePath("Cool.toml"));
        QVERIFY(QDir(dir.path() + "/themes").exists());
        QVERIFY(mgr.userThemePath("a/b").isEmpty());
    }

    void testUserThemesListAndExists()
    {
        QTemporaryDir dir;
        QDir().mkpath(dir.path() + "/themes");
        QFile t(dir.path() + "/themes/Cool.toml");
        QVERIFY(t.open(QIODevice::WriteOnly));
        t.write("[colors]\naccent = \"#123456\"\nbase = \"#000000\"\n");
        t.close();

        ConfigManager mgr(dir.path() + "/config.toml");
        QVERIFY(mgr.userThemeExists("Cool"));
        QVERIFY(!mgr.userThemeExists("Nope"));
        const QVariantList list = mgr.userThemes();
        QCOMPARE(list.size(), 1);
        QCOMPARE(list.first().toMap().value("name").toString(), QString("Cool"));
        QCOMPARE(list.first().toMap().value("accent").toString(), QString("#123456"));
    }

    void testThemePathResolution()
    {
        QTemporaryDir dir;
        QDir().mkpath(dir.path() + "/install");
        QFile bf(dir.path() + "/install/bifrost.toml");
        QVERIFY(bf.open(QIODevice::WriteOnly));
        bf.write("[colors]\naccent=\"#D4AA6A\"\n");
        bf.close();
        QDir().mkpath(dir.path() + "/themes");
        QFile ct(dir.path() + "/themes/Cool.toml");
        QVERIFY(ct.open(QIODevice::WriteOnly));
        ct.write("[colors]\naccent=\"#123456\"\n");
        ct.close();

        ConfigManager mgr(dir.path() + "/config.toml", nullptr, dir.path() + "/install");
        QCOMPARE(mgr.themePath("custom"), mgr.customThemePath());
        QCOMPARE(mgr.themePath("Cool"), QDir(dir.path() + "/themes").filePath("Cool.toml"));
        QCOMPARE(mgr.themePath("bifrost"), QDir(dir.path() + "/install").filePath("bifrost.toml"));
    }

    void testDeleteUserTheme()
    {
        QTemporaryDir dir;
        QDir().mkpath(dir.path() + "/install");
        QFile bf(dir.path() + "/install/bifrost.toml");
        QVERIFY(bf.open(QIODevice::WriteOnly));
        bf.write("[colors]\naccent=\"#D4AA6A\"\n");
        bf.close();
        QDir().mkpath(dir.path() + "/themes");
        QFile ct(dir.path() + "/themes/Cool.toml");
        QVERIFY(ct.open(QIODevice::WriteOnly));
        ct.write("[colors]\naccent=\"#123456\"\n");
        ct.close();

        ConfigManager mgr(dir.path() + "/config.toml", nullptr, dir.path() + "/install");
        QVERIFY(!mgr.deleteUserTheme("bifrost"));   // reserved -> refused
        QVERIFY(QFile::exists(dir.path() + "/install/bifrost.toml"));
        QVERIFY(!mgr.deleteUserTheme("Nope"));      // missing -> false
        QVERIFY(mgr.deleteUserTheme("Cool"));       // user file -> removed
        QVERIFY(!QFile::exists(dir.path() + "/themes/Cool.toml"));
    }

    void testAvailableThemesIncludesUserThemes()
    {
        QTemporaryDir dir;
        QDir().mkpath(dir.path() + "/install");
        QFile bf(dir.path() + "/install/bifrost.toml");
        QVERIFY(bf.open(QIODevice::WriteOnly));
        bf.write("[colors]\naccent=\"#D4AA6A\"\n");
        bf.close();
        QDir().mkpath(dir.path() + "/themes");
        QFile ct(dir.path() + "/themes/Cool.toml");
        QVERIFY(ct.open(QIODevice::WriteOnly));
        ct.write("[colors]\naccent=\"#123456\"\n");
        ct.close();

        ConfigManager mgr(dir.path() + "/config.toml", nullptr, dir.path() + "/install");
        const QStringList themes = mgr.availableThemes();
        QVERIFY(themes.contains("bifrost"));
        QVERIFY(themes.contains("Cool"));
    }
```

- [ ] **Step 2: Build and confirm the tests fail**

Run: `cmake --build build --target tst_configmanager 2>&1 | tail -15`
Expected: **compile FAILS** (the new methods don't exist yet — `userThemesDir`, `themeNameError`, etc.).

- [ ] **Step 3: Declare the new API in `configmanager.h`**

In `src/services/configmanager.h`, in the `public:` section immediately after the `customThemePath()` declaration (line 59), add:

```cpp
    // User theme presets — writable, in the config dir's themes/ subdir. The
    // Colours settings saves the full current palette here and lists them as
    // deletable swatches alongside the read-only install presets.
    Q_INVOKABLE QString userThemesDir() const;
    Q_INVOKABLE QString userThemePath(const QString &name) const;   // "" if name invalid; creates the dir
    Q_INVOKABLE QString themeNameError(const QString &name) const;  // "" ok, else empty/reserved/invalid
    Q_INVOKABLE bool userThemeExists(const QString &name) const;
    Q_INVOKABLE bool deleteUserTheme(const QString &name);          // refuses reserved/built-in names
    Q_INVOKABLE QVariantList userThemes() const;                    // [{name, accent}, ...]
    Q_INVOKABLE QString themePath(const QString &name) const;       // resolve custom/user/install -> path
```

In the `private:` section after `void setDefaults();` (line 104) add:

```cpp
    bool isReservedThemeName(const QString &name) const;
```

- [ ] **Step 4: Implement in `configmanager.cpp`**

In `src/services/configmanager.cpp`, immediately after the `customThemePath()` definition (the function that returns `QFileInfo(m_configPath).dir().filePath("custom.toml")`, ~line 224), add:

```cpp
QString ConfigManager::userThemesDir() const
{
    return QFileInfo(m_configPath).dir().filePath(QStringLiteral("themes"));
}

bool ConfigManager::isReservedThemeName(const QString &name) const
{
    const QString n = name.trimmed();
    if (n.compare(QStringLiteral("custom"), Qt::CaseInsensitive) == 0)
        return true;
    if (m_themesDir.isEmpty())
        return false;
    // Any theme shipped in the read-only install dir is reserved.
    const QStringList installed = QDir(m_themesDir)
        .entryList({QStringLiteral("*.toml")}, QDir::Files);
    for (const QString &f : installed) {
        if (QFileInfo(f).completeBaseName().compare(n, Qt::CaseInsensitive) == 0)
            return true;
    }
    return false;
}

QString ConfigManager::themeNameError(const QString &name) const
{
    const QString n = name.trimmed();
    if (n.isEmpty())
        return QStringLiteral("empty");
    if (isReservedThemeName(n))
        return QStringLiteral("reserved");
    if (n.length() > 64 || n.contains(QLatin1Char('/')) || n.contains(QLatin1Char('\\'))
        || n.startsWith(QLatin1Char('.')))
        return QStringLiteral("invalid");
    return QString();
}

QString ConfigManager::userThemePath(const QString &name) const
{
    if (!themeNameError(name).isEmpty())
        return QString();
    QDir().mkpath(userThemesDir());
    return QDir(userThemesDir()).filePath(name.trimmed() + QStringLiteral(".toml"));
}

bool ConfigManager::userThemeExists(const QString &name) const
{
    const QString n = name.trimmed();
    if (n.isEmpty())
        return false;
    return QFile::exists(QDir(userThemesDir()).filePath(n + QStringLiteral(".toml")));
}

bool ConfigManager::deleteUserTheme(const QString &name)
{
    const QString n = name.trimmed();
    if (n.isEmpty() || isReservedThemeName(n))
        return false;
    const QString path = QDir(userThemesDir()).filePath(n + QStringLiteral(".toml"));
    if (!QFile::exists(path))
        return false;
    return QFile::remove(path);
}

QVariantList ConfigManager::userThemes() const
{
    QVariantList out;
    const QString dir = userThemesDir();
    if (!QDir(dir).exists())
        return out;
    const QStringList files = QDir(dir).entryList(
        {QStringLiteral("*.toml")}, QDir::Files, QDir::Name | QDir::IgnoreCase);
    for (const QString &fileName : files) {
        const QString name = QFileInfo(fileName).completeBaseName();
        if (isReservedThemeName(name))
            continue; // never shadow a built-in
        QString accent = QStringLiteral("#D4AA6A"); // default if the file omits it
        try {
            auto tbl = toml::parse_file(QDir(dir).filePath(fileName).toStdString());
            if (auto v = tbl["colors"]["accent"].value<std::string>())
                accent = QString::fromStdString(*v);
        } catch (const toml::parse_error &) {
            // keep the default accent for an unparseable file
        }
        QVariantMap m;
        m.insert(QStringLiteral("name"), name);
        m.insert(QStringLiteral("accent"), accent);
        out.append(m);
    }
    return out;
}

QString ConfigManager::themePath(const QString &name) const
{
    if (name == QStringLiteral("custom"))
        return customThemePath();
    const QString userPath = QDir(userThemesDir()).filePath(name + QStringLiteral(".toml"));
    if (QFile::exists(userPath))
        return userPath;
    if (!m_themesDir.isEmpty())
        return QDir(m_themesDir).filePath(name + QStringLiteral(".toml"));
    return name; // last resort: let ThemeLoader try it as a path
}
```

- [ ] **Step 5: Make `availableThemes()` also list user presets**

In `src/services/configmanager.cpp`, in `availableThemes()`, insert the user-dir scan just BEFORE the existing `custom` append (the `if (!themes.contains("custom") ...)` block). The function becomes:

```cpp
QStringList ConfigManager::availableThemes() const
{
    if (m_themesDir.isEmpty())
        return {};

    QDir dir(m_themesDir);
    const QStringList files = dir.entryList({"*.toml"}, QDir::Files, QDir::Name | QDir::IgnoreCase);

    QStringList themes;
    themes.reserve(files.size());
    for (const QString &fileName : files)
        themes.append(QFileInfo(fileName).completeBaseName());

    // User presets (writable config dir) appear alongside the install themes.
    const QString userDir = userThemesDir();
    if (QDir(userDir).exists()) {
        const QStringList userFiles = QDir(userDir).entryList(
            {QStringLiteral("*.toml")}, QDir::Files, QDir::Name | QDir::IgnoreCase);
        for (const QString &fileName : userFiles) {
            const QString name = QFileInfo(fileName).completeBaseName();
            if (!themes.contains(name))
                themes.append(name);
        }
    }

    // Surface the user's editable palette (config dir, not the read-only
    // install themes dir) as a selectable theme once it has been created.
    if (!themes.contains(QStringLiteral("custom"))
        && QFile::exists(customThemePath()))
        themes.append(QStringLiteral("custom"));

    return themes;
}
```

- [ ] **Step 6: Build and run the tests (GREEN)**

Run: `cmake --build build --target tst_configmanager 2>&1 | tail -5 && ./build/tests/tst_configmanager 2>&1 | tail -5`
Expected: **all pass**.

- [ ] **Step 7: Full suite**

Run: `ctest --test-dir build --output-on-failure 2>&1 | tail -5`
Expected: 24/24 pass.

- [ ] **Step 8: Commit**

```bash
git add src/services/configmanager.h src/services/configmanager.cpp tests/tst_configmanager.cpp
git commit -m "feat(config): user theme preset API (save/list/delete/resolve)"
```
Repo convention: NO Co-Authored-By / attribution lines.

---

## Task 2: main.cpp — resolve theme via `themePath`

**Files:**
- Modify: `src/main.cpp:230` and `src/main.cpp:343-346`

- [ ] **Step 1: Startup load**

In `src/main.cpp`, change line 230 from:
```cpp
    theme->loadTheme(config->theme(), themesDir);
```
to:
```cpp
    theme->loadTheme(config->themePath(config->theme()), QString());
```

- [ ] **Step 2: Reload on config change**

In `src/main.cpp`, replace the `configChanged` reload (lines 343-346):
```cpp
        theme->loadTheme(config->theme() == QStringLiteral("custom")
                             ? config->customThemePath()
                             : config->theme(),
                         themesDir);
```
with:
```cpp
        theme->loadTheme(config->themePath(config->theme()), QString());
```

- [ ] **Step 3: Build + smoke + full suite**

Run: `cmake --build build 2>&1 | tail -3 && ctest --test-dir build --output-on-failure 2>&1 | tail -5`
Expected: clean build; 24/24 pass (the existing themeloader/configmanager tests still cover load + path resolution; `tst_qml_smoke` confirms the app still loads its theme).

- [ ] **Step 4: Commit**

```bash
git add src/main.cpp
git commit -m "feat(theme): resolve active theme via ConfigManager.themePath (user/install/custom)"
```

---

## Task 3: Pinned-header slot + relocate the picker

**Files:**
- Modify: `src/qml/components/SettingsPanel.qml` (add the pinned-header Loader)
- Modify: `src/qml/components/SettingsSectionColors.qml` (move the picker into a `pinnedHeader` Component)

This isolates the layout change: the existing built-in picker is moved out of the scrolling body into a fixed region above it. No feature behavior changes yet.

- [ ] **Step 1: Add the pinned-header Loader in SettingsPanel.qml**

In `src/qml/components/SettingsPanel.qml`, find the section title `Text` (the one bound to `root.sectionItems[root.currentSectionIndex].title`) and the `Flickable { id: contentFlick ... }` immediately after it. Insert this Loader BETWEEN them (after the title's closing `}`, before `Flickable {`):

```qml
                            // A section page may pin a fixed header above the
                            // scroll area via `property Component pinnedHeader`.
                            // The Component is declared inside the page, so it
                            // resolves the page's ids/state through its creation
                            // context even though it is instantiated here. Only
                            // the Colours page uses it (the preset picker).
                            Loader {
                                id: pinnedHeaderLoader
                                Layout.fillWidth: true
                                active: pageLoader.item
                                        ? ((pageLoader.item.pinnedHeader || null) !== null)
                                        : false
                                sourceComponent: active ? pageLoader.item.pinnedHeader : null
                            }
```

- [ ] **Step 2: Move the picker into a `pinnedHeader` Component in SettingsSectionColors.qml**

In `src/qml/components/SettingsSectionColors.qml`:

(a) Add a `pinnedHeader` Component to `colorsRoot`. Place it right after the `presets` property (after line 36):

```qml
    // The preset picker, pinned above the scroll by SettingsPanel. Declared
    // here so it resolves colorsRoot/config/theme/panel via its creation
    // context. (Custom swatches + save/delete are added in the next task.)
    property Component pinnedHeader: Component {
        ColumnLayout {
            spacing: 6

            Text {
                text: "Theme preset"
                color: Theme.accent
                font.pointSize: Theme.fontSmall
                font.bold: true
                Layout.topMargin: 2
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Repeater {
                    model: colorsRoot.presets
                    delegate: ColumnLayout {
                        id: swatch
                        required property var modelData
                        readonly property bool active: config.theme === swatch.modelData.name
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 46
                            height: 46
                            radius: Theme.radiusMedium
                            color: Theme.panel
                            border.width: swatch.active ? 2 : 1
                            border.color: swatch.active
                                ? Theme.gold
                                : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, swatchHover.hovered ? 0.40 : 0.18)

                            Rectangle {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                radius: 13
                                color: swatch.modelData.accent
                            }

                            HoverHandler { id: swatchHover }
                            TapHandler {
                                onTapped: {
                                    colorsRoot.panel.setDraftTheme(swatch.modelData.name)
                                    colorsRoot.panel.applySettingsNow()
                                    colorsRoot.rev++
                                }
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: swatch.modelData.label
                            color: swatch.active ? Theme.accent : Theme.subtext
                            font.pointSize: Theme.fontSmall
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            Q.Separator { Layout.topMargin: 4 }
        }
    }
```

(b) Remove the now-relocated picker from the body. Delete these blocks (the W2 picker, currently ~lines 212-278): the `Text { text: "Theme preset" ... }`, the `RowLayout { ... Repeater over presets ... }`, the `SettingDescription { text: "Pick an accent preset..." }`, and the `Q.Separator { Layout.topMargin: 6; Layout.bottomMargin: 2 }` that followed it.

After this, the body flows: `SettingDescription` (edit tokens) → contrast-warning `Rectangle` → `Text "Accent"` + groups → tip. (The `Q.Separator` between the contrast warning and "Accent" is gone with the picker block; that's fine — the "Accent" header has `Layout.topMargin: 4`.)

- [ ] **Step 3: Build + smoke**

Run: `cmake --build build 2>&1 | tail -3 && ctest --test-dir build -R tst_qml_smoke --output-on-failure 2>&1 | tail -8`
Expected: clean build; smoke PASSES (both files parse; the `pinnedHeader` Component instantiates). Grep sanity: `grep -n "pinnedHeader" src/qml/components/SettingsPanel.qml src/qml/components/SettingsSectionColors.qml` shows the Loader + the property.

- [ ] **Step 4: Commit**

```bash
git add src/qml/components/SettingsPanel.qml src/qml/components/SettingsSectionColors.qml
git commit -m "feat(settings): pin the Colours preset picker above the scroll area"
```

---

## Task 4: Custom swatches + save / delete

**Files:**
- Modify: `src/qml/components/SettingsSectionColors.qml`

Extend `colorsRoot` with user-preset state + save/delete helpers, and rewrite the `pinnedHeader` picker to show custom swatches (with a hover ×), a `+` Save tile, and an inline name field with overwrite-confirm.

- [ ] **Step 1: Add user-preset state + helpers to `colorsRoot`**

In `src/qml/components/SettingsSectionColors.qml`, add these to `colorsRoot` (place after the `presets` property, before the `pinnedHeader` Component):

```qml
    // User-saved presets ({name, accent}), refreshed from ConfigManager.
    property var userPresets: []
    function refreshUserPresets() { userPresets = config.userThemes() }
    Component.onCompleted: refreshUserPresets()

    // Inline "save as preset" state for the picker.
    property bool naming: false
    property string nameError: ""        // "", "empty", "reserved", "invalid"
    property bool confirmingOverwrite: false

    // Built-ins (not deletable) + user presets (deletable) as one swatch model.
    readonly property var builtinSwatches: presets.map(function (p) {
        return { name: p.name, label: p.label, accent: p.accent, deletable: false }
    })
    property var allSwatches: builtinSwatches.concat(userPresets.map(function (u) {
        return { name: u.name, label: u.name, accent: u.accent, deletable: true }
    }))

    function selectPreset(name) {
        colorsRoot.panel.setDraftTheme(name)
        colorsRoot.panel.applySettingsNow()
        colorsRoot.rev++ // re-seed the granular editor rows
    }
    function beginSave() {
        colorsRoot.naming = true
        colorsRoot.nameError = ""
        colorsRoot.confirmingOverwrite = false
    }
    function cancelSave() {
        colorsRoot.naming = false
        colorsRoot.nameError = ""
        colorsRoot.confirmingOverwrite = false
    }
    function attemptSave(rawName) {
        var n = ("" + (rawName || "")).trim()
        var err = config.themeNameError(n)
        if (err !== "") { colorsRoot.nameError = err; colorsRoot.confirmingOverwrite = false; return }
        colorsRoot.nameError = ""
        if (!colorsRoot.confirmingOverwrite && config.userThemeExists(n)) {
            colorsRoot.confirmingOverwrite = true   // ask before clobbering an existing user preset
            return
        }
        var path = config.userThemePath(n)
        if (path === "") { colorsRoot.nameError = "invalid"; return }
        theme.saveThemeFile(path)                   // full current palette
        colorsRoot.refreshUserPresets()
        colorsRoot.selectPreset(n)                  // make the new preset active
        colorsRoot.naming = false
        colorsRoot.confirmingOverwrite = false
    }
    function deletePreset(name) {
        var wasActive = (config.theme === name)
        if (config.deleteUserTheme(name)) {
            if (wasActive) {
                colorsRoot.panel.setDraftTheme("bifrost")
                colorsRoot.panel.applySettingsNow()
            }
            colorsRoot.refreshUserPresets()
            colorsRoot.rev++
        }
    }
    function nameErrorText(code) {
        if (code === "empty")    return "Enter a name."
        if (code === "reserved") return "That name is reserved (built-in)."
        if (code === "invalid")  return "Use a simple name (no /, \\ or leading dot)."
        return ""
    }
```

- [ ] **Step 2: Rewrite the `pinnedHeader` Component**

Replace the entire `property Component pinnedHeader: Component { ... }` from Task 3 with:

```qml
    property Component pinnedHeader: Component {
        ColumnLayout {
            spacing: 6

            Text {
                text: "Theme preset"
                color: Theme.accent
                font.pointSize: Theme.fontSmall
                font.bold: true
                Layout.topMargin: 2
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Repeater {
                    model: colorsRoot.allSwatches
                    delegate: ColumnLayout {
                        id: swatch
                        required property var modelData
                        readonly property bool active: config.theme === swatch.modelData.name
                        spacing: 4

                        Rectangle {
                            id: swatchTile
                            Layout.alignment: Qt.AlignHCenter
                            width: 46
                            height: 46
                            radius: Theme.radiusMedium
                            color: Theme.panel
                            border.width: swatch.active ? 2 : 1
                            border.color: swatch.active
                                ? Theme.gold
                                : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, swatchHover.hovered ? 0.40 : 0.18)

                            Rectangle {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                radius: 13
                                color: swatch.modelData.accent
                            }

                            // Delete badge — custom presets only, on hover.
                            Rectangle {
                                visible: swatch.modelData.deletable && swatchHover.hovered
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: -4
                                anchors.rightMargin: -4
                                width: 16
                                height: 16
                                radius: 8
                                color: Theme.error
                                border.width: 1
                                border.color: Theme.panel
                                z: 2
                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    color: Theme.knob
                                    font.pointSize: Theme.fontSmall
                                }
                                TapHandler { onTapped: colorsRoot.deletePreset(swatch.modelData.name) }
                            }

                            HoverHandler { id: swatchHover }
                            TapHandler { onTapped: colorsRoot.selectPreset(swatch.modelData.name) }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: 56
                            text: swatch.modelData.label
                            color: swatch.active ? Theme.accent : Theme.subtext
                            font.pointSize: Theme.fontSmall
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                // "+" save tile.
                ColumnLayout {
                    spacing: 4
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 46
                        height: 46
                        radius: Theme.radiusMedium
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, saveHover.hovered ? 0.40 : 0.18)
                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            color: Theme.subtext
                            font.pointSize: Theme.fontLarge + 4
                        }
                        HoverHandler { id: saveHover }
                        TapHandler { onTapped: colorsRoot.beginSave() }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Save"
                        color: Theme.subtext
                        font.pointSize: Theme.fontSmall
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // Inline name field (shown after pressing +).
            RowLayout {
                Layout.fillWidth: true
                visible: colorsRoot.naming
                spacing: 8

                Q.TextField {
                    id: nameField
                    Layout.preferredWidth: 180
                    placeholder: "Preset name"
                    onTextEdited: { colorsRoot.nameError = ""; colorsRoot.confirmingOverwrite = false }
                    onAccepted: colorsRoot.attemptSave(nameField.text)
                }
                Q.Button {
                    text: colorsRoot.confirmingOverwrite ? "Overwrite" : "Save"
                    onClicked: colorsRoot.attemptSave(nameField.text)
                }
                Q.Button {
                    text: "Cancel"
                    variant: "ghost"
                    onClicked: { colorsRoot.cancelSave(); nameField.text = "" }
                }
                Item { Layout.fillWidth: true }
            }

            Text {
                Layout.fillWidth: true
                visible: colorsRoot.naming && (colorsRoot.nameError !== "" || colorsRoot.confirmingOverwrite)
                wrapMode: Text.WordWrap
                text: colorsRoot.nameError !== ""
                      ? colorsRoot.nameErrorText(colorsRoot.nameError)
                      : "A preset with that name exists — Overwrite to replace it."
                color: Theme.warning
                font.pointSize: Theme.fontSmall
            }

            Q.Separator { Layout.topMargin: 4 }
        }
    }
```

- [ ] **Step 3: Build + smoke**

Run: `cmake --build build 2>&1 | tail -3 && ctest --test-dir build -R tst_qml_smoke --output-on-failure 2>&1 | tail -8`
Expected: clean build; smoke PASSES (the picker Component instantiates with the new model/handlers; no missing-id / missing-property errors). If smoke reports `Q.Button`/`Q.TextField`/`Q.Separator` issues, confirm the file already imports `Quill as Q` (it does) — those components are used elsewhere in this file.

- [ ] **Step 4: Full suite**

Run: `ctest --test-dir build --output-on-failure 2>&1 | tail -5`
Expected: 24/24 pass.

- [ ] **Step 5: Commit**

```bash
git add src/qml/components/SettingsSectionColors.qml
git commit -m "feat(settings): save/delete named custom theme presets as swatches"
```

---

## Task 5: Final integration verification

**Files:** none (verification only)

- [ ] **Step 1: Clean build + full suite**

Run: `cmake --build build --clean-first 2>&1 | tail -3 && ctest --test-dir build --output-on-failure 2>&1 | tail -6`
Expected: clean build; 24/24 pass.

- [ ] **Step 2: User GUI verification (Wayland)** — deferred to the user's evening check

Run `./build/src/wayfile` → Settings → Colours:
- The preset row (Theme preset header + swatches + Save) stays **pinned** while the token editor below scrolls.
- Edit a few tokens → press **+** → type a name → **Save** → a new swatch appears, becomes active, and the token editor stays put.
- **Restart** → the saved preset persists and loads.
- Hover a custom swatch → **×** deletes it (built-in 5 have no ×); deleting the active one falls back to Bifröst.
- Try saving a reserved name (e.g. `bifrost`) → inline "reserved" notice, no save. Save a name that already exists → "Overwrite?" → Overwrite replaces it.
- Built-in swatches still switch/retint live (W2 behavior intact).

- [ ] **Step 3: Update memory** — mark the feature code-complete (pending the GUI check), then proceed to W3 per the autonomous run order.

---

## Self-review notes

- **Spec coverage:** user themes dir + full-palette save (T1 `userThemePath`/`themeNameError`, T4 `theme.saveThemeFile`) ✓; `ConfigManager` resolver + list + delete + name validation (T1) ✓; `main.cpp` uses resolver (T2) ✓; pinned picker (T3) ✓; extra deletable swatches + `+` save + inline name + overwrite-confirm + built-ins protected (T4) ✓; active = swatch highlight only (T3/T4 `active` binding) ✓; delete active → Bifröst (T4 `deletePreset`) ✓; reserved-name rejection (T1 `isReservedThemeName` via install-dir scan + `custom`) ✓.
- **Simplification vs spec:** the spec mentioned a `userThemesChanged` signal; the plan instead refreshes `userPresets` imperatively after save/delete (`refreshUserPresets()`), which is simpler and sufficient (the picker is the only writer). The spec floated `managesOwnScroll`; the plan uses the cleaner **`pinnedHeader` Component slot** (the design message's described mechanism) — picker and token editor stay one component, sharing state via the Component's creation context.
- **Type/name consistency:** `themePath`/`userThemePath`/`themeNameError`/`userThemeExists`/`deleteUserTheme`/`userThemes`/`userThemesDir` names match across T1 (decl + impl + tests), T2 (main.cpp `themePath`), and T4 (QML calls). The QML helpers `selectPreset/beginSave/cancelSave/attemptSave/deletePreset/refreshUserPresets/nameErrorText` and state `naming/nameError/confirmingOverwrite/userPresets/allSwatches/builtinSwatches` are defined in T4 Step 1 and used in T4 Step 2.
- **Out of scope:** tabs/W4, rename-in-place, import/export, per-preset file-type/git colours.
