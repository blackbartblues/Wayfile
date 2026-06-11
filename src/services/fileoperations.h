#pragma once

#include <QObject>
#include <QProcess>
#include <QByteArray>
#include <QHash>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <functional>

class QThread;
class GioTransferWorker;

class FileOperations : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(QString speed READ speed NOTIFY speedChanged)
    Q_PROPERTY(QString eta READ eta NOTIFY etaChanged)
    Q_PROPERTY(bool paused READ paused NOTIFY pausedChanged)
    Q_PROPERTY(QString currentFile READ currentFile NOTIFY currentFileChanged)
    Q_PROPERTY(QVariantList activeTransfers READ activeTransfers NOTIFY activeTransfersChanged)
    Q_PROPERTY(QStringList pendingTargetPaths READ pendingTargetPaths NOTIFY activeTransfersChanged)
    // Cached: whether the system clipboard holds an image. Refreshed async via
    // refreshClipboardImageAvailable() so the paste UI never blocks on wl-paste.
    Q_PROPERTY(bool hasClipboardImage READ hasClipboardImage NOTIFY clipboardImageAvailableChanged)

public:
    explicit FileOperations(QObject *parent = nullptr);
    ~FileOperations() override;

    bool busy() const;
    double progress() const;
    QString statusText() const;
    QString speed() const;
    QString eta() const;
    bool paused() const;
    QString currentFile() const;
    QVariantList activeTransfers() const;
    QStringList pendingTargetPaths() const;

    Q_INVOKABLE void pauseTransfer(int transferId = -1);
    Q_INVOKABLE void resumeTransfer(int transferId = -1);
    Q_INVOKABLE void cancelTransfer(int transferId = -1);

    Q_INVOKABLE void copyFiles(const QStringList &sources, const QString &destination);
    Q_INVOKABLE void copyResolvedItems(const QVariantList &operations);
    Q_INVOKABLE void moveFiles(const QStringList &sources, const QString &destination);
    Q_INVOKABLE void moveResolvedItems(const QVariantList &operations);
    Q_INVOKABLE void trashFiles(const QStringList &paths);
    Q_INVOKABLE void restoreFromTrash(const QStringList &paths);
    Q_INVOKABLE bool isTrashPath(const QString &path) const;
    Q_INVOKABLE QString trashFilesPathFor(const QString &path) const;
    Q_INVOKABLE QVariantList transferPlan(const QStringList &sources, const QString &destination) const;
    Q_INVOKABLE QString uniqueNameForDestination(const QString &destinationDir, const QString &desiredName,
                                                 const QStringList &blockedNames = {}) const;
    QString conflictBackupPath(const QString &targetPath) const;
    Q_INVOKABLE void deleteFiles(const QStringList &paths);
    Q_INVOKABLE bool rename(const QString &path, const QString &newName);
    Q_INVOKABLE QVariantMap renameResolvedItems(const QVariantList &operations);
    Q_INVOKABLE void createFolder(const QString &parentPath, const QString &name);
    Q_INVOKABLE void createFile(const QString &parentPath, const QString &name);
    Q_INVOKABLE void openFile(const QString &path);
    Q_INVOKABLE bool pathExists(const QString &path) const;
    Q_INVOKABLE bool isRemotePath(const QString &path) const;
    Q_INVOKABLE QString parentPath(const QString &path) const;
    Q_INVOKABLE QString displayNameForPath(const QString &path) const;
    Q_INVOKABLE QVariantList breadcrumbSegments(const QString &path) const;
    Q_INVOKABLE void emptyTrash();
    Q_INVOKABLE void openFileWith(const QString &path, const QString &desktopFile);
    // Property getter — returns the cached flag (see refreshClipboardImageAvailable).
    bool hasClipboardImage() const;
    // Re-probe the clipboard for an image without blocking: instant Qt check
    // first, else an async `wl-paste --list-types`. Updates the cached flag and
    // emits clipboardImageAvailableChanged when it changes. Call before showing
    // paste UI (context menu, Ctrl+V) so the cached value is current.
    Q_INVOKABLE void refreshClipboardImageAvailable();
    Q_INVOKABLE QString pasteClipboardImage(const QString &destinationDir);
    Q_INVOKABLE void copyPathToClipboard(const QString &path);
    Q_INVOKABLE void openInTerminal(const QString &dirPath);
    Q_INVOKABLE void compressFiles(const QStringList &paths, const QString &format);
    Q_INVOKABLE void extractArchive(const QString &archivePath, const QString &destination);
    Q_INVOKABLE static bool isArchive(const QString &path);
    // Synchronous variant: kept for tests and fast non-GUI paths. Blocks the
    // calling thread up to 5s while it lists the archive's table of contents.
    Q_INVOKABLE QString archiveRootFolder(const QString &archivePath);
    // Async variant for the GUI thread: spawns the listing process without
    // blocking and reports the common root folder via archiveRootFolderReady.
    Q_INVOKABLE void requestArchiveRootFolder(const QString &archivePath);
    Q_INVOKABLE void setWallpaper(const QString &path);
    Q_INVOKABLE void setHyprlandRounding(const QString &windowTitle, int radius);
    Q_INVOKABLE void setHyprlandBorder(const QString &windowTitle, int size);

