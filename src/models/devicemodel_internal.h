#pragma once

#include <QString>

// GIO headers use 'signals' as a struct member, which conflicts with Qt's
// signals keyword. Temporarily undefine it before including GIO headers.
#undef signals
#include <gio/gio.h>
#define signals Q_SIGNALS

// The single free helper shared between devicemodel_enumerate.cpp (where it is
// defined and used by applyManagedObjects) and devicemodel_mount.cpp (used by
// the GIO mount callback). Every other helper is TU-local to its consumer.
namespace devicemodel_detail {

QString uriFromGFile(GFile *file);

} // namespace devicemodel_detail
