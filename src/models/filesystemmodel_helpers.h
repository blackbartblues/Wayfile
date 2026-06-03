#pragma once

#include <QDateTime>
#include <QFileInfo>
#include <QHash>
#include <QMimeDatabase>
#include <QString>
#include <QStringList>
#include <QVariantMap>

class QProcess;

// Free helper functions shared across the FileSystemModel translation units
// (core / reload / properties / apps). These were originally a file-local
// anonymous namespace in filesystemmodel.cpp; promoted to external linkage so
// the split TUs can all reach them. Behavior is unchanged.
namespace FsmHelpers {

// Whether a file/video can be thumbnailed. Computed via QMimeDatabase so it
// handles ambiguous extensions like .ts (TypeScript vs MPEG-TS).
enum class PreviewKind { None, Image, Video };

QMimeDatabase &mimeDb();

bool isTrashUri(const QString &path);
bool shouldSpawnHostTool();
void startHostToolProcess(QProcess *process, const QString &program, const QStringList &arguments);
bool isRemoteUri(const QString &path);
QString remoteAuthority(const QString &uri);
QString normalizeRemoteUri(const QString &path);
QString normalizeLocation(const QString &path);
QString gioLocationArg(const QString &path);
QString locationFileName(const QString &path);
QString parentLocation(const QString &path);
QString afcDocumentsUriFor(const QString &path);
QString expandUserPath(const QString &path);
QString displayPathForSuggestion(const QString &path);

QDateTime dateTimeFromSeconds(const QString &value);
QString permissionsStringFromMode(int mode);
int accessIndexFromMode(int mode, int readMask, int writeMask, int execMask);
QString formattedSize(qint64 size, bool verbose = false);
QString iconNameForMimeName(const QString &mimeName);
QString iconNameForEntry(const QString &name, bool isDir, const QString &contentType = QString());
QString fileTypeForEntry(const QString &name, bool isDir, const QString &contentType = QString());
// Coarse type taxonomy used for folder badges + the hybrid view:
// folder / image / video / audio / document / code / archive / other.
QString fileCategoryForEntry(const QString &name, bool isDir, const QString &contentType = QString());
// Well-known folder type for a directory's absolute path, matched against the
// XDG user-dirs (QStandardPaths) + the ~/Projects convention. Returns one of
// home / documents / downloads / pictures / music / videos / desktop / projects,
// or "" for any other directory. Drives the typed-folder emblem/badge overlay.
QString folderTypeForPath(const QString &absolutePath);
PreviewKind previewKindForEntry(const QString &localPath, bool isDir,
                                const QString &contentType = QString());
QString permissionsString(const QFileInfo &info);

QHash<QString, QString> parseGioAttributes(const QString &attributeText);
QVariantMap buildRemoteEntryFromLine(const QString &line);
QVariantMap buildFallbackRemoteProperties(const QString &path);
QVariantMap buildRemotePropertiesFromEntry(const QVariantMap &entry);
QVariantMap buildTrashEntryFromLine(const QString &line);
QVariantMap buildTrashProperties(const QVariantMap &entry);

// True when this binary is running inside a Flatpak sandbox.
bool runningInFlatpak();
// Run a host CLI tool, transparently wrapping it in `flatpak-spawn --host`
// when inside a Flatpak sandbox. Returns trimmed stdout.
QString runHostTool(const QString &program, const QStringList &arguments, int timeoutMs = 3000);

} // namespace FsmHelpers
