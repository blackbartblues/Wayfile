#pragma once

#include <QString>

class QProcess;

// Free helpers shared across previewservice.cpp (core), previewservice_text.cpp
// and previewservice_binary.cpp. Defined once in the core TU. runningInFlatpak
// and batExecutable stay TU-local to their sole consumers.
namespace previewservice_detail {

QString encodedUri(const QString &path);

// Spawn `gio cat <uri>` for reading trash:// URIs. Inside a Flatpak we route
// through `flatpak-spawn --host` so the host's gio reads from the host's real
// trash (the sandbox's gio sees only an empty per-app trash).
void startGioCat(QProcess &proc, const QString &uri);

} // namespace previewservice_detail
