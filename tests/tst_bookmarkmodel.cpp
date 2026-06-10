#include <QTest>
#include <QSignalSpy>
#include <QAbstractItemModelTester>
#include <QDir>
#include "models/bookmarkmodel.h"

class TestBookmarkModel : public QObject
{
    Q_OBJECT

private slots:
    void testModelConsistency()
    {
        BookmarkModel model;
        auto *tester = new QAbstractItemModelTester(&model,
            QAbstractItemModelTester::FailureReportingMode::QtTest);
        Q_UNUSED(tester)

        model.setBookmarks({"~/Documents", "~/Downloads", "~/Pictures"});
        model.setBookmarks({"~/Music"});
        model.setBookmarks({});
    }

    void testLoadBookmarks()
    {
        BookmarkModel model;
        model.setBookmarks({"~/Documents", "~/Downloads"});
        QCOMPARE(model.rowCount(), 2);
    }

    void testBookmarkData()
    {
        BookmarkModel model;
        model.setBookmarks({"~/Documents"});
        QModelIndex idx = model.index(0);
        QString name = model.data(idx, BookmarkModel::NameRole).toString();
        QCOMPARE(name, QString("Documents"));
    }

    void testExpandTilde()
    {
        BookmarkModel model;
        model.setBookmarks({"~/Documents"});
        QModelIndex idx = model.index(0);
        QString path = model.data(idx, BookmarkModel::PathRole).toString();
        QVERIFY(path.startsWith("/"));
        QVERIFY(path.endsWith("/Documents"));
        QVERIFY(!path.contains("~"));
    }

    void testIconForKnownPaths_data()
    {
        QTest::addColumn<QString>("bookmark");
        QTest::addColumn<bool>("hasIcon");

        QTest::newRow("Documents") << "~/Documents" << true;
        QTest::newRow("Downloads") << "~/Downloads" << true;
        QTest::newRow("Pictures") << "~/Pictures" << true;
        QTest::newRow("Music") << "~/Music" << true;
        QTest::newRow("Videos") << "~/Videos" << true;
        QTest::newRow("Unknown") << "~/RandomDir" << true; // should have fallback icon
    }

    void testIconForKnownPaths()
    {
        QFETCH(QString, bookmark);
        QFETCH(bool, hasIcon);

        BookmarkModel model;
        model.setBookmarks({bookmark});
        QModelIndex idx = model.index(0);
        QString icon = model.data(idx, BookmarkModel::IconRole).toString();
        QCOMPARE(!icon.isEmpty(), hasIcon);
    }

    void testEmptyBookmarkList()
    {
        BookmarkModel model;
        model.setBookmarks({});
        QCOMPARE(model.rowCount(), 0);
    }

    void testReplaceBookmarks()
    {
        BookmarkModel model;
        model.setBookmarks({"~/Documents", "~/Downloads"});
        QCOMPARE(model.rowCount(), 2);

        model.setBookmarks({"~/Music"});
        QCOMPARE(model.rowCount(), 1);

        QModelIndex idx = model.index(0);
        QCOMPARE(model.data(idx, BookmarkModel::NameRole).toString(), QString("Music"));
    }

    void testRoleNames()
    {
        BookmarkModel model;
        auto roles = model.roleNames();
        QCOMPARE(roles[BookmarkModel::NameRole], QByteArray("name"));
        QCOMPARE(roles[BookmarkModel::PathRole], QByteArray("path"));
        QCOMPARE(roles[BookmarkModel::IconRole], QByteArray("icon"));
        QCOMPARE(roles[BookmarkModel::ColorRole], QByteArray("color"));
    }

    void testDefaultColorEmpty()
    {
        BookmarkModel model;
        model.setBookmarks({"~/Documents"});
        QModelIndex idx = model.index(0);
        QCOMPARE(model.data(idx, BookmarkModel::ColorRole).toString(), QString());
    }

