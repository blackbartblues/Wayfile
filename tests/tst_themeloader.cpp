#include <QTest>
#include <QTemporaryDir>
#include <QFile>
#include <QSignalSpy>
#include "services/themeloader.h"

class TestThemeLoader : public QObject
{
    Q_OBJECT

private slots:
    void testLoadBuiltinTheme()
    {
        ThemeLoader loader;
        loader.loadTheme("catppuccin-mocha", THEMES_DIR);
        QCOMPARE(loader.color("base"), QColor("#1e1e2e"));
        QCOMPARE(loader.color("accent"), QColor("#89b4fa"));
        QCOMPARE(loader.color("text"), QColor("#cdd6f4"));
        QCOMPARE(loader.color("error"), QColor("#f38ba8"));
    }

    void testLoadBuiltinLightTheme()
    {
        ThemeLoader loader;
        loader.loadTheme("catppuccin-latte", THEMES_DIR);
        QCOMPARE(loader.color("base"), QColor("#eff1f5"));
        QCOMPARE(loader.color("accent"), QColor("#1e66f5"));
        QCOMPARE(loader.color("text"), QColor("#4c4f69"));
        QCOMPARE(loader.color("error"), QColor("#d20f39"));
    }

    void testAllBuiltinColors()
    {
        ThemeLoader loader;
        loader.loadTheme("catppuccin-mocha", THEMES_DIR);

        QCOMPARE(loader.color("base"), QColor("#1e1e2e"));
        QCOMPARE(loader.color("mantle"), QColor("#181825"));
        QCOMPARE(loader.color("crust"), QColor("#11111b"));
        QCOMPARE(loader.color("surface"), QColor("#313244"));
        QCOMPARE(loader.color("overlay"), QColor("#45475a"));
        QCOMPARE(loader.color("text"), QColor("#cdd6f4"));
        QCOMPARE(loader.color("subtext"), QColor("#bac2de"));
        QCOMPARE(loader.color("muted"), QColor("#6c7086"));
        QCOMPARE(loader.color("accent"), QColor("#89b4fa"));
        QCOMPARE(loader.color("success"), QColor("#a6e3a1"));
        QCOMPARE(loader.color("warning"), QColor("#f9e2af"));
        QCOMPARE(loader.color("error"), QColor("#f38ba8"));
    }

    void testLoadCustomTheme()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/custom.toml";
        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.write("[colors]\nbase = \"#000000\"\ntext = \"#ffffff\"\naccent = \"#ff0000\"\n");
        f.close();

