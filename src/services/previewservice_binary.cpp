#include "services/previewservice.h"
#include "services/previewservice_internal.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QFontDatabase>
#include <QProcess>
#include <QRawFont>
#include <QRegularExpression>
#include <QUrl>

// Binary preview path: archive listings, font metadata, and PDF page info
// (sync + async), plus the trash-aware local-file materialiser localPreviewPath.
// Split out of previewservice.cpp. Shares encodedUri/startGioCat with the core
// TU via previewservice_internal.h.

using namespace previewservice_detail;

bool PreviewService::archiveListCommand(const QString &path, QString &program, QStringList &args)
{
    // Reuse the same detection as fileoperations.
    const QString lower = path.toLower();
    if (lower.endsWith(".zip")) {
        program = "unzip";
        args = {"-Z1", path};
    } else if (lower.endsWith(".tar.gz") || lower.endsWith(".tgz")) {
        program = "tar";
        args = {"-tzf", path};
    } else if (lower.endsWith(".tar.xz") || lower.endsWith(".txz")) {
        program = "tar";
        args = {"-tJf", path};
    } else if (lower.endsWith(".tar.bz2") || lower.endsWith(".tbz2")) {
        program = "tar";
        args = {"-tjf", path};
    } else if (lower.endsWith(".tar")) {
        program = "tar";
        args = {"-tf", path};
    } else if (lower.endsWith(".7z") || lower.endsWith(".rar")) {
        program = "7z";
        args = {"l", "-slt", path};
    } else {
        return false;
    }
    return true;
}

QVariantMap PreviewService::parseArchiveListing(const QString &program, const QString &output,
                                                const QString &path, int maxEntries)
{
    QStringList entries;
    bool truncated = false;

    if (program == "7z") {
        // 7z -slt output: "Path = filename" lines
        static const QRegularExpression pathRe(R"(^Path = (.+)$)", QRegularExpression::MultilineOption);
        auto it = pathRe.globalMatch(output);
        while (it.hasNext()) {
            const QString entry = it.next().captured(1).trimmed();
            if (entry.isEmpty() || entry == path)
                continue;
            if (entries.size() >= maxEntries) { truncated = true; break; }
            entries.append(entry);
        }
    } else {
        const QStringList lines = output.split('\n', Qt::SkipEmptyParts);
        for (const QString &line : lines) {
            const QString trimmed = line.trimmed();
            if (trimmed.isEmpty())
                continue;
            if (entries.size() >= maxEntries) { truncated = true; break; }
            entries.append(trimmed);
        }
    }

    QVariantMap result;
    result["entries"] = entries;
    result["truncated"] = truncated;
    result["error"] = QString();
    result["count"] = entries.size();
    return result;
}

QVariantMap PreviewService::loadArchivePreview(const QString &path, int maxEntries) const
{
    QVariantMap result;
    result["entries"] = QStringList();
    result["truncated"] = false;
    result["error"] = QString();
    result["count"] = 0;

    QString program;
    QStringList args;
    if (!archiveListCommand(path, program, args)) {
        result["error"] = "Unsupported archive format";
        return result;
    }

    QProcess proc;
    proc.start(program, args);
    if (!proc.waitForFinished(10000) || proc.exitCode() != 0) {
        result["error"] = "Could not list archive contents";
        return result;
    }
    return parseArchiveListing(program, QString::fromUtf8(proc.readAllStandardOutput()), path, maxEntries);
}

