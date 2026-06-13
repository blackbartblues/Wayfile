#include "services/fileoperations.h"
#include "services/fileoperations_helpers.h"

#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QMimeData>
#include <QMimeDatabase>
#include <QPixmap>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QUuid>

#include <memory>

using namespace FileOperationsHelpers;

// Open / clipboard-image / path-display / wallpaper / Hyprland cluster, split
// from fileoperations.cpp. The clipboard-image extraction, the gio-open arg
// wrapper, and the breadcrumb builder below are used only here; cross-cluster
// path helpers come from FileOperationsHelpers. No raw GIO calls live here.
namespace {

QImage clipboardImage(const QClipboard *clipboard)
{
    if (!clipboard)
        return {};

    const QMimeData *mime = clipboard->mimeData();
    if (!mime || !mime->hasImage())
        return {};

    QImage image = clipboard->image();
    if (!image.isNull())
        return image;

    const QVariant imageData = mime->imageData();
    if (imageData.canConvert<QImage>())
        return qvariant_cast<QImage>(imageData);
    if (imageData.canConvert<QPixmap>())
        return qvariant_cast<QPixmap>(imageData).toImage();
    return {};
}

QString gioLocationArg(const QString &path)
{
    const QString normalized = normalizeLocation(path);
    if (isUriPath(normalized))
        return normalized;
    return normalized;
}

QVariantList buildBreadcrumbs(const QString &path)
{
    QVariantList segments;
    const QString normalized = normalizeLocation(path);

    if (normalized.isEmpty())
        return segments;

    if (isTrashUriPath(normalized)) {
        if (normalized == QStringLiteral("trash:///") || normalized == QStringLiteral("trash://")) {
            segments.append(QVariantMap{{QStringLiteral("label"), QStringLiteral("Trash")},
                                        {QStringLiteral("fullPath"), QStringLiteral("trash:///")}});
            return segments;
        }

        QString current = normalized;
        if (current.endsWith('/'))
            current.chop(1);
        QString remainder = current.mid(QStringLiteral("trash:///").size());
        segments.append(QVariantMap{{QStringLiteral("label"), QStringLiteral("Trash")},
                                    {QStringLiteral("fullPath"), QStringLiteral("trash:///")}});

        QString accumulated = QStringLiteral("trash:///");
        const QStringList parts = remainder.split('/', Qt::SkipEmptyParts);
        for (const QString &part : parts) {
            accumulated = joinLocation(accumulated, QUrl::fromPercentEncoding(part.toUtf8()));
            segments.append(QVariantMap{{QStringLiteral("label"), QUrl::fromPercentEncoding(part.toUtf8())},
                                        {QStringLiteral("fullPath"), accumulated}});
        }
        return segments;
    }

    if (isRemoteUriPath(normalized)) {
        const QUrl url(normalized);
        const QString authority = !remoteAuthority(normalized).isEmpty()
            ? QUrl::fromPercentEncoding(remoteAuthority(normalized).toUtf8())
            : url.scheme().toUpper();
        const QString rootPath = url.scheme().toLower() + QStringLiteral("://")
            + remoteAuthority(normalized) + QStringLiteral("/");
        segments.append(QVariantMap{{QStringLiteral("label"), authority},
                                    {QStringLiteral("fullPath"), rootPath}});

        QString accumulatedPath;
        const QStringList parts = url.path(QUrl::FullyEncoded).split('/', Qt::SkipEmptyParts);
        for (const QString &part : parts) {
            accumulatedPath += QStringLiteral("/") + part;
            segments.append(QVariantMap{{QStringLiteral("label"), QUrl::fromPercentEncoding(part.toUtf8())},
                                        {QStringLiteral("fullPath"), rootPath.left(rootPath.size() - 1) + accumulatedPath}});
        }
        return segments;
    }

    if (normalized == QStringLiteral("/"))
        return segments;

    QString accumulated;
    const QStringList parts = normalized.split('/', Qt::SkipEmptyParts);
    for (const QString &part : parts) {
        accumulated += QStringLiteral("/") + part;
        segments.append(QVariantMap{{QStringLiteral("label"), part},
                                    {QStringLiteral("fullPath"), accumulated}});
    }

    return segments;
}

} // namespace

