pragma Singleton
import QtQuick

// Centralised model-role ints for QML-side `model.data(index, role)` calls.
// These mirror the C++ role enums and MUST stay in sync with the headers below.
// Qt.UserRole == 256; each enum member increments from `Qt::UserRole + 1`.
//
// Single source of truth for the magic role ints that several views and the
// sidebar previously hard-coded inline (258/257/265). Reference them by name,
// e.g. `Roles.fs.path`, `Roles.bookmark.name`.
QtObject {
    // FileSystemModel::Roles — src/models/filesystemmodel.h
    readonly property QtObject fs: QtObject {
        readonly property int name: 257   // FileNameRole = Qt::UserRole + 1
        readonly property int path: 258   // FilePathRole
        readonly property int isDir: 265  // IsDirRole
    }

    // BookmarkModel::Roles — src/models/bookmarkmodel.h
    readonly property QtObject bookmark: QtObject {
        readonly property int name: 257   // NameRole = Qt::UserRole + 1
        readonly property int path: 258   // PathRole
    }
}