    void testSetBookmarkColorRoundtrips()
    {
        BookmarkModel model;
        model.setBookmarks({"~/Documents", "~/Downloads"});

        QSignalSpy dataSpy(&model, &QAbstractItemModel::dataChanged);
        QSignalSpy colorSpy(&model, &BookmarkModel::bookmarkColorChanged);

        model.setBookmarkColor(0, "#D4AA6A");

        // ColorRole reflects the new color; the other row is untouched.
        QCOMPARE(model.data(model.index(0), BookmarkModel::ColorRole).toString(),
                 QString("#D4AA6A"));
        QCOMPARE(model.data(model.index(1), BookmarkModel::ColorRole).toString(),
                 QString());

        // dataChanged(ColorRole) + bookmarkColorChanged(path, color) emitted.
        QCOMPARE(dataSpy.count(), 1);
        QCOMPARE(colorSpy.count(), 1);
        const QList<QVariant> args = colorSpy.takeFirst();
        QVERIFY(args.at(0).toString().endsWith("/Documents"));
        QCOMPARE(args.at(1).toString(), QString("#D4AA6A"));
    }

    void testClearBookmarkColor()
    {
        BookmarkModel model;
        model.setBookmarks({"~/Documents"});
        model.setBookmarkColor(0, "#57C7BF");
        QCOMPARE(model.data(model.index(0), BookmarkModel::ColorRole).toString(),
                 QString("#57C7BF"));

        QSignalSpy colorSpy(&model, &BookmarkModel::bookmarkColorChanged);
        model.setBookmarkColor(0, "");
        QCOMPARE(model.data(model.index(0), BookmarkModel::ColorRole).toString(),
                 QString());
        QCOMPARE(colorSpy.count(), 1);
        QCOMPARE(colorSpy.takeFirst().at(1).toString(), QString());
    }

    void testSeededColorsApplyOnLoad()
    {
        // setBookmarkColors before setBookmarks should colorize on first load,
        // keyed by the EXPANDED absolute path (matches ConfigManager storage).
        const QString docs = QDir::homePath() + "/Documents";
        BookmarkModel model;
        QVariantMap colors;
        colors.insert(docs, QStringLiteral("#B292E8"));
        model.setBookmarkColors(colors);
        model.setBookmarks({"~/Documents", "~/Downloads"});

        QCOMPARE(model.data(model.index(0), BookmarkModel::ColorRole).toString(),
                 QString("#B292E8"));
        QCOMPARE(model.data(model.index(1), BookmarkModel::ColorRole).toString(),
                 QString());
    }

    void testColorSurvivesReorder()
    {
        BookmarkModel model;
        model.setBookmarks({"~/Documents", "~/Downloads"});
        model.setBookmarkColor(0, "#E68B5C");
        model.moveBookmark(0, 1);
        // Color follows the path, not the slot.
        QModelIndex moved = model.index(1);
        QCOMPARE(model.data(moved, BookmarkModel::PathRole).toString().endsWith("/Documents"), true);
        QCOMPARE(model.data(moved, BookmarkModel::ColorRole).toString(), QString("#E68B5C"));
    }

    void testSetBookmarkColorInvalidIndexNoop()
    {
        BookmarkModel model;
        model.setBookmarks({"~/Documents"});
        QSignalSpy colorSpy(&model, &BookmarkModel::bookmarkColorChanged);
        model.setBookmarkColor(-1, "#D4AA6A");
        model.setBookmarkColor(99, "#D4AA6A");
        QCOMPARE(colorSpy.count(), 0);
    }

    void testInvalidIndex()
    {
        BookmarkModel model;
        model.setBookmarks({"~/Documents"});
        QModelIndex bad = model.index(999);
        QVERIFY(!model.data(bad, BookmarkModel::NameRole).isValid());
    }

    void testAbsolutePath()
    {
        BookmarkModel model;
        model.setBookmarks({"/tmp"});
        QModelIndex idx = model.index(0);
        QCOMPARE(model.data(idx, BookmarkModel::PathRole).toString(), QString("/tmp"));
        QCOMPARE(model.data(idx, BookmarkModel::NameRole).toString(), QString("tmp"));
    }

    void testRemoteBookmarkName()
    {
        BookmarkModel model;
        model.setBookmarks({"sftp://example.com/home/jim"});
        QModelIndex idx = model.index(0);
        QCOMPARE(model.data(idx, BookmarkModel::PathRole).toString(), QString("sftp://example.com/home/jim"));
        QCOMPARE(model.data(idx, BookmarkModel::NameRole).toString(), QString("jim"));
    }

    void testRowsResetSignal()
    {
        BookmarkModel model;
        QSignalSpy resetSpy(&model, &QAbstractItemModel::modelReset);

        model.setBookmarks({"~/Documents"});
        QVERIFY(resetSpy.count() >= 1);
    }
};

QTEST_MAIN(TestBookmarkModel)
#include "tst_bookmarkmodel.moc"
