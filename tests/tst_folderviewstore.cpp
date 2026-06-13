#include <QTest>
#include <QTemporaryDir>
#include "models/folderviewstore.h"

class TestFolderViewStore : public QObject
{
    Q_OBJECT

private:
    QString storePath(const QTemporaryDir &dir) const
    {
        return dir.path() + "/folder-views.json";
    }

private slots:
    void testMissReturnsEmptyAndNoWrite()
    {
        QTemporaryDir dir;
        FolderViewStore store(storePath(dir));
        QCOMPARE(store.viewForFolder("/tmp"), QString());
        // A pure lookup must not create the file.
        QVERIFY(!QFile::exists(storePath(dir)));
    }

    void testRememberThenLookup()
    {
        QTemporaryDir dir;
        FolderViewStore store(storePath(dir));
        store.rememberView("/tmp/a", "grid");
        QCOMPARE(store.viewForFolder("/tmp/a"), QString("grid"));
    }

    void testTrailingSlashNormalized()
    {
        QTemporaryDir dir;
        FolderViewStore store(storePath(dir));
        store.rememberView("/tmp/a/", "detailed");
        QCOMPARE(store.viewForFolder("/tmp/a"), QString("detailed"));
        QCOMPARE(store.viewForFolder("/tmp/a/"), QString("detailed"));
    }

    void testUpdateOverwritesNotDuplicates()
    {
        QTemporaryDir dir;
        FolderViewStore store(storePath(dir));
        store.rememberView("/x", "grid");
        store.rememberView("/x", "miller");
        QCOMPARE(store.viewForFolder("/x"), QString("miller"));
        // Reload to confirm only one entry persisted.
        FolderViewStore reloaded(storePath(dir));
        QCOMPARE(reloaded.viewForFolder("/x"), QString("miller"));
    }

    void testBlankPathOrModeIgnored()
    {
        QTemporaryDir dir;
        FolderViewStore store(storePath(dir));
        store.rememberView("", "grid");
        store.rememberView("/y", "");
        QCOMPARE(store.viewForFolder("/y"), QString());
    }

    void testForgetAndClear()
    {
        QTemporaryDir dir;
        FolderViewStore store(storePath(dir));
        store.rememberView("/a", "grid");
        store.rememberView("/b", "miller");
        store.forget("/a");
        QCOMPARE(store.viewForFolder("/a"), QString());
        QCOMPARE(store.viewForFolder("/b"), QString("miller"));
        store.clear();
        QCOMPARE(store.viewForFolder("/b"), QString());
    }

    void testPersistAcrossInstances()
    {
        QTemporaryDir dir;
        {
            FolderViewStore store(storePath(dir));
            store.rememberView("/keep", "detailed");
        }
        FolderViewStore reopened(storePath(dir));
        QCOMPARE(reopened.viewForFolder("/keep"), QString("detailed"));
    }

    void testGarbageFileToleratedAsEmpty()
    {
        QTemporaryDir dir;
        QFile f(storePath(dir));
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("not json at all {[");
        f.close();
        FolderViewStore store(storePath(dir));   // must not crash
        QCOMPARE(store.viewForFolder("/anything"), QString());
        store.rememberView("/ok", "grid");       // and stays usable
        QCOMPARE(store.viewForFolder("/ok"), QString("grid"));
    }
};

QTEST_MAIN(TestFolderViewStore)
#include "tst_folderviewstore.moc"
