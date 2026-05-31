#include "services/fileoperations.h"

#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>

// Archive compression / extraction cluster, split from fileoperations.cpp.
// All helpers here are used only by the archive methods, so they stay local to
// this translation unit. No shared FileOperationsHelpers are needed.
namespace {

QString shellQuote(const QString &value)
{
    QString escaped = value;
    escaped.replace("'", "'\"'\"'");
    return QStringLiteral("'") + escaped + QStringLiteral("'");
}

enum class ArchiveKind {
    None,
    Zip,
    Tar,
    TarGz,
    TarXz,
    TarBz2,
    Gz,
    Xz,
    Bz2,
    SevenZip,
    Rar,
};

ArchiveKind archiveKindForPath(const QString &path)
{
    const QString lower = path.toLower();
    if (lower.endsWith(QStringLiteral(".tar.gz")) || lower.endsWith(QStringLiteral(".tgz")))
        return ArchiveKind::TarGz;
    if (lower.endsWith(QStringLiteral(".tar.xz")) || lower.endsWith(QStringLiteral(".txz")))
        return ArchiveKind::TarXz;
    if (lower.endsWith(QStringLiteral(".tar.bz2")) || lower.endsWith(QStringLiteral(".tbz2")))
        return ArchiveKind::TarBz2;
    if (lower.endsWith(QStringLiteral(".tar")))
        return ArchiveKind::Tar;
    if (lower.endsWith(QStringLiteral(".zip")))
        return ArchiveKind::Zip;
    if (lower.endsWith(QStringLiteral(".7z")))
        return ArchiveKind::SevenZip;
    if (lower.endsWith(QStringLiteral(".rar")))
        return ArchiveKind::Rar;
    if (lower.endsWith(QStringLiteral(".gz")))
        return ArchiveKind::Gz;
    if (lower.endsWith(QStringLiteral(".xz")))
        return ArchiveKind::Xz;
    if (lower.endsWith(QStringLiteral(".bz2")))
        return ArchiveKind::Bz2;
    return ArchiveKind::None;
}

bool archiveExtractCommand(const QString &archivePath, const QString &destination,
                           QString *program, QStringList *args)
{
    switch (archiveKindForPath(archivePath)) {
    case ArchiveKind::Zip:
        *program = QStringLiteral("unzip");
        *args = {QStringLiteral("-o"), archivePath, QStringLiteral("-d"), destination};
        return true;
    case ArchiveKind::TarGz:
        *program = QStringLiteral("tar");
        *args = {QStringLiteral("-xzf"), archivePath, QStringLiteral("-C"), destination};
        return true;
    case ArchiveKind::TarXz:
        *program = QStringLiteral("tar");
        *args = {QStringLiteral("-xJf"), archivePath, QStringLiteral("-C"), destination};
        return true;
    case ArchiveKind::TarBz2:
        *program = QStringLiteral("tar");
        *args = {QStringLiteral("-xjf"), archivePath, QStringLiteral("-C"), destination};
        return true;
    case ArchiveKind::Tar:
        *program = QStringLiteral("tar");
        *args = {QStringLiteral("-xf"), archivePath, QStringLiteral("-C"), destination};
        return true;
    case ArchiveKind::Gz:
        *program = QStringLiteral("gunzip");
        *args = {QStringLiteral("-k"), archivePath};
        return true;
    case ArchiveKind::Xz:
        *program = QStringLiteral("unxz");
        *args = {QStringLiteral("-k"), archivePath};
        return true;
    case ArchiveKind::Bz2:
        *program = QStringLiteral("bunzip2");
        *args = {QStringLiteral("-k"), archivePath};
        return true;
    case ArchiveKind::SevenZip:
    case ArchiveKind::Rar:
        if (!QStandardPaths::findExecutable(QStringLiteral("7z")).isEmpty()) {
            *program = QStringLiteral("7z");
            *args = {QStringLiteral("x"), QStringLiteral("-aoa"),
                     QStringLiteral("-o%1").arg(destination), archivePath};
            return true;
        }
        if (!QStandardPaths::findExecutable(QStringLiteral("bsdtar")).isEmpty()) {
            *program = QStringLiteral("bsdtar");
            *args = {QStringLiteral("-xf"), archivePath, QStringLiteral("-C"), destination};
            return true;
        }
        return false;
    case ArchiveKind::None:
        return false;
    }

    return false;
}

bool archiveListCommand(const QString &archivePath, QString *program, QStringList *args)
{
    switch (archiveKindForPath(archivePath)) {
    case ArchiveKind::Zip:
        *program = QStringLiteral("unzip");
        *args = {QStringLiteral("-Z1"), archivePath};
        return true;
    case ArchiveKind::TarGz:
        *program = QStringLiteral("tar");
        *args = {QStringLiteral("-tzf"), archivePath};
        return true;
    case ArchiveKind::TarXz:
        *program = QStringLiteral("tar");
        *args = {QStringLiteral("-tJf"), archivePath};
        return true;
    case ArchiveKind::TarBz2:
        *program = QStringLiteral("tar");
        *args = {QStringLiteral("-tjf"), archivePath};
        return true;
    case ArchiveKind::Tar:
        *program = QStringLiteral("tar");
        *args = {QStringLiteral("-tf"), archivePath};
        return true;
    case ArchiveKind::SevenZip:
    case ArchiveKind::Rar:
        if (!QStandardPaths::findExecutable(QStringLiteral("bsdtar")).isEmpty()) {
            *program = QStringLiteral("bsdtar");
            *args = {QStringLiteral("-tf"), archivePath};
            return true;
        }
        if (!QStandardPaths::findExecutable(QStringLiteral("7z")).isEmpty()) {
            *program = QStringLiteral("7z");
            *args = {QStringLiteral("l"), QStringLiteral("-ba"), QStringLiteral("-slt"), archivePath};
            return true;
        }
        return false;
    case ArchiveKind::Gz:
    case ArchiveKind::Xz:
    case ArchiveKind::Bz2:
    case ArchiveKind::None:
        return false;
    }

    return false;
}

QStringList archiveEntriesFromOutput(const QString &program, const QString &output)
{
    QStringList entries;

    if (program == QStringLiteral("7z")) {
        bool inEntries = false;
        const QStringList lines = output.split('\n');
        for (const QString &line : lines) {
            const QString trimmed = line.trimmed();
            if (trimmed == QStringLiteral("----------")) {
                inEntries = true;
                continue;
            }
            if (!inEntries || !trimmed.startsWith(QStringLiteral("Path = ")))
                continue;

            const QString entry = QDir::cleanPath(trimmed.mid(7).trimmed());
            if (!entry.isEmpty() && entry != QStringLiteral("."))
                entries.append(entry);
        }
        return entries;
    }

    const QStringList lines = output.split('\n', Qt::SkipEmptyParts);
    for (const QString &line : lines) {
        QString entry = line.trimmed();
        if (entry.startsWith(QStringLiteral("./")))
            entry.remove(0, 2);
        entry = QDir::cleanPath(entry);
        if (!entry.isEmpty() && entry != QStringLiteral("."))
            entries.append(entry);
    }

    return entries;
}

QString commonArchiveRootFolder(const QStringList &entries)
{
    QString root;
    for (QString entry : entries) {
        while (entry.startsWith('/'))
            entry.remove(0, 1);
        if (entry.isEmpty())
            continue;

        const QString top = entry.section('/', 0, 0);
        if (top.isEmpty())
            return {};

        if (root.isEmpty())
            root = top;
        else if (top != root)
            return {};
    }

    return root;
}

} // namespace

