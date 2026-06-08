#include <QTest>
#include <QStandardPaths>
#include <QFileSystemModel>
#include "models/foldertreemodel.h"
#include "testdir.h"

// Unit tests for FolderTreeModel — the folders-only QFileSystemModel that backs
// the Gallery sidebar's folder tree. QFileSystemModel populates directories
// asynchronously, so QTRY_* is used to wait for the watched dir to load.
class TestFolderTreeModel : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
    }

    void testListsOnlyFolders()
    {
        TestDir dir;
        dir.createDir("alpha");
        dir.createDir("beta");
        dir.createFile("note.txt", "x");   // file → excluded

        FolderTreeModel model;
        const QModelIndex root = model.setRootPath(dir.path());
        QTRY_COMPARE(model.rowCount(root), 2);

        QStringList names;
        for (int r = 0; r < model.rowCount(root); ++r)
            names << model.index(r, 0, root).data(QFileSystemModel::FileNameRole).toString();
        names.sort();
        QCOMPARE(names, (QStringList{"alpha", "beta"}));
    }

    void testExcludesHiddenFolders()
    {
        TestDir dir;
        dir.createDir("visible");
        dir.createDir(".secret");          // hidden folder → excluded

        FolderTreeModel model;
        const QModelIndex root = model.setRootPath(dir.path());
        QTRY_COMPARE(model.rowCount(root), 1);
        QCOMPARE(model.index(0, 0, root).data(QFileSystemModel::FileNameRole).toString(),
                 QString("visible"));
    }

    void testIndexForPathRoundTrips()
    {
        TestDir dir;
        dir.createDir("alpha");

        FolderTreeModel model;
        const QModelIndex root = model.setRootPath(dir.path());
        QTRY_COMPARE(model.rowCount(root), 1);

        const QString alphaPath = dir.path() + "/alpha";
        const QModelIndex idx = model.indexForPath(alphaPath);
        QVERIFY(idx.isValid());
        QCOMPARE(model.pathAt(idx), alphaPath);

        QVERIFY(!model.indexForPath(dir.path() + "/does-not-exist").isValid());
    }

    void testSetRootDirChangesRoot()
    {
        TestDir dir1; dir1.createDir("a");
        TestDir dir2; dir2.createDir("b");

        FolderTreeModel model;
        model.setRootDir(dir1.path());
        const QModelIndex r1 = model.index(dir1.path());
        QTRY_COMPARE(model.rowCount(r1), 1);

        // identity — must not crash or re-emit
        model.setRootDir(dir1.path());
        QCOMPARE(model.rootPath(), dir1.path());

        // real change
        model.setRootDir(dir2.path());
        const QModelIndex r2 = model.index(dir2.path());
        QTRY_COMPARE(model.rowCount(r2), 1);
        QCOMPARE(model.rootPath(), dir2.path());
    }
};

QTEST_GUILESS_MAIN(TestFolderTreeModel)
#include "tst_foldertreemodel.moc"
