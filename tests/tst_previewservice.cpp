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

    // gio's trash index can lag a moment behind `gio trash`, so a single lookup
    // right after trashing sometimes misses. Retry briefly so the async trash
    // tests reliably run instead of skipping on a transient empty result.
    static QString awaitTrashEntryUri(const QString &originalPath)
    {
        QString uri;
        for (int i = 0; i < 20 && uri.isEmpty(); ++i) {
            uri = findTrashEntryUri(originalPath);
            if (uri.isEmpty())
                QTest::qWait(100);
        }
        return uri;
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

    void testRequestTrashTextAsync()
    {
        if (QStandardPaths::findExecutable("gio").isEmpty())
            QSKIP("gio not found in PATH");

        const QString uniqueId = QUuid::createUuid().toString(QUuid::WithoutBraces);
        const QString dirPath = QDir::homePath() + "/.cache/heimdall-test-preview-service-" + uniqueId;
        QDir().mkpath(dirPath);

        const QString filePath = dirPath + "/async-preview.txt";
        QFile file(filePath);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("async trash preview text");
        file.close();

        QProcess trashProc;
        trashProc.start("gio", {"trash", filePath});
        if (!trashProc.waitForFinished(5000) || trashProc.exitCode() != 0)
            QSKIP("gio trash failed in this environment");

        const QString trashUri = awaitTrashEntryUri(filePath);
        if (trashUri.isEmpty())
            QSKIP("Could not find trashed file URI");

        PreviewService service;
        QSignalSpy spy(&service, &PreviewService::previewReady);
        service.requestTrashText(trashUri, 1024, 20);

        QVERIFY(spy.wait(10000));
        QCOMPARE(spy.count(), 1);

        const QList<QVariant> args = spy.takeFirst();
        QCOMPARE(args.at(0).toString(), QStringLiteral("text")); // kind
        QCOMPARE(args.at(1).toString(), trashUri);               // path
        const QVariantMap result = args.at(2).toMap();
        QCOMPARE(result.value("error").toString(), QString());
        QCOMPARE(result.value("isBinary").toBool(), false);
        QVERIFY(result.value("content").toString().contains("async trash preview text"));

        // Async result must match the sync plain loader's shape/content so QML
        // bindings (content/truncated/isBinary) behave identically.
        const QVariantMap sync = service.loadTextPlain(trashUri, 1024, 20);
        QCOMPARE(result.value("content").toString(), sync.value("content").toString());
        QCOMPARE(result.value("truncated").toBool(), sync.value("truncated").toBool());
        QCOMPARE(result.value("isBinary").toBool(), sync.value("isBinary").toBool());

        QProcess removeProc;
        removeProc.start("gio", {"remove", "-f", trashUri});
        removeProc.waitForFinished(5000);
        QDir(dirPath).removeRecursively();
    }

    void testDuplicateTrashTextRequestDeduped()
    {
        if (QStandardPaths::findExecutable("gio").isEmpty())
            QSKIP("gio not found in PATH");

        const QString uniqueId = QUuid::createUuid().toString(QUuid::WithoutBraces);
        const QString dirPath = QDir::homePath() + "/.cache/heimdall-test-preview-service-" + uniqueId;
        QDir().mkpath(dirPath);

        const QString filePath = dirPath + "/dup-preview.txt";
        QFile file(filePath);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("dup trash preview text");
        file.close();

        QProcess trashProc;
        trashProc.start("gio", {"trash", filePath});
        if (!trashProc.waitForFinished(5000) || trashProc.exitCode() != 0)
            QSKIP("gio trash failed in this environment");

        const QString trashUri = awaitTrashEntryUri(filePath);
        if (trashUri.isEmpty())
            QSKIP("Could not find trashed file URI");

        PreviewService service;
        QSignalSpy spy(&service, &PreviewService::previewReady);
        // Two requests for the SAME path before the event loop spins: the second
        // must dedup onto the first's in-flight gio cat, so exactly one emit.
        service.requestTrashText(trashUri, 1024, 20);
        service.requestTrashText(trashUri, 1024, 20);

        QVERIFY(spy.wait(10000));
        QTest::qWait(200); // give any erroneous second emission time to arrive
        QCOMPARE(spy.count(), 1);

        QProcess removeProc;
        removeProc.start("gio", {"remove", "-f", trashUri});
        removeProc.waitForFinished(5000);
        QDir(dirPath).removeRecursively();
    }

    void testRequestDirectoryPreviewAsync()
    {
        if (QStandardPaths::findExecutable("gio").isEmpty())
            QSKIP("gio not found in PATH");

        const QString uniqueId = QUuid::createUuid().toString(QUuid::WithoutBraces);
        const QString dirPath = QDir::homePath() + "/.cache/heimdall-test-preview-service-" + uniqueId;
        QDir().mkpath(dirPath);

        const QString innerDir = dirPath + "/trashed-folder";
        QDir().mkpath(innerDir);
        for (const QString &name : {QStringLiteral("one.txt"), QStringLiteral("two.txt")}) {
            QFile f(innerDir + "/" + name);
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write("x");
            f.close();
        }

        QProcess trashProc;
        trashProc.start("gio", {"trash", innerDir});
        if (!trashProc.waitForFinished(5000) || trashProc.exitCode() != 0)
            QSKIP("gio trash failed in this environment");

        const QString trashUri = awaitTrashEntryUri(innerDir);
        if (trashUri.isEmpty())
            QSKIP("Could not find trashed folder URI");

        PreviewService service;
        QSignalSpy spy(&service, &PreviewService::previewReady);
        service.requestDirectoryPreview(trashUri, 40);

        QVERIFY(spy.wait(10000));
        QCOMPARE(spy.count(), 1);

        const QList<QVariant> args = spy.takeFirst();
        QCOMPARE(args.at(0).toString(), QStringLiteral("directory")); // kind
        QCOMPARE(args.at(1).toString(), trashUri);                    // path
        const QVariantMap result = args.at(2).toMap();
        QCOMPARE(result.value("error").toString(), QString());
        const QStringList entries = result.value("entries").toStringList();
        const QString joined = entries.join('\n');
        QVERIFY(joined.contains("one.txt"));
        QVERIFY(joined.contains("two.txt"));
        QCOMPARE(result.value("count").toInt(), entries.size());

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

    // Write a tiny valid single-page PDF via QPdfWriter so the async pdf tests
    // don't depend on any external PDF fixture. Returns the path, or empty.
    static QString makePdf(const QString &dirPath, const QString &name)
    {
        const QString path = dirPath + "/" + name;
        QPdfWriter writer(path);
        writer.setPageSize(QPageSize(QPageSize::A4));
        QPainter painter(&writer);
        painter.drawText(QPointF(72.0, 100.0), QStringLiteral("Async PDF Test"));
        painter.end();
        return QFileInfo::exists(path) ? path : QString();
    }

    void testRequestPdfPreviewAsync()
    {
        PreviewService service;
        if (!service.pdfPreviewAvailable())
            QSKIP("PDF preview support is unavailable in this build");

        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString pdfPath = makePdf(dir.path(), "async.pdf");
        QVERIFY(!pdfPath.isEmpty());

        QSignalSpy spy(&service, &PreviewService::previewReady);
        service.requestPdfPreview(pdfPath);

        QVERIFY(spy.wait(10000));
        QCOMPARE(spy.count(), 1);

        const QList<QVariant> args = spy.takeFirst();
        QCOMPARE(args.at(0).toString(), QStringLiteral("pdf")); // kind
        QCOMPARE(args.at(1).toString(), pdfPath);               // path
        const QVariantMap result = args.at(2).toMap();

        // Async result must be byte-for-byte identical to the sync loader for
        // localPath/pageCount/error so QML bindings behave the same.
        const QVariantMap sync = service.loadPdfPreview(pdfPath);
        QCOMPARE(result.value("error").toString(), sync.value("error").toString());
        QCOMPARE(result.value("localPath").toString(), sync.value("localPath").toString());
        QCOMPARE(result.value("pageCount").toInt(), sync.value("pageCount").toInt());
        QCOMPARE(result.value("error").toString(), QString());
        QCOMPARE(result.value("localPath").toString(), pdfPath);
        QVERIFY(result.value("pageCount").toInt() >= 1);
    }

    void testDuplicatePdfRequestDeduped()
    {
        PreviewService service;
        if (!service.pdfPreviewAvailable())
            QSKIP("PDF preview support is unavailable in this build");

        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString pdfPath = makePdf(dir.path(), "dup.pdf");
        QVERIFY(!pdfPath.isEmpty());

        QSignalSpy spy(&service, &PreviewService::previewReady);
        // Two requests for the SAME path before the event loop spins: the
        // second must be deduped onto the first's in-flight process, so exactly
        // one previewReady is emitted.
        service.requestPdfPreview(pdfPath);
        service.requestPdfPreview(pdfPath);

        QVERIFY(spy.wait(10000));
        QTest::qWait(200); // give any erroneous second emission time to arrive
        QCOMPARE(spy.count(), 1);
    }

    void testConcurrentPdfPreviewsBothEmit()
    {
        // Regression: previewService is shared across every supertab pane's
        // FileMillerView plus the global QuickPreview. A single in-flight slot
        // would let a second consumer's request cancel the first's pdfinfo,
        // leaving that consumer stuck on "Reading PDF…" forever. Two concurrent
        // requests for DIFFERENT paths must each emit.
        PreviewService service;
        if (!service.pdfPreviewAvailable())
            QSKIP("PDF preview support is unavailable in this build");

        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString a = makePdf(dir.path(), "alpha.pdf");
        const QString b = makePdf(dir.path(), "beta.pdf");
        QVERIFY(!a.isEmpty());
        QVERIFY(!b.isEmpty());

        QSignalSpy spy(&service, &PreviewService::previewReady);
        service.requestPdfPreview(a);
        service.requestPdfPreview(b);

        QSet<QString> seenPaths;
        while (seenPaths.size() < 2 && spy.wait(5000)) {
            while (!spy.isEmpty())
                seenPaths.insert(spy.takeFirst().at(1).toString());
        }
        while (!spy.isEmpty())
            seenPaths.insert(spy.takeFirst().at(1).toString());

        QVERIFY2(seenPaths.contains(a), "first pdf preview was lost (single-slot regression)");
        QVERIFY2(seenPaths.contains(b), "second pdf preview was lost");
    }

    void testLargeTextFileBatOutputBounded()
    {
        // Repro for the large-file freeze/RAM bug: bat must highlight only the capped bytes, not the whole file.
        if (QStandardPaths::findExecutable("bat").isEmpty() && QStandardPaths::findExecutable("batcat").isEmpty())
            QSKIP("bat not installed");
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString p = dir.path() + "/big.html";
        QFile f(p);
        QVERIFY(f.open(QIODevice::WriteOnly));
        // A single ~3 MB line — exactly the pathological shape (long line + large file).
        f.write("<div class=\"x\">");
        f.write(QByteArray(3 * 1024 * 1024, 'a'));
        f.write("</div>\n");
        f.close();

        PreviewService service;
        const QVariantMap r = service.loadTextPreview(p);   // default maxBytes=131072, maxLines=400
        // content is always capped:
        QVERIFY(r.value("content").toString().toUtf8().size() <= 131072 + 8);
        // If bat ran, its html MUST be bounded by the cap, not derived from the full 3 MB file.
        if (r.value("usesBat").toBool()) {
            const int htmlBytes = r.value("html").toString().toUtf8().size();
            QVERIFY2(htmlBytes < 1024 * 1024,
                     qPrintable(QStringLiteral("bat html must be bounded by the byte cap; got %1 bytes").arg(htmlBytes)));
        }
    }

    void testRequestTextHighlightAsync()
    {
        if (!batAvailable())
            QSKIP("bat not installed");

        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.path() + "/highlight.txt";
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("alpha\nbeta\ngamma\n");
        file.close();

        PreviewService service;
        QSignalSpy spy(&service, &PreviewService::previewReady);
        service.requestTextHighlight(path);

        QVERIFY(spy.wait(10000));
        QCOMPARE(spy.count(), 1);

        const QList<QVariant> args = spy.takeFirst();
        QCOMPARE(args.at(0).toString(), QStringLiteral("text")); // kind
        QCOMPARE(args.at(1).toString(), path);                   // path
        const QVariantMap result = args.at(2).toMap();

        QCOMPARE(result.value("error").toString(), QString());
        QCOMPARE(result.value("isBinary").toBool(), false);
        QCOMPARE(result.value("usesBat").toBool(), true);
        QVERIFY(!result.value("html").toString().isEmpty());

        // The async result is a superset of the plain one: identical content so
        // the highlight fades in over the same text, plus html/usesBat.
        const QVariantMap plain = service.loadTextPlain(path);
        QCOMPARE(result.value("content").toString(), plain.value("content").toString());
        QVERIFY(result.value("content").toString().contains("beta"));
    }

    void testTextHighlightWithoutBatEmitsPlain()
    {
        // No process is spawned when there's nothing to highlight; the plain
        // result must still be emitted so the preview shows the file. Use a
        // binary file so this holds whether or not bat is installed.
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.path() + "/blob.bin";
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(QByteArray::fromHex("89504e470d0a1a0a00000000"));
        file.close();

        PreviewService service;
        QSignalSpy spy(&service, &PreviewService::previewReady);
        // No bat process is spawned, so previewReady fires synchronously during
        // the call — assert directly rather than waiting for a queued signal.
        service.requestTextHighlight(path);

        QCOMPARE(spy.count(), 1);
        const QList<QVariant> args = spy.takeFirst();
        QCOMPARE(args.at(0).toString(), QStringLiteral("text"));
        QCOMPARE(args.at(1).toString(), path);
        const QVariantMap result = args.at(2).toMap();
        QCOMPARE(result.value("isBinary").toBool(), true);
        QCOMPARE(result.value("usesBat").toBool(), false);
    }

    void testDuplicateTextHighlightDeduped()
    {
        if (!batAvailable())
            QSKIP("bat not installed");

        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.path() + "/dup.txt";
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("one\ntwo\n");
        file.close();

        PreviewService service;
        QSignalSpy spy(&service, &PreviewService::previewReady);
        // Two requests for the SAME path before the event loop spins: the second
        // must be deduped onto the first's in-flight bat, so exactly one
        // previewReady is emitted.
        service.requestTextHighlight(path);
        service.requestTextHighlight(path);

        QVERIFY(spy.wait(10000));
        QTest::qWait(200); // give any erroneous second emission time to arrive
        QCOMPARE(spy.count(), 1);
    }

    void testConcurrentTextHighlightsBothEmit()
    {
        // Regression: previewService is shared across every supertab pane's
        // FileMillerView plus the global QuickPreview. A single in-flight slot
        // would let a second consumer's request cancel the first's bat, leaving
        // that consumer's preview un-highlighted. Two concurrent requests for
        // DIFFERENT paths must each emit.
        if (!batAvailable())
            QSKIP("bat not installed");

        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString a = dir.path() + "/alpha.txt";
        const QString b = dir.path() + "/beta.txt";
        for (const QString &p : {a, b}) {
            QFile f(p);
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write("content\n");
            f.close();
        }

        PreviewService service;
        QSignalSpy spy(&service, &PreviewService::previewReady);
        service.requestTextHighlight(a);
        service.requestTextHighlight(b);

        QSet<QString> seenPaths;
        while (seenPaths.size() < 2 && spy.wait(5000)) {
            while (!spy.isEmpty())
                seenPaths.insert(spy.takeFirst().at(1).toString());
        }
        while (!spy.isEmpty())
            seenPaths.insert(spy.takeFirst().at(1).toString());

        QVERIFY2(seenPaths.contains(a), "first text highlight was lost (single-slot regression)");
        QVERIFY2(seenPaths.contains(b), "second text highlight was lost");
    }
};

QTEST_MAIN(TestPreviewService)
#include "tst_previewservice.moc"
