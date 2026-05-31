#pragma once

#include <QLoggingCategory>
#include <QString>

// GIO headers use 'signals' as a struct member, which conflicts with Qt's
// signals keyword. Temporarily undefine it before including GIO headers.
#undef signals
#include <gio/gio.h>
#define signals Q_SIGNALS

// Defined in giotransferworker.cpp; shared by the recursive TU for logging.
Q_DECLARE_LOGGING_CATEGORY(lcTransfer)

// Free helpers shared between giotransferworker.cpp (orchestration in execute())
// and giotransferworker_recursive.cpp (scan/copy/delete). Defined once in the
// core TU.
namespace giotransferworker_detail {

GFile *gFileForLocation(const QString &path);
QString humanizeMobileDeviceError(const QString &raw);
bool mountEnclosingVolumeSync(GFile *file, QString *errorOut, int *errCodeOut);

} // namespace giotransferworker_detail