void FileOperations::compressFiles(const QStringList &paths, const QString &format)
{
    if (paths.isEmpty()) return;

    // Determine output name from first file's parent + name
    QFileInfo first(paths.first());
    QString baseName = (paths.size() == 1) ? first.completeBaseName() : "archive";
    QString parentDir = first.absolutePath();
    QString outputPath;

    QString cmd;
    if (format == "zip") {
        QString outPath = parentDir + "/" + baseName + ".zip";
        outputPath = outPath;
        // Use cd + relative paths for proper zip structure
        cmd = "cd " + shellQuote(parentDir) + " && zip -rv " + shellQuote(outPath);
        for (const auto &p : paths)
            cmd += " " + shellQuote(QFileInfo(p).fileName());
    } else if (format == "tar.gz") {
        QString outPath = parentDir + "/" + baseName + ".tar.gz";
        outputPath = outPath;
        cmd = "tar -cvzf " + shellQuote(outPath) + " -C " + shellQuote(parentDir);
        for (const auto &p : paths)
            cmd += " " + shellQuote(QFileInfo(p).fileName());
    } else if (format == "tar.xz") {
        QString outPath = parentDir + "/" + baseName + ".tar.xz";
        outputPath = outPath;
        cmd = "tar -cvJf " + shellQuote(outPath) + " -C " + shellQuote(parentDir);
        for (const auto &p : paths)
            cmd += " " + shellQuote(QFileInfo(p).fileName());
    } else if (format == "tar.bz2") {
        QString outPath = parentDir + "/" + baseName + ".tar.bz2";
        outputPath = outPath;
        cmd = "tar -cvjf " + shellQuote(outPath) + " -C " + shellQuote(parentDir);
        for (const auto &p : paths)
            cmd += " " + shellQuote(QFileInfo(p).fileName());
    } else if (format == "tar") {
        QString outPath = parentDir + "/" + baseName + ".tar";
        outputPath = outPath;
        cmd = "tar -cvf " + shellQuote(outPath) + " -C " + shellQuote(parentDir);
        for (const auto &p : paths)
            cmd += " " + shellQuote(QFileInfo(p).fileName());
    } else if (format == "7z") {
        QString outPath = parentDir + "/" + baseName + ".7z";
        outputPath = outPath;
        cmd = "cd " + shellQuote(parentDir) + " && 7z a " + shellQuote(outPath);
        for (const auto &p : paths)
            cmd += " " + shellQuote(QFileInfo(p).fileName());
    } else {
        return;
    }

    const QString statusText = QString("Compressing %1 item(s)...").arg(paths.size());
    startSimpleOperation(statusText, {outputPath},
        [paths, cmd](ProgressReporter report) -> QString {
            // Pre-count files for progress
            int totalFiles = 0;
            for (const auto &p : paths) {
                QFileInfo fi(p);
                if (fi.isDir()) {
                    QDirIterator it(p, QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden,
                                    QDirIterator::Subdirectories);
                    while (it.hasNext()) { it.next(); ++totalFiles; }
                } else {
                    ++totalFiles;
                }
            }
            if (totalFiles <= 0) totalFiles = 1;

            report(0, totalFiles, {});

            // Run with verbose output and count lines for progress
            QProcess proc;
            proc.setProcessChannelMode(QProcess::MergedChannels);
            proc.start(QStringLiteral("sh"), {QStringLiteral("-c"), cmd});
            if (!proc.waitForStarted(5000))
                return QStringLiteral("Failed to start compression");

            int processed = 0;
            while (proc.state() != QProcess::NotRunning || proc.canReadLine()) {
                if (!proc.canReadLine())
                    proc.waitForReadyRead(200);
                while (proc.canReadLine()) {
                    const QString line = QString::fromUtf8(proc.readLine()).trimmed();
                    if (line.isEmpty()) continue;
                    ++processed;
                    const QString fileName = line.mid(line.lastIndexOf('/') + 1);
                    report(qMin(processed, totalFiles), totalFiles, fileName);
                }
            }

            proc.waitForFinished(5000);
            if (proc.exitCode() != 0)
                return QStringLiteral("Compression failed");
            return {};
        });
}

