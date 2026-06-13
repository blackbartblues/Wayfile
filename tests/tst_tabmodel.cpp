#include <QTest>
#include <QJsonArray>
#include <QJsonObject>
#include <QSignalSpy>
#include <QAbstractItemModelTester>
#include <QFileInfo>
#include "models/tabmodel.h"
#include "models/tablistmodel.h"

class TestTabModel : public QObject
{
    Q_OBJECT

private slots:
    // === TabModel tests ===

    void testTabInitialState()
    {
        TabModel tab;
        QCOMPARE(tab.currentPath(), QDir::homePath());
        QCOMPARE(tab.viewMode(), QString("hybrid"));
        QCOMPARE(tab.canGoBack(), false);
        QCOMPARE(tab.canGoForward(), false);
        QCOMPARE(tab.sortBy(), QString("name"));
        QCOMPARE(tab.sortAscending(), true);
    }

    void testNavigate()
    {
        TabModel tab;
        QSignalSpy spy(&tab, &TabModel::currentPathChanged);

        tab.navigateTo("/tmp");

        QCOMPARE(tab.currentPath(), QString("/tmp"));
        QCOMPARE(tab.canGoBack(), true);
        QCOMPARE(tab.canGoForward(), false);
        QCOMPARE(spy.count(), 1);
    }

    void testNavigateMultiple()
    {
        TabModel tab;
        tab.navigateTo("/tmp");
        tab.navigateTo("/usr");
        tab.navigateTo("/var");

        QCOMPARE(tab.currentPath(), QString("/var"));
        QCOMPARE(tab.canGoBack(), true);
    }

    void testBackForward()
    {
        TabModel tab;
        tab.navigateTo("/tmp");
        tab.navigateTo("/usr");

        QSignalSpy historySpy(&tab, &TabModel::historyChanged);

        tab.goBack();
        QCOMPARE(tab.currentPath(), QString("/tmp"));
        QCOMPARE(tab.canGoForward(), true);
        QVERIFY(historySpy.count() >= 1);

        tab.goForward();
        QCOMPARE(tab.currentPath(), QString("/usr"));
    }

    void testSupertabPaneState()
    {
        TabModel tab;

        // A fresh tab is single-pane and not a supertab; non-primary pane
        // accessors report empty / false until a pane is grown.
        QCOMPARE(tab.paneCount(), 1);
        QCOMPARE(tab.isSupertab(), false);
        QCOMPARE(tab.paneCurrentPath(1), QString());
        QCOMPARE(tab.paneCanGoBack(1), false);
        QCOMPARE(tab.paneCanGoForward(1), false);

        QCOMPARE(tab.addPane("/tmp"), 1);
        QCOMPARE(tab.paneCount(), 2);
        QCOMPARE(tab.paneCurrentPath(1), QString("/tmp"));
        tab.setSupertab(true);
        QCOMPARE(tab.isSupertab(), true);
    }

    void testSetViewModeNoLongerMirrors()
    {
        TabModel tab;                       // pane 0 starts "hybrid"
        tab.addPane("/tmp");                // pane 1 inherits "hybrid"
        tab.setViewMode("grid");            // sets pane 0 only now
        QCOMPARE(tab.paneViewMode(0), QString("grid"));
        QCOMPARE(tab.paneViewMode(1), QString("hybrid"));   // NOT mirrored
    }

    void testSetPaneViewModeIndependent()
    {
        TabModel tab;
        tab.addPane("/tmp");
        tab.setPaneViewMode(1, "detailed");
        QCOMPARE(tab.paneViewMode(0), QString("hybrid"));
        QCOMPARE(tab.paneViewMode(1), QString("detailed"));
    }

    void testSetPaneViewModeSignal()
    {
        TabModel tab;
        QSignalSpy spy(&tab, &TabModel::paneViewModeChanged);
        tab.setPaneViewMode(0, "miller");
        QCOMPARE(spy.count(), 1);
        QCOMPARE(spy.at(0).at(0).toInt(), 0);
        // idx 0 also pulses the tab-level signal for session/back-compat readers.
        QSignalSpy tabSpy(&tab, &TabModel::viewModeChanged);
        tab.setPaneViewMode(0, "grid");
        QCOMPARE(tabSpy.count(), 1);
    }

