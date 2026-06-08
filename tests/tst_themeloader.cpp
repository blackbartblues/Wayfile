#include <QTest>
#include <QTemporaryDir>
#include <QFile>
#include <QSignalSpy>
#include "services/themeloader.h"

class TestThemeLoader : public QObject
{
    Q_OBJECT

private slots:
    // ── Bifröst = the shared obsidian base + gold accent ────────────────────
    void testLoadBifrost()
    {
        ThemeLoader loader;
        loader.loadTheme("bifrost", THEMES_DIR);
        QCOMPARE(loader.color("base"), QColor("#1E2126"));
        QCOMPARE(loader.color("accent"), QColor("#D4AA6A"));
        QCOMPARE(loader.color("text"), QColor("#E6E1D6"));
        QCOMPARE(loader.color("error"), QColor("#E06C75"));
    }

    void testObsidianBaseTokens()
    {
        ThemeLoader loader;
        loader.loadTheme("bifrost", THEMES_DIR);
        // Semantic tokens (muted nudged #6C7177 -> #787E85 for WCAG AA).
        QCOMPARE(loader.color("base"), QColor("#1E2126"));
        QCOMPARE(loader.color("mantle"), QColor("#1A1D21"));
        QCOMPARE(loader.color("crust"), QColor("#15181C"));
        QCOMPARE(loader.color("surface"), QColor("#25292E"));
        QCOMPARE(loader.color("overlay"), QColor("#2F343A"));
        QCOMPARE(loader.color("text"), QColor("#E6E1D6"));
        QCOMPARE(loader.color("subtext"), QColor("#A3A8AE"));
        QCOMPARE(loader.color("muted"), QColor("#787E85"));
        QCOMPARE(loader.color("accent"), QColor("#D4AA6A"));
        QCOMPARE(loader.color("success"), QColor("#56B881"));
        QCOMPARE(loader.color("warning"), QColor("#E0B26C"));
        QCOMPARE(loader.color("error"), QColor("#E06C75"));
        // Obsidian surfaces.
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
        // Atmosphere (scrim carries alpha).
        QCOMPARE(loader.scrim(), QColor("#C715181C"));
        QCOMPARE(loader.sheen(), QColor("#FFF0D7"));
    }

    // ── Presets override only the accent; the base is shared ────────────────
    void testPresetAccents()
    {
        const QList<QPair<QString, QColor>> presets = {
            {"bifrost", QColor("#D4AA6A")}, {"aurora", QColor("#57C7BF")},
            {"nebula", QColor("#B292E8")},  {"ember", QColor("#E68B5C")},
            {"verdant", QColor("#84C98A")},
        };
        for (const auto &p : presets) {
            ThemeLoader loader;
            loader.loadTheme(p.first, THEMES_DIR);
            QCOMPARE(loader.color("accent"), p.second);
        }
    }

    void testPresetsShareObsidianBase()
    {
        const QStringList presets = {"aurora", "nebula", "ember", "verdant"};
        // The obsidian base never moves across presets.
        const QStringList baseTokens = {"base", "mantle", "crust", "surface",
            "overlay", "text", "subtext", "muted", "success", "warning",
            "error", "page", "line", "hair"};
        ThemeLoader ref;
        ref.loadTheme("bifrost", THEMES_DIR);
        for (const QString &name : presets) {
            ThemeLoader loader;
            loader.loadTheme(name, THEMES_DIR);
            for (const QString &tok : baseTokens)
                QCOMPARE(loader.color(tok), ref.color(tok));
            // ...but the accent differs.
            QVERIFY(loader.color("accent") != ref.color("accent"));
        }
    }

