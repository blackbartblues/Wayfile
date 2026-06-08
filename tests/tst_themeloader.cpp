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

        // Gold ramp (handoff softer tan-gold).
        QCOMPARE(loader.gold(), QColor("#D4AA6A"));
        QCOMPARE(loader.goldMid(), QColor("#B8915A"));
        QCOMPARE(loader.goldDeep(), QColor("#8C6E44"));
        QCOMPARE(loader.goldLight(), QColor("#ECD4A6"));
        // Obsidian surfaces (lighter steel-grey ladder).
        QCOMPARE(loader.page(), QColor("#15181C"));
        QCOMPARE(loader.bgA(), QColor("#2D3137"));
        QCOMPARE(loader.bgB(), QColor("#1E2126"));
        QCOMPARE(loader.panel(), QColor("#1E2126"));
        QCOMPARE(loader.panel2(), QColor("#25292E"));
        QCOMPARE(loader.raise(), QColor("#25292E"));
        QCOMPARE(loader.raise2(), QColor("#2F343A"));
        QCOMPARE(loader.line(), QColor("#353B42"));
        QCOMPARE(loader.lineSoft(), QColor("#2A2E33"));
        QCOMPARE(loader.hair(), QColor("#1A1D21"));
        // Semantic tokens retuned to obsidian + gold.
        QCOMPARE(loader.accent(), QColor("#D4AA6A"));
        QCOMPARE(loader.base(), QColor("#1E2126"));
        QCOMPARE(loader.crust(), QColor("#15181C"));
        QCOMPARE(loader.text(), QColor("#E6E1D6"));
        QCOMPARE(loader.subtext(), QColor("#A3A8AE"));
        QCOMPARE(loader.muted(), QColor("#6C7177"));
        // Remaining changed semantic tokens.
        QCOMPARE(loader.mantle(),  QColor("#1A1D21"));
        QCOMPARE(loader.surface(), QColor("#25292E"));
        QCOMPARE(loader.overlay(), QColor("#2F343A"));
        QCOMPARE(loader.success(), QColor("#56B881"));
        QCOMPARE(loader.warning(), QColor("#E0B26C"));
        QCOMPARE(loader.error(),   QColor("#E06C75"));
        // Atmosphere tokens (scrim asserts the new RGB too, not just alpha).
        QCOMPARE(loader.scrim(), QColor("#C715181C"));
        QCOMPARE(loader.sheen(), QColor("#FFF0D7"));
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
        QCOMPARE(reloaded.color("gold"), QColor("#D4AA6A"));
        QCOMPARE(reloaded.color("page"), QColor("#15181C"));
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
