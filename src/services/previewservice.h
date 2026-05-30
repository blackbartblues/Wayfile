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
    // The plain-text half of loadTextPreview (decode + line cap) with no bat
    // syntax highlighting — returns instantly (no QProcess). The async preview
    // path renders this immediately, then layers the highlight on via
    // requestTextHighlight()/previewReady("text", …).
    Q_INVOKABLE QVariantMap loadTextPlain(const QString &path, int maxBytes = 131072,
                                          int maxLines = 400) const;
    Q_INVOKABLE QVariantMap loadDirectoryPreview(const QString &path, int maxEntries = 40) const;
    Q_INVOKABLE QVariantMap loadArchivePreview(const QString &path, int maxEntries = 200) const;
    Q_INVOKABLE QVariantMap loadPdfPreview(const QString &path) const;

    // Async variants of the slow process-based loaders. The archive listing
    // (unzip/tar/7z), pdfinfo, and bat syntax highlighting each block the GUI
    // thread via QProcess::waitForFinished; these start the process
    // asynchronously and emit previewReady(kind, path, result) when done, so the
    // window stays responsive. The QML consumer guards on `path` to drop results
    // for a file it has since navigated away from. The synchronous load*
    // variants above stay for tests / callers that want a blocking result.
    Q_INVOKABLE void requestArchivePreview(const QString &path, int maxEntries = 200);
    Q_INVOKABLE void requestPdfPreview(const QString &path);
    // Highlight a text file asynchronously. Emits previewReady("text", path,
    // result) with the same shape loadTextPreview returns (plain fields + html +
    // usesBat). When there's nothing to highlight (read error, binary, empty, or
    // bat not installed) it emits the plain result once without spawning bat.
    Q_INVOKABLE void requestTextHighlight(const QString &path, int maxBytes = 131072,
                                          int maxLines = 400);
    Q_INVOKABLE QVariantMap loadFontPreview(const QString &path);
    Q_INVOKABLE QString localPreviewPath(const QString &path) const;

public slots:
    // Re-check availability of external tools (pdftoppm/pdfinfo). Called
    // when the user clicks Re-check in the Missing Dependencies dialog
    // after installing a package.
    void refreshSupport();

signals:
    void supportChanged();
    // kind is "archive", "pdf", or "text" (more kinds as other loaders go
    // async). path is the file the result is for; result has the same shape the
    // matching sync load* method returns.
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
    // Watchdog for an in-flight async QProcess: if it hasn't finished within
    // `ms`, kill it so its finished/errorOccurred handler runs (emitting an
    // error/fallback result and freeing its per-path dedup slot). Restores the
    // bound the synchronous waitForFinished(N) used to provide once the loaders
    // went async. The timer is parented to proc, so it's torn down with it.
    void armProcessTimeout(QProcess *proc, int ms);

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
    // In-flight async bat syntax-highlight calls, keyed by text-file path. Same
    // per-path keying and dedup rationale as m_archiveProcs / m_pdfProcs: one
    // shared service, many consumers (every supertab pane's FileMillerView plus
    // the global QuickPreview), so a single slot would let one consumer cancel
    // another's bat and leave its preview un-highlighted.
    QHash<QString, QProcess *> m_textProcs;
};
