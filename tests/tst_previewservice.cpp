#include <QTest>
#include <QDir>
#include <QFile>
#include <QPainter>
#include <QPdfWriter>
#include <QProcess>
#include <QSet>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QUuid>

#include "services/previewservice.h"

class TestPreviewService : public QObject
{
    Q_OBJECT

private:
    static bool batAvailable()
    {
        return !QStandardPaths::findExecutable("bat").isEmpty()
            || !QStandardPaths::findExecutable("batcat").isEmpty();
    }

    // Build a tiny uncompressed .tar so archive tests don't depend on
    // compression tools; tar -tf is what archiveListCommand() runs for .tar.
    // Returns the archive path, or empty on failure.
    static QString makeTar(const QString &dirPath, const QString &archiveName,
                           const QStringList &innerNames)
    {
        for (const QString &name : innerNames) {
            QFile f(dirPath + "/" + name);
            if (!f.open(QIODevice::WriteOnly))
                return {};
            f.write(name.toUtf8());
        }
        const QString archivePath = dirPath + "/" + archiveName;
        QProcess tar;
        tar.start("tar", QStringList{"-cf", archivePath, "-C", dirPath} << innerNames);
        if (!tar.waitForFinished(5000) || tar.exitCode() != 0)
            return {};
        return archivePath;
    }

    static QString findTrashEntryUri(const QString &originalPath)
    {
        QProcess proc;
        proc.start("gio", {
            "list",
            "-l",
            "-u",
            "-a",
            "trash::orig-path",
            "trash:///"
        });
        if (!proc.waitForFinished(5000) || proc.exitCode() != 0)
            return {};

        const QStringList lines = QString::fromUtf8(proc.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts);
        for (const QString &line : lines) {
            if (line.contains("trash::orig-path=" + originalPath))
                return line.section('\t', 0, 0).trimmed();
        }

        return {};
    }

private slots:
    void testLoadTextPreview()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        const QString path = dir.path() + "/notes.txt";
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("alpha\nbeta\ngamma\n");
        file.close();

        PreviewService service;
        const QVariantMap preview = service.loadTextPreview(path, 1024, 20);