void FileOperations::openFile(const QString &path)
{
    const QString normalized = normalizeLocation(path);

    auto *proc = new QProcess(this);
    connect(proc, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            proc, &QProcess::deleteLater);

    // gio:// / sftp:// / smb:// / trash:// → use `gio open` which talks
    // to gvfs. On the host this is just `gio open <uri>`; inside a Flatpak
    // we run it on the host so it sees the host's gvfsd mounts.
    if (isUriPath(normalized)) {
        const QStringList args = {QStringLiteral("open"), gioLocationArg(normalized)};
        if (runningInFlatpak()) {
            proc->start(QStringLiteral("flatpak-spawn"),
                        QStringList{QStringLiteral("--host"), QStringLiteral("gio")} + args);
        } else {
            proc->start(QStringLiteral("gio"), args);
        }
        return;
    }

    // Flatpak local files: shell out to `flatpak-spawn --host xdg-open` so the
    // host opens the file with its default app, bypassing the sandbox. (Out of
    // scope for the App Chooser fallback — left as fire-and-forget.)
    if (runningInFlatpak()) {
        proc->start(QStringLiteral("flatpak-spawn"),
                    {QStringLiteral("--host"), QStringLiteral("xdg-open"), normalized});
        return;
    }

    // Host local files: launch via `gio open`, which honors the user's default
    // app AND the MIME subclass hierarchy and — unlike xdg-open / QDesktopServices
    // — has no web-browser fallback for unhandled types. When gio reports no
    // default handler (non-zero exit) or fails to start, emit openFileFailed so
    // the UI can offer the App Chooser. Reported at most once.
    auto reported = std::make_shared<bool>(false);
    auto reportFailure = [this, normalized, reported]() {
        if (*reported)
            return;
        *reported = true;
        QMimeDatabase mimeDb;
        emit openFileFailed(normalized, mimeDb.mimeTypeForFile(normalized).name());
    };
    connect(proc, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
            [reportFailure](int exitCode, QProcess::ExitStatus status) {
                if (status != QProcess::NormalExit || exitCode != 0)
                    reportFailure();
            });
    connect(proc, &QProcess::errorOccurred, this,
            [reportFailure](QProcess::ProcessError) { reportFailure(); });
    proc->start(QStringLiteral("gio"), {QStringLiteral("open"), normalized});
}

bool FileOperations::pathExists(const QString &path) const
{
    return pathExistsSync(path);
}

bool FileOperations::isRemotePath(const QString &path) const
{
    return isRemoteUriPath(normalizeLocation(path));
}

QString FileOperations::parentPath(const QString &path) const
{
    return parentLocation(path);
}

QString FileOperations::displayNameForPath(const QString &path) const
{
    return locationFileName(path);
}

QVariantList FileOperations::breadcrumbSegments(const QString &path) const
{
    return buildBreadcrumbs(path);
}

void FileOperations::openFileWith(const QString &path, const QString &desktopFile)
{
    auto *proc = new QProcess(this);
    connect(proc, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            proc, &QProcess::deleteLater);

    const QString normalized = normalizeLocation(path);
    if (runningInFlatpak()) {
        proc->start(QStringLiteral("flatpak-spawn"),
                    {QStringLiteral("--host"),
                     QStringLiteral("gtk-launch"), desktopFile, normalized});
    } else {
        proc->start(QStringLiteral("gtk-launch"), {desktopFile, normalized});
    }
}

bool FileOperations::hasClipboardImage() const
{
    return m_hasClipboardImage;
}

void FileOperations::setClipboardImageAvailable(bool available)
{
    if (m_hasClipboardImage == available)
        return;
    m_hasClipboardImage = available;
    emit clipboardImageAvailableChanged();
}

void FileOperations::refreshClipboardImageAvailable()
{
    // Instant Qt path: if Qt can already read a clipboard image, we're done.
    const QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboardImage(clipboard).isNull()) {
        setClipboardImageAvailable(true);
        return;
    }

    const QString wlPastePath = QStandardPaths::findExecutable(QStringLiteral("wl-paste"));
    if (wlPastePath.isEmpty()) {
        setClipboardImageAvailable(false);
        return;
    }

    // Supersede any in-flight probe: only the latest result matters.
    if (m_clipboardProbeProcess) {
        m_clipboardProbeProcess->disconnect(this);
        m_clipboardProbeProcess->kill();
        m_clipboardProbeProcess->deleteLater();
        m_clipboardProbeProcess = nullptr;
    }

    auto *proc = new QProcess(this);
    m_clipboardProbeProcess = proc;

    // Only `--list-types` is needed for the boolean — never the (slow) `--type`
    // fetch. The pointer guard drops a superseded/double-fired result.
    connect(proc, &QProcess::finished, this,
            [this, proc](int code, QProcess::ExitStatus status) {
                if (m_clipboardProbeProcess != proc) {
                    proc->deleteLater();
                    return;
                }
                m_clipboardProbeProcess = nullptr;
                bool hasImage = false;
                if (status == QProcess::NormalExit && code == 0) {
                    const QStringList types = QString::fromUtf8(proc->readAllStandardOutput())
                                                  .split('\n', Qt::SkipEmptyParts);
                    for (const QString &type : types) {
                        if (type.startsWith(QStringLiteral("image/"))) {
                            hasImage = true;
                            break;
                        }
                    }
                }
                setClipboardImageAvailable(hasImage);
                proc->deleteLater();
            });
    connect(proc, &QProcess::errorOccurred, this,
            [this, proc](QProcess::ProcessError) {
                if (m_clipboardProbeProcess != proc) {
                    proc->deleteLater();
                    return;
                }
                m_clipboardProbeProcess = nullptr;
                setClipboardImageAvailable(false);
                proc->deleteLater();
            });

    // Watchdog mirrors the old 1s list-types cap.
    QTimer::singleShot(1000, proc, [proc]() {
        if (proc->state() != QProcess::NotRunning)
            proc->kill();
    });

    proc->start(wlPastePath, {QStringLiteral("--list-types")});
}