void FileOperations::extractArchive(const QString &archivePath, const QString &destination)
{
    QString program;
    QStringList args;
    if (!archiveExtractCommand(archivePath, destination, &program, &args))
        return;

    // Add verbose flag for progress tracking
    QStringList verboseArgs = args;
    if (program == "tar" || program == "bsdtar")
        verboseArgs.prepend(QStringLiteral("-v"));
    else if (program == "unzip")
        { /* unzip is already verbose by default */ }
    // 7z, gunzip, unxz, bunzip2 — no easy verbose line-per-file

    // Pre-count files in archive for progress
    QString listProg;
    QStringList listArgs;
    const bool canList = archiveListCommand(archivePath, &listProg, &listArgs);

    startSimpleOperation(QStringLiteral("Extracting..."), {destination},
        [program, verboseArgs, canList, listProg, listArgs](ProgressReporter report) -> QString {
            int totalFiles = 0;
            if (canList) {
                QProcess listProc;
                listProc.start(listProg, listArgs);
                if (listProc.waitForFinished(30000) && listProc.exitCode() == 0) {
                    const QByteArray output = listProc.readAllStandardOutput();
                    totalFiles = output.count('\n');
                }
            }
            if (totalFiles <= 0) totalFiles = 1;

            report(0, totalFiles, {});

            QProcess proc;
            proc.setProcessChannelMode(QProcess::MergedChannels);
            proc.start(program, verboseArgs);
            if (!proc.waitForStarted(5000))
                return QStringLiteral("Failed to start extraction");

            int processed = 0;
            while (proc.state() != QProcess::NotRunning || proc.canReadLine()) {
                if (!proc.canReadLine())
                    proc.waitForReadyRead(200);
                while (proc.canReadLine()) {
                    const QString line = QString::fromUtf8(proc.readLine()).trimmed();
                    if (line.isEmpty()) continue;
                    ++processed;
                    const QString fileName = line.mid(line.lastIndexOf('/') + 1);
                    report(qMin(processed, totalFiles), totalFiles, fileName);
                }
            }

            proc.waitForFinished(5000);
            if (proc.exitCode() != 0)
                return QStringLiteral("Extraction failed");
            return {};
        });
}

QString FileOperations::archiveRootFolder(const QString &archivePath)
{
    QString program;
    QStringList args;
    if (!archiveListCommand(archivePath, &program, &args))
        return {};

    QProcess proc;
    proc.start(program, args);
    if (!proc.waitForFinished(5000) || proc.exitCode() != 0)
        return {};

    const QString output = QString::fromUtf8(proc.readAllStandardOutput());
    const QStringList entries = archiveEntriesFromOutput(program, output);
    if (entries.isEmpty())
        return {};

    return commonArchiveRootFolder(entries);
}

bool FileOperations::isArchive(const QString &path)
{
    return archiveKindForPath(path) != ArchiveKind::None;
}