    // ── Fallback / robustness (now obsidian defaults) ───────────────────────
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
        // Everything else falls back to the obsidian defaults.
        QCOMPARE(loader.color("text"), QColor("#E6E1D6"));
        QCOMPARE(loader.color("accent"), QColor("#D4AA6A"));
        QCOMPARE(loader.color("error"), QColor("#E06C75"));
    }

    void testMissingThemeFile()
    {
        ThemeLoader loader;
        loader.loadTheme("nonexistent-theme", "/nonexistent/path");
        QCOMPARE(loader.color("base"), QColor("#1E2126"));
        QCOMPARE(loader.color("text"), QColor("#E6E1D6"));
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
        QCOMPARE(loader.color("base"), QColor("#1E2126"));
    }

    void testUnknownColorNameReturnsFallback()
    {
        ThemeLoader loader;
        loader.loadTheme("bifrost", THEMES_DIR);
        // An unknown token resolves to the hot-magenta sentinel (innermost
        // fallback in ThemeLoader::color); pin it so the contract is explicit.
        QCOMPARE(loader.color("nonexistent_color"), QColor("#ff00ff"));
    }

    void testThemeChangedSignal()
    {
        ThemeLoader loader;
        QSignalSpy spy(&loader, &ThemeLoader::themeChanged);
        loader.loadTheme("bifrost", THEMES_DIR);
        QCOMPARE(spy.count(), 1);
    }

    void testLoadThemeByName()
    {
        ThemeLoader loader;
        loader.loadTheme("aurora", THEMES_DIR);
        QCOMPARE(loader.color("accent"), QColor("#57C7BF"));
        QCOMPARE(loader.color("base"), QColor("#1E2126"));
    }

    void testPropertyAccessors()
    {
        ThemeLoader loader;
        loader.loadTheme("bifrost", THEMES_DIR);
        QCOMPARE(loader.base(), QColor("#1E2126"));
        QCOMPARE(loader.text(), QColor("#E6E1D6"));
        QCOMPARE(loader.accent(), QColor("#D4AA6A"));
    }

    void testEmptyThemeFile()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/empty.toml";
        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.close();

        ThemeLoader loader;
        loader.loadTheme(path, "");
        QCOMPARE(loader.color("base"), QColor("#1E2126"));
    }

    void testColorsSectionMissing()
    {
        QTemporaryDir dir;
        QString path = dir.path() + "/nocolor.toml";
        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.write("[metadata]\nname = \"test\"\n");
        f.close();

        ThemeLoader loader;
        loader.loadTheme(path, "");
        QCOMPARE(loader.color("base"), QColor("#1E2126"));
    }

    void testNewTokensFallBackToDefaults()
    {
        // A theme that omits the gold/obsidian tokens resolves them via s_defaults.
        QTemporaryDir dir;
        QString path = dir.path() + "/partial.toml";
        QFile f(path);
        f.open(QIODevice::WriteOnly);
        f.write("[colors]\nbase = \"#000000\"\n");
        f.close();

        ThemeLoader loader;
        loader.loadTheme(path, "");
        QCOMPARE(loader.gold(), QColor("#D4AA6A"));
        QCOMPARE(loader.page(), QColor("#15181C"));
        QCOMPARE(loader.hair(), QColor("#1A1D21"));
        QCOMPARE(loader.color("goldMid"), QColor("#B8915A"));
        QCOMPARE(loader.color("goldDeep"), QColor("#8C6E44"));
        QCOMPARE(loader.color("goldLight"), QColor("#ECD4A6"));
    }

    // ── Live colour editing (granular Colours editor) ───────────────────────
    void testSetColorEmitsAndUpdates()
    {
        ThemeLoader loader;
        loader.loadTheme("bifrost", THEMES_DIR);
        QSignalSpy spy(&loader, &ThemeLoader::themeChanged);

        loader.setColor("accent", QColor("#ff0000"));
        QCOMPARE(loader.color("accent"), QColor("#ff0000"));
        QCOMPARE(spy.count(), 1);

        loader.setColor("accent", QColor("#ff0000")); // same -> no-op
        QCOMPARE(spy.count(), 1);

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

        ThemeLoader reloaded;
        reloaded.loadTheme(path, "");
        QCOMPARE(reloaded.color("accent"), QColor("#123456"));
        QCOMPARE(reloaded.color("text"), QColor("#abcdef"));
        QCOMPARE(reloaded.color("gold"), QColor("#D4AA6A"));
        QCOMPARE(reloaded.color("page"), QColor("#15181C"));
    }

    void testSaveThemeFilePreservesAlpha()
    {
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