void PreviewService::requestArchivePreview(const QString &path, int maxEntries)
{
    // A listing for this exact path is already running. Its previewReady will
    // reach every consumer guarding on this path, so don't start a duplicate —
    // this also means two panes previewing the same archive share one process.
    if (m_archiveProcs.contains(path))
        return;

    QString program;
    QStringList args;
    if (!archiveListCommand(path, program, args)) {
        QVariantMap result;
        result["entries"] = QStringList();
        result["truncated"] = false;
        result["count"] = 0;
        result["error"] = QStringLiteral("Unsupported archive format");
        emit previewReady(QStringLiteral("archive"), path, result);
        return;
    }

    auto *proc = new QProcess(this);
    m_archiveProcs.insert(path, proc);

    connect(proc, &QProcess::finished, this,
            [this, proc, path, program, maxEntries](int code, QProcess::ExitStatus status) {
                // Ignore if this proc is no longer the tracked listing for
                // `path` (superseded/cancelled). value() defaults to nullptr.
                if (m_archiveProcs.value(path) != proc) {
                    proc->deleteLater();
                    return;
                }
                m_archiveProcs.remove(path);
                QVariantMap result;
                if (status != QProcess::NormalExit || code != 0) {
                    result["entries"] = QStringList();
                    result["truncated"] = false;
                    result["count"] = 0;
                    result["error"] = QStringLiteral("Could not list archive contents");
                } else {
                    result = parseArchiveListing(
                        program, QString::fromUtf8(proc->readAllStandardOutput()), path, maxEntries);
                }
                emit previewReady(QStringLiteral("archive"), path, result);
                proc->deleteLater();
            });
    connect(proc, &QProcess::errorOccurred, this,
            [this, proc, path](QProcess::ProcessError) {
                if (m_archiveProcs.value(path) != proc) {
                    proc->deleteLater();
                    return;
                }
                m_archiveProcs.remove(path);
                QVariantMap result;
                result["entries"] = QStringList();
                result["truncated"] = false;
                result["count"] = 0;
                result["error"] = QStringLiteral("Could not list archive contents");
                emit previewReady(QStringLiteral("archive"), path, result);
                proc->deleteLater();
            });

    armProcessTimeout(proc, 10000);
    proc->start(program, args);
}