QString FileOperations::pasteClipboardImage(const QString &destinationDir)
{
    const QString outputPath = uniqueImagePastePath(destinationDir);
    if (outputPath.isEmpty()) {
        emit operationFinished(false, "Destination folder does not exist");
        return {};
    }

    // Prefer the live Qt clipboard image so we paste the current selection
    // instead of stale external clipboard-manager data.
    const QClipboard *clipboard = QGuiApplication::clipboard();
    const QImage image = clipboardImage(clipboard);
    if (!image.isNull()) {
        if (!image.save(outputPath, "PNG")) {
            emit operationFinished(false, "Failed to save clipboard image");
            return {};
        }
        emitChangedPaths({outputPath});
        emit operationFinished(true, QString());
        return outputPath;
    }

    // Qt couldn't read the image directly (e.g. an external app's clipboard).
    // Fall back to wl-paste, async, so the paste action never blocks the GUI.
    // The result is delivered via operationFinished; the return is empty (the
    // QML caller ignores it and listens for operationFinished).
    startExternalClipboardImagePaste(outputPath);
    return {};
}

void FileOperations::startExternalClipboardImagePaste(const QString &outputPath)
{
    const QString wlPastePath = QStandardPaths::findExecutable(QStringLiteral("wl-paste"));
    if (wlPastePath.isEmpty()) {
        emit operationFinished(false, "Clipboard does not contain an image");
        return;
    }

    auto *listProc = new QProcess(this);
    connect(listProc, &QProcess::finished, this,
            [this, listProc, wlPastePath, outputPath](int code, QProcess::ExitStatus status) {
                listProc->deleteLater();
                if (status != QProcess::NormalExit || code != 0) {
                    emit operationFinished(false, "Clipboard does not contain an image");
                    return;
                }
                const QStringList types = QString::fromUtf8(listProc->readAllStandardOutput())
                                              .split('\n', Qt::SkipEmptyParts);
                QString imageType;
                if (types.contains(QStringLiteral("image/png"))) {
                    imageType = QStringLiteral("image/png");
                } else {
                    for (const QString &type : types) {
                        if (type.startsWith(QStringLiteral("image/"))) {
                            imageType = type;
                            break;
                        }
                    }
                }
                // Defence-in-depth: imageType is echoed from wl-paste's own
                // --list-types output and passed back as an argv (no shell), but
                // pin it to a well-formed image/* MIME so nothing unexpected ever
                // reaches the --type argument.
                static const QRegularExpression mimeRe(
                    QStringLiteral("^image/[A-Za-z0-9][A-Za-z0-9.+-]*$"));
                if (imageType.isEmpty() || !mimeRe.match(imageType).hasMatch()) {
                    emit operationFinished(false, "Clipboard does not contain an image");
                    return;
                }
                fetchAndWriteClipboardImage(wlPastePath, imageType, outputPath);
            });
    connect(listProc, &QProcess::errorOccurred, this,
            [this, listProc](QProcess::ProcessError err) {
                // A started-then-killed process still fires finished; only act
                // on can't-start here so the error is reported exactly once.
                if (err != QProcess::FailedToStart)
                    return;
                listProc->deleteLater();
                emit operationFinished(false, "Clipboard does not contain an image");
            });
    QTimer::singleShot(1000, listProc, [listProc]() {
        if (listProc->state() != QProcess::NotRunning)
            listProc->kill();
    });
    listProc->start(wlPastePath, {QStringLiteral("--list-types")});
}