    void testSetPaneViewModeOutOfRangeNoop()
    {
        TabModel tab;
        QSignalSpy spy(&tab, &TabModel::paneViewModeChanged);
        tab.setPaneViewMode(5, "grid");     // no pane 5
        tab.setPaneViewMode(-1, "grid");
        QCOMPARE(spy.count(), 0);
        QCOMPARE(tab.paneViewMode(0), QString("hybrid"));
    }

    void testNonPrimaryPaneNavigation()
    {
        TabModel tab;
        tab.addPane(tab.currentPath());  // grow pane 1 at the primary's path

        QSignalSpy pathSpy(&tab, &TabModel::panePathChanged);

        tab.navigateInPane(1, "/tmp");
        QCOMPARE(tab.paneCurrentPath(1), QString("/tmp"));
        QCOMPARE(tab.paneCanGoBack(1), true);
        QCOMPARE(tab.paneCanGoForward(1), false);
        QCOMPARE(pathSpy.count(), 1);

        tab.navigateInPane(1, "/usr");
        tab.paneGoBack(1);
        QCOMPARE(tab.paneCurrentPath(1), QString("/tmp"));
        QCOMPARE(tab.paneCanGoForward(1), true);

        tab.paneGoForward(1);
        QCOMPARE(tab.paneCurrentPath(1), QString("/usr"));
    }

    void testNavigateClearsForwardHistory()
    {
        TabModel tab;
        tab.navigateTo("/tmp");
        tab.navigateTo("/usr");
        tab.goBack();
        QCOMPARE(tab.canGoForward(), true);

        tab.navigateTo("/var");
        QCOMPARE(tab.canGoForward(), false);
    }

    void testGoBackAtStart()
    {
        TabModel tab;
        // At start, back should be no-op
        tab.goBack();
        QCOMPARE(tab.currentPath(), QDir::homePath());
    }

    void testGoForwardAtEnd()
    {
        TabModel tab;
        // At end, forward should be no-op
        tab.goForward();
        QCOMPARE(tab.currentPath(), QDir::homePath());
    }

    void testGoUp()
    {
        TabModel tab;
        tab.navigateTo("/tmp");
        tab.goUp();
        QCOMPARE(tab.currentPath(), QString("/"));
    }

    void testGoUpAtRoot()
    {
        TabModel tab;
        tab.navigateTo("/");
        tab.goUp();
        // Should stay at root, not crash
        QCOMPARE(tab.currentPath(), QString("/"));
    }

    void testViewMode()
    {
        TabModel tab;
        QSignalSpy spy(&tab, &TabModel::viewModeChanged);

        tab.setViewMode("list");
        QCOMPARE(tab.viewMode(), QString("list"));
        QCOMPARE(spy.count(), 1);

        tab.setViewMode("detailed");
        QCOMPARE(tab.viewMode(), QString("detailed"));
        QCOMPARE(spy.count(), 2);

        tab.setViewMode("grid");
        QCOMPARE(tab.viewMode(), QString("grid"));
    }

    void testSortProperties()
    {
        TabModel tab;
        QSignalSpy spy(&tab, &TabModel::sortChanged);

        tab.setSortBy("size");
        QCOMPARE(tab.sortBy(), QString("size"));
        QVERIFY(spy.count() >= 1);

        tab.setSortAscending(false);
        QCOMPARE(tab.sortAscending(), false);
    }

    void testTabTitle()
    {
        TabModel tab;
        QCOMPARE(tab.title(), QDir::home().dirName());

        tab.navigateTo("/tmp");
        QCOMPARE(tab.title(), QString("tmp"));

        tab.navigateTo("/");
        QCOMPARE(tab.title(), QString("/"));

        tab.navigateTo("/usr/local/bin");
        QCOMPARE(tab.title(), QString("bin"));

        // A merged supertab joins every pane's name with ' · '.
        tab.addPane("/tmp");
        tab.setSupertab(true);
        QCOMPARE(tab.title(), QString("bin · tmp"));
    }

    void testRemoteTabTitleAndGoUp()
    {
        TabModel tab;
        tab.navigateTo("sftp://example.com/home/jim/projects");
        QCOMPARE(tab.title(), QString("projects"));

        tab.goUp();
        QCOMPARE(tab.currentPath(), QString("sftp://example.com/home/jim"));

        tab.navigateTo("sftp://example.com/");
        QCOMPARE(tab.title(), QString("example.com"));
        tab.goUp();
        QCOMPARE(tab.currentPath(), QString("sftp://example.com/"));
    }

