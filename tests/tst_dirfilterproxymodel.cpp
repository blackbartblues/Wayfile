#include <QTest>
#include <QSignalSpy>
#include <QStandardPaths>
#include "models/dirfilterproxymodel.h"
#include "models/filesystemmodel.h"
#include "testdir.h"

// Unit tests for DirFilterProxyModel — the folders-only / files-only split
// proxy that backs the hybrid view's two sections.
class TestDirFilterProxyModel : public QObject
{
    Q_OBJECT

    // Build a model over a fixture with 3 folders + 4 files and return it.
    static void populate(TestDir &dir)
    {
        dir.createDir("alpha");
        dir.createDir("Beta");
        dir.createDir("gamma");
        dir.createFile("one.txt", "aaaa");        // 4 bytes
        dir.createFile("two.md", "bb");           // 2 bytes
        dir.createFile("Three.json", "cccccc");   // 6 bytes
        dir.createFile("four.png", "d");          // 1 byte
    }

    static int rowForName(const QAbstractItemModel &m, const QString &name)
    {
        for (int r = 0; r < m.rowCount(); ++r)
            if (m.data(m.index(r, 0), FileSystemModel::FileNameRole).toString() == name)
                return r;
        return -1;
    }

private slots:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
    }

    void testFoldersOnlyKeepsOnlyDirectories()
    {
        TestDir dir; populate(dir);
        FileSystemModel model; model.setSynchronousReload(true);
        model.setRootPath(dir.path());

        DirFilterProxyModel proxy;
        proxy.setMode(DirFilterProxyModel::FoldersOnly);
        proxy.setSourceModel(&model);

        QCOMPARE(proxy.rowCount(), 3);
        for (int r = 0; r < proxy.rowCount(); ++r)
            QVERIFY(proxy.isDir(r));
    }

    void testFilesOnlyKeepsOnlyFiles()
    {
        TestDir dir; populate(dir);
        FileSystemModel model; model.setSynchronousReload(true);
        model.setRootPath(dir.path());

        DirFilterProxyModel proxy;
        proxy.setMode(DirFilterProxyModel::FilesOnly);
        proxy.setSourceModel(&model);

        QCOMPARE(proxy.rowCount(), 4);
        for (int r = 0; r < proxy.rowCount(); ++r)
            QVERIFY(!proxy.isDir(r));
    }

    void testSetModeEmitsAndReFilters()
    {
        TestDir dir; populate(dir);
        FileSystemModel model; model.setSynchronousReload(true);
        model.setRootPath(dir.path());

        DirFilterProxyModel proxy;
        proxy.setSourceModel(&model);   // default FilesOnly
        QCOMPARE(proxy.rowCount(), 4);

        QSignalSpy spy(&proxy, &DirFilterProxyModel::modeChanged);
        proxy.setMode(DirFilterProxyModel::FoldersOnly);
        QCOMPARE(spy.count(), 1);
        QCOMPARE(proxy.rowCount(), 3);

        // Same value -> no signal.
        proxy.setMode(DirFilterProxyModel::FoldersOnly);
        QCOMPARE(spy.count(), 1);
    }

    void testFilesSortByNameIndependentOfFolders()
    {
        TestDir dir; populate(dir);
        FileSystemModel model; model.setSynchronousReload(true);
        model.setRootPath(dir.path());

        DirFilterProxyModel files;
        files.setMode(DirFilterProxyModel::FilesOnly);
        files.setSourceModel(&model);

        files.sortByColumn("name", true);   // ascending, case-insensitive
        QStringList asc;
        for (int r = 0; r < files.rowCount(); ++r)
            asc << files.fileName(r);
        QCOMPARE(asc, (QStringList{"four.png", "one.txt", "Three.json", "two.md"}));

        files.sortByColumn("name", false);  // descending
        QStringList desc;
        for (int r = 0; r < files.rowCount(); ++r)
            desc << files.fileName(r);
        QStringList expectedDesc = asc;
        std::reverse(expectedDesc.begin(), expectedDesc.end());
        QCOMPARE(desc, expectedDesc);
    }

    void testFilesSortBySize()
    {
        TestDir dir; populate(dir);
        FileSystemModel model; model.setSynchronousReload(true);
        model.setRootPath(dir.path());

        DirFilterProxyModel files;
        files.setMode(DirFilterProxyModel::FilesOnly);
        files.setSourceModel(&model);

        files.sortByColumn("size", true);   // ascending by byte size
        QStringList bySize;
        for (int r = 0; r < files.rowCount(); ++r)
            bySize << files.fileName(r);
        // 1, 2, 4, 6 bytes -> four.png, two.md, one.txt, Three.json
        QCOMPARE(bySize, (QStringList{"four.png", "two.md", "one.txt", "Three.json"}));
    }

    void testRowMappingRoundTrips()
    {
        TestDir dir; populate(dir);
        FileSystemModel model; model.setSynchronousReload(true);
        model.setRootPath(dir.path());

        DirFilterProxyModel files;
        files.setMode(DirFilterProxyModel::FilesOnly);
        files.setSourceModel(&model);

        const int sourceRow = rowForName(model, "two.md");
        QVERIFY(sourceRow >= 0);
        const int proxyRow = files.mapRowFromSource(sourceRow);
        QVERIFY(proxyRow >= 0);
        QCOMPARE(files.mapRowToSource(proxyRow), sourceRow);
        QCOMPARE(files.fileName(proxyRow), QString("two.md"));

        // A folder maps to -1 in the files-only proxy.
        const int folderSourceRow = rowForName(model, "alpha");
        QVERIFY(folderSourceRow >= 0);
        QCOMPARE(files.mapRowFromSource(folderSourceRow), -1);
    }

    void testRoleNamesInheritedFromSource()
    {
        FileSystemModel model; model.setSynchronousReload(true);
        DirFilterProxyModel proxy;
        proxy.setSourceModel(&model);

        const auto roles = proxy.roleNames();
        QVERIFY(roles.values().contains(QByteArray("fileName")));
        QVERIFY(roles.values().contains(QByteArray("isDir")));
        QVERIFY(roles.values().contains(QByteArray("fileCategory")));
    }

    void testMediaKeepsOnlyPreviewableMedia()
    {
        TestDir dir;
        dir.createDir("sub");
        dir.createFile("pic.png",   "d");   // image
        dir.createFile("clip.mp4",  "d");   // video
        dir.createFile("song.mp3",  "d");   // audio
        dir.createFile("doc.pdf",   "d");   // pdf (category "document", matched by extension)
        dir.createFile("notes.txt", "aaa"); // document -> excluded
        dir.createFile("arch.zip",  "bb");  // archive -> excluded

        FileSystemModel model; model.setSynchronousReload(true);
        model.setRootPath(dir.path());

        DirFilterProxyModel proxy;
        proxy.setMode(DirFilterProxyModel::Media);
        proxy.setSourceModel(&model);

        QCOMPARE(proxy.rowCount(), 4);
        QVERIFY(rowForName(proxy, "pic.png")  >= 0);
        QVERIFY(rowForName(proxy, "doc.pdf")  >= 0);
        QVERIFY(rowForName(proxy, "clip.mp4") >= 0);
        QVERIFY(rowForName(proxy, "song.mp3") >= 0);
        QCOMPARE(rowForName(proxy, "notes.txt"), -1);
        QCOMPARE(rowForName(proxy, "arch.zip"),  -1);
        QCOMPARE(rowForName(proxy, "sub"),       -1);
        for (int r = 0; r < proxy.rowCount(); ++r)
            QVERIFY(!proxy.isDir(r));
    }
};

QTEST_MAIN(TestDirFilterProxyModel)
#include "tst_dirfilterproxymodel.moc"
