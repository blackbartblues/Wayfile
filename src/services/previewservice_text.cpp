#include "services/previewservice.h"
#include "services/previewservice_internal.h"

#include <QColor>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>

#include <memory>

// Text preview path: ANSI→HTML conversion, bat syntax highlighting, and the
// plain/highlight/trash/directory text loaders (sync + async). Split out of
// previewservice.cpp. Shares encodedUri/startGioCat with the core TU via
// previewservice_internal.h; the ANSI/bat helpers and batExecutable are local.

using namespace previewservice_detail;

namespace {

QString batExecutable()
{
    static const QString executable = []() {
        const QString bat = QStandardPaths::findExecutable(QStringLiteral("bat"));
        if (!bat.isEmpty())
            return bat;
        return QStandardPaths::findExecutable(QStringLiteral("batcat"));
    }();

    return executable;
}

QColor ansiColor(int code, bool bright)
{
    static const QColor normalColors[] = {
        QColor(QStringLiteral("#1e1e2e")), QColor(QStringLiteral("#f38ba8")),
        QColor(QStringLiteral("#a6e3a1")), QColor(QStringLiteral("#f9e2af")),
        QColor(QStringLiteral("#89b4fa")), QColor(QStringLiteral("#cba6f7")),
        QColor(QStringLiteral("#94e2d5")), QColor(QStringLiteral("#bac2de"))
    };
    static const QColor brightColors[] = {
        QColor(QStringLiteral("#45475a")), QColor(QStringLiteral("#eba0ac")),
        QColor(QStringLiteral("#a6e3a1")), QColor(QStringLiteral("#f9e2af")),
        QColor(QStringLiteral("#89dceb")), QColor(QStringLiteral("#f5c2e7")),
        QColor(QStringLiteral("#94e2d5")), QColor(QStringLiteral("#f5e0dc"))
    };

    if (code < 0 || code > 7)
        return {};
    return bright ? brightColors[code] : normalColors[code];
}

QColor ansi256Color(int index)
{
    if (index < 0)
        return {};
    if (index < 8)
        return ansiColor(index, false);
    if (index < 16)
        return ansiColor(index - 8, true);
    if (index < 232) {
        const int base = index - 16;
        const int r = base / 36;
        const int g = (base / 6) % 6;
        const int b = base % 6;
        auto scale = [](int value) { return value == 0 ? 0 : 55 + value * 40; };
        return QColor(scale(r), scale(g), scale(b));
    }
    if (index < 256) {
        const int gray = 8 + (index - 232) * 10;
        return QColor(gray, gray, gray);
    }
    return {};
}

struct AnsiState {
    bool bold = false;
    bool italic = false;
    bool underline = false;
    QColor fg;
    QColor bg;
};

QString htmlStyle(const AnsiState &state)
{
    QStringList style;
    if (state.fg.isValid())
        style.append(QStringLiteral("color:%1").arg(state.fg.name()));
    if (state.bg.isValid())
        style.append(QStringLiteral("background-color:%1").arg(state.bg.name()));
    if (state.bold)
        style.append(QStringLiteral("font-weight:700"));
    if (state.italic)
        style.append(QStringLiteral("font-style:italic"));
    if (state.underline)
        style.append(QStringLiteral("text-decoration:underline"));
    return style.join(QStringLiteral(";"));
}

void applyAnsiCode(AnsiState &state, const QList<int> &codes)
{
    QList<int> values = codes;
    if (values.isEmpty())
        values.append(0);

    for (int i = 0; i < values.size(); ++i) {
        const int code = values.at(i);
        if (code == 0) {
            state = {};
        } else if (code == 1) {
            state.bold = true;
        } else if (code == 3) {
            state.italic = true;
        } else if (code == 4) {
            state.underline = true;
        } else if (code == 22) {
            state.bold = false;
        } else if (code == 23) {
            state.italic = false;
        } else if (code == 24) {
            state.underline = false;
        } else if (code >= 30 && code <= 37) {
            state.fg = ansiColor(code - 30, false);
        } else if (code >= 90 && code <= 97) {
            state.fg = ansiColor(code - 90, true);
        } else if (code == 39) {
            state.fg = QColor();
        } else if (code >= 40 && code <= 47) {
            state.bg = ansiColor(code - 40, false);
        } else if (code >= 100 && code <= 107) {
            state.bg = ansiColor(code - 100, true);
        } else if (code == 49) {
            state.bg = QColor();
        } else if ((code == 38 || code == 48) && i + 1 < values.size()) {
            QColor color;
            const int mode = values.at(++i);
            if (mode == 5 && i + 1 < values.size()) {
                color = ansi256Color(values.at(++i));
            } else if (mode == 2 && i + 3 < values.size()) {
                color = QColor(values.at(i + 1), values.at(i + 2), values.at(i + 3));
                i += 3;
            }

            if (code == 38)
                state.fg = color;
            else
                state.bg = color;
        }
    }
}

QString ansiToHtml(const QByteArray &ansiText)
{
    QString html = QStringLiteral("<pre style=\"margin:0;font-family:monospace;white-space:pre;\">");
    AnsiState state;
    bool spanOpen = false;

    auto updateSpan = [&]() {
        if (spanOpen) {
            html += QStringLiteral("</span>");
            spanOpen = false;
        }
        const QString style = htmlStyle(state);
        if (!style.isEmpty()) {
            html += QStringLiteral("<span style=\"") + style.toHtmlEscaped() + QStringLiteral("\">");
            spanOpen = true;
        }
    };

    int index = 0;
    while (index < ansiText.size()) {
        if (ansiText.at(index) == '\x1b' && index + 1 < ansiText.size() && ansiText.at(index + 1) == '[') {
            const int seqStart = index + 2;
            int seqEnd = seqStart;
            while (seqEnd < ansiText.size() && ansiText.at(seqEnd) != 'm')
                ++seqEnd;

            if (seqEnd < ansiText.size() && ansiText.at(seqEnd) == 'm') {
                const QByteArray params = ansiText.mid(seqStart, seqEnd - seqStart);
                QList<int> codes;
                const QList<QByteArray> parts = params.split(';');
                for (const QByteArray &part : parts) {
                    if (part.isEmpty())
                        codes.append(0);
                    else
                        codes.append(part.toInt());
                }
                applyAnsiCode(state, codes);
                updateSpan();
                index = seqEnd + 1;
                continue;
            }
        }

        int nextEscape = ansiText.indexOf('\x1b', index);
        if (nextEscape < 0)
            nextEscape = ansiText.size();
        QString chunk = QString::fromUtf8(ansiText.mid(index, nextEscape - index));
        chunk.replace(QStringLiteral("\t"), QStringLiteral("    "));
        html += chunk.toHtmlEscaped();
        index = nextEscape;
    }

    if (spanOpen)
        html += QStringLiteral("</span>");
    html += QStringLiteral("</pre>");
    return html;
}

QByteArray batPreview(const QByteArray &data, const QString &fileName, int maxLines, QString *error)
{
    if (error)
        error->clear();

    const QString executable = batExecutable();
    if (executable.isEmpty())
        return {};

    QStringList args = {
        QStringLiteral("--color=always"),
        QStringLiteral("--paging=never"),
        QStringLiteral("--style=plain"),
        QStringLiteral("--wrap=never")
    };
    if (maxLines > 0)
        args.append(QStringLiteral("--line-range=:%1").arg(maxLines));
    if (!fileName.isEmpty())
        args.append(QStringLiteral("--file-name=") + fileName);
    args.append(QStringLiteral("-"));

    QProcess proc;
    proc.start(executable, args);
    if (!proc.waitForStarted(5000)) {
        if (error)
            *error = QStringLiteral("bat failed to start");
        return {};
    }
    proc.write(data);
    proc.closeWriteChannel();
    if (!proc.waitForFinished(10000)) {
        if (error)
            *error = QStringLiteral("bat preview timed out");
        return {};
    }
    if (proc.exitCode() != 0) {
        if (error)
            *error = QString::fromUtf8(proc.readAllStandardError()).trimmed();
        return {};
    }

    return proc.readAllStandardOutput();
}

}