    // === TabListModel tests ===

    void testTabListModelInitialState()
    {
        TabListModel model;
        QCOMPARE(model.rowCount(), 1);
        QCOMPARE(model.activeIndex(), 0);
        QVERIFY(model.activeTab() != nullptr);
    }

    void testTabListModelConsistency()
    {
        TabListModel model;
        auto *tester = new QAbstractItemModelTester(&model,
            QAbstractItemModelTester::FailureReportingMode::QtTest);
        Q_UNUSED(tester)

        model.addTab();
        model.addTab();
        model.closeTab(1);
        model.addTab();
    }

    void testTabListModelAddRemove()
    {
        TabListModel model;
        QSignalSpy countSpy(&model, &TabListModel::countChanged);

        model.addTab();
        QCOMPARE(model.rowCount(), 2);
        QCOMPARE(model.activeIndex(), 1); // New tab becomes active
        QVERIFY(countSpy.count() >= 1);

        model.closeTab(0);
        QCOMPARE(model.rowCount(), 1);
        QCOMPARE(model.activeIndex(), 0);
    }

    void testTabListModelCannotCloseLastTab()
    {
        TabListModel model;
        QSignalSpy lastTabSpy(&model, &TabListModel::lastTabClosed);

        model.closeTab(0);
        QCOMPARE(model.rowCount(), 1); // Still one tab
    }

    void testTabListModelActiveIndex()
    {
        TabListModel model;
        model.addTab(); // idx 1
        model.addTab(); // idx 2

        QSignalSpy spy(&model, &TabListModel::activeIndexChanged);

        model.setActiveIndex(0);
        QCOMPARE(model.activeIndex(), 0);
        QVERIFY(spy.count() >= 1);
    }

    void testReopenClosedTab()
    {
        TabListModel model;
        model.activeTab()->navigateTo("/tmp");
        model.activeTab()->addPane("/usr");
        model.activeTab()->setSupertab(true);
        model.addTab();
        model.closeTab(0);
        QCOMPARE(model.rowCount(), 1);

        model.reopenClosedTab();
        QCOMPARE(model.rowCount(), 2);
        QCOMPARE(model.tabAt(1)->currentPath(), QString("/tmp"));
        QCOMPARE(model.tabAt(1)->paneCount(), 2);
        QCOMPARE(model.tabAt(1)->paneCurrentPath(1), QString("/usr"));
        QCOMPARE(model.tabAt(1)->isSupertab(), true);
    }

    void testReopenMultipleClosedTabs()
    {
        TabListModel model;
        model.activeTab()->navigateTo("/tmp");
        model.addTab();
        model.activeTab()->navigateTo("/usr");
        model.addTab();

        // Close tabs (LIFO order matters)
        model.closeTab(1); // /usr
        model.closeTab(0); // /tmp

        model.reopenClosedTab();
        // Most recently closed should come back first
        QCOMPARE(model.rowCount(), 2);
    }

    void testReopenWhenNothingClosed()
    {
        TabListModel model;
        // Should be no-op
        model.reopenClosedTab();
        QCOMPARE(model.rowCount(), 1);
    }

    void testTabListModelRoles()
    {
        TabListModel model;
        model.activeTab()->navigateTo("/tmp");

        QModelIndex idx = model.index(0);
        QCOMPARE(model.data(idx, TabListModel::TitleRole).toString(), QString("tmp"));
        QCOMPARE(model.data(idx, TabListModel::PathRole).toString(), QString("/tmp"));
        QVERIFY(model.data(idx, TabListModel::TabObjectRole).value<TabModel*>() != nullptr);

        model.activeTab()->addPane("/usr");
        model.activeTab()->setSupertab(true);
        QCOMPARE(model.data(idx, TabListModel::TitleRole).toString(), QString("tmp · usr"));
    }

    void testCloseTabAdjustsActiveIndex()
    {
        TabListModel model;
        model.addTab();
        model.addTab();
        model.setActiveIndex(2);
        QCOMPARE(model.activeIndex(), 2);

        // Close tab before active
        model.closeTab(0);
        // Active index should adjust down
        QCOMPARE(model.activeIndex(), 1);
    }

