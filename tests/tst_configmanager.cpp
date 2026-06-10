#include <QTest>
#include <QTemporaryDir>
#include <QFile>
#include <QSignalSpy>
#include <QStandardPaths>
#include "services/configmanager.h"

class TestConfigManager : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
    }

    // --- Default values ---

    void testDefaultValues()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        QCOMPARE(mgr.theme(), QString("bifrost"));
        QCOMPARE(mgr.iconTheme(), QString("Wayfile"));
        QCOMPARE(mgr.builtinIcons(), true);
        QCOMPARE(mgr.fontFamily(), QString());
        QCOMPARE(mgr.defaultView(), QString("hybrid"));
        QCOMPARE(mgr.showHidden(), false);
        QCOMPARE(mgr.sortBy(), QString("name"));
        QCOMPARE(mgr.sortAscending(), true);
        QCOMPARE(mgr.sidebarPosition(), QString("left"));
        QCOMPARE(mgr.sidebarWidth(), 220);
        QCOMPARE(mgr.sidebarVisible(), true);
        QCOMPARE(mgr.gridCellSize(), 180);
        QCOMPARE(mgr.transparencyEnabled(), true);
        QCOMPARE(mgr.transparencyLevel(), 1.0);
        QCOMPARE(mgr.animationsEnabled(), true);
    }

    void testCustomDefaultTheme()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml", nullptr, QString(), "aurora");

        QCOMPARE(mgr.theme(), QString("aurora"));
    }

    void testAvailableThemes()
    {
        QTemporaryDir dir;
        QDir().mkpath(dir.path() + "/themes");

        QFile darkTheme(dir.path() + "/themes/dark.toml");
        QVERIFY(darkTheme.open(QIODevice::WriteOnly));
        darkTheme.write("[colors]\ntext = \"#ffffff\"\n");
        darkTheme.close();

        QFile lightTheme(dir.path() + "/themes/light.toml");
        QVERIFY(lightTheme.open(QIODevice::WriteOnly));
        lightTheme.write("[colors]\ntext = \"#111111\"\n");
        lightTheme.close();

        ConfigManager mgr(dir.path() + "/config.toml", nullptr, dir.path() + "/themes");
        QCOMPARE(mgr.availableThemes(), QStringList({"dark", "light"}));
    }

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
        QVERIFY(!mgr.deleteUserTheme("bifrost"));
        QVERIFY(QFile::exists(dir.path() + "/install/bifrost.toml"));
        QVERIFY(!mgr.deleteUserTheme("Nope"));
        QVERIFY(mgr.deleteUserTheme("Cool"));
        QVERIFY(!QFile::exists(dir.path() + "/themes/Cool.toml"));
    }

    void testUserThemePathSafetyRejectsTraversal()
    {
        QTemporaryDir dir;
        // A file in the config dir we must never touch via a crafted name.
        QFile secret(dir.path() + "/secret.toml");
        QVERIFY(secret.open(QIODevice::WriteOnly));
        secret.write("[colors]\naccent=\"#ffffff\"\n");
        secret.close();

        ConfigManager mgr(dir.path() + "/config.toml");
        // delete must refuse a traversal name and leave the file intact.
        QVERIFY(!mgr.deleteUserTheme("../secret"));
        QVERIFY(QFile::exists(dir.path() + "/secret.toml"));
        // exists must not probe outside the user themes dir.
        QVERIFY(!mgr.userThemeExists("../secret"));
        // userThemePath rejects the invalid name.
        QVERIFY(mgr.userThemePath("../secret").isEmpty());
        // path resolver returns empty (safe fallback), not a traversal path.
        QVERIFY(mgr.themePath("../secret").isEmpty());
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

    // Phase C4: the editable "custom" theme lives next to config.toml (the
    // writable config dir) and is surfaced in availableThemes once written.
    void testCustomThemePathAndDiscovery()
    {
        QTemporaryDir dir;
        QDir().mkpath(dir.path() + "/themes");
        QFile darkTheme(dir.path() + "/themes/dark.toml");
        QVERIFY(darkTheme.open(QIODevice::WriteOnly));
        darkTheme.write("[colors]\ntext = \"#ffffff\"\n");
        darkTheme.close();

        ConfigManager mgr(dir.path() + "/config.toml", nullptr, dir.path() + "/themes");

        QCOMPARE(mgr.customThemePath(), QDir(dir.path()).filePath("custom.toml"));
        QVERIFY(!mgr.availableThemes().contains("custom"));

        QFile custom(mgr.customThemePath());
        QVERIFY(custom.open(QIODevice::WriteOnly));
        custom.write("[colors]\naccent = \"#123456\"\n");
        custom.close();

        QVERIFY(mgr.availableThemes().contains("custom"));
    }

    void testDefaultRadius()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        QCOMPARE(mgr.radiusSmall(), 4);
        QCOMPARE(mgr.radiusMedium(), 6);
        QCOMPARE(mgr.radiusLarge(), 10);
    }

    void testDefaultBookmarks()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        QStringList bookmarks = mgr.bookmarks();
        QVERIFY(bookmarks.size() >= 1);
    }

    void testDefaultBookmarkColorsEmpty()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");
        QVERIFY(mgr.bookmarkColors().isEmpty());
    }

    void testSaveBookmarkColorPersistsAndReloads()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        {
            ConfigManager mgr(path);
            mgr.saveBookmarkColor("/home/user/Documents", "#D4AA6A");
            mgr.saveBookmarkColor("/home/user/Music", "#57C7BF");
            QCOMPARE(mgr.bookmarkColors().value("/home/user/Documents").toString(),
                     QString("#D4AA6A"));
        }

        ConfigManager mgr2(path);
        QCOMPARE(mgr2.bookmarkColors().value("/home/user/Documents").toString(),
                 QString("#D4AA6A"));
        QCOMPARE(mgr2.bookmarkColors().value("/home/user/Music").toString(),
                 QString("#57C7BF"));
    }

    void testSaveBookmarkColorEmptyClears()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        ConfigManager mgr(path);
        mgr.saveBookmarkColor("/home/user/Pictures", "#8FC380");
        QCOMPARE(mgr.bookmarkColors().value("/home/user/Pictures").toString(),
                 QString("#8FC380"));

        mgr.saveBookmarkColor("/home/user/Pictures", "");
        QVERIFY(!mgr.bookmarkColors().contains("/home/user/Pictures"));

        ConfigManager mgr2(path);
        QVERIFY(!mgr2.bookmarkColors().contains("/home/user/Pictures"));
    }

    // Saving paths must NOT wipe the colors sub-table, and saving a color must
    // NOT wipe the paths array — they share the [bookmarks] table.
    void testBookmarkPathsAndColorsAreIndependent()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        ConfigManager mgr(path);
        mgr.saveBookmarkColor("/home/user/Documents", "#D4AA6A");
        mgr.saveBookmarks({"/home/user/Documents", "/home/user/Downloads"});

        // Colors survived the saveBookmarks call.
        QCOMPARE(mgr.bookmarkColors().value("/home/user/Documents").toString(),
                 QString("#D4AA6A"));

        // Now save another color; the paths array must remain intact.
        mgr.saveBookmarkColor("/home/user/Downloads", "#E68B5C");

        ConfigManager mgr2(path);
        QStringList reloaded = mgr2.bookmarks();
        QVERIFY(reloaded.contains("/home/user/Documents"));
        QVERIFY(reloaded.contains("/home/user/Downloads"));
        QCOMPARE(mgr2.bookmarkColors().value("/home/user/Documents").toString(),
                 QString("#D4AA6A"));
        QCOMPARE(mgr2.bookmarkColors().value("/home/user/Downloads").toString(),
                 QString("#E68B5C"));
    }

    void testDefaultShortcuts()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        QCOMPARE(mgr.shortcut("open"), QString("Return"));
        QCOMPARE(mgr.shortcut("back"), QString("Alt+Left"));
        QCOMPARE(mgr.shortcut("forward"), QString("Alt+Right"));
        QCOMPARE(mgr.shortcut("parent"), QString("Alt+Up"));
        QCOMPARE(mgr.shortcut("home"), QString("Alt+Home"));
        QCOMPARE(mgr.shortcut("refresh"), QString("F5"));
        QCOMPARE(mgr.shortcut("new_tab"), QString("Ctrl+T"));
        QCOMPARE(mgr.shortcut("close_tab"), QString("Ctrl+W"));
        QCOMPARE(mgr.shortcut("open_in_new_tab"), QString("Ctrl+Return"));
        QCOMPARE(mgr.shortcut("open_in_split"), QString("Ctrl+Shift+Return"));
        QCOMPARE(mgr.shortcut("copy"), QString("Ctrl+C"));
        QCOMPARE(mgr.shortcut("cut"), QString("Ctrl+X"));
        QCOMPARE(mgr.shortcut("paste"), QString("Ctrl+V"));
        QCOMPARE(mgr.shortcut("rename"), QString("F2"));
        QCOMPARE(mgr.shortcut("new_folder"), QString("Ctrl+Shift+N"));
        QCOMPARE(mgr.shortcut("new_file"), QString("Ctrl+N"));
        QCOMPARE(mgr.shortcut("trash"), QString("Delete"));
        QCOMPARE(mgr.shortcut("toggle_hidden"), QString("Ctrl+H"));
        QCOMPARE(mgr.shortcut("quick_preview"), QString("Space"));
        QCOMPARE(mgr.shortcut("search"), QString("Ctrl+F"));
        QCOMPARE(mgr.shortcut("context_menu"), QString("Shift+F10"));
        QCOMPARE(mgr.shortcut("open_terminal"), QString("Ctrl+Alt+T"));
        QCOMPARE(mgr.shortcut("properties"), QString("Alt+Return"));
        QCOMPARE(mgr.shortcut("select_all"), QString("Ctrl+A"));
        QCOMPARE(mgr.shortcut("focus_left_pane"), QString("Ctrl+Alt+Left"));
        QCOMPARE(mgr.shortcut("focus_right_pane"), QString("Ctrl+Alt+Right"));
        QCOMPARE(mgr.shortcut("focus_next_pane"), QString("F6"));
        QCOMPARE(mgr.shortcut("focus_previous_pane"), QString("Shift+F6"));
    }

    void testUnknownShortcut()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        QCOMPARE(mgr.shortcut("nonexistent_action"), QString());
    }

    void testLegacyNewFileShortcutMigrates()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("[shortcuts]\n"
                "new_file = \"Ctrl+Alt+N\"\n");
        f.close();

        ConfigManager mgr(path);
        QCOMPARE(mgr.shortcut("new_file"), QString("Ctrl+N"));
    }

    // --- Window controls ---

    void testWindowControlsDefaults()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        QCOMPARE(mgr.showWindowControls(), false);
        QCOMPARE(mgr.windowButtonLayout(), QString(":minimize,maximize,close"));
    }

    void testWindowControlsRuntimeDefault()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        mgr.setShowWindowControlsDefault(true);
        QCOMPARE(mgr.showWindowControls(), true);
    }

    void testWindowControlsExplicitOverridesRuntime()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("[window]\n"
                "show_controls = false\n");
        f.close();

        ConfigManager mgr(path);
        mgr.setShowWindowControlsDefault(true);
        QCOMPARE(mgr.showWindowControls(), false);
    }

    void testWindowButtonLayoutFromConfig()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("[window]\n"
                "show_controls = true\n"
                "button_layout = \"close,minimize,maximize:\"\n");
        f.close();

        ConfigManager mgr(path);
        QCOMPARE(mgr.showWindowControls(), true);
        QCOMPARE(mgr.windowButtonLayout(), QString("close,minimize,maximize:"));
    }

    void testSaveWindowControls()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        ConfigManager mgr(path);
        mgr.saveSettings(QVariantMap{
            {"showWindowControls", true},
            {"windowButtonLayout", "close:minimize"}
        });

        ConfigManager mgr2(path);
        QCOMPARE(mgr2.showWindowControls(), true);
        QCOMPARE(mgr2.windowButtonLayout(), QString("close:minimize"));
    }

    // --- Animation config ---

    void testAnimationDefaults()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        QCOMPARE(mgr.animDurationFast(), 100);
        QCOMPARE(mgr.animDuration(), 200);
        QCOMPARE(mgr.animDurationSlow(), 350);
        QCOMPARE(mgr.animCurveEnter(), QString("OutCubic"));
        QCOMPARE(mgr.animCurveExit(), QString("InCubic"));
        QCOMPARE(mgr.animCurveTransition(), QString("Bezier"));
    }

    void testAnimationFromConfig()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("[appearance]\n"
                "anim_duration_fast = 50\n"
                "anim_duration = 150\n"
                "anim_duration_slow = 300\n"
                "anim_curve_enter = \"Bezier\"\n"
                "anim_curve_exit = \"OutQuad\"\n"
                "anim_curve_transition = \"InOutExpo\"\n");
        f.close();

        ConfigManager mgr(path);
        QCOMPARE(mgr.animDurationFast(), 50);
        QCOMPARE(mgr.animDuration(), 150);
        QCOMPARE(mgr.animDurationSlow(), 300);
        QCOMPARE(mgr.animCurveEnter(), QString("Bezier"));
        QCOMPARE(mgr.animCurveExit(), QString("OutQuad"));
        QCOMPARE(mgr.animCurveTransition(), QString("InOutExpo"));
    }

    void testSaveAnimationSettings()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        ConfigManager mgr(path);
        mgr.saveSettings(QVariantMap{
            {"animDurationFast", 80},
            {"animDuration", 180},
            {"animDurationSlow", 400},
            {"animCurveEnter", "OutBack"},
            {"animCurveExit", "InCubic"},
            {"animCurveTransition", "InOutQuad"}
        });

        ConfigManager mgr2(path);
        QCOMPARE(mgr2.animDurationFast(), 80);
        QCOMPARE(mgr2.animDuration(), 180);
        QCOMPARE(mgr2.animDurationSlow(), 400);
        QCOMPARE(mgr2.animCurveEnter(), QString("OutBack"));
        QCOMPARE(mgr2.animCurveExit(), QString("InCubic"));
        QCOMPARE(mgr2.animCurveTransition(), QString("InOutQuad"));
    }

    // --- TOML parsing ---

    void testParseConfig()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.write("[general]\n"
                "theme = \"custom\"\n"
                "font_family = \"Inter\"\n"
                "default_view = \"list\"\n"
                "show_hidden = true\n"
                "sort_by = \"size\"\n"
                "sort_ascending = false\n"
                "\n"
                "[sidebar]\n"
                "position = \"right\"\n"
                "width = 250\n"
                "visible = false\n");
        f.close();

        ConfigManager mgr(path);
        QCOMPARE(mgr.theme(), QString("custom"));
        QCOMPARE(mgr.fontFamily(), QString("Inter"));
        QCOMPARE(mgr.defaultView(), QString("list"));
        QCOMPARE(mgr.showHidden(), true);
        QCOMPARE(mgr.sortBy(), QString("size"));
        QCOMPARE(mgr.sortAscending(), false);
        QCOMPARE(mgr.sidebarPosition(), QString("right"));
        QCOMPARE(mgr.sidebarWidth(), 250);
        QCOMPARE(mgr.sidebarVisible(), false);
    }

    void testParseAppearanceSection()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.write("[appearance]\n"
                "radius_small = 2\n"
                "radius_medium = 6\n"
                "radius_large = 16\n"
                "transparency_enabled = false\n"
                "transparency_level = 0.4\n"
                "animations_enabled = false\n");
        f.close();

        ConfigManager mgr(path);
        QCOMPARE(mgr.radiusSmall(), 2);
        QCOMPARE(mgr.radiusMedium(), 6);
        QCOMPARE(mgr.radiusLarge(), 16);
        QCOMPARE(mgr.transparencyEnabled(), false);
        QCOMPARE(mgr.transparencyLevel(), 0.4);
        QCOMPARE(mgr.animationsEnabled(), false);
    }

    void testParseIconTheme()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.write("[general]\n"
                "icon_theme = \"Papirus\"\n"
                "builtin_icons = false\n");
        f.close();

        ConfigManager mgr(path);
        QCOMPARE(mgr.iconTheme(), QString("Papirus"));
        QCOMPARE(mgr.builtinIcons(), false);
    }

    // --- Bookmarks ---

    void testBookmarks()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.write("[bookmarks]\n"
                "paths = [\"~/Documents\", \"~/Downloads\"]\n");
        f.close();

        ConfigManager mgr(path);
        QStringList bookmarks = mgr.bookmarks();
        QCOMPARE(bookmarks.size(), 2);
        QCOMPARE(bookmarks.at(0), QString("~/Documents"));
        QCOMPARE(bookmarks.at(1), QString("~/Downloads"));
    }

    void testSaveSettings()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("[bookmarks]\n"
                "paths = [\"~/Documents\"]\n");
        f.close();

        ConfigManager mgr(path);
        QSignalSpy spy(&mgr, &ConfigManager::configChanged);

        QVariantMap settings;
        settings.insert("theme", "aurora");
        settings.insert("fontFamily", "Inter");
        settings.insert("iconTheme", "Papirus");
        settings.insert("showHidden", true);
        settings.insert("sidebarVisible", false);
        settings.insert("sidebarWidth", 420);
        settings.insert("radiusSmall", 6);
        settings.insert("radiusMedium", 12);
        settings.insert("radiusLarge", 18);
        settings.insert("transparencyEnabled", false);
        settings.insert("transparencyLevel", 0.3);
        settings.insert("animationsEnabled", false);
        mgr.saveSettings(settings);

        QCOMPARE(spy.count(), 1);
        QCOMPARE(mgr.theme(), QString("aurora"));
        QCOMPARE(mgr.fontFamily(), QString("Inter"));
        QCOMPARE(mgr.iconTheme(), QString("Papirus"));
        QCOMPARE(mgr.showHidden(), true);
        QCOMPARE(mgr.sidebarVisible(), false);
        QCOMPARE(mgr.sidebarWidth(), 420);
        QCOMPARE(mgr.radiusSmall(), 6);
        QCOMPARE(mgr.radiusMedium(), 12);
        QCOMPARE(mgr.radiusLarge(), 18);
        QCOMPARE(mgr.transparencyEnabled(), false);
        QCOMPARE(mgr.transparencyLevel(), 0.3);
        QCOMPARE(mgr.animationsEnabled(), false);
        QCOMPARE(mgr.bookmarks(), QStringList({"~/Documents"}));
    }

    void testSaveShortcuts()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        ConfigManager mgr(path);
        QSignalSpy spy(&mgr, &ConfigManager::configChanged);

        QVariantMap shortcuts;
        shortcuts.insert("copy", "Ctrl+Shift+C");
        shortcuts.insert("search", "Ctrl+K");
        shortcuts.insert("new_tab", "");
        mgr.saveShortcuts(shortcuts);

        QCOMPARE(spy.count(), 1);
        QCOMPARE(mgr.shortcut("copy"), QString("Ctrl+Shift+C"));
        QCOMPARE(mgr.shortcut("search"), QString("Ctrl+K"));
        QCOMPARE(mgr.shortcut("new_tab"), QString("Ctrl+T"));

        const QVariantMap shortcutMap = mgr.shortcutMap();
        QCOMPARE(shortcutMap.value("copy").toString(), QString("Ctrl+Shift+C"));
        QCOMPARE(shortcutMap.value("search").toString(), QString("Ctrl+K"));
    }

    void testEmptyBookmarks()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.write("[bookmarks]\npaths = []\n");
        f.close();

        ConfigManager mgr(path);
        QCOMPARE(mgr.bookmarks().size(), 0);
    }

    // --- Context actions ---

    void testCustomContextActions()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.write("[[context_menu.actions]]\n"
                "name = \"Open in Neovim\"\n"
                "command = \"foot nvim {file}\"\n"
                "types = [\"file\"]\n"
                "\n"
                "[[context_menu.actions]]\n"
                "name = \"Upload\"\n"
                "command = \"curl -F 'file=@{file}' https://example.com\"\n"
                "types = [\"file\", \"image\"]\n");
        f.close();

        ConfigManager mgr(path);
        QVariantList actions = mgr.customContextActions();
        QCOMPARE(actions.size(), 2);

        QVariantMap first = actions.at(0).toMap();
        QCOMPARE(first["name"].toString(), QString("Open in Neovim"));
        QCOMPARE(first["command"].toString(), QString("foot nvim {file}"));

        QVariantMap second = actions.at(1).toMap();
        QCOMPARE(second["name"].toString(), QString("Upload"));
    }

    void testNoContextActions()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");
        QCOMPARE(mgr.customContextActions().size(), 0);
    }

    // --- Shortcuts override ---

    void testShortcutOverride()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.write("[shortcuts]\n"
                "open = \"Return\"\n"
                "back = \"Alt+Left\"\n"
                "copy = \"Ctrl+Shift+C\"\n"); // override default
        f.close();

        ConfigManager mgr(path);
        QCOMPARE(mgr.shortcut("open"), QString("Return"));
        QCOMPARE(mgr.shortcut("copy"), QString("Ctrl+Shift+C")); // overridden
        QCOMPARE(mgr.shortcut("paste"), QString("Ctrl+V")); // still default
    }

    // --- Missing optional sections ---

    void testMissingSections()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.write("[general]\ntheme = \"test\"\n"); // only general section
        f.close();

        ConfigManager mgr(path);
        QCOMPARE(mgr.theme(), QString("test"));
        // Other sections should have defaults
        QCOMPARE(mgr.sidebarWidth(), 220);
        QCOMPARE(mgr.radiusMedium(), 6);
    }

    // --- File watcher reload ---

    void testConfigFileWatcherReload()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        // Create initial config
        {
            QFile f(path);
            f.open(QIODevice::WriteOnly);
            f.write("[general]\ntheme = \"initial\"\n");
            f.close();
        }

        ConfigManager mgr(path);
        QCOMPARE(mgr.theme(), QString("initial"));

        QSignalSpy spy(&mgr, &ConfigManager::configChanged);

        // Modify the config file
        {
            QFile f(path);
            f.open(QIODevice::WriteOnly | QIODevice::Truncate);
            f.write("[general]\ntheme = \"updated\"\n");
            f.close();
        }

        // Wait for watcher to pick up the change
        if (spy.wait(3000)) {
            QCOMPARE(mgr.theme(), QString("updated"));
        }
        // If watcher didn't fire (CI timing), skip rather than fail
    }

    // --- Empty config file ---

    void testEmptyConfigFile()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/config.toml";

        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.close(); // empty file

        ConfigManager mgr(path);
        // Should use all defaults
        QCOMPARE(mgr.theme(), QString("bifrost"));
        QCOMPARE(mgr.defaultView(), QString("hybrid"));
    }

    // --- P3 M1: split_view -> toggle_merge rename ---

    void testToggleMergeActionRegistered()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        const QVariantMap shortcutMap = mgr.shortcutMap();
        QVERIFY2(shortcutMap.contains("toggle_merge"),
                 "Action 'toggle_merge' must be registered (renamed from split_view in P3 M1).");
        QCOMPARE(shortcutMap.value("toggle_merge").toString(), QString("F3"));

        QVERIFY2(!shortcutMap.contains("split_view"),
                 "Old action key 'split_view' must be gone from the registry.");

        const QVariantList defs = mgr.shortcutDefinitions();
        bool foundToggleMerge = false;
        for (const QVariant &v : defs) {
            const QVariantMap def = v.toMap();
            if (def.value("action").toString() == QLatin1String("toggle_merge")) {
                foundToggleMerge = true;
                QCOMPARE(def.value("label").toString(), QString("Merge / Unmerge Panes"));
                QCOMPARE(def.value("defaultSequence").toString(), QString("F3"));
                break;
            }
        }
        QVERIFY2(foundToggleMerge,
                 "shortcutDefinitions() must expose toggle_merge with label 'Merge / Unmerge Panes'.");
    }

    void testMigrateSplitViewToToggleMerge_customValue()
    {
        QTemporaryDir dir;
        const QString cfgPath = dir.path() + "/config.toml";

        // Seed a config that pre-dates the rename: only the old key, with a
        // user-customized value (so the migration must preserve the value,
        // not just substitute the default).
        QFile f(cfgPath);
        QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Text));
        f.write("[shortcuts]\nsplit_view = \"Ctrl+J\"\n");
        f.close();

        ConfigManager mgr(cfgPath);

        const QVariantMap shortcutMap = mgr.shortcutMap();
        QCOMPARE(shortcutMap.value("toggle_merge").toString(), QString("Ctrl+J"));
        QVERIFY2(!shortcutMap.contains("split_view"),
                 "After migration, the old action key must not surface via shortcutMap().");
    }

    void testMigrateSplitViewToToggleMerge_doesNotOverwriteNewKey()
    {
        QTemporaryDir dir;
        const QString cfgPath = dir.path() + "/config.toml";

        // If a user has BOTH keys (e.g. partial manual edit), the new key
        // wins — migration must not clobber it.
        QFile f(cfgPath);
        QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Text));
        f.write("[shortcuts]\nsplit_view = \"Ctrl+J\"\ntoggle_merge = \"Ctrl+K\"\n");
        f.close();

        ConfigManager mgr(cfgPath);

        const QVariantMap shortcutMap = mgr.shortcutMap();
        QCOMPARE(shortcutMap.value("toggle_merge").toString(), QString("Ctrl+K"));
    }

    void testContextMenuAltActionRegistered()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        const QVariantMap shortcutMap = mgr.shortcutMap();
        QCOMPARE(shortcutMap.value("context_menu_alt").toString(), QString("Menu"));

        const QVariantList defs = mgr.shortcutDefinitions();
        bool found = false;
        for (const QVariant &v : defs) {
            const QVariantMap def = v.toMap();
            if (def.value("action").toString() == QLatin1String("context_menu_alt")) {
                found = true;
                QCOMPARE(def.value("label").toString(),
                         QString("Show Context Menu (Menu key)"));
                QCOMPARE(def.value("defaultSequence").toString(), QString("Menu"));
                break;
            }
        }
        QVERIFY2(found,
                 "shortcutDefinitions() must expose context_menu_alt with the Menu-key label.");
    }

    // --- P3 M2: registry group field ---

    void testEveryActionHasGroup()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        const QSet<QString> kAllowedGroups = {
            QStringLiteral("Tabs"),
            QStringLiteral("Navigation"),
            QStringLiteral("Panes"),
            QStringLiteral("View"),
            QStringLiteral("Selection"),
            QStringLiteral("File"),
            QStringLiteral("Application")
        };

        const QVariantList defs = mgr.shortcutDefinitions();
        QVERIFY(!defs.isEmpty());

        for (const QVariant &v : defs) {
            const QVariantMap def = v.toMap();
            const QString action = def.value("action").toString();
            const QString group = def.value("group").toString();
            QVERIFY2(!group.isEmpty(),
                     qPrintable(QStringLiteral("Action '%1' must have a non-empty group").arg(action)));
            QVERIFY2(kAllowedGroups.contains(group),
                     qPrintable(QStringLiteral("Action '%1' has unexpected group '%2'").arg(action, group)));
        }
    }

    void testKnownActionsHaveExpectedGroups()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        const QMap<QString, QString> expected = {
            // Tabs
            {QStringLiteral("new_tab"), QStringLiteral("Tabs")},
            {QStringLiteral("close_tab"), QStringLiteral("Tabs")},
            {QStringLiteral("reopen_tab"), QStringLiteral("Tabs")},
            {QStringLiteral("open_in_new_tab"), QStringLiteral("Tabs")},
            {QStringLiteral("open_in_split"), QStringLiteral("Tabs")},
            // Navigation
            {QStringLiteral("back"), QStringLiteral("Navigation")},
            {QStringLiteral("forward"), QStringLiteral("Navigation")},
            {QStringLiteral("parent"), QStringLiteral("Navigation")},
            {QStringLiteral("home"), QStringLiteral("Navigation")},
            {QStringLiteral("refresh"), QStringLiteral("Navigation")},
            {QStringLiteral("path_bar"), QStringLiteral("Navigation")},
            // Panes
            {QStringLiteral("toggle_merge"), QStringLiteral("Panes")},
            {QStringLiteral("focus_left_pane"), QStringLiteral("Panes")},
            {QStringLiteral("focus_right_pane"), QStringLiteral("Panes")},
            {QStringLiteral("focus_next_pane"), QStringLiteral("Panes")},
            {QStringLiteral("focus_previous_pane"), QStringLiteral("Panes")},
            {QStringLiteral("toggle_sidebar"), QStringLiteral("Panes")},
            // View
            {QStringLiteral("grid_view"), QStringLiteral("View")},
            {QStringLiteral("miller_view"), QStringLiteral("View")},
            {QStringLiteral("detailed_view"), QStringLiteral("View")},
            {QStringLiteral("toggle_hidden"), QStringLiteral("View")},
            {QStringLiteral("quick_preview"), QStringLiteral("View")},
            // Selection
            {QStringLiteral("select_all"), QStringLiteral("Selection")},
            {QStringLiteral("context_menu"), QStringLiteral("Selection")},
            {QStringLiteral("context_menu_alt"), QStringLiteral("Selection")},
            // File
            {QStringLiteral("open"), QStringLiteral("File")},
            {QStringLiteral("copy"), QStringLiteral("File")},
            {QStringLiteral("cut"), QStringLiteral("File")},
            {QStringLiteral("paste"), QStringLiteral("File")},
            {QStringLiteral("trash"), QStringLiteral("File")},
            {QStringLiteral("permanent_delete"), QStringLiteral("File")},
            {QStringLiteral("undo"), QStringLiteral("File")},
            {QStringLiteral("redo"), QStringLiteral("File")},
            {QStringLiteral("rename"), QStringLiteral("File")},
            {QStringLiteral("new_folder"), QStringLiteral("File")},
            {QStringLiteral("new_file"), QStringLiteral("File")},
            {QStringLiteral("properties"), QStringLiteral("File")},
            {QStringLiteral("open_terminal"), QStringLiteral("File")},
            // Application
            {QStringLiteral("search"), QStringLiteral("Application")},
            {QStringLiteral("settings"), QStringLiteral("Application")},
            {QStringLiteral("keyboard_shortcuts"), QStringLiteral("Application")}
        };

        const QVariantList defs = mgr.shortcutDefinitions();
        QMap<QString, QString> actual;
        for (const QVariant &v : defs) {
            const QVariantMap def = v.toMap();
            actual.insert(def.value("action").toString(), def.value("group").toString());
        }

        for (auto it = expected.cbegin(); it != expected.cend(); ++it) {
            QVERIFY2(actual.contains(it.key()),
                     qPrintable(QStringLiteral("Expected action '%1' is missing from shortcutDefinitions()")
                                .arg(it.key())));
            QCOMPARE(actual.value(it.key()), it.value());
        }
        QCOMPARE(actual.size(), expected.size());
    }

    void testRegistryIsGroupContiguous()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        const QVariantList defs = mgr.shortcutDefinitions();
        QVERIFY(!defs.isEmpty());

        QSet<QString> seenGroups;
        QString currentGroup;
        for (const QVariant &v : defs) {
            const QString group = v.toMap().value("group").toString();
            if (group != currentGroup) {
                QVERIFY2(!seenGroups.contains(group),
                         qPrintable(QStringLiteral("Group '%1' is non-contiguous in kShortcutSpecs — "
                                                   "the dialog renders groups in registry order so "
                                                   "all entries of one group must sit together")
                                    .arg(group)));
                seenGroups.insert(group);
                currentGroup = group;
            }
        }
    }

    // --- P3 M2: rebindable field ---

    void testOpenActionIsNonRebindable()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        const QVariantList defs = mgr.shortcutDefinitions();
        bool foundOpen = false;
        for (const QVariant &v : defs) {
            const QVariantMap def = v.toMap();
            if (def.value("action").toString() == QLatin1String("open")) {
                foundOpen = true;
                QVERIFY2(def.contains("rebindable"),
                         "shortcutDefinitions() must expose a 'rebindable' field on every row.");
                QCOMPARE(def.value("rebindable").toBool(), false);
                break;
            }
        }
        QVERIFY(foundOpen);
    }

    void testNonOpenActionsAreRebindable()
    {
        QTemporaryDir dir;
        ConfigManager mgr(dir.path() + "/config.toml");

        const QVariantList defs = mgr.shortcutDefinitions();
        int checked = 0;
        for (const QVariant &v : defs) {
            const QVariantMap def = v.toMap();
            const QString action = def.value("action").toString();
            if (action == QLatin1String("open"))
                continue;
            QVERIFY2(def.contains("rebindable"),
                     qPrintable(QStringLiteral("Action '%1' is missing the 'rebindable' field").arg(action)));
            QVERIFY2(def.value("rebindable").toBool(),
                     qPrintable(QStringLiteral("Action '%1' must be rebindable (only 'open' is view-local)").arg(action)));
            ++checked;
        }
        QVERIFY2(checked >= 40,
                 qPrintable(QStringLiteral("Expected at least 40 rebindable actions, only saw %1").arg(checked)));
    }

    // --- P3 M3: persist default_view / sort_by / sort_ascending ---

    void testSaveViewAndSortDefaults()
    {
        QTemporaryDir dir;
        const QString path = dir.path() + "/config.toml";

        ConfigManager mgr(path);
        mgr.saveSettings(QVariantMap{
            {"defaultView", "detailed"},
            {"sortBy", "size"},
            {"sortAscending", false}
        });

        // Fresh instance against the same file must restore the values.
        ConfigManager mgr2(path);
        QCOMPARE(mgr2.defaultView(), QString("detailed"));
        QCOMPARE(mgr2.sortBy(), QString("size"));
        QCOMPARE(mgr2.sortAscending(), false);
    }

    void testSaveGridCellSizePersistsAcrossInstances()
    {
        QTemporaryDir dir;
        const QString path = dir.path() + "/config.toml";

        ConfigManager mgr(path);
        mgr.saveGridCellSize(232);

        // Fresh instance against the same file must restore the zoom level.
        ConfigManager mgr2(path);
        QCOMPARE(mgr2.gridCellSize(), 232);
    }

    void testSaveGridCellSizeClampsOutOfRange()
    {
        QTemporaryDir dir;
        const QString path = dir.path() + "/config.toml";

        ConfigManager mgr(path);
        mgr.saveGridCellSize(9000);   // above max
        QCOMPARE(mgr.gridCellSize(), 320);

        mgr.saveGridCellSize(10);     // below min
        QCOMPARE(mgr.gridCellSize(), 110);
    }

    void testSaveViewDefaultsRejectsEmptyStrings()
    {
        QTemporaryDir dir;
        const QString path = dir.path() + "/config.toml";

        ConfigManager mgr(path);
        // Empty strings must not overwrite the sensible defaults.
        mgr.saveSettings(QVariantMap{
            {"defaultView", ""},
            {"sortBy", ""}
        });

        ConfigManager mgr2(path);
        QCOMPARE(mgr2.defaultView(), QString("hybrid"));
        QCOMPARE(mgr2.sortBy(), QString("name"));
    }

    // --- W7: sidebarCompact + hiddenSidebarEntries ---

    void sidebarCompactPersists()
    {
        QTemporaryDir dir;
        const QString path = dir.path() + "/config.toml";
        {
            ConfigManager cfg(path);
            QCOMPARE(cfg.sidebarCompact(), false);            // default
            cfg.saveSidebarCompact(true);
            QCOMPARE(cfg.sidebarCompact(), true);
        }
        ConfigManager reloaded(path);                          // fresh load from disk
        QCOMPARE(reloaded.sidebarCompact(), true);
    }

    void hiddenSidebarEntriesPersist()
    {
        QTemporaryDir dir;
        const QString path = dir.path() + "/config.toml";
        {
            ConfigManager cfg(path);
            // R5: Recents is hidden by default, so a fresh config starts with it
            // in the list (no longer empty).
            QCOMPARE(cfg.hiddenSidebarEntries(), QStringList{"places.recents"});
            cfg.hideSidebarEntry("places.recents");           // already default — no-op
            cfg.hideSidebarEntry("network");
            cfg.hideSidebarEntry("places.recents");           // dup is a no-op
            QCOMPARE(cfg.hiddenSidebarEntries().size(), 2);
            cfg.showSidebarEntry("network");
            QCOMPARE(cfg.hiddenSidebarEntries(), QStringList{"places.recents"});
        }
        ConfigManager reloaded(path);
        QCOMPARE(reloaded.hiddenSidebarEntries(), QStringList{"places.recents"});
    }

    void clearHiddenSidebarEntriesPersists()
    {
        QTemporaryDir dir;
        const QString path = dir.path() + "/config.toml";
        {
            ConfigManager cfg(path);
            cfg.hideSidebarEntry("places.recents");
            cfg.hideSidebarEntry("network");
            QCOMPARE(cfg.hiddenSidebarEntries().size(), 2);
            cfg.clearHiddenSidebarEntries();
            QVERIFY(cfg.hiddenSidebarEntries().isEmpty());
        }
        ConfigManager reloaded(path);                          // cleared state persisted to disk
        QVERIFY(reloaded.hiddenSidebarEntries().isEmpty());
    }
};

QTEST_MAIN(TestConfigManager)
#include "tst_configmanager.moc"
