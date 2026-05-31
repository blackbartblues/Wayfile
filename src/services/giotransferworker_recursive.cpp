#include "services/giotransferworker.h"
#include "services/giotransferworker_internal.h"

// Recursive scan/copy/delete helpers + GError translation, split out of
// giotransferworker.cpp to keep each translation unit under the line cap.
// The orchestration (execute) and progress reporting stay in the core TU;
// these are the heavy filesystem-walking routines it delegates to.

using namespace giotransferworker_detail;

qint64 GioTransferWorker::scanTotalBytes(const QList<TransferItem> &items)
{
    qint64 total = 0;
    for (const auto &item : items) {
        GFile *file = gFileForLocation(item.sourcePath);
        total += scanPathBytes(file);
        g_object_unref(file);
    }
    return total;
}

qint64 GioTransferWorker::scanPathBytes(GFile *file)
{
    GError *err = nullptr;
    GFileInfo *info = g_file_query_info(file,
        G_FILE_ATTRIBUTE_STANDARD_SIZE "," G_FILE_ATTRIBUTE_STANDARD_TYPE,
        G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS, nullptr, &err);

    if (!info) {
        if (err) g_error_free(err);
        return 1;
    }

    GFileType type = g_file_info_get_file_type(info);

    if (type == G_FILE_TYPE_SYMBOLIC_LINK) {
        g_object_unref(info);
        return 1;
    }

    if (type == G_FILE_TYPE_REGULAR) {
        goffset size = g_file_info_get_size(info);
        g_object_unref(info);
        return size < 1 ? 1 : size;
    }

    if (type == G_FILE_TYPE_DIRECTORY) {
        g_object_unref(info);
        qint64 total = 1; // 1 byte for the directory entry itself

        GError *enumErr = nullptr;
        GFileEnumerator *enumerator = g_file_enumerate_children(file,
            G_FILE_ATTRIBUTE_STANDARD_NAME "," G_FILE_ATTRIBUTE_STANDARD_SIZE "," G_FILE_ATTRIBUTE_STANDARD_TYPE,
            G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS, nullptr, &enumErr);

        if (!enumerator) {
            if (enumErr) g_error_free(enumErr);
            return total;
        }

        GFileInfo *childInfo;
        while ((childInfo = g_file_enumerator_next_file(enumerator, nullptr, nullptr)) != nullptr) {
            const char *name = g_file_info_get_name(childInfo);
            GFile *child = g_file_get_child(file, name);
            total += scanPathBytes(child);
            g_object_unref(child);
            g_object_unref(childInfo);
        }

        g_file_enumerator_close(enumerator, nullptr, nullptr);
        g_object_unref(enumerator);
        return total;
    }

    g_object_unref(info);
    return 1;
}