QVariantMap PreviewService::buildTextPlainResult(const QByteArray &data, bool truncated, int maxLines)
{
    const bool binary = looksBinary(data);
    QString text;
    if (!binary)
        text = decodeText(data);

    QStringList lines = text.split('\n');
    if (maxLines > 0 && lines.size() > maxLines) {
        lines = lines.mid(0, maxLines);
        truncated = true;
    }

    QVariantMap result;
    result["content"] = lines.join('\n');
    result["html"] = QString();
    result["truncated"] = truncated;
    result["isBinary"] = binary;
    result["usesBat"] = false;
    result["error"] = QString();
    result["lineCount"] = lines.size();
    return result;
}

QVariantMap PreviewService::loadTextPlain(const QString &path, int maxBytes, int maxLines) const
{
    bool truncated = false;
    QString error;
    const QByteArray data = readPathBytes(path, maxBytes, &truncated, &error);

    if (!error.isEmpty()) {
        QVariantMap result;
        result["content"] = QString();
        result["html"] = QString();
        result["truncated"] = false;
        result["isBinary"] = false;
        result["usesBat"] = false;
        result["error"] = error;
        return result;
    }

    return buildTextPlainResult(data, truncated, maxLines);
}

QVariantMap PreviewService::loadTextPreview(const QString &path, int maxBytes, int maxLines) const
{
    // Plain text plus bat syntax highlighting in one blocking call (kept for
    // tests / callers that want a synchronous result). The QML preview uses the
    // async path instead: loadTextPlain() renders instantly, then
    // requestTextHighlight() layers the highlight on without blocking the GUI.
    QVariantMap result = loadTextPlain(path, maxBytes, maxLines);
    if (!result.value("error").toString().isEmpty() || result.value("isBinary").toBool())
        return result;

    bool truncated = false;
    QString error;
    const QByteArray data = readPathBytes(path, maxBytes, &truncated, &error);
    QString batError;
    const QString fileName = QFileInfo(path).fileName();
    const QByteArray coloredOutput = batPreview(data, fileName, maxLines, &batError);
    if (!coloredOutput.isEmpty()) {
        result["html"] = ansiToHtml(coloredOutput);
        result["usesBat"] = true;
    }
    return result;
}

