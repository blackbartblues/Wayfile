cmake_minimum_required(VERSION 3.20)
project(wayfile VERSION 1.0.1 LANGUAGES CXX)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-2.0 gio-unix-2.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 DBus Widgets SvgWidgets Svg Network Concurrent Multimedia)
find_package(KF6WindowSystem QUIET)

add_subdirectory(src)

# Install themes
install(DIRECTORY themes/ DESTINATION share/wayfile/themes FILES_MATCHING PATTERN "*.toml")

# Install QML sources (Quill module + icons needed at runtime)
install(DIRECTORY src/qml/ DESTINATION share/wayfile/src/qml)

# Install the generated Wayfile QML module: qmldir + qml/ tree + qmltypes.
# Without the qml/ subtree on disk, Qt has nothing to fall back on if the
# embedded qrc bundle is missing a file (we hit exactly that with Qt 6.7.3
# in v0.4.14, where SettingsPanel.qml made it into the qmldir but not into
# qrc_wayfile_raw_qml_0, leaving "SettingsPanel is not a type" at runtime).
install(DIRECTORY ${CMAKE_BINARY_DIR}/src/Wayfile/
    DESTINATION share/wayfile/Wayfile
    FILES_MATCHING
        PATTERN "*.qml"
        PATTERN "qmldir"
        PATTERN "*.qmltypes")

# Qt generates `prefer :/Wayfile/` in the module qmldir. That makes deployed
# bundles keep resolving Wayfile types from the embedded qrc even when the
# installed on-disk module has the full file set, which is exactly how a
# missing qrc SettingsPanel.qml turns into "SettingsPanel is not a type".
install(CODE [[
    set(_wayfile_qmldir "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/share/wayfile/Wayfile/qmldir")
    if(EXISTS "${_wayfile_qmldir}")
        file(READ "${_wayfile_qmldir}" _wayfile_qmldir_contents)
        string(REPLACE "prefer :/Wayfile/\n" "" _wayfile_qmldir_contents "${_wayfile_qmldir_contents}")
        string(REPLACE "prefer :/Wayfile/\r\n" "" _wayfile_qmldir_contents "${_wayfile_qmldir_contents}")
        file(WRITE "${_wayfile_qmldir}" "${_wayfile_qmldir_contents}")
    endif()
]])

option(BUILD_TESTS "Build tests" ON)
if(BUILD_TESTS)
    enable_testing()
    find_package(Qt6 REQUIRED COMPONENTS Test)
    add_subdirectory(tests)
endif()
