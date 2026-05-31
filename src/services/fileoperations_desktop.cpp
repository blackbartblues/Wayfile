#include "services/fileoperations.h"
#include "services/fileoperations_helpers.h"

#include <QClipboard>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QMimeData>
#include <QPixmap>
#include <QProcess>
#include <QStandardPaths>
#include <QUrl>
#include <QUuid>

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

    // Local files. Outside a sandbox: hand off to Qt's QDesktopServices
    // (which uses xdg-open / kde-open / gio-launch under the hood and
    // honors the user's MIME associations). Inside a Flatpak: shell out
    // to `flatpak-spawn --host xdg-open` so the host opens the file with
    // the host's default app, completely bypassing the sandbox. This is
    // the same pattern Nautilus and Dolphin use when running as Flatpaks.
    if (runningInFlatpak()) {
        proc->start(QStringLiteral("flatpak-spawn"),
                    {QStringLiteral("--host"), QStringLiteral("xdg-open"), normalized});
        return;
    }

    proc->deleteLater();
    const QUrl url = QUrl::fromLocalFile(normalized);
    if (!QDesktopServices::openUrl(url))
        qWarning() << "FileOperations::openFile: failed to open" << normalized;
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
    const QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboardImage(clipboard).isNull())
        return true;

    return !clipboardImageData().isEmpty();
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

    const QByteArray rawImage = clipboardImageData();
    if (rawImage.isEmpty()) {
        emit operationFinished(false, "Clipboard does not contain an image");
        return {};
    }

    QFile file(outputPath);
    if (!file.open(QIODevice::WriteOnly)) {
        emit operationFinished(false, "Failed to write clipboard image");
        return {};
    }
    if (file.write(rawImage) != rawImage.size()) {
        file.close();
        file.remove();
        emit operationFinished(false, "Failed to write clipboard image");
        return {};
    }
    if (!file.flush()) {
        file.close();
        file.remove();
        emit operationFinished(false, "Failed to write clipboard image");
        return {};
    }
    file.close();

    emitChangedPaths({outputPath});
    emit operationFinished(true, QString());
    return outputPath;
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

    QString terminal = qEnvironmentVariable("TERMINAL", "kitty");
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

QByteArray FileOperations::clipboardImageData() const
{
    const QString wlPastePath = QStandardPaths::findExecutable("wl-paste");
    if (wlPastePath.isEmpty())
        return {};

    QProcess listProcess;
    listProcess.start(wlPastePath, {"--list-types"});
    if (!listProcess.waitForFinished(1000) || listProcess.exitCode() != 0)
        return {};

    const QStringList types = QString::fromUtf8(listProcess.readAllStandardOutput())
                                  .split('\n', Qt::SkipEmptyParts);
    QString imageType;
    if (types.contains("image/png"))
        imageType = "image/png";
    else {
        for (const QString &type : types) {
            if (type.startsWith("image/")) {
                imageType = type;
                break;
            }
        }
    }

    if (imageType.isEmpty())
        return {};

    QProcess imageProcess;
    imageProcess.start(wlPastePath, {"--no-newline", "--type", imageType});
    if (!imageProcess.waitForFinished(3000) || imageProcess.exitCode() != 0)
        return {};

    return imageProcess.readAllStandardOutput();
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