void FileOperations::fetchAndWriteClipboardImage(const QString &wlPastePath, const QString &imageType,
                                                 const QString &outputPath)
{
    auto *imgProc = new QProcess(this);
    connect(imgProc, &QProcess::finished, this,
            [this, imgProc, outputPath](int code, QProcess::ExitStatus status) {
                imgProc->deleteLater();
                if (status != QProcess::NormalExit || code != 0) {
                    emit operationFinished(false, "Clipboard does not contain an image");
                    return;
                }
                const QByteArray rawImage = imgProc->readAllStandardOutput();
                if (rawImage.isEmpty()) {
                    emit operationFinished(false, "Clipboard does not contain an image");
                    return;
                }
                QFile file(outputPath);
                if (!file.open(QIODevice::WriteOnly)
                    || file.write(rawImage) != rawImage.size()
                    || !file.flush()) {
                    file.close();
                    file.remove();
                    emit operationFinished(false, "Failed to write clipboard image");
                    return;
                }
                file.close();
                emitChangedPaths({outputPath});
                emit operationFinished(true, QString());
            });
    connect(imgProc, &QProcess::errorOccurred, this,
            [this, imgProc](QProcess::ProcessError err) {
                if (err != QProcess::FailedToStart)
                    return;
                imgProc->deleteLater();
                emit operationFinished(false, "Clipboard does not contain an image");
            });
    QTimer::singleShot(3000, imgProc, [imgProc]() {
        if (imgProc->state() != QProcess::NotRunning)
            imgProc->kill();
    });
    imgProc->start(wlPastePath, {QStringLiteral("--no-newline"), QStringLiteral("--type"), imageType});
}

void FileOperations::copyPathToClipboard(const QString &path)
{
    // Use Qt's clipboard rather than spawning wl-copy: works on X11 too and
    // reports nothing silently on failure the way an unmonitored QProcess does.
    if (QClipboard *clipboard = QGuiApplication::clipboard())
        clipboard->setText(path);
}

void FileOperations::openInTerminal(const QString &dirPath)
{
    if (isUriPath(dirPath)) {
        emit operationFinished(false, QStringLiteral("Open in Terminal is only available for local folders"));
        return;
    }

    // Resolve $TERMINAL to a real executable rather than handing an arbitrary
    // env value straight to QProcess (which would just silently fail to start on
    // a bogus value). Fall back to kitty when unset or unresolvable.
    const QString requested = qEnvironmentVariable("TERMINAL", QStringLiteral("kitty"));
    QString terminal = QStandardPaths::findExecutable(requested);
    if (terminal.isEmpty())
        terminal = QStandardPaths::findExecutable(QStringLiteral("kitty"));
    if (terminal.isEmpty()) {
        emit operationFinished(false, QStringLiteral("No terminal emulator found ($TERMINAL not set or not installed)"));
        return;
    }
    auto *proc = new QProcess(this);
    proc->setWorkingDirectory(dirPath);
    proc->start(terminal, {});
    connect(proc, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            proc, &QProcess::deleteLater);
}

QString FileOperations::uniqueImagePastePath(const QString &destinationDir) const
{
    QDir dir(destinationDir);
    if (!dir.exists())
        return {};

    const QString baseName = "Pasted image";
    const QString extension = ".png";
    QString candidate = dir.filePath(baseName + extension);
    if (!QFileInfo::exists(candidate))
        return candidate;

    for (int i = 2; i < 10000; ++i) {
        candidate = dir.filePath(QString("%1 %2%3").arg(baseName).arg(i).arg(extension));
        if (!QFileInfo::exists(candidate))
            return candidate;
    }

    return {};
}

void FileOperations::setWallpaper(const QString &path)
{
    const QString resolved = QFileInfo(path).absoluteFilePath();
    auto *proc = new QProcess(this);
    connect(proc, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, [proc, resolved](int exitCode, QProcess::ExitStatus) {
                if (exitCode != 0)
                    qWarning() << "FileOperations::setWallpaper: hyprctl failed for" << resolved;
                proc->deleteLater();
            });
    proc->start(QStringLiteral("hyprctl"),
                {QStringLiteral("hyprpaper"), QStringLiteral("wallpaper"),
                 QStringLiteral(",") + resolved});
}

void FileOperations::setHyprlandRounding(const QString &windowTitle, int radius)
{
    auto *proc = new QProcess(this);
    connect(proc, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, [proc](int, QProcess::ExitStatus) { proc->deleteLater(); });
    proc->start(QStringLiteral("hyprctl"),
                {QStringLiteral("setprop"),
                 QStringLiteral("title:") + windowTitle,
                 QStringLiteral("rounding"),
                 QString::number(radius)});
}

void FileOperations::setHyprlandBorder(const QString &windowTitle, int size)
{
    auto *proc = new QProcess(this);
    connect(proc, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, [proc](int, QProcess::ExitStatus) { proc->deleteLater(); });
    proc->start(QStringLiteral("hyprctl"),
                {QStringLiteral("setprop"),
                 QStringLiteral("title:") + windowTitle,
                 QStringLiteral("bordersize"),
                 QString::number(size)});
}