    void testCloseActiveTabSelectsPrevious()
    {
        TabListModel model;
        model.addTab();
        model.addTab();
        model.setActiveIndex(1);

        model.closeTab(1);
        QVERIFY(model.activeIndex() >= 0);
        QVERIFY(model.activeIndex() < model.rowCount());
    }

    void testTabListModelSessionChanged()
    {
        TabListModel model;
        QSignalSpy sessionSpy(&model, &TabListModel::sessionChanged);

        model.activeTab()->navigateTo("/tmp");
        QVERIFY(sessionSpy.count() >= 1);

        sessionSpy.clear();
        model.addTab();
        QVERIFY(sessionSpy.count() >= 1);
    }

    void testRestoreSessionFallsBackToExistingPath()
    {
        TabListModel model;

        QJsonArray tabs;
        QJsonObject tab;
        tab["path"] = "/definitely/missing/path/for/wayfile";
        tab["viewMode"] = "grid";
        tab["sortBy"] = "name";
        tab["sortAscending"] = true;
        tabs.append(tab);

        model.restoreSession(tabs, 0);

        QVERIFY(model.activeTab() != nullptr);
        QVERIFY(QFileInfo::exists(model.activeTab()->currentPath()));
    }

    void testSessionPersistsMergedSupertab()
    {
        TabListModel model;

        // Build a 3-pane merged supertab on the active tab.
        TabModel *tab = model.activeTab();
        tab->navigateTo("/tmp");
        tab->addPane("/usr");
        tab->addPane("/home");
        tab->setSupertab(true);
        QCOMPARE(tab->paneCount(), 3);
        QVERIFY(tab->isSupertab());

        // Round-trip through the session JSON.
        const QJsonArray saved = model.saveSession();
        TabListModel restored;
        restored.restoreSession(saved, 0);

        TabModel *rtab = restored.activeTab();
        QVERIFY(rtab != nullptr);
        QCOMPARE(rtab->paneCount(), 3);          // merge group survived
        QVERIFY(rtab->isSupertab());
        QCOMPARE(rtab->paneCurrentPath(0), QString("/tmp"));
        QCOMPARE(rtab->paneCurrentPath(1), QString("/usr"));
        QCOMPARE(rtab->paneCurrentPath(2), QString("/home"));
    }

    void testSessionPreservesPerPaneViews()
    {
        TabListModel model;
        TabModel *tab = model.activeTab();
        tab->navigateTo("/tmp");
        tab->addPane("/usr");
        tab->setSupertab(true);
        tab->setPaneViewMode(0, "grid");
        tab->setPaneViewMode(1, "detailed");

        const QJsonArray saved = model.saveSession();
        TabListModel restored;
        restored.restoreSession(saved, 0);

        TabModel *rt = restored.activeTab();
        QCOMPARE(rt->paneCount(), 2);
        QCOMPARE(rt->paneViewMode(0), QString("grid"));
        QCOMPARE(rt->paneViewMode(1), QString("detailed"));
    }

    void testLegacySessionStringPanesRestore()
    {
        // Sessions written before this feature stored panes as bare path
        // strings and a single top-level viewMode. They must still restore.
        QJsonObject legacy{
            {"path", "/tmp"},
            {"viewMode", "miller"},
            {"sortBy", "name"},
            {"sortAscending", true},
            {"panes", QJsonArray{QString("/tmp"), QString("/usr")}},
            {"isSupertab", true},
        };
        TabListModel model;
        model.restoreSession(QJsonArray{legacy}, 0);
        TabModel *tab = model.activeTab();
        QCOMPARE(tab->paneCount(), 2);
        QCOMPARE(tab->paneViewMode(0), QString("miller"));
        QCOMPARE(tab->paneViewMode(1), QString("miller"));   // legacy → shared
    }

    void testReopenClosedTabKeepsPerPaneViews()
    {
        TabListModel model;
        model.addTab();                       // a 2nd tab so close is allowed
        model.setActiveIndex(1);              // pin to the new tab deterministically
        TabModel *tab = model.activeTab();
        tab->navigateTo("/tmp");
        tab->addPane("/usr");
        tab->setSupertab(true);
        tab->setPaneViewMode(0, "grid");
        tab->setPaneViewMode(1, "detailed");

        model.closeTab(model.activeIndex());
        model.reopenClosedTab();

        TabModel *rt = model.activeTab();
        QCOMPARE(rt->paneCount(), 2);
        QCOMPARE(rt->paneViewMode(0), QString("grid"));
        QCOMPARE(rt->paneViewMode(1), QString("detailed"));
    }