bool GioTransferWorker::copyRecursive(GFile *source, GFile *destination, GFileCopyFlags flags, QString *error)
{
    gchar *dstUriRaw = g_file_get_uri(destination);
    const QString dstUri = QString::fromUtf8(dstUriRaw ? dstUriRaw : "");
    if (dstUriRaw) g_free(dstUriRaw);

    qCDebug(lcTransfer) << "recurse mkdir" << dstUri;

    // Create target directory. If the backing GVfs volume timed out between
    // the user opening it in the sidebar and this transfer firing, we get
    // G_IO_ERROR_NOT_MOUNTED — remount once and try again.
    GError *mkErr = nullptr;
    g_file_make_directory_with_parents(destination, m_cancellable, &mkErr);
    if (mkErr && mkErr->code == G_IO_ERROR_NOT_MOUNTED) {
        qCInfo(lcTransfer) << "recurse mkdir hit NOT_MOUNTED; attempting remount for" << dstUri;
        g_error_free(mkErr);
        mkErr = nullptr;

        QString mountErr;
        int mountCode = 0;
        if (mountEnclosingVolumeSync(destination, &mountErr, &mountCode)) {
            qCInfo(lcTransfer) << "recurse remount ok; retrying mkdir on" << dstUri;
            g_file_make_directory_with_parents(destination, m_cancellable, &mkErr);
        } else {
            qCWarning(lcTransfer).nospace()
                << "recurse remount failed  dst=" << dstUri
                << " code=" << mountCode
                << " msg=" << mountErr;
            *error = humanizeMobileDeviceError(mountErr.isEmpty()
                ? QStringLiteral("Could not mount destination volume") : mountErr);
            return false;
        }
    }
    if (mkErr) {
        if (mkErr->code != G_IO_ERROR_EXISTS) {
            qCWarning(lcTransfer).nospace()
                << "recurse mkdir failed  dst=" << dstUri
                << " code=" << mkErr->code
                << " msg=" << mkErr->message;
            *error = humanizeMobileDeviceError(gErrorToUserMessage(mkErr));
            g_error_free(mkErr);
            return false;
        }
        g_error_free(mkErr);
    }

    m_completedBytes += 1; // directory entry

    // Enumerate children
    GError *enumErr = nullptr;
    GFileEnumerator *enumerator = g_file_enumerate_children(source,
        G_FILE_ATTRIBUTE_STANDARD_NAME "," G_FILE_ATTRIBUTE_STANDARD_TYPE "," G_FILE_ATTRIBUTE_STANDARD_SYMLINK_TARGET,
        G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS, m_cancellable, &enumErr);

    if (!enumerator) {
        *error = gErrorToUserMessage(enumErr);
        if (enumErr) g_error_free(enumErr);
        return false;
    }

    GFileInfo *childInfo;
    while ((childInfo = g_file_enumerator_next_file(enumerator, m_cancellable, nullptr)) != nullptr) {
        if (m_cancelled.load()) {
            g_object_unref(childInfo);
            break;
        }

        const char *name = g_file_info_get_name(childInfo);
        GFileType childType = g_file_info_get_file_type(childInfo);
        GFile *childSrc = g_file_get_child(source, name);
        GFile *childDst = g_file_get_child(destination, name);

        bool ok = true;

        if (childType == G_FILE_TYPE_DIRECTORY) {
            ok = copyRecursive(childSrc, childDst, flags, error);
        } else if (childType == G_FILE_TYPE_SYMBOLIC_LINK) {
            const char *slTarget = g_file_info_has_attribute(
                childInfo, G_FILE_ATTRIBUTE_STANDARD_SYMLINK_TARGET)
                ? g_file_info_get_symlink_target(childInfo)
                : nullptr;
            if (!slTarget) {
                *error = tr("Could not read symbolic link target");
                ok = false;
            }

            GError *slErr = nullptr;
            if (ok)
                g_file_make_symbolic_link(childDst, slTarget, m_cancellable, &slErr);
            if (slErr) {
                *error = gErrorToUserMessage(slErr);
                g_error_free(slErr);
                ok = false;
            }
            m_completedBytes += 1;
        } else {
            // Regular file
            GError *cpErr = nullptr;
            qCDebug(lcTransfer) << "recurse copy" << name;
            gboolean cpOk = g_file_copy(childSrc, childDst, flags,
                m_cancellable, progressCallback, this, &cpErr);
            if (!cpOk) {
                gchar *cdUri = g_file_get_uri(childDst);
                qCWarning(lcTransfer).nospace()
                    << "recurse copy failed  child=" << (cdUri ? cdUri : name)
                    << " code=" << (cpErr ? cpErr->code : -1)
                    << " msg=" << (cpErr ? cpErr->message : "(null)");
                if (cdUri) g_free(cdUri);
                *error = humanizeMobileDeviceError(gErrorToUserMessage(cpErr));
                if (cpErr) g_error_free(cpErr);
                ok = false;
            } else {
                m_completedBytes += m_currentItemBytes;
                m_currentItemBytes = 0;
            }
        }

        g_object_unref(childSrc);
        g_object_unref(childDst);
        g_object_unref(childInfo);

        if (!ok) {
            g_file_enumerator_close(enumerator, nullptr, nullptr);
            g_object_unref(enumerator);
            return false;
        }
    }

    g_file_enumerator_close(enumerator, nullptr, nullptr);
    g_object_unref(enumerator);

    // Copy directory metadata (permissions, timestamps) from source to destination
    GError *attrErr = nullptr;
    GFileInfo *srcInfo = g_file_query_info(source,
        "unix::mode,time::modified,time::modified-usec,time::access,time::access-usec",
        G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS, m_cancellable, &attrErr);
    if (srcInfo) {
        GError *setErr = nullptr;
        g_file_set_attributes_from_info(destination, srcInfo, G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS,
            m_cancellable, &setErr);
        if (setErr) g_error_free(setErr);
        g_object_unref(srcInfo);
    }
    if (attrErr) g_error_free(attrErr);

    return true;
}

bool GioTransferWorker::deleteRecursive(GFile *file, QString *error)
{
    // Try to enumerate children (if not a dir, this fails — do direct delete)
    GError *enumErr = nullptr;
    GFileEnumerator *enumerator = g_file_enumerate_children(file,
        G_FILE_ATTRIBUTE_STANDARD_NAME,
        G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS, m_cancellable, &enumErr);

    if (!enumerator) {
        // Not a directory, direct delete
        if (enumErr) g_error_free(enumErr);
        GError *delErr = nullptr;
        gboolean ok = g_file_delete(file, m_cancellable, &delErr);
        if (!ok) {
            *error = gErrorToUserMessage(delErr);
            if (delErr) g_error_free(delErr);
            return false;
        }
        return true;
    }

    // Delete children recursively
    GFileInfo *childInfo;
    while ((childInfo = g_file_enumerator_next_file(enumerator, m_cancellable, nullptr)) != nullptr) {
        const char *name = g_file_info_get_name(childInfo);
        GFile *child = g_file_get_child(file, name);
        g_object_unref(childInfo);

        if (!deleteRecursive(child, error)) {
            g_object_unref(child);
            g_file_enumerator_close(enumerator, nullptr, nullptr);
            g_object_unref(enumerator);
            return false;
        }
        g_object_unref(child);
    }

    g_file_enumerator_close(enumerator, nullptr, nullptr);
    g_object_unref(enumerator);

    // Delete the directory itself
    GError *delErr = nullptr;
    gboolean ok = g_file_delete(file, m_cancellable, &delErr);
    if (!ok) {
        *error = gErrorToUserMessage(delErr);
        if (delErr) g_error_free(delErr);
        return false;
    }
    return true;
}

QString GioTransferWorker::gErrorToUserMessage(GError *error)
{
    if (!error)
        return {};

    if (error->domain == G_IO_ERROR) {
        switch (error->code) {
        case G_IO_ERROR_NO_SPACE:
            return QStringLiteral("Not enough disk space");
        case G_IO_ERROR_PERMISSION_DENIED:
            return QStringLiteral("Permission denied");
        case G_IO_ERROR_NOT_FOUND:
            return QStringLiteral("Source file not found");
        case G_IO_ERROR_CANCELLED:
            return {};
        default:
            break;
        }
    }

    return QString::fromUtf8(error->message);
}