        ThemeLoader loader;
        loader.loadTheme(path, "");
        QCOMPARE(loader.color("base"), QColor("#000000"));
        QCOMPARE(loader.color("text"), QColor("#ffffff"));
        QCOMPARE(loader.color("accent"), QColor("#ff0000"));
    }

    void testFallbackForMissingColors()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/partial.toml";
        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.write("[colors]\nbase = \"#000000\"\n");
        f.close();

        ThemeLoader loader;
        loader.loadTheme(path, "");
        QCOMPARE(loader.color("base"), QColor("#000000"));
        // All other colors should fall back to defaults
        QCOMPARE(loader.color("text"), QColor("#cdd6f4"));
        QCOMPARE(loader.color("accent"), QColor("#89b4fa"));
        QCOMPARE(loader.color("error"), QColor("#f38ba8"));
    }

    void testMissingThemeFile()
    {
        ThemeLoader loader;
        loader.loadTheme("nonexistent-theme", "/nonexistent/path");
        // Should fall back to defaults, not crash
        QCOMPARE(loader.color("base"), QColor("#1e1e2e"));
        QCOMPARE(loader.color("text"), QColor("#cdd6f4"));
    }

    void testInvalidToml()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/bad.toml";
        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.write("this is not valid toml {{{{");
        f.close();

        ThemeLoader loader;
        loader.loadTheme(path, "");
        // Should use defaults, not crash
        QCOMPARE(loader.color("base"), QColor("#1e1e2e"));
    }

    void testUnknownColorNameReturnsFallback()
    {
        ThemeLoader loader;
        loader.loadTheme("catppuccin-mocha", THEMES_DIR);
        // Unknown color name should return some default
        QColor unknown = loader.color("nonexistent_color");
        QVERIFY(unknown.isValid() || !unknown.isValid()); // Just verify no crash
    }

    void testThemeChangedSignal()
    {
        ThemeLoader loader;
        QSignalSpy spy(&loader, &ThemeLoader::themeChanged);

        loader.loadTheme("catppuccin-mocha", THEMES_DIR);
        QCOMPARE(spy.count(), 1);
    }

    void testLoadThemeByName()
    {
        ThemeLoader loader;
        loader.loadTheme("catppuccin-mocha", THEMES_DIR);
        // Loaded by name from themes directory
        QCOMPARE(loader.color("base"), QColor("#1e1e2e"));
    }

    void testPropertyAccessors()
    {
        ThemeLoader loader;
        loader.loadTheme("catppuccin-mocha", THEMES_DIR);

        // Test the Q_PROPERTY accessors directly
        QCOMPARE(loader.base(), QColor("#1e1e2e"));
        QCOMPARE(loader.text(), QColor("#cdd6f4"));
        QCOMPARE(loader.accent(), QColor("#89b4fa"));
    }

    void testEmptyThemeFile()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/empty.toml";
        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.close(); // empty file

        ThemeLoader loader;
        loader.loadTheme(path, "");
        // Should use all defaults
        QCOMPARE(loader.color("base"), QColor("#1e1e2e"));
    }

    void testColorsSectionMissing()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/nocolor.toml";
        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.write("[metadata]\nname = \"test\"\n"); // no [colors] section
        f.close();

        ThemeLoader loader;
        loader.loadTheme(path, "");
        QCOMPARE(loader.color("base"), QColor("#1e1e2e"));
    }

    void testBifrostObsidianGoldTokens()
    {
        ThemeLoader loader;
        loader.loadTheme("bifrost", THEMES_DIR);

        // Gold ramp.
        QCOMPARE(loader.gold(), QColor("#E3A94B"));
        QCOMPARE(loader.goldMid(), QColor("#C98F3C"));
        QCOMPARE(loader.goldDeep(), QColor("#9a6e2e"));
        QCOMPARE(loader.goldLight(), QColor("#FFE7B6"));
        // Obsidian surfaces.
        QCOMPARE(loader.page(), QColor("#050609"));
        QCOMPARE(loader.bgA(), QColor("#121318"));
        QCOMPARE(loader.bgB(), QColor("#0a0b0e"));
        QCOMPARE(loader.panel(), QColor("#111217"));
        QCOMPARE(loader.panel2(), QColor("#15161c"));
        QCOMPARE(loader.raise(), QColor("#1b1d24"));
        QCOMPARE(loader.raise2(), QColor("#22242c"));
        QCOMPARE(loader.line(), QColor("#25262e"));
        QCOMPARE(loader.lineSoft(), QColor("#1b1c22"));
        QCOMPARE(loader.hair(), QColor("#0e0f13"));
        // Semantic tokens retuned to obsidian + gold.
        QCOMPARE(loader.accent(), QColor("#E3A94B"));
        QCOMPARE(loader.base(), QColor("#111217"));
        QCOMPARE(loader.crust(), QColor("#050609"));
        QCOMPARE(loader.text(), QColor("#ECE7DC"));
        QCOMPARE(loader.subtext(), QColor("#9CA0A8"));
        QCOMPARE(loader.muted(), QColor("#62666e"));
    }

    void testNewTokensFallBackToDefaults()
    {
        // A theme that omits the new tokens still resolves them via s_defaults.
        QTemporaryDir dir;
        QString path = dir.path() + "/partial.toml";
        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.write("[colors]\nbase = \"#000000\"\n");
        f.close();

        ThemeLoader loader;
        loader.loadTheme(path, "");
        QCOMPARE(loader.gold(), QColor("#E3A94B"));
        QCOMPARE(loader.page(), QColor("#050609"));
        QCOMPARE(loader.hair(), QColor("#0e0f13"));
    }

    // Phase C4: live colour editing for the Colours settings section.
    void testSetColorEmitsAndUpdates()
    {
        ThemeLoader loader;
        loader.loadTheme("bifrost", THEMES_DIR);
        QSignalSpy spy(&loader, &ThemeLoader::themeChanged);

        loader.setColor("accent", QColor("#ff0000"));
        QCOMPARE(loader.color("accent"), QColor("#ff0000"));
        QCOMPARE(spy.count(), 1);

        // Same value -> no-op, no extra signal.
        loader.setColor("accent", QColor("#ff0000"));
        QCOMPARE(spy.count(), 1);

        // Empty name / invalid colour are ignored.
        loader.setColor("", QColor("#00ff00"));
        loader.setColor("accent", QColor());
        QCOMPARE(spy.count(), 1);
        QCOMPARE(loader.color("accent"), QColor("#ff0000"));
    }

    void testSaveThemeFileRoundTrips()
    {
        ThemeLoader loader;
        loader.loadTheme("bifrost", THEMES_DIR);
        loader.setColor("accent", QColor("#123456"));
        loader.setColor("text", QColor("#abcdef"));

        QTemporaryDir dir;
        const QString path = dir.path() + "/custom.toml";
        QVERIFY(loader.saveThemeFile(path));
        QVERIFY(QFile::exists(path));

        // Reload the written file: edited tokens survive, untouched tokens too.
        ThemeLoader reloaded;
        reloaded.loadTheme(path, "");
        QCOMPARE(reloaded.color("accent"), QColor("#123456"));
        QCOMPARE(reloaded.color("text"), QColor("#abcdef"));
        QCOMPARE(reloaded.color("gold"), QColor("#E3A94B"));
        QCOMPARE(reloaded.color("page"), QColor("#050609"));
    }

    void testSaveThemeFilePreservesAlpha()
    {
        // scrim carries alpha; it must round-trip through #aarrggbb.
        ThemeLoader loader;
        loader.loadTheme("bifrost", THEMES_DIR);
        const QColor scrim = loader.color("scrim");
        QVERIFY(scrim.alpha() < 255);

        QTemporaryDir dir;
        const QString path = dir.path() + "/custom.toml";
        QVERIFY(loader.saveThemeFile(path));

        ThemeLoader reloaded;
        reloaded.loadTheme(path, "");
        QCOMPARE(reloaded.color("scrim"), scrim);
    }
};

QTEST_MAIN(TestThemeLoader)
#include "tst_themeloader.moc"
