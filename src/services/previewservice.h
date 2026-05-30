#pragma once

#include <QByteArray>
#include <QHash>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>

class QProcess;

class PreviewService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool pdfPreviewAvailable READ pdfPreviewAvailable NOTIFY supportChanged)

public:
    explicit PreviewService(QObject *parent = nullptr);
    ~PreviewService() override;

    bool pdfPreviewAvailable() const;

    Q_INVOKABLE QVariantMap loadTextPreview(const QString &path, int maxBytes = 131072,
                                            int maxLines = 400) const;
    Q_INVOKABLE QVariantMap loadDirectoryPreview(const QString &path, int maxEntries = 40) const;
    Q_INVOKABLE QVariantMap loadArchivePreview(const QString &path, int maxEntries = 200) const;
    Q_INVOKABLE QVariantMap loadPdfPreview(const QString &path) const;

    // Async variants of the slow process-based loaders. The archive listing
    // (unzip/tar/7z) and pdfinfo each block the GUI thread for up to 5-10s via
    // QProcess::waitForFinished; these start the process asynchronously and
    // emit previewReady(kind, path, result) when done, so the window stays
    // responsive. The QML consumer guards on `path` to drop results for a file
    // it has since navigated away from. The synchronous load* variants above
    // stay for tests / callers that want a blocking result.
    Q_INVOKABLE void requestArchivePreview(const QString &path, int maxEntries = 200);
    Q_INVOKABLE void requestPdfPreview(const QString &path);
    Q_INVOKABLE QVariantMap loadFontPreview(const QString &path);
    Q_INVOKABLE QString localPreviewPath(const QString &path) const;

public slots:
    // Re-check availability of external tools (pdftoppm/pdfinfo). Called
    // when the user clicks Re-check in the Missing Dependencies dialog
    // after installing a package.
    void refreshSupport();

signals:
    void supportChanged();
    // kind is "archive" or "pdf" (more kinds as other loaders go async). path
    // is the file the result is for; result has the same shape the matching
    // sync load* method returns.
    void previewReady(const QString &kind, const QString &path, const QVariantMap &result);

private:
    QByteArray readPathBytes(const QString &path, qint64 maxBytes, bool *truncated,
                             QString *error) const;
    QStringList listDirectoryEntries(const QString &path, int maxEntries, bool *truncated,
                                     QString *error) const;
    static bool isTrashUri(const QString &path);
    static bool looksBinary(const QByteArray &data);
    static QString decodeText(const QByteArray &data);
    // Shared by the sync + async archive loaders: pick the listing command for
    // an archive path, and parse its stdout into the entries/truncated/count
    // result map.
    static bool archiveListCommand(const QString &path, QString &program, QStringList &args);
    static QVariantMap parseArchiveListing(const QString &program, const QString &output,
                                           const QString &path, int maxEntries);
    // Shared by the sync + async pdf loaders: parse pdfinfo stdout into the
    // localPath/pageCount/error result map. localPath is set only on success;
    // error is "Unable to read PDF page count" when the Pages line is absent.
    static QVariantMap parsePdfInfo(const QString &output, const QString &localPath);

    int m_activeFontPreviewId = -1;
    QString m_activeFontPreviewPath;
    // In-flight async archive listings, keyed by archive path. previewService
    // is a single shared object but has many consumers (every supertab pane's
    // FileMillerView plus the global QuickPreview), so listings must be keyed
    // per path rather than a single slot — otherwise a second consumer's
    // request would cancel the first's process and leave it stuck "loading".
    // A duplicate request for a path already in flight is deduped: the one
    // process's previewReady reaches every consumer guarding on that path.
    QHash<QString, QProcess *> m_archiveProcs;
    // In-flight async pdfinfo calls, keyed by pdf path. Same per-path keying
    // and dedup rationale as m_archiveProcs: one shared service, many consumers
    // (every supertab pane's FileMillerView plus the global QuickPreview), so a
    // single slot would let one consumer cancel another's pdfinfo and leave it
    // stuck "loading".
    QHash<QString, QProcess *> m_pdfProcs;
};