void PreviewService::requestTextHighlight(const QString &path, int maxBytes, int maxLines)
{
    // A highlight for this exact path is already running. Its previewReady will
    // reach every consumer guarding on this path, so don't start a duplicate —
    // this also means two panes previewing the same file share one bat process.
    if (m_textProcs.contains(path))
        return;

    // The plain result is both the instant render the QML already showed and
    // the fallback when there's nothing to highlight. Re-read the byte-capped
    // data for bat's stdin (cheap — capped at maxBytes).
    const QVariantMap plain = loadTextPlain(path, maxBytes, maxLines);
    bool truncated = false;
    QString error;
    const QByteArray data = readPathBytes(path, maxBytes, &truncated, &error);
    const QString executable = batExecutable();

    if (!error.isEmpty() || plain.value("isBinary").toBool() || data.isEmpty()
        || executable.isEmpty()) {
        // Read error, binary, empty, or no bat installed — nothing to highlight.
        // Emit the plain result once; no process is spawned.
        emit previewReady(QStringLiteral("text"), path, plain);
        return;
    }

    QStringList args = {
        QStringLiteral("--color=always"),
        QStringLiteral("--paging=never"),
        QStringLiteral("--style=plain"),
        QStringLiteral("--wrap=never")
    };
    if (maxLines > 0)
        args.append(QStringLiteral("--line-range=:%1").arg(maxLines));
    const QString fileName = QFileInfo(path).fileName();
    if (!fileName.isEmpty())
        args.append(QStringLiteral("--file-name=") + fileName);
    args.append(QStringLiteral("-"));

    auto *proc = new QProcess(this);
    m_textProcs.insert(path, proc);

    connect(proc, &QProcess::finished, this,
            [this, proc, path, plain](int code, QProcess::ExitStatus status) {
                // Ignore if this proc is no longer the tracked highlight for
                // `path` (superseded/cancelled). value() defaults to nullptr.
                if (m_textProcs.value(path) != proc) {
                    proc->deleteLater();
                    return;
                }
                m_textProcs.remove(path);
                QVariantMap result = plain;
                if (status == QProcess::NormalExit && code == 0) {
                    const QByteArray out = proc->readAllStandardOutput();
                    if (!out.isEmpty()) {
                        result["html"] = ansiToHtml(out);
                        result["usesBat"] = true;
                    }
                }
                // On non-zero exit / crash (incl. watchdog kill) fall back to the
                // plain result so the preview still shows the file.
                emit previewReady(QStringLiteral("text"), path, result);
                proc->deleteLater();
            });
    connect(proc, &QProcess::errorOccurred, this,
            [this, proc, path, plain](QProcess::ProcessError) {
                if (m_textProcs.value(path) != proc) {
                    proc->deleteLater();
                    return;
                }
                m_textProcs.remove(path);
                emit previewReady(QStringLiteral("text"), path, plain);
                proc->deleteLater();
            });

    armProcessTimeout(proc, 10000);
    proc->start(executable, args);
    // QProcess buffers writes made while it's still starting and flushes them
    // once it's running; closeWriteChannel closes stdin after that flush. bat
    // deadlocks waiting on stdin if the channel is never closed.
    proc->write(data);
    proc->closeWriteChannel();
}