signals:
    void busyChanged();
    void progressChanged();
    void statusTextChanged();
    void speedChanged();
    void etaChanged();
    void pausedChanged();
    void currentFileChanged();
    void activeTransfersChanged();
    void pathsChanged(const QStringList &paths);
    void operationFinished(bool success, const QString &error);
    void archiveRootFolderReady(const QString &archivePath, const QString &rootFolder);
    // Extraction-specific completion, carrying the archive path so a listener can
    // tell ITS extraction apart from the global operationFinished (which every
    // paste/rename/clipboard op also emits). Always fires exactly once per
    // extractArchive() call — including the early-return when the format is
    // unsupported — so post-extraction navigation never leaks its handlers.
    void archiveExtractFinished(const QString &archivePath, bool success, const QString &error);
    void clipboardImageAvailableChanged();

private:
    struct ActiveTransfer {
        int id = 0;
        QThread *thread = nullptr;
        GioTransferWorker *worker = nullptr;
        QString statusText;
        double progress = -1.0;
        QString speed;
        QString eta;
        QString currentFile;
        bool paused = false;
        QStringList changedPaths;
        QStringList targetPaths;
    };

    void transferResolvedItems(const QVariantList &operations, bool moveOperation);
    void resetTransferState();
    void setProgressValue(double progress, const QString &speed = {}, const QString &eta = {});
    void setPendingChangedPaths(const QStringList &paths);
    void emitPendingChangedPaths();
    void emitChangedPaths(const QStringList &paths);
    void setClipboardImageAvailable(bool available);
    // Two-step async fallback for pasteClipboardImage when Qt can't read the
    // clipboard image directly: `wl-paste --list-types` then `--type <image>`,
    // writing the result and reporting via operationFinished.
    void startExternalClipboardImagePaste(const QString &outputPath);
    void fetchAndWriteClipboardImage(const QString &wlPastePath, const QString &imageType,
                                     const QString &outputPath);
    QString uniqueImagePastePath(const QString &destinationDir) const;
    void startGioTransfer(const QVariantList &operations, bool moveOperation);
    using ProgressReporter = std::function<void(int current, int total, const QString &fileName)>;
    void startSimpleOperation(const QString &statusText, const QStringList &changedPaths,
                              std::function<QString(ProgressReporter)> work,
                              std::function<void(bool success, const QString &error)> onFinished = {});
    void cleanupTransfer(int transferId);
    void emitAggregatedState();
    ActiveTransfer *findTransfer(int id);

    bool m_busy = false;
    double m_progress = 0.0;
    QString m_statusText;
    QString m_speed;
    QString m_eta;
    bool m_paused = false;
    QString m_currentFile;
    QList<ActiveTransfer> m_activeTransfers;
    int m_nextTransferId = 1;
    QStringList m_pendingChangedPaths;
    // In-flight async archive-root listings, keyed by archive path. Lets a new
    // request supersede a stale one and lets the destructor stop them cleanly.
    QHash<QString, QProcess *> m_archiveRootProcs;
    // Cached clipboard-image flag + the in-flight async probe (single slot: a
    // newer probe supersedes the previous one). See refreshClipboardImageAvailable.
    bool m_hasClipboardImage = false;
    QProcess *m_clipboardProbeProcess = nullptr;
};
