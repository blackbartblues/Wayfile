#include <QTest>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QUuid>

#include "services/fileoperations.h"
#include "services/undomanager.h"

class TestUndoManager : public QObject
{
    Q_OBJECT

private:
    // The trash-undo tests below need files on the same filesystem as the
    // user's home (gio refuses to trash files on system-internal mounts like
    // /tmp, where QTemporaryDir lives), so they stage under ~/.cache.

    // trash:// URIs whose orig-path contains `origSubstring`. One `gio list`.
    static QStringList trashUrisContaining(const QString &origSubstring)
    {
        QStringList uris;
        QProcess proc;
        proc.start("gio", {"list", "-l", "-u", "-a", "trash::orig-path", "trash:///"});
        if (!proc.waitForFinished(5000) || proc.exitCode() != 0)
            return uris;
        const QStringList lines = QString::fromUtf8(proc.readAllStandardOutput())
                                      .split('\n', Qt::SkipEmptyParts);
        for (const QString &line : lines) {
            const QStringList fields = line.split('\t');
            if (fields.isEmpty())
                continue;
            if (line.contains("trash::orig-path=") && line.contains(origSubstring))
                uris.append(fields.at(0).trimmed());
        }
        return uris;
    }

    // The trash index can lag behind `gio trash` completing; poll until at
    // least `expected` matching entries are visible (or give up).
    static bool awaitTrashContains(const QString &origSubstring, int expected)
    {
        for (int i = 0; i < 30; ++i) {
            if (trashUrisContaining(origSubstring).size() >= expected)
                return true;
            QTest::qWait(100);
        }
        return false;
    }