void PreviewService::requestTrashText(const QString &path, int maxBytes, int maxLines)
{
    // A read for this exact path is already running (shares m_textProcs with
    // the bat highlighter — a path is either trash or not, never both, so they
    // never collide). Its previewReady reaches every consumer guarding on path.
    if (m_textProcs.contains(path))
        return;

    auto *proc = new QProcess(this);
    m_textProcs.insert(path, proc);

    // Accumulate stdout, capping memory the way the sync readPathBytes does:
    // kill `gio cat` once we have one byte past maxBytes (then truncate).
    const qint64 readLimit = qMax<qint64>(1, maxBytes) + 1;
    auto buffer = std::make_shared<QByteArray>();
    connect(proc, &QProcess::readyReadStandardOutput, proc, [proc, buffer, readLimit]() {
        *buffer += proc->readAllStandardOutput();
        if (buffer->size() >= readLimit && proc->state() != QProcess::NotRunning)
            proc->kill();
    });

    connect(proc, &QProcess::finished, this,
            [this, proc, path, buffer, maxBytes, maxLines](int, QProcess::ExitStatus status) {
                if (m_textProcs.value(path) != proc) {
                    proc->deleteLater();
                    return;
                }
                m_textProcs.remove(path);
                *buffer += proc->readAllStandardOutput();

                QByteArray data = *buffer;
                bool truncated = false;
                if (data.size() > maxBytes) {
                    truncated = true;
                    data.truncate(maxBytes);
                }

                QVariantMap result;
                // Killing at the read limit yields CrashExit with data present;
                // only an abnormal exit with NO data is a real read failure
                // (mirrors readPathBytes).
                if (status != QProcess::NormalExit && data.isEmpty()) {
                    result["content"] = QString();
                    result["html"] = QString();
                    result["truncated"] = false;
                    result["isBinary"] = false;
                    result["usesBat"] = false;
                    result["error"] = QStringLiteral("Failed to read preview data");
                } else {
                    result = buildTextPlainResult(data, truncated, maxLines);
                }
                emit previewReady(QStringLiteral("text"), path, result);
                proc->deleteLater();
            });
    connect(proc, &QProcess::errorOccurred, this,
            [this, proc, path](QProcess::ProcessError err) {
                // A process that started and then died still fires finished;
                // only handle the can't-start case here to avoid double-emit.
                if (err != QProcess::FailedToStart)
                    return;
                if (m_textProcs.value(path) != proc) {
                    proc->deleteLater();
                    return;
                }
                m_textProcs.remove(path);
                QVariantMap result;
                result["content"] = QString();
                result["html"] = QString();
                result["truncated"] = false;
                result["isBinary"] = false;
                result["usesBat"] = false;
                result["error"] = QStringLiteral("Failed to start preview reader");
                emit previewReady(QStringLiteral("text"), path, result);
                proc->deleteLater();
            });

    armProcessTimeout(proc, 5000);
    startGioCat(*proc, encodedUri(path));
}

void PreviewService::requestDirectoryPreview(const QString &path, int maxEntries)
{
    if (m_dirProcs.contains(path))
        return;

    auto *proc = new QProcess(this);
    m_dirProcs.insert(path, proc);

    connect(proc, &QProcess::finished, this,
            [this, proc, path, maxEntries](int code, QProcess::ExitStatus status) {
                if (m_dirProcs.value(path) != proc) {
                    proc->deleteLater();
                    return;
                }
                m_dirProcs.remove(path);
                QVariantMap result;
                if (status != QProcess::NormalExit || code != 0) {
                    result["entries"] = QStringList();
                    result["truncated"] = false;
                    result["error"] = QString::fromUtf8(proc->readAllStandardError()).trimmed();
                    result["count"] = 0;
                } else {
                    const QStringList allEntries =
                        QString::fromUtf8(proc->readAllStandardOutput()).split('\n', Qt::SkipEmptyParts);
                    const bool truncated = maxEntries > 0 && allEntries.size() > maxEntries;
                    const QStringList entries = maxEntries > 0 ? allEntries.mid(0, maxEntries) : allEntries;
                    result["entries"] = entries;
                    result["truncated"] = truncated;
                    result["error"] = QString();
                    result["count"] = entries.size();
                }
                emit previewReady(QStringLiteral("directory"), path, result);
                proc->deleteLater();
            });
    connect(proc, &QProcess::errorOccurred, this,
            [this, proc, path](QProcess::ProcessError) {
                if (m_dirProcs.value(path) != proc) {
                    proc->deleteLater();
                    return;
                }
                m_dirProcs.remove(path);
                QVariantMap result;
                result["entries"] = QStringList();
                result["truncated"] = false;
                result["error"] = QStringLiteral("Could not list folder contents");
                result["count"] = 0;
                emit previewReady(QStringLiteral("directory"), path, result);
                proc->deleteLater();
            });

    armProcessTimeout(proc, 5000);
    // Matches the sync listDirectoryEntries trash branch: plain `gio list -h`.
    proc->start(QStringLiteral("gio"), {QStringLiteral("list"), QStringLiteral("-h"), encodedUri(path)});
}