    // Phase C: merge button (no explicit multi-selection) — default to the
    // tab on the RIGHT of the active one.
    void testMergeActiveWithAdjacentPrefersRight()
    {
        TabListModel model;
        model.activeTab()->navigateTo("/tmp");   // index 0
        model.addTab();
        model.tabAt(1)->navigateTo("/usr");       // index 1
        model.addTab();
        model.tabAt(2)->navigateTo("/home");      // index 2
        QCOMPARE(model.rowCount(), 3);

        model.setActiveIndex(1);                  // active = middle tab (/usr)
        model.mergeActiveWithAdjacent();

        // Merges with the right neighbour (/home); receiver is the lower index.
        QCOMPARE(model.rowCount(), 2);
        QCOMPARE(model.activeIndex(), 1);
        TabModel *merged = model.tabAt(1);
        QVERIFY(merged->isSupertab());
        QCOMPARE(merged->paneCount(), 2);
        QCOMPARE(merged->paneCurrentPath(0), QString("/usr"));
        QCOMPARE(merged->paneCurrentPath(1), QString("/home"));
        // The left tab (/tmp) is untouched.
        QCOMPARE(model.tabAt(0)->currentPath(), QString("/tmp"));
        QVERIFY(!model.tabAt(0)->isSupertab());
    }

    // Phase C: when the active tab is the last one, fall back to the left
    // neighbour.
    void testMergeActiveWithAdjacentFallsBackLeft()
    {
        TabListModel model;
        model.activeTab()->navigateTo("/tmp");   // 0
        model.addTab();
        model.tabAt(1)->navigateTo("/usr");       // 1
        model.addTab();
        model.tabAt(2)->navigateTo("/home");      // 2

        model.setActiveIndex(2);                  // active = last tab (/home)
        model.mergeActiveWithAdjacent();

        // No right neighbour -> merge with the left one (/usr) at index 1.
        QCOMPARE(model.rowCount(), 2);
        QCOMPARE(model.activeIndex(), 1);
        TabModel *merged = model.tabAt(1);
        QVERIFY(merged->isSupertab());
        QCOMPARE(merged->paneCount(), 2);
        QCOMPARE(merged->paneCurrentPath(0), QString("/usr"));
        QCOMPARE(merged->paneCurrentPath(1), QString("/home"));
        QCOMPARE(model.tabAt(0)->currentPath(), QString("/tmp"));
    }

    // Phase C: a lone tab spawns a fresh tab and merges into a 2-pane supertab.
    void testMergeActiveWithAdjacentSpawnsWhenAlone()
    {
        TabListModel model;
        model.activeTab()->navigateTo("/tmp");
        QCOMPARE(model.rowCount(), 1);

        model.mergeActiveWithAdjacent();

        QCOMPARE(model.rowCount(), 1);            // the two tabs merged into one
        TabModel *merged = model.activeTab();
        QVERIFY(merged->isSupertab());
        QCOMPARE(merged->paneCount(), 2);
        QCOMPARE(merged->paneCurrentPath(0), QString("/tmp"));
    }

    // Phase C: refuse (without disturbing the selection) when merging the
    // neighbour would exceed the 4-pane cap.
    void testMergeActiveWithAdjacentRespectsPaneCap()
    {
        TabListModel model;
        model.activeTab()->navigateTo("/tmp");   // 0, single pane
        model.addTab();                           // 1
        TabModel *b = model.tabAt(1);
        b->navigateTo("/");
        b->addPane("/usr");
        b->addPane("/home");
        b->addPane("/etc");
        b->setSupertab(true);
        QCOMPARE(b->paneCount(), 4);

        model.setActiveIndex(0);
        QSignalSpy limitSpy(&model, &TabListModel::selectionLimitReached);
        model.mergeActiveWithAdjacent();

        // 1 + 4 = 5 > kMaxPanes -> refused, both tabs intact, no dangling sel.
        QVERIFY(limitSpy.count() >= 1);
        QCOMPARE(model.rowCount(), 2);
        QCOMPARE(model.selectedCount(), 1);
        QVERIFY(!model.tabAt(0)->isSupertab());
        QCOMPARE(model.tabAt(1)->paneCount(), 4);
    }
};

QTEST_MAIN(TestTabModel)
#include "tst_tabmodel.moc"
