#pragma once

#include <QHash>
#include <QObject>
#include <QStringList>
#include <QVariantMap>

#include <functional>

class QProcess;

class MetadataExtractor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool hasExifSupport READ hasExifSupport NOTIFY supportChanged)
    Q_PROPERTY(bool hasTagLibSupport READ hasTagLibSupport NOTIFY supportChanged)
    Q_PROPERTY(bool hasVideoSupport READ hasVideoSupport NOTIFY supportChanged)
    Q_PROPERTY(bool hasPdfSupport READ hasPdfSupport NOTIFY supportChanged)

public:
    explicit MetadataExtractor(QObject *parent = nullptr);
    ~MetadataExtractor() override;

    bool hasExifSupport() const;
    bool hasTagLibSupport() const;
    bool hasVideoSupport() const;
    bool hasPdfSupport() const;

    Q_INVOKABLE QVariantMap extract(const QString &path) const;
    // Async variant of extract(). Each specialized extractor spawns an external
    // tool (exiftool/ffprobe/pdfinfo) that blocks the GUI thread for up to 5s
    // via QProcess::waitForFinished in the sync path; this starts the process
    // asynchronously and emits metadataReady(path, result) when done, so the
    // window stays responsive. The QML consumer guards on `path` to drop results
    // for a file it has since navigated away from. The sync extract() above stays
    // for tests / callers (e.g. remote-path properties) that want a blocking
    // result, and shares the same static parse helpers so the output is identical.
    Q_INVOKABLE void requestExtract(const QString &path);
    Q_INVOKABLE QString missingDepsHint(const QString &mimeType) const;

public slots:
    void refreshSupport();

signals:
    void supportChanged();
    // path is the file the result is for; result has the same shape extract()
    // returns. Note: two args (path, result), unlike PreviewService::previewReady
    // which also carries a kind.
    void metadataReady(const QString &path, const QVariantMap &result);

private:
    QVariantMap extractImage(const QString &path) const;
    QVariantMap extractAudio(const QString &path) const;
    QVariantMap extractVideo(const QString &path) const;
    QVariantMap extractPdf(const QString &path) const;

    // Spawn `program args` asynchronously for `path`, dedup per path, and on
    // completion call `parse(stdoutBytes, ok)` to build the result map before
    // emitting metadataReady. Mirrors PreviewService's request* proc lifecycle.
    void startMetaProc(const QString &path, const QString &program, const QStringList &args,
                       const std::function<QVariantMap(const QByteArray &stdoutBytes, bool ok)> &parse);

    // Shared by the sync extract* and the async requestExtract so the two paths
    // produce byte-for-byte identical result maps.
    static QVariantMap imageBaseMeta(const QString &path);
    static QVariantMap parseExifJson(const QByteArray &out, QVariantMap base);
    static QVariantMap parseAudioProbe(const QByteArray &ffprobeOut);
    static QVariantMap parseVideoProbe(const QByteArray &ffprobeOut);
    static QVariantMap parsePdfMeta(const QByteArray &pdfinfoOut);
    static QStringList exiftoolArgs(const QString &path);
    static QStringList ffprobeArgs(const QString &path);

    // In-flight async extractions, keyed by path. metadataExtractor is a single
    // shared object with many consumers (every supertab pane's FileMillerView,
    // the global QuickPreview, the properties dialog), so extractions must be
    // keyed per path rather than a single slot — otherwise a second consumer's
    // request would cancel the first's process and leave it stuck "loading". A
    // duplicate request for a path already in flight is deduped: the one
    // process's metadataReady reaches every consumer guarding on that path.
    QHash<QString, QProcess *> m_procs;
};