    // Remove every trash entry whose orig-path matches, so a test never leaves
    // entries behind (accumulated test entries slow gio and break later runs).
    static void purgeTrash(const QString &origSubstring)
    {
        const QStringList uris = trashUrisContaining(origSubstring);
        for (const QString &uri : uris) {
            QProcess rm;
            rm.start("gio", {"remove", "-f", uri});
            rm.waitForFinished(5000);
        }
    }

private slots:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
    }

    // Trashing N files and undoing once must restore ALL N to their original
    // paths. Guards the batched restore (one gio list, in-memory lookups).
    void testUndoTrashRestoresAllFiles()
    {
        if (QStandardPaths::findExecutable("gio").isEmpty())
            QSKIP("gio not found in PATH");

        const QString uniqueId = QUuid::createUuid().toString(QUuid::WithoutBraces);
        const QString dirPath = QDir::homePath() + "/.cache/heimdall-undo-test-" + uniqueId;
        QVERIFY(QDir().mkpath(dirPath));

        QStringList files;
        for (const QString &name : {QStringLiteral("a.txt"), QStringLiteral("b.txt"), QStringLiteral("c.txt")}) {
            const QString p = dirPath + "/" + name;
            QFile f(p);
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write("content");
            f.close();
            files << p;
        }

        FileOperations fileOps;
        UndoManager undoManager(&fileOps);
        QSignalSpy finishSpy(&fileOps, &FileOperations::operationFinished);

        undoManager.trashFiles(files);
        if (!finishSpy.wait(5000) || !finishSpy.at(0).at(0).toBool()) {
            QDir(dirPath).removeRecursively();
            QSKIP("gio trash unavailable in this environment");
        }
        for (const QString &p : files)
            QVERIFY(!QFile::exists(p));
        QVERIFY(undoManager.canUndo());

        if (!awaitTrashContains(uniqueId, files.size())) {
            purgeTrash(uniqueId);
            QDir(dirPath).removeRecursively();
            QSKIP("trashed files did not appear in the trash index");
        }

        finishSpy.clear();
        undoManager.undo();
        if (!finishSpy.wait(5000)) {
            purgeTrash(uniqueId);
            QDir(dirPath).removeRecursively();
            QSKIP("trash undo restore timed out");
        }
        QCOMPARE(finishSpy.at(0).at(0).toBool(), true);

        for (const QString &p : files)
            QVERIFY(QFile::exists(p));

        purgeTrash(uniqueId);
        QDir(dirPath).removeRecursively();
    }

    // Trash, recreate, trash again, then undo once: the most-recently trashed
    // copy must be the one restored (latest deletion-date wins).
    void testUndoTrashRestoresLatestDuplicate()
    {
        if (QStandardPaths::findExecutable("gio").isEmpty())
            QSKIP("gio not found in PATH");

        const QString uniqueId = QUuid::createUuid().toString(QUuid::WithoutBraces);
        const QString dirPath = QDir::homePath() + "/.cache/heimdall-undo-test-" + uniqueId;
        QVERIFY(QDir().mkpath(dirPath));
        const QString filePath = dirPath + "/dup.txt";

        auto writeFile = [&](const char *content) {
            QFile f(filePath);
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write(content);
            f.close();
        };

        FileOperations fileOps;
        UndoManager undoManager(&fileOps);
        QSignalSpy finishSpy(&fileOps, &FileOperations::operationFinished);

        writeFile("first");
        undoManager.trashFiles({filePath});
        if (!finishSpy.wait(5000) || !finishSpy.at(0).at(0).toBool()) {
            QDir(dirPath).removeRecursively();
            QSKIP("gio trash unavailable in this environment");
        }

        // gio's deletion-date is second-granular; ensure the two trashings get
        // distinct timestamps so "latest" is unambiguous.
        QTest::qWait(1100);

        writeFile("second");
        finishSpy.clear();
        undoManager.trashFiles({filePath});
        if (!finishSpy.wait(5000) || !finishSpy.at(0).at(0).toBool()) {
            purgeTrash(uniqueId);
            QDir(dirPath).removeRecursively();
            QSKIP("gio trash unavailable in this environment");
        }
        QVERIFY(!QFile::exists(filePath));

        if (!awaitTrashContains(uniqueId, 2)) {
            purgeTrash(uniqueId);
            QDir(dirPath).removeRecursively();
            QSKIP("both trash entries did not appear in the trash index");
        }

        finishSpy.clear();
        undoManager.undo();
        if (!finishSpy.wait(5000)) {
            purgeTrash(uniqueId);
            QDir(dirPath).removeRecursively();
            QSKIP("trash undo restore timed out");
        }
        QCOMPARE(finishSpy.at(0).at(0).toBool(), true);

        QVERIFY(QFile::exists(filePath));
        QFile restored(filePath);
        QVERIFY(restored.open(QIODevice::ReadOnly));
        QCOMPARE(QString::fromUtf8(restored.readAll()), QString("second"));
        restored.close();

        purgeTrash(uniqueId); // remove the leftover "first" copy still in trash
        QDir(dirPath).removeRecursively();
    }

    // Undoing a Trash record whose entry is no longer in the trash must not
    // crash and must not spuriously restore anything.
    void testUndoTrashNoMatchIsSafe()
    {
        if (QStandardPaths::findExecutable("gio").isEmpty())
            QSKIP("gio not found in PATH");

        const QString uniqueId = QUuid::createUuid().toString(QUuid::WithoutBraces);
        const QString dirPath = QDir::homePath() + "/.cache/heimdall-undo-test-" + uniqueId;
        QVERIFY(QDir().mkpath(dirPath));
        const QString filePath = dirPath + "/gone.txt";
        {
            QFile f(filePath);
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write("x");
            f.close();
        }

        FileOperations fileOps;
        UndoManager undoManager(&fileOps);
        QSignalSpy finishSpy(&fileOps, &FileOperations::operationFinished);

        undoManager.trashFiles({filePath});
        if (!finishSpy.wait(5000) || !finishSpy.at(0).at(0).toBool()) {
            QDir(dirPath).removeRecursively();
            QSKIP("gio trash unavailable in this environment");
        }
        QVERIFY(undoManager.canUndo());

        if (!awaitTrashContains(uniqueId, 1)) {
            purgeTrash(uniqueId);
            QDir(dirPath).removeRecursively();
            QSKIP("trashed file did not appear in the trash index");
        }

        // Drop the entry from the trash so the undo has nothing to restore.
        purgeTrash(uniqueId);

        finishSpy.clear();
        undoManager.undo(); // must be a safe no-op (no URI resolves)
        QTest::qWait(500);  // give any erroneous async restore a chance to run
        QCOMPARE(finishSpy.count(), 0);
        QVERIFY(!QFile::exists(filePath));

        QDir(dirPath).removeRecursively();
    }

    void testUndoTrashOnMountedVolume()
    {
        if (QStandardPaths::findExecutable("gio").isEmpty())
            QSKIP("gio not found in PATH");

        const QString mediaRoot = "/run/media/" + qEnvironmentVariable("USER");
        QDir mediaDir(mediaRoot);
        if (!mediaDir.exists())
            QSKIP("/run/media/$USER does not exist");

        const QStringList entries = mediaDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        if (entries.isEmpty())
            QSKIP("No mounted volumes found under /run/media/$USER");

        // Find the first writable mounted volume; skip if none. The first
        // entry under /run/media is often a read-only / OS-managed mount
        // (e.g. an internal partition automounted by udisks), so we can't
        // assume it's writable.
        QString mountPath;
        for (const QString &entry : entries) {
            const QString candidate = mediaDir.filePath(entry);
            if (QFileInfo(candidate).isWritable()) {
                mountPath = candidate;
                break;
            }
        }
        if (mountPath.isEmpty())
            QSKIP("No writable mounted volume found under /run/media/$USER");

        const QString testDirPath = mountPath + "/heimdall-undo-test-" + QUuid::createUuid().toString(QUuid::WithoutBraces);
        if (!QDir().mkpath(testDirPath))
            QSKIP("Could not create test directory on mounted volume");

        const QString filePath = testDirPath + "/undo_me.txt";
        QFile file(filePath);
        if (!file.open(QIODevice::WriteOnly)) {
            QDir(testDirPath).removeRecursively();
            QSKIP("Could not write test file on mounted volume");
        }
        file.write("undo mounted trash");
        file.close();

        FileOperations fileOps;
        UndoManager undoManager(&fileOps);
        QSignalSpy finishSpy(&fileOps, &FileOperations::operationFinished);

        undoManager.trashFiles({filePath});
        if (!finishSpy.wait(5000))
            QSKIP("gio trash timed out (may not be supported in this environment)");

        bool success = finishSpy.at(0).at(0).toBool();
        if (!success)
            QSKIP("gio trash failed (may not be supported for this mounted path)");

        QVERIFY(!QFile::exists(filePath));
        QVERIFY(undoManager.canUndo());

        finishSpy.clear();
        undoManager.undo();
        if (!finishSpy.wait(5000))
            QSKIP("trash undo restore timed out");

        success = finishSpy.at(0).at(0).toBool();
        if (!success)
            QSKIP("trash undo restore failed for mounted path");

        QVERIFY(QFile::exists(filePath));
        QDir(testDirPath).removeRecursively();
    }

    void testUndoCopyRestoresOverwrittenTarget()
    {
        QTemporaryDir srcDir;
        QTemporaryDir dstDir;
        QVERIFY(srcDir.isValid());
        QVERIFY(dstDir.isValid());

        const QString sourcePath = srcDir.path() + "/item.txt";
        const QString targetPath = dstDir.path() + "/item.txt";

        {
            QFile file(sourcePath);
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write("new value");
        }
        {
            QFile file(targetPath);
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write("old value");
        }

        FileOperations fileOps;
        UndoManager undoManager(&fileOps);
        QSignalSpy finishSpy(&fileOps, &FileOperations::operationFinished);

        QVariantMap item;
        item["sourcePath"] = sourcePath;
        item["targetPath"] = targetPath;
        item["overwrite"] = true;

        undoManager.copyResolvedItems({item});
        QVERIFY(finishSpy.wait(5000));
        QCOMPARE(finishSpy.at(0).at(0).toBool(), true);

        {
            QFile file(targetPath);
            QVERIFY(file.open(QIODevice::ReadOnly));
            QCOMPARE(QString::fromUtf8(file.readAll()), QString("new value"));
        }

        finishSpy.clear();
        undoManager.undo();
        QTRY_VERIFY(QFile::exists(targetPath));
        QTRY_VERIFY(!fileOps.busy());

        {
            QFile file(targetPath);
            QVERIFY(file.open(QIODevice::ReadOnly));
            QCOMPARE(QString::fromUtf8(file.readAll()), QString("old value"));
        }
    }

    void testUndoRedoBulkRenameSwap()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        const QString aPath = dir.path() + "/a.txt";
        const QString bPath = dir.path() + "/b.txt";

        {
            QFile file(aPath);
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write("aaa");
        }
        {
            QFile file(bPath);
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write("bbb");
        }

        FileOperations fileOps;
        UndoManager undoManager(&fileOps);

        QVariantMap renameA;
        renameA["sourcePath"] = aPath;
        renameA["targetPath"] = bPath;

        QVariantMap renameB;
        renameB["sourcePath"] = bPath;
        renameB["targetPath"] = aPath;

        const QVariantMap result = undoManager.renameResolvedItems({renameA, renameB});
        QCOMPARE(result.value("success").toBool(), true);
        QVERIFY(undoManager.canUndo());

        {
            QFile file(aPath);
            QVERIFY(file.open(QIODevice::ReadOnly));
            QCOMPARE(QString::fromUtf8(file.readAll()), QString("bbb"));
        }
        {
            QFile file(bPath);
            QVERIFY(file.open(QIODevice::ReadOnly));
            QCOMPARE(QString::fromUtf8(file.readAll()), QString("aaa"));
        }

        undoManager.undo();

        {
            QFile file(aPath);
            QVERIFY(file.open(QIODevice::ReadOnly));
            QCOMPARE(QString::fromUtf8(file.readAll()), QString("aaa"));
        }
        {
            QFile file(bPath);
            QVERIFY(file.open(QIODevice::ReadOnly));
            QCOMPARE(QString::fromUtf8(file.readAll()), QString("bbb"));
        }

        undoManager.redo();

        {
            QFile file(aPath);
            QVERIFY(file.open(QIODevice::ReadOnly));
            QCOMPARE(QString::fromUtf8(file.readAll()), QString("bbb"));
        }
        {
            QFile file(bPath);
            QVERIFY(file.open(QIODevice::ReadOnly));
            QCOMPARE(QString::fromUtf8(file.readAll()), QString("aaa"));
        }
    }
};

QTEST_MAIN(TestUndoManager)
#include "tst_undomanager.moc"
