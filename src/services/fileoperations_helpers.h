#pragma once

#include <QString>
#include <QStringList>

// Forward-declare GLib's GFile so headers including this one don't pull in
// <gio/gio.h>. The definition lives in fileoperations_helpers.cpp.
typedef struct _GFile GFile;

// Path / URI helpers shared across the FileOperations translation units. Only
// genuinely cross-cluster helpers live here; single-cluster helpers stay in
// their respective .cpp anonymous namespaces. Cluster .cpp files pull these in
// via `using namespace FileOperationsHelpers;` so existing unqualified call
// sites keep working unchanged.
namespace FileOperationsHelpers {

// True when this binary is running inside a Flatpak sandbox.
bool runningInFlatpak();

bool isTrashUriPath(const QString &path);
bool isUriPath(const QString &path);
bool isRemoteUriPath(const QString &path);

// Extracts the authority (host[:port]) component of a URI string.
QString remoteAuthority(const QString &uri);

// Normalizes a remote URI: lowercases the scheme, normalizes path segments,
// strips a trailing slash, and re-encodes.
QString normalizeRemoteUri(const QString &path);

// Unified normalization: file:// -> local path, remote URI -> normalizeRemoteUri,
// else QDir::cleanPath.
QString normalizeLocation(const QString &path);

// Filename / display-name component of any path or URI.
QString locationFileName(const QString &path);

// Parent directory of any path/URI; handles trash:// and remote URIs.
QString parentLocation(const QString &path);

// Joins parent + name, handling URIs and local paths.
QString joinLocation(const QString &parentPath, const QString &name);

// Creates a GFile* for either a URI or a local path (caller owns the ref).
GFile *gFileForLocation(const QString &path);

// GIO-based existence check via g_file_query_info.
bool gioPathExists(const QString &path);

// Existence check dispatching to gioPathExists (URIs) or QFileInfo::exists.
bool pathExistsSync(const QString &path);

} // namespace FileOperationsHelpers
