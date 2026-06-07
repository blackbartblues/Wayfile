#include <QtTest>
#include <QTemporaryDir>
#include <QSignalSpy>
#include <QStandardPaths>

#include "services/configmanager.h"

// P3 M6 — persistence backstop.
//
// The existing tst_configmanager only checks DEFAULT values. This suite proves
// that every persisted setting / shortcut / bookmark survives a full
// write -> save-to-TOML -> reload-from-a-fresh-instance round-trip (i.e. the
// "save, quit, relaunch, value sticks" guarantee), plus that a theme change
// hot-swaps live and emits configChanged. A key that silently stops persisting
// will reload as its default and fail the corresponding QCOMPARE.
class TestConfigManagerRoundtrip : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
    }

    // Every general/sidebar/appearance/window setting must round-trip. Values
    // are deliberately non-default (and within each key's accepted range /
    // whitelist) so a non-persisting key reloads as its default and fails.
    void testSettingsRoundtrip()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.path() + "/config.toml";

        const QVariantMap s {
            {"theme", "nord"},
            {"iconTheme", "Papirus"},
            {"builtinIcons", false},
            {"fontFamily", "JetBrains Mono"},
            {"defaultView", "detailed"},
            {"showHidden", true},
            {"sortBy", "modified"},
            {"sortAscending", false},
            {"sidebarPosition", "right"},
            {"sidebarWidth", 333},
            {"sidebarVisible", false},
            {"scrollSpeed", 7.0},
            {"radiusSmall", 6},
            {"radiusMedium", 10},
            {"radiusLarge", 20},
            {"transparencyEnabled", false},
            {"transparencyLevel", 0.5},
            {"animationsEnabled", false},
            {"animDurationFast", 150},
            {"animDuration", 250},
            {"animDurationSlow", 500},
            {"animCurveEnter", "Linear"},
            {"animCurveExit", "OutQuad"},
            {"animCurveTransition", "InOutCubic"},
            {"showWindowControls", true},
            {"windowButtonLayout", "close,maximize,minimize:"},
        };

        {
            ConfigManager mgr(path);
            mgr.saveSettings(s);
        }

        // Fresh instance reads from disk in its constructor.
        ConfigManager r(path);
        QCOMPARE(r.theme(), QString("nord"));
        QCOMPARE(r.iconTheme(), QString("Papirus"));
        QCOMPARE(r.builtinIcons(), false);
        QCOMPARE(r.fontFamily(), QString("JetBrains Mono"));
        QCOMPARE(r.defaultView(), QString("detailed"));
        QCOMPARE(r.showHidden(), true);
        QCOMPARE(r.sortBy(), QString("modified"));
        QCOMPARE(r.sortAscending(), false);
        QCOMPARE(r.sidebarPosition(), QString("right"));
        QCOMPARE(r.sidebarWidth(), 333);
        QCOMPARE(r.sidebarVisible(), false);
        QCOMPARE(r.scrollSpeed(), 7.0);
        QCOMPARE(r.radiusSmall(), 6);
        QCOMPARE(r.radiusMedium(), 10);
        QCOMPARE(r.radiusLarge(), 20);
        QCOMPARE(r.transparencyEnabled(), false);
        QCOMPARE(r.transparencyLevel(), 0.5);
        QCOMPARE(r.animationsEnabled(), false);
        QCOMPARE(r.animDurationFast(), 150);
        QCOMPARE(r.animDuration(), 250);
        QCOMPARE(r.animDurationSlow(), 500);
        QCOMPARE(r.animCurveEnter(), QString("Linear"));
        QCOMPARE(r.animCurveExit(), QString("OutQuad"));
        QCOMPARE(r.animCurveTransition(), QString("InOutCubic"));
        QCOMPARE(r.showWindowControls(), true);
        QCOMPARE(r.windowButtonLayout(), QString("close,maximize,minimize:"));
    }

    // saveSidebarWidth is the dedicated convenience setter (drag-resize path);
    // it must persist independently of a full saveSettings.
    void testSidebarWidthConvenienceRoundtrip()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.path() + "/config.toml";

        {
            ConfigManager mgr(path);
            mgr.saveSidebarWidth(290);
        }
        ConfigManager r(path);
        QCOMPARE(r.sidebarWidth(), 290);
    }

    // Out-of-range values must be clamped on save and the clamped value must
    // survive reload (so a bad width from a drag never persists out of bounds).
    void testOutOfRangeValuesClampOnRoundtrip()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.path() + "/config.toml";

        {
            ConfigManager mgr(path);
            mgr.saveSettings(QVariantMap {
                {"sidebarWidth", 99999},      // clamps to 480
                {"scrollSpeed", 999.0},       // clamps to 10.0
                {"transparencyLevel", 5.0},   // clamps to 1.0
            });
        }
        ConfigManager r(path);
        QCOMPARE(r.sidebarWidth(), 480);
        QCOMPARE(r.scrollSpeed(), 10.0);
        QCOMPARE(r.transparencyLevel(), 1.0);
    }

    // Custom keyboard shortcuts must round-trip. Values are computed to differ
    // from each action's default so a non-persisting binding fails.
    void testShortcutsRoundtrip()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.path() + "/config.toml";

        QString origNewTab, origToggleMerge, origBack;
        {
            ConfigManager mgr(path);
            origNewTab = mgr.shortcut("new_tab");
            origToggleMerge = mgr.shortcut("toggle_merge");
            origBack = mgr.shortcut("back");

            const QString customNewTab = "Ctrl+Shift+F1";
            const QString customToggleMerge = "Ctrl+Shift+F2";
            // Sanity: these must differ from the defaults, or the test would
            // pass trivially without proving persistence.
            QVERIFY(customNewTab != origNewTab);
            QVERIFY(customToggleMerge != origToggleMerge);

            mgr.saveShortcuts(QVariantMap {
                {"new_tab", customNewTab},
                {"toggle_merge", customToggleMerge},
            });
        }

        ConfigManager r(path);
        QCOMPARE(r.shortcut("new_tab"), QString("Ctrl+Shift+F1"));
        QCOMPARE(r.shortcut("toggle_merge"), QString("Ctrl+Shift+F2"));
        // An action we did NOT override keeps its default after reload.
        QCOMPARE(r.shortcut("back"), origBack);
    }

    // A shortcut reset back to its default must NOT linger in the file as a
    // stale custom value (saveShortcuts only writes non-default bindings).
    void testShortcutResetToDefaultRoundtrips()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.path() + "/config.toml";

        QString defaultNewTab;
        {
            ConfigManager mgr(path);
            defaultNewTab = mgr.shortcut("new_tab");
            mgr.saveShortcuts(QVariantMap{{"new_tab", "Ctrl+Shift+F9"}});
        }
        {
            ConfigManager mid(path);
            QCOMPARE(mid.shortcut("new_tab"), QString("Ctrl+Shift+F9"));
            // Reset to default value.
            mid.saveShortcuts(QVariantMap{{"new_tab", defaultNewTab}});
        }
        ConfigManager r(path);
        QCOMPARE(r.shortcut("new_tab"), defaultNewTab);
    }

    void testBookmarksRoundtrip()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.path() + "/config.toml";

        const QStringList bookmarks { "~/Music", "/tmp", "~/Code/wayfile" };
        {
            ConfigManager mgr(path);
            mgr.saveBookmarks(bookmarks);
        }
        ConfigManager r(path);
        QCOMPARE(r.bookmarks(), bookmarks);
    }

    // Theme hot-swap: changing the theme updates the live getter immediately
    // (no reload) and emits configChanged so bound UI re-themes without restart.
    void testThemeHotSwapEmitsConfigChanged()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.path() + "/config.toml";

        ConfigManager mgr(path);
        QSignalSpy spy(&mgr, &ConfigManager::configChanged);
        QVERIFY(spy.isValid());

        QVERIFY(mgr.theme() != QString("nord"));
        mgr.saveSettings(QVariantMap{{"theme", "nord"}});

        QCOMPARE(mgr.theme(), QString("nord"));   // live, no reload
        QVERIFY(spy.count() >= 1);                // configChanged fired
    }

    // Saving one section must not clobber a previously-saved different section
    // (saveSettings/saveBookmarks/saveShortcuts each merge into the same file).
    void testPartialSavesDoNotClobberOtherSections()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.path() + "/config.toml";

        {
            ConfigManager mgr(path);
            mgr.saveSettings(QVariantMap{{"theme", "nord"}, {"sidebarWidth", 412}});
            mgr.saveBookmarks(QStringList{"/tmp", "~/x"});
            mgr.saveShortcuts(QVariantMap{{"new_tab", "Ctrl+Shift+F3"}});
        }
        ConfigManager r(path);
        QCOMPARE(r.theme(), QString("nord"));
        QCOMPARE(r.sidebarWidth(), 412);
        QCOMPARE(r.bookmarks(), QStringList({"/tmp", "~/x"}));
        QCOMPARE(r.shortcut("new_tab"), QString("Ctrl+Shift+F3"));
    }
};

QTEST_MAIN(TestConfigManagerRoundtrip)
#include "tst_configmanager_roundtrip.moc"