QString PreviewService::localPreviewPath(const QString &path) const
{
    if (path.isEmpty())
        return {};

    if (!isTrashUri(path))
        return QFileInfo::exists(path) ? path : QString();

    QString cacheRoot = QDir::homePath() + "/.cache/heimdall/preview-cache";
    QDir().mkpath(cacheRoot);

    const QString suffix = QFileInfo(QUrl(path).fileName()).suffix();
    const QString hash = QString::fromLatin1(QCryptographicHash::hash(path.toUtf8(), QCryptographicHash::Sha1).toHex());
    const QString cachedPath = QDir(cacheRoot).filePath(suffix.isEmpty() ? hash : hash + "." + suffix);

    QProcess proc;
    startGioCat(proc, encodedUri(path));
    if (!proc.waitForFinished(10000) || proc.exitCode() != 0)
        return {};

    QFile cacheFile(cachedPath);
    if (!cacheFile.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return {};

    cacheFile.write(proc.readAllStandardOutput());
    cacheFile.close();

    return cachedPath;
}

QVariantMap PreviewService::loadFontPreview(const QString &path)
{
    QVariantMap result;
    result["family"] = QString();
    result["styleName"] = QString();
    result["weight"] = static_cast<int>(QFont::Normal);
    result["italic"] = false;
    result["valid"] = false;
    result["error"] = QString();

    if (path.isEmpty() || !QFileInfo::exists(path)) {
        result["error"] = QStringLiteral("Font file not found");
        return result;
    }

    // Short-circuit when the same path is already loaded so repeated reads
    // (e.g. preview refresh on selection change) don't thrash the database.
    const bool alreadyLoaded = m_activeFontPreviewId >= 0 && m_activeFontPreviewPath == path;

    if (!alreadyLoaded) {
        if (m_activeFontPreviewId >= 0) {
            QFontDatabase::removeApplicationFont(m_activeFontPreviewId);
            m_activeFontPreviewId = -1;
            m_activeFontPreviewPath.clear();
        }

        const int id = QFontDatabase::addApplicationFont(path);
        if (id < 0) {
            result["error"] = QStringLiteral("Unable to load font file");
            return result;
        }
        m_activeFontPreviewId = id;
        m_activeFontPreviewPath = path;
    }

    const QStringList families = QFontDatabase::applicationFontFamilies(m_activeFontPreviewId);
    if (families.isEmpty()) {
        result["error"] = QStringLiteral("Font contains no usable families");
        return result;
    }

    const QString family = families.first();

    // Pull exact face metadata straight from the file so variants of the
    // same family (e.g. MapleMono-Bold vs MapleMono-Italic) don't alias.
    QRawFont raw(path, 16.0);
    QString styleName = raw.isValid() ? raw.styleName() : QString();
    int weight = raw.isValid() ? raw.weight() : static_cast<int>(QFont::Normal);
    const bool italic = raw.isValid() ? (raw.style() != QFont::StyleNormal) : false;

    if (styleName.isEmpty()) {
        const QStringList styles = QFontDatabase::styles(family);
        if (!styles.isEmpty())
            styleName = styles.first();
    }

    result["family"] = family;
    result["styleName"] = styleName;
    result["weight"] = weight;
    result["italic"] = italic;
    result["valid"] = true;
    return result;
}

QVariantMap PreviewService::parsePdfInfo(const QString &output, const QString &localPath)
{
    QVariantMap result;
    result["localPath"] = QString();
    result["pageCount"] = 0;
    result["error"] = QString();

    static const QRegularExpression pagesRe(QStringLiteral(R"(^Pages:\s*(\d+))"),
                                            QRegularExpression::MultilineOption);
    const auto m = pagesRe.match(output);
    if (!m.hasMatch()) {
        result["error"] = QStringLiteral("Unable to read PDF page count");
        return result;
    }

    result["localPath"] = localPath;
    result["pageCount"] = m.captured(1).toInt();
    return result;
}

QVariantMap PreviewService::loadPdfPreview(const QString &path) const
{
    QVariantMap result;
    result["localPath"] = QString();
    result["pageCount"] = 0;
    result["error"] = QString();

    const QString localPath = localPreviewPath(path);
    if (localPath.isEmpty()) {
        result["error"] = QStringLiteral("Unable to prepare PDF preview");
        return result;
    }

    if (!pdfPreviewAvailable()) {
        result["error"] = QStringLiteral("Install poppler-utils for PDF preview");
        return result;
    }

    QProcess proc;
    proc.start(QStringLiteral("pdfinfo"), {localPath});
    if (!proc.waitForFinished(5000) || proc.exitCode() != 0) {
        result["error"] = QStringLiteral("Unable to open PDF document");
        return result;
    }

    return parsePdfInfo(QString::fromUtf8(proc.readAllStandardOutput()), localPath);
}

void PreviewService::requestPdfPreview(const QString &path)
{
    // A pdfinfo for this exact path is already running. Its previewReady will
    // reach every consumer guarding on this path, so don't start a duplicate —
    // this also means two panes previewing the same PDF share one process.
    if (m_pdfProcs.contains(path))
        return;

    const QString localPath = localPreviewPath(path);
    if (localPath.isEmpty()) {
        QVariantMap result;
        result["localPath"] = QString();
        result["pageCount"] = 0;
        result["error"] = QStringLiteral("Unable to prepare PDF preview");
        emit previewReady(QStringLiteral("pdf"), path, result);
        return;
    }

    if (!pdfPreviewAvailable()) {
        QVariantMap result;
        result["localPath"] = QString();
        result["pageCount"] = 0;
        result["error"] = QStringLiteral("Install poppler-utils for PDF preview");
        emit previewReady(QStringLiteral("pdf"), path, result);
        return;
    }

    auto *proc = new QProcess(this);
    m_pdfProcs.insert(path, proc);

    connect(proc, &QProcess::finished, this,
            [this, proc, path, localPath](int code, QProcess::ExitStatus status) {
                // Ignore if this proc is no longer the tracked pdfinfo for
                // `path` (superseded/cancelled). value() defaults to nullptr.
                if (m_pdfProcs.value(path) != proc) {
                    proc->deleteLater();
                    return;
                }
                m_pdfProcs.remove(path);
                QVariantMap result;
                if (status != QProcess::NormalExit || code != 0) {
                    result["localPath"] = QString();
                    result["pageCount"] = 0;
                    result["error"] = QStringLiteral("Unable to open PDF document");
                } else {
                    result = parsePdfInfo(QString::fromUtf8(proc->readAllStandardOutput()), localPath);
                }
                emit previewReady(QStringLiteral("pdf"), path, result);
                proc->deleteLater();
            });
    connect(proc, &QProcess::errorOccurred, this,
            [this, proc, path](QProcess::ProcessError) {
                if (m_pdfProcs.value(path) != proc) {
                    proc->deleteLater();
                    return;
                }
                m_pdfProcs.remove(path);
                QVariantMap result;
                result["localPath"] = QString();
                result["pageCount"] = 0;
                result["error"] = QStringLiteral("Unable to open PDF document");
                emit previewReady(QStringLiteral("pdf"), path, result);
                proc->deleteLater();
            });

    armProcessTimeout(proc, 5000);
    proc->start(QStringLiteral("pdfinfo"), {localPath});
}
