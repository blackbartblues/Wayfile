#include <QTest>
#include <QImage>
#include <QPainter>
#include <QPdfWriter>
#include <QSet>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>

#include "services/metadataextractor.h"

class TestMetadataExtractor : public QObject
{
    Q_OBJECT

private:
    // Write a tiny solid-colour PNG so image tests don't depend on any external
    // tool: QImageReader (in-process) always yields Dimensions, so the result is
    // identical whether or not exiftool is installed. Returns path, or empty.
    static QString makePng(const QString &dirPath, const QString &name)
    {
        const QString path = dirPath + "/" + name;
        QImage img(8, 8, QImage::Format_RGB32);
        img.fill(Qt::red);
        return img.save(path, "PNG") ? path : QString();
    }

    // Write a tiny valid single-page PDF via QPdfWriter so the pdf tests don't
    // depend on any external PDF fixture. Returns path, or empty.
    static QString makePdf(const QString &dirPath, const QString &name)
    {
        const QString path = dirPath + "/" + name;
        QPdfWriter writer(path);
        writer.setPageSize(QPageSize(QPageSize::A4));
        QPainter painter(&writer);
        painter.drawText(QPointF(72.0, 100.0), QStringLiteral("Async Metadata Test"));
        painter.end();
        return QFileInfo::exists(path) ? path : QString();
    }

    static bool pdfinfoAvailable()
    {
        return !QStandardPaths::findExecutable("pdfinfo").isEmpty();
    }

private slots:
    void testRequestExtractEmitsForImage()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString png = makePng(dir.path(), "pixel.png");
        QVERIFY(!png.isEmpty());

        MetadataExtractor extractor;
        QSignalSpy spy(&extractor, &MetadataExtractor::metadataReady);
        extractor.requestExtract(png);

        // With exiftool installed the result arrives async via a QProcess;
        // without exiftool requestExtract emits synchronously (the in-process
        // QImageReader base is all there is). Tolerate both: only wait if
        // nothing has been emitted yet.
        if (spy.isEmpty())
            QVERIFY(spy.wait(10000));
        QCOMPARE(spy.count(), 1);

        const QList<QVariant> args = spy.takeFirst();
        QCOMPARE(args.at(0).toString(), png); // path
        const QVariantMap result = args.at(1).toMap();

        // A PNG always yields Dimensions from QImageReader regardless of exiftool.
        QVERIFY(result.contains("Dimensions"));

        // Async result must be byte-for-byte identical to the sync extract() so
        // QML bindings behave the same. Parity holds whether or not exiftool is
        // installed (same static parse helpers feed both paths).
        QCOMPARE(result, extractor.extract(png));
    }

    void testDuplicateExtractRequestDeduped()
    {
        // Dedup is a property of the async (process-spawning) path, so exercise
        // it with a PDF (pdfinfo). The synchronous early-emit branches (image
        // without exiftool, unsupported/remote types) have no in-flight process
        // to dedup against — same as PreviewService's early-emit branches.
        if (!pdfinfoAvailable())
            QSKIP("pdfinfo not found in PATH");

        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString pdf = makePdf(dir.path(), "dup.pdf");
        QVERIFY(!pdf.isEmpty());

        MetadataExtractor extractor;
        QSignalSpy spy(&extractor, &MetadataExtractor::metadataReady);
        // Two requests for the SAME path before the event loop spins: the second
        // must be deduped onto the first's in-flight process, so exactly one
        // metadataReady is emitted.
        extractor.requestExtract(pdf);
        extractor.requestExtract(pdf);

        QVERIFY(spy.wait(10000));
        QTest::qWait(200); // give any erroneous second emission time to arrive
        QCOMPARE(spy.count(), 1);
    }

    void testConcurrentExtractsBothEmit()
    {
        // Regression: metadataExtractor is shared across every supertab pane's
        // FileMillerView plus the global QuickPreview and the properties dialog.
        // A single in-flight slot would let a second consumer's request cancel
        // the first's process, leaving that consumer stuck "loading" forever.
        // Two concurrent requests for DIFFERENT paths must each emit. Use PDFs so
        // both go through the real async process path.
        if (!pdfinfoAvailable())
            QSKIP("pdfinfo not found in PATH");

        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString a = makePdf(dir.path(), "alpha.pdf");
        const QString b = makePdf(dir.path(), "beta.pdf");
        QVERIFY(!a.isEmpty());
        QVERIFY(!b.isEmpty());

        MetadataExtractor extractor;
        QSignalSpy spy(&extractor, &MetadataExtractor::metadataReady);
        extractor.requestExtract(a);
        extractor.requestExtract(b);

        QSet<QString> seenPaths;
        while (seenPaths.size() < 2 && spy.wait(5000)) {
            while (!spy.isEmpty())
                seenPaths.insert(spy.takeFirst().at(0).toString());
        }
        while (!spy.isEmpty())
            seenPaths.insert(spy.takeFirst().at(0).toString());

        QVERIFY2(seenPaths.contains(a), "first extraction was lost (single-slot regression)");
        QVERIFY2(seenPaths.contains(b), "second extraction was lost");
    }

    void testRequestExtractEmitsForPdf()
    {
        if (!pdfinfoAvailable())
            QSKIP("pdfinfo not found in PATH");

        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString pdf = makePdf(dir.path(), "async.pdf");
        QVERIFY(!pdf.isEmpty());

        MetadataExtractor extractor;
        QSignalSpy spy(&extractor, &MetadataExtractor::metadataReady);
        extractor.requestExtract(pdf);

        QVERIFY(spy.wait(10000));
        QCOMPARE(spy.count(), 1);

        const QList<QVariant> args = spy.takeFirst();
        QCOMPARE(args.at(0).toString(), pdf); // path
        const QVariantMap result = args.at(1).toMap();

        // Async result must be byte-for-byte identical to the sync extract().
        QCOMPARE(result, extractor.extract(pdf));
        QVERIFY(result.contains("Pages"));
    }
};

QTEST_MAIN(TestMetadataExtractor)
#include "tst_metadataextractor.moc"
