import QtQuick
import Wayfile

// Shared, non-visual preview state + loaders for the two file-preview surfaces
// (the QuickPreview overlay and FileMillerView's preview column). Both used to
// duplicate ~200 lines of identical file-type detection, async preview/metadata
// loading and PDF paging. That logic now lives here once; each surface keeps
// its own (intentionally different) rendering and forwards to this object.
//
// Inputs:
//   filePath   — file/URI to preview ("" clears everything)
//   isDir      — whether filePath is a directory. QuickPreview binds this to
//                fileProps.isDir; Miller sets it externally from navigation
//                (it must be set before filePath — see the first-load-blank fix).
//   fileModel  — model used for fileProperties() lookups (defaults to fsModel).
//   loadEnabled — when false, refresh() is a no-op and stale data is kept (lets
//                 QuickPreview avoid loading while the overlay is hidden).
//
// Computed flags / data (read-only by convention; consumers only read them):
//   fileProps, is* flags, *Preview data, fileMetadata, metadataHint,
//   metadataLoading, pdfPageIndex, detailKind, metadataEntries, visualSource,
//   pdfImageSource, pdfPageLabel, fileName.
Item {
    id: state

    property string filePath: ""
    property bool isDir: false
    property var fileModel: fsModel
    property bool loadEnabled: true

    property var fileProps: ({})
    property var textPreview: ({ content: "", truncated: false, isBinary: false, error: "" })
    property var directoryPreview: ({ entries: [], truncated: false, error: "", count: 0 })
    property var pdfPreview: ({ localPath: "", pageCount: 0, error: "" })
    property var fontPreview: ({ family: "", styleName: "", weight: 400, italic: false, valid: false, error: "" })
    property var fileMetadata: ({})
    property string metadataHint: ""
    property bool metadataLoading: false
    property int pdfPageIndex: 0
    property real pdfWheelAccumulator: 0

    property string fileName: {
        if (fileProps.name)
            return fileProps.name
        if (filePath === "")
            return ""
        var idx = filePath.lastIndexOf("/")
        return idx >= 0 ? filePath.substring(idx + 1) : filePath
    }
    property string fileExtension: {
        var name = fileName
        var dot = name.lastIndexOf(".")
        return dot >= 0 ? name.substring(dot + 1).toLowerCase() : ""
    }

    property string _mime: fileProps.mimeType || ""
    property bool isRemoteUri: filePath !== "" && fileOps.isRemotePath(filePath)
    property bool isTrashUri: filePath.startsWith("trash:///")
    property bool isArchive: !isDir && fileOps.isArchive(filePath)
    property bool isImage: !isRemoteUri && !isDir && _mime.startsWith("image/")
    // SVGs need explicit routing through the thumbnail provider (QSvgRenderer
    // path). Qt's default Image handler treats viewBox-only SVGs as 0×0.
    property bool isSvg: isImage && _mime === "image/svg+xml"
    property bool isVideo: !isRemoteUri && !isDir && _mime.startsWith("video/")
    property bool isAudio: !isRemoteUri && !isDir && _mime.startsWith("audio/")
    property bool isPdf: !isRemoteUri && !isDir && _mime === "application/pdf"
    property bool isFont: {
        if (isRemoteUri || isDir)
            return false
        if (_mime.startsWith("font/") || _mime === "application/x-font-ttf"
            || _mime === "application/x-font-otf" || _mime === "application/vnd.ms-fontobject")
            return true
        return ["ttf", "otf", "woff", "woff2"].indexOf(fileExtension) >= 0
    }
    property bool isText: {
        if (isRemoteUri || isDir || isPdf || isImage || isVideo || isAudio || isArchive || isFont)
            return false
        if (_mime.startsWith("text/"))
            return true
        var textMimes = [
            "application/json", "application/xml", "application/x-yaml",
            "application/toml", "application/x-shellscript",
            "application/javascript", "application/typescript",
            "application/x-tex", "application/x-makefile",
            "application/x-desktop", "application/x-ruby",
            "application/x-perl", "application/x-python"
        ]
        if (textMimes.indexOf(_mime) >= 0)
            return true
        // Fallback: extensionless files and known text extensions not covered by MIME
        if (fileExtension === "")
            return filePath !== ""
        var textExt = ["txt", "md", "json", "yaml", "yml", "toml", "ini", "cfg", "conf",
                       "sh", "bash", "zsh", "fish", "py", "js", "ts", "tsx", "jsx",
                       "css", "html", "htm", "xml", "c", "cpp", "h", "hpp", "rs",
                       "go", "java", "tex", "rb", "lua", "vim", "log", "diff",
                       "patch", "cmake", "qml", "mk", "desktop"]
        return textExt.indexOf(fileExtension) >= 0
    }
    property bool pdfPreviewAvailable: previewService.pdfPreviewAvailable
    property bool videoPreviewAvailable: runtimeFeatures.ffmpegAvailable
    property bool textHighlightAvailable: runtimeFeatures.batAvailable
    property bool hasVisualPreview: isImage || (isVideo && videoPreviewAvailable)
    property string visualSource: {
        if (!hasVisualPreview || filePath === "")
            return ""
        if (isVideo || isTrashUri || isSvg)
            return "image://thumbnail/" + filePath
        return "file://" + filePath
    }
    property string pdfImageSource: {
        if (!isPdf || !pdfPreview.localPath || pdfPreview.error !== "")
            return ""
        return "image://pdfpreview/" + encodeURIComponent(pdfPreview.localPath)
            + "?page=" + pdfPageIndex
    }
    property string pdfPageLabel: {
        if (!isPdf || pdfPreview.pageCount <= 0)
            return ""
        return "Page " + (pdfPageIndex + 1) + " of " + pdfPreview.pageCount
    }
    property string detailKind: {
        if (isDir)
            return "Folder"
        if (isArchive)
            return "Archive"
        if (isAudio)
            return "Audio"
        if (isVideo)
            return "Video"
        if (fileProps.mimeDescription)
            return fileProps.mimeDescription
        if (fileExtension !== "")
            return fileExtension.toUpperCase() + " file"
        return "File"
    }
    property var metadataEntries: {
        var result = []
        var md = fileMetadata || {}
        var keys = Object.keys(md)
        for (var i = 0; i < keys.length; ++i) {
            var value = md[keys[i]]
            if (value !== undefined && value !== null && String(value) !== "")
                result.push({ label: keys[i], value: String(value) })
        }
        return result
    }

    function changePdfPage(delta) {
        if (!isPdf || pdfPreview.pageCount <= 0)
            return
        pdfPageIndex = Math.max(0, Math.min(pdfPreview.pageCount - 1, pdfPageIndex + delta))
    }

    function handlePdfWheel(wheel) {
        if (!isPdf || pdfPreview.pageCount <= 1)
            return

        var delta = 0
        if (wheel.angleDelta && wheel.angleDelta.y !== 0)
            delta = wheel.angleDelta.y
        else if (wheel.pixelDelta && wheel.pixelDelta.y !== 0)
            delta = wheel.pixelDelta.y * 3

        if (delta === 0)
            return

        pdfWheelAccumulator += delta
        while (pdfWheelAccumulator >= 120) {
            changePdfPage(-1)
            pdfWheelAccumulator -= 120
        }
        while (pdfWheelAccumulator <= -120) {
            changePdfPage(1)
            pdfWheelAccumulator += 120
        }

        wheel.accepted = true
    }

    function refresh() {
        if (filePath === "") {
            fileProps = ({})
            textPreview = ({ content: "", truncated: false, isBinary: false, error: "" })
            directoryPreview = ({ entries: [], truncated: false, error: "", count: 0 })
            pdfPreview = ({ localPath: "", pageCount: 0, error: "" })
            fontPreview = ({ family: "", styleName: "", weight: 400, italic: false, valid: false, error: "" })
            fileMetadata = ({})
            metadataLoading = false
            metadataHint = ""
            return
        }

        // Keep stale data while a consumer (e.g. the hidden QuickPreview overlay)
        // has us disabled — avoids loading previews that aren't visible.
        if (!loadEnabled)
            return

        if (fileModel && fileModel.fileProperties)
            fileProps = fileModel.fileProperties(filePath)
        else
            fileProps = ({})

        if (isRemoteUri) {
            textPreview = ({ content: "", truncated: false, isBinary: false, error: "" })
            directoryPreview = ({ entries: [], truncated: false, error: "", count: 0 })
            pdfPreview = ({ localPath: "", pageCount: 0, error: "" })
            fontPreview = ({ family: "", styleName: "", weight: 400, italic: false, valid: false, error: "" })
            fileMetadata = ({})
            metadataLoading = false
            metadataHint = ""
            return
        }

        if (isText) {
            if (isTrashUri) {
                // Reading a trash entry goes through `gio cat`, which blocks, so
                // load it async and show a placeholder until previewReady("text").
                textPreview = ({ content: "", truncated: false, isBinary: false, error: "", loading: true })
                previewService.requestTrashText(filePath)
            } else {
                // Render plain text instantly, then highlight asynchronously so a
                // slow/hung bat can't block the GUI. The highlighted result arrives
                // via onPreviewReady and just fades in over identical content.
                textPreview = previewService.loadTextPlain(filePath)
                previewService.requestTextHighlight(filePath)
            }
        } else {
            textPreview = ({ content: "", truncated: false, isBinary: false, error: "" })
        }

        if (isPdf) {
            // pdfinfo can block for seconds, so load asynchronously and show a
            // placeholder until previewReady.
            pdfPreview = ({ localPath: "", pageCount: 0, error: "", loading: true })
            previewService.requestPdfPreview(filePath)
        } else {
            pdfPreview = ({ localPath: "", pageCount: 0, error: "" })
        }

        if (isFont)
            fontPreview = previewService.loadFontPreview(filePath)
        else
            fontPreview = ({ family: "", styleName: "", weight: 400, italic: false, valid: false, error: "" })

        if (isDir) {
            if (isTrashUri) {
                // Listing a trash folder goes through `gio list`, which blocks,
                // so load it async and show a placeholder until
                // previewReady("directory").
                directoryPreview = ({ entries: [], truncated: false, error: "", count: 0, loading: true })
                previewService.requestDirectoryPreview(filePath)
            } else {
                directoryPreview = previewService.loadDirectoryPreview(filePath)
            }
        } else if (isArchive) {
            // Listing a large archive (unzip/tar/7z) can block for seconds, so
            // load it asynchronously and show a placeholder until previewReady.
            directoryPreview = ({ entries: [], truncated: false, error: "", count: 0, loading: true })
            previewService.requestArchivePreview(filePath)
        } else
            directoryPreview = ({ entries: [], truncated: false, error: "", count: 0 })

        // Extract rich metadata. exiftool/ffprobe/pdfinfo can block for seconds,
        // so extract asynchronously and show a placeholder until metadataReady.
        fileMetadata = ({})
        metadataLoading = true
        metadataExtractor.requestExtract(filePath)
        metadataHint = metadataExtractor.missingDepsHint(fileProps.mimeType || "")
    }

    onFilePathChanged: {
        pdfPageIndex = 0
        pdfWheelAccumulator = 0
        refresh()
    }
    onLoadEnabledChanged: refresh()
    onFileModelChanged: {
        pdfWheelAccumulator = 0
        refresh()
    }

    // Async metadata result. Guard on filePath so a slow extraction for a file
    // the user already navigated away from doesn't overwrite the current preview.
    Connections {
        target: metadataExtractor
        function onMetadataReady(path, result) {
            if (path === state.filePath) {
                state.fileMetadata = result
                state.metadataLoading = false
            }
        }
    }

    // Async preview results (archive listing, pdfinfo, text highlight). Guard on
    // filePath so a slow result for a file the user already navigated away from
    // doesn't overwrite the current preview.
    Connections {
        target: previewService
        function onPreviewReady(kind, path, result) {
            if ((kind === "archive" || kind === "directory") && path === state.filePath)
                state.directoryPreview = result
            else if (kind === "pdf" && path === state.filePath) {
                state.pdfPreview = result
                if (state.pdfPageIndex >= (state.pdfPreview.pageCount || 0))
                    state.pdfPageIndex = 0
            }
            else if (kind === "text" && path === state.filePath)
                state.textPreview = result
        }
    }
}