        QCOMPARE(preview.value("error").toString(), QString());
        QCOMPARE(preview.value("isBinary").toBool(), false);
        QVERIFY(preview.value("content").toString().contains("beta"));
        if (batAvailable()) {
            QCOMPARE(preview.value("usesBat").toBool(), true);
            QVERIFY(preview.value("html").toString().contains("alpha"));
        }
    }

    void testBinaryPreviewDetection()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        const QString path = dir.path() + "/blob.bin";
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(QByteArray::fromHex("89504e470d0a1a0a00000000"));
        file.close();

        PreviewService service;
        const QVariantMap preview = service.loadTextPreview(path, 1024, 20);

        QCOMPARE(preview.value("isBinary").toBool(), true);
        QCOMPARE(preview.value("content").toString(), QString());
    }

    void testDirectoryPreview()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        QDir root(dir.path());
        QVERIFY(root.mkdir("Folder"));
        QFile file(root.filePath("alpha.txt"));
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("hello");
        file.close();

        PreviewService service;
        const QVariantMap preview = service.loadDirectoryPreview(dir.path(), 20);
        const QStringList entries = preview.value("entries").toStringList();

        QVERIFY(entries.contains("Folder/"));
        QVERIFY(entries.contains("alpha.txt"));
    }

    void testLocalPreviewPathForRegularFile()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        const QString path = dir.path() + "/doc.pdf";
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("dummy");
        file.close();

        PreviewService service;
        QCOMPARE(service.localPreviewPath(path), path);
    }

    void testLoadPdfPreview()
    {
        PreviewService service;
        if (!service.pdfPreviewAvailable())
            QSKIP("PDF preview support is unavailable in this build");

        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        const QString path = dir.path() + "/preview.pdf";
        QPdfWriter writer(path);
        writer.setPageSize(QPageSize(QPageSize::A4));
        QPainter painter(&writer);
        painter.drawText(QPointF(72.0, 100.0), QStringLiteral("Preview Test"));
        painter.end();

        const QVariantMap preview = service.loadPdfPreview(path);
        QCOMPARE(preview.value("error").toString(), QString());
        QCOMPARE(preview.value("localPath").toString(), path);
        QVERIFY(preview.value("pageCount").toInt() >= 1);
    }

    void testTrashTextPreview()
    {
        if (QStandardPaths::findExecutable("gio").isEmpty())
            QSKIP("gio not found in PATH");

        const QString uniqueId = QUuid::createUuid().toString(QUuid::WithoutBraces);
        const QString dirPath = QDir::homePath() + "/.cache/heimdall-test-preview-service-" + uniqueId;
        QDir().mkpath(dirPath);

        const QString filePath = dirPath + "/preview.txt";
        QFile file(filePath);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("trash preview text");
        file.close();

        QProcess trashProc;
        trashProc.start("gio", {"trash", filePath});
        if (!trashProc.waitForFinished(5000) || trashProc.exitCode() != 0)
            QSKIP("gio trash failed in this environment");

        const QString trashUri = findTrashEntryUri(filePath);
        if (trashUri.isEmpty())
            QSKIP("Could not find trashed file URI");

        PreviewService service;
        const QVariantMap preview = service.loadTextPreview(trashUri, 1024, 20);

        QCOMPARE(preview.value("error").toString(), QString());
        QCOMPARE(preview.value("isBinary").toBool(), false);
        QVERIFY(preview.value("content").toString().contains("trash preview text"));
        if (batAvailable())
            QCOMPARE(preview.value("usesBat").toBool(), true);

        const QString cachedPath = service.localPreviewPath(trashUri);
        QVERIFY(!cachedPath.isEmpty());
        QVERIFY(QFileInfo::exists(cachedPath));

        QProcess removeProc;
        removeProc.start("gio", {"remove", "-f", trashUri});
        removeProc.waitForFinished(5000);
        QDir(dirPath).removeRecursively();
    }

    void testRequestArchivePreviewAsync()
    {
        if (QStandardPaths::findExecutable("tar").isEmpty())
            QSKIP("tar not found in PATH");

        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString archivePath = makeTar(dir.path(), "test.tar", {"one.txt", "two.txt"});
        QVERIFY(!archivePath.isEmpty());

        PreviewService service;
        QSignalSpy spy(&service, &PreviewService::previewReady);
        service.requestArchivePreview(archivePath, 200);

        QVERIFY(spy.wait(10000));
        QCOMPARE(spy.count(), 1);

        const QList<QVariant> args = spy.takeFirst();
        QCOMPARE(args.at(0).toString(), QStringLiteral("archive")); // kind
        QCOMPARE(args.at(1).toString(), archivePath);               // path
        const QVariantMap result = args.at(2).toMap();
        QCOMPARE(result.value("error").toString(), QString());
        const QStringList entries = result.value("entries").toStringList();
        QVERIFY(entries.contains("one.txt"));
        QVERIFY(entries.contains("two.txt"));

        // Async result must have the same shape/content as the sync loader so
        // QML bindings (entries/truncated/error/count) behave identically.
        const QVariantMap sync = service.loadArchivePreview(archivePath, 200);
        QCOMPARE(result.value("entries").toStringList(), sync.value("entries").toStringList());
        QCOMPARE(result.value("truncated").toBool(), sync.value("truncated").toBool());
        QCOMPARE(result.value("count").toInt(), sync.value("count").toInt());
    }

    void testDuplicateArchiveRequestDeduped()
    {
        if (QStandardPaths::findExecutable("tar").isEmpty())
            QSKIP("tar not found in PATH");

        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString archivePath = makeTar(dir.path(), "dup.tar", {"inner.txt"});
        QVERIFY(!archivePath.isEmpty());

        PreviewService service;
        QSignalSpy spy(&service, &PreviewService::previewReady);
        // Two requests for the SAME path before the event loop spins: the
        // second must be deduped onto the first's in-flight process, so exactly
        // one previewReady is emitted.
        service.requestArchivePreview(archivePath, 200);
        service.requestArchivePreview(archivePath, 200);

        QVERIFY(spy.wait(10000));
        QTest::qWait(200); // give any erroneous second emission time to arrive
        QCOMPARE(spy.count(), 1);
    }

    void testConcurrentArchivePreviewsBothEmit()
    {
        // Regression: previewService is shared across every supertab pane's
        // FileMillerView plus the global QuickPreview. A single in-flight slot
        // would let a second consumer's request cancel the first's process,
        // leaving that consumer stuck on "Listing archive…" forever. Two
        // concurrent requests for DIFFERENT paths must each emit.
        if (QStandardPaths::findExecutable("tar").isEmpty())
            QSKIP("tar not found in PATH");

        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString a = makeTar(dir.path(), "alpha.tar", {"a_inner.txt"});
        const QString b = makeTar(dir.path(), "beta.tar", {"b_inner.txt"});
        QVERIFY(!a.isEmpty());
        QVERIFY(!b.isEmpty());

        PreviewService service;
        QSignalSpy spy(&service, &PreviewService::previewReady);
        service.requestArchivePreview(a, 200);
        service.requestArchivePreview(b, 200);

        QSet<QString> seenPaths;
        while (seenPaths.size() < 2 && spy.wait(5000)) {
            while (!spy.isEmpty())
                seenPaths.insert(spy.takeFirst().at(1).toString());
        }
        while (!spy.isEmpty())
            seenPaths.insert(spy.takeFirst().at(1).toString());

        QVERIFY2(seenPaths.contains(a), "first archive listing was lost (single-slot regression)");
        QVERIFY2(seenPaths.contains(b), "second archive listing was lost");
    }
};

QTEST_MAIN(TestPreviewService)
#include "tst_previewservice.moc"
