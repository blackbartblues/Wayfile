import QtQuick
import QtQuick.Controls
import Heimdall

// Miller view preview column — owns its PreviewState and renders the
// per-kind preview (directory/archive/image/video/PDF/text/font/fallback)
// plus the metadata info bar. Extracted verbatim from FileMillerView.qml;
// the parent sets previewFilePath/previewIsDir via root.updatePreview().
Item {
    id: previewColumn
    property string previewFilePath: ""
    property bool previewIsDir: false

    // Shared preview state + loaders — file-type detection, async
    // preview/metadata loading and PDF paging all live in
    // PreviewState.qml (previously duplicated here and in QuickPreview).
    // previewIsDir is set before previewFilePath in updatePreview() so
    // the refresh triggered by the filePath change sees the right flag.
    PreviewState {
        id: previewState
        filePath: previewColumn.previewFilePath
        isDir: previewColumn.previewIsDir
    }

    // Forward the shared state so the rendering below stays unchanged.
    property alias fileProps: previewState.fileProps
    property alias textPreview: previewState.textPreview
    property alias directoryPreview: previewState.directoryPreview
    property alias pdfPreview: previewState.pdfPreview
    property alias fontPreview: previewState.fontPreview
    property alias metadataHint: previewState.metadataHint
    property alias metadataLoading: previewState.metadataLoading
    property alias pdfPageIndex: previewState.pdfPageIndex
    property alias previewFileName: previewState.fileName
    property alias detailKind: previewState.detailKind
    property alias metadataEntries: previewState.metadataEntries
    property alias isArchive: previewState.isArchive
    property alias isAudio: previewState.isAudio
    property alias isFont: previewState.isFont
    property alias isPdf: previewState.isPdf
    property alias isText: previewState.isText
    property alias isVideo: previewState.isVideo
    property alias hasVisualPreview: previewState.hasVisualPreview
    property alias visualSource: previewState.visualSource
    property alias pdfImageSource: previewState.pdfImageSource
    property alias pdfPageLabel: previewState.pdfPageLabel
    property alias pdfPreviewAvailable: previewState.pdfPreviewAvailable
    property alias videoPreviewAvailable: previewState.videoPreviewAvailable
    property alias textHighlightAvailable: previewState.textHighlightAvailable

    function changePdfPage(delta) {
        previewState.changePdfPage(delta)
    }

    function handlePdfWheel(wheel) {
        previewState.handlePdfWheel(wheel)
    }

    // ── Preview content area (top) + info bar (bottom) ───────────
    Column {
        anchors.fill: parent

        // Preview area
        Item {
            id: previewArea
            width: parent.width
            height: parent.height - infoBar.height

            // Directory listing
            ListView {
                id: previewDirList
                anchors.fill: parent
                visible: previewColumn.previewIsDir
                model: millerPreviewModel
                clip: true
                reuseItems: true
                cacheBuffer: 256
                interactive: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Item {
                    width: previewDirList.width
                    height: 24

                    required property int index
                    required property string fileName
                    required property bool isDir
                    required property string fileIconName

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 4
                        spacing: 6

                        Image {
                            width: 14; height: 14
                            anchors.verticalCenter: parent.verticalCenter
                            source: "image://icon/" + fileIconName + "?theme=" + config.iconTheme + "&builtin=" + (config.builtinIcons ? "1" : "0")
                            sourceSize: Qt.size(14, 14)
                            asynchronous: true
                        }

                        Text {
                            width: parent.width - 14 - parent.spacing - parent.anchors.leftMargin - parent.anchors.rightMargin
                            anchors.verticalCenter: parent.verticalCenter
                            text: fileName
                            color: Theme.subtext
                            font.pointSize: Theme.fontSmall
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // Archive contents preview
            Item {
                anchors.fill: parent
                visible: previewColumn.isArchive

                Text {
                    id: archivePreviewTitle
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 8
                    text: "Archive contents"
                    color: Theme.text
                    font.pointSize: Theme.fontSmall
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    anchors.top: archivePreviewTitle.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 8
                    visible: previewColumn.directoryPreview.error !== ""
                    text: previewColumn.directoryPreview.error
                    color: Theme.error
                    font.pointSize: Theme.fontSmall
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                Text {
                    anchors.top: archivePreviewTitle.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 8
                    visible: previewColumn.directoryPreview.loading === true
                    text: "Listing archive…"
                    color: Theme.subtext
                    font.pointSize: Theme.fontSmall
                }

                ListView {
                    id: archivePreviewList
                    anchors.top: archivePreviewTitle.bottom
                    anchors.topMargin: 8
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    visible: previewColumn.directoryPreview.error === ""
                    model: previewColumn.directoryPreview.entries || []
                    clip: true
                    spacing: 4

                    delegate: Text {
                        width: archivePreviewList.width - 12
                        text: modelData
                        color: Theme.subtext
                        font.pointSize: Theme.fontSmall
                        elide: Text.ElideMiddle
                    }

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }
            }

            // Image/Video preview
            Image {
                id: visualPreview
                anchors.fill: parent
                anchors.margins: 8
                visible: previewColumn.hasVisualPreview && !previewColumn.previewIsDir && !previewColumn.isPdf
                source: previewColumn.visualSource
                sourceSize: Qt.size(width, height)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }

            // PDF preview
            Image {
                id: pdfPreviewImage
                anchors.fill: parent
                anchors.margins: 8
                visible: previewColumn.isPdf
                    && previewColumn.pdfPreviewAvailable
                    && previewColumn.pdfPreview.localPath !== ""
                    && previewColumn.pdfPreview.error === ""
                source: previewColumn.pdfImageSource
                sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }

            MouseArea {
                anchors.fill: parent
                visible: pdfPreviewImage.visible
                acceptedButtons: Qt.NoButton
                onWheel: (wheel) => previewColumn.handlePdfWheel(wheel)
            }

            Row {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 10
                anchors.rightMargin: 10
                spacing: 6
                visible: pdfPreviewImage.visible && previewColumn.pdfPreview.pageCount > 1

                Rectangle {
                    width: 26
                    height: 26
                    radius: 13
                    enabled: previewColumn.pdfPageIndex > 0
                    opacity: enabled ? 1 : 0.45
                    color: pdfPrevMouse.containsMouse
                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                        : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                    IconChevronUp {
                        anchors.centerIn: parent
                        size: 14
                        color: Theme.text
                    }

                    MouseArea {
                        id: pdfPrevMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: parent.enabled
                        onClicked: previewColumn.changePdfPage(-1)
                    }
                }

                Rectangle {
                    width: 26
                    height: 26
                    radius: 13
                    enabled: previewColumn.pdfPageIndex < previewColumn.pdfPreview.pageCount - 1
                    opacity: enabled ? 1 : 0.45
                    color: pdfNextMouse.containsMouse
                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                        : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                    IconChevronDown {
                        anchors.centerIn: parent
                        size: 14
                        color: Theme.text
                    }

                    MouseArea {
                        id: pdfNextMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: parent.enabled
                        onClicked: previewColumn.changePdfPage(1)
                    }
                }
            }

            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                visible: pdfPreviewImage.visible && previewColumn.pdfPageLabel !== ""
                text: previewColumn.pdfPageLabel
                color: Theme.subtext
                font.pointSize: Theme.fontSmall
            }

            Rectangle {
                anchors.centerIn: parent
                visible: (previewColumn.hasVisualPreview && visualPreview.status === Image.Loading)
                    || (pdfPreviewImage.visible && pdfPreviewImage.status === Image.Loading)
                color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.72)
                radius: Theme.radiusMedium
                width: 170
                height: 40

                Text {
                    anchors.centerIn: parent
                    text: previewColumn.isPdf ? "Rendering PDF..." : "Loading preview..."
                    color: Theme.text
                    font.pointSize: Theme.fontSmall
                }
            }

            // Async pdfinfo placeholder: shown while the page count is
            // still being read (localPath/error not yet set).
            Text {
                anchors.centerIn: parent
                visible: previewColumn.isPdf && previewColumn.pdfPreview.loading === true
                text: "Reading PDF…"
                color: Theme.subtext
                font.pointSize: Theme.fontSmall
            }

            Column {
                anchors.centerIn: parent
                spacing: 8
                visible: (previewColumn.hasVisualPreview && visualPreview.status === Image.Error)
                    || (pdfPreviewImage.visible && pdfPreviewImage.status === Image.Error)

                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 64; height: 64
                    source: "image://icon/" + (previewColumn.fileProps.iconName || (previewColumn.isPdf ? "application-pdf" : "image-x-generic")) + "?theme=" + config.iconTheme + "&builtin=" + (config.builtinIcons ? "1" : "0")
                    sourceSize: Qt.size(64, 64)
                    asynchronous: true
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: previewColumn.isPdf ? "PDF preview could not be loaded" : "Preview could not be loaded"
                    color: Theme.subtext
                    font.pointSize: Theme.fontSmall
                }
            }

            // Text preview
            Flickable {
                id: textPreviewFlick
                anchors.fill: parent
                anchors.margins: 6
                visible: previewColumn.isText && !previewColumn.hasVisualPreview
                    && !previewColumn.previewIsDir && !previewColumn.isPdf && !previewColumn.isArchive
                clip: true
                interactive: true
                boundsMovement: Flickable.StopAtBounds
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: Math.max(width, textArea.implicitWidth)
                contentHeight: Math.max(height, textArea.implicitHeight)

                TextEdit {
                    id: textArea
                    readOnly: true
                    selectByMouse: true
                    width: Math.max(implicitWidth, textPreviewFlick.width)
                    height: Math.max(implicitHeight, textPreviewFlick.height)
                    textFormat: previewColumn.textPreview.usesBat && previewColumn.textPreview.html !== ""
                        ? TextEdit.RichText
                        : TextEdit.PlainText
                    text: previewColumn.textPreview.error !== ""
                        ? previewColumn.textPreview.error
                        : (previewColumn.textPreview.isBinary
                            ? "This file looks binary and cannot be previewed as text."
                            : (previewColumn.textPreview.usesBat && previewColumn.textPreview.html !== ""
                                ? previewColumn.textPreview.html
                                : previewColumn.textPreview.content))
                    color: Theme.text
                    wrapMode: TextEdit.NoWrap
                    font.family: "monospace"
                    font.pointSize: Theme.fontSmall - 1

                    onCursorRectangleChanged: {
                        var r = cursorRectangle
                        var pad = 4
                        if (r.x - pad < textPreviewFlick.contentX)
                            textPreviewFlick.contentX = Math.max(0, r.x - pad)
                        else if (r.x + r.width + pad > textPreviewFlick.contentX + textPreviewFlick.width)
                            textPreviewFlick.contentX = Math.min(
                                textPreviewFlick.contentWidth - textPreviewFlick.width,
                                r.x + r.width + pad - textPreviewFlick.width)
                        if (r.y - pad < textPreviewFlick.contentY)
                            textPreviewFlick.contentY = Math.max(0, r.y - pad)
                        else if (r.y + r.height + pad > textPreviewFlick.contentY + textPreviewFlick.height)
                            textPreviewFlick.contentY = Math.min(
                                textPreviewFlick.contentHeight - textPreviewFlick.height,
                                r.y + r.height + pad - textPreviewFlick.height)
                    }
                }

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            }

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                visible: textPreviewFlick.visible
                    && previewColumn.textPreview.error === ""
                    && !previewColumn.textPreview.isBinary
                    && !previewColumn.textPreview.usesBat
                    && !previewColumn.textHighlightAvailable
                text: runtimeFeatures.installHint("textHighlight")
                color: Theme.subtext
                font.pointSize: Theme.fontSmall
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                horizontalAlignment: Text.AlignHCenter
            }

            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: previewColumn.isPdf
                    && (!previewColumn.pdfPreviewAvailable || previewColumn.pdfPreview.error !== "")

                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 72; height: 72
                    source: "image://icon/" + (previewColumn.fileProps.iconName || "application-pdf") + "?theme=" + config.iconTheme + "&builtin=" + (config.builtinIcons ? "1" : "0")
                    sourceSize: Qt.size(72, 72)
                    asynchronous: true
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 220
                    text: previewColumn.pdfPreviewAvailable
                        ? "PDF preview is unavailable for this file"
                        : "PDF preview support is unavailable"
                    color: Theme.text
                    font.pointSize: Theme.fontSmall
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 220
                    text: previewColumn.pdfPreview.error !== ""
                        ? previewColumn.pdfPreview.error
                        : runtimeFeatures.installHint("pdfPreview")
                    color: Theme.subtext
                    font.pointSize: Theme.fontSmall
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            // Font preview
            Flickable {
                id: millerFontFlick
                anchors.fill: parent
                anchors.margins: 10
                visible: previewColumn.isFont
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: millerFontColumn.implicitHeight

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                    id: millerFontColumn
                    width: millerFontFlick.width
                    spacing: 10

                    Text {
                        width: parent.width
                        visible: !previewColumn.fontPreview.valid
                        text: previewColumn.fontPreview.error || "Unable to load this font"
                        color: Theme.error
                        font.pointSize: Theme.fontSmall
                    }

                    Text {
                        width: parent.width
                        visible: previewColumn.fontPreview.valid
                        text: previewColumn.fontPreview.styleName && previewColumn.fontPreview.styleName !== ""
                            ? (previewColumn.fontPreview.family + " — " + previewColumn.fontPreview.styleName)
                            : (previewColumn.fontPreview.family || "")
                        color: Theme.subtext
                        font.pointSize: Theme.fontSmall
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Repeater {
                        model: previewColumn.fontPreview.valid ? [12, 16, 22, 30] : []
                        delegate: Text {
                            width: millerFontColumn.width
                            text: "The quick brown fox jumps over the lazy dog"
                            color: Theme.text
                            font.family: previewColumn.fontPreview.family || ""
                            font.styleName: previewColumn.fontPreview.styleName || ""
                            font.weight: previewColumn.fontPreview.weight || Font.Normal
                            font.italic: previewColumn.fontPreview.italic || false
                            font.pointSize: modelData
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }
                    }

                    Text {
                        width: parent.width
                        visible: previewColumn.fontPreview.valid
                        text: "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789"
                        color: Theme.text
                        font.family: previewColumn.fontPreview.family || ""
                        font.styleName: previewColumn.fontPreview.styleName || ""
                        font.weight: previewColumn.fontPreview.weight || Font.Normal
                        font.italic: previewColumn.fontPreview.italic || false
                        font.pointSize: 16
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    Text {
                        width: parent.width
                        visible: previewColumn.fontPreview.valid
                        text: "Glyphs & ligatures"
                        color: Theme.subtext
                        font.pointSize: Theme.fontSmall
                        font.weight: Font.DemiBold
                        topPadding: 4
                    }

                    Repeater {
                        model: previewColumn.fontPreview.valid
                            ? [
                                "~!@#$%^&* {} [] () I1l O0o",
                                "!== \\\\ <= #{ -> ~@ |> 0x12",
                                "|=>==<==>=|======|===|===>",
                                "<---|--|--------|-<->--<-|",
                                "[INFO] todo)) fixme))"
                              ]
                            : []
                        delegate: Text {
                            width: millerFontColumn.width
                            text: modelData
                            color: Theme.text
                            font.family: previewColumn.fontPreview.family || ""
                            font.styleName: previewColumn.fontPreview.styleName || ""
                            font.weight: previewColumn.fontPreview.weight || Font.Normal
                            font.italic: previewColumn.fontPreview.italic || false
                            font.pointSize: 14
                            wrapMode: Text.NoWrap
                        }
                    }
                }
            }

            // Fallback: icon for non-previewable files
            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: !previewColumn.previewIsDir && !previewColumn.isArchive
                    && !previewColumn.hasVisualPreview && !previewColumn.isText
                    && !previewColumn.isPdf && !previewColumn.isFont
                    && previewColumn.previewFilePath !== ""

                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 64; height: 64
                    source: previewColumn.fileProps.iconName
                        ? ("image://icon/" + previewColumn.fileProps.iconName + "?theme=" + config.iconTheme + "&builtin=" + (config.builtinIcons ? "1" : "0"))
                        : ("image://icon/text-x-generic?theme=" + config.iconTheme + "&builtin=" + (config.builtinIcons ? "1" : "0"))
                    sourceSize: Qt.size(64, 64)
                    asynchronous: true
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 220
                    text: previewColumn.isAudio
                        ? "Audio preview is not available yet"
                        : (previewColumn.isVideo && !previewColumn.videoPreviewAvailable
                            ? "Video preview support is unavailable"
                            : "Preview not available")
                    color: Theme.text
                    font.pointSize: Theme.fontSmall
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 220
                    text: previewColumn.isVideo && !previewColumn.videoPreviewAvailable
                        ? runtimeFeatures.installHint("videoPreview")
                        : "Open Quick Preview for a larger preview surface."
                    color: Theme.subtext
                    font.pointSize: Theme.fontSmall
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            // Empty state
            Text {
                anchors.centerIn: parent
                visible: previewColumn.previewFilePath === ""
                text: "No selection"
                color: Qt.rgba(Theme.subtext.r, Theme.subtext.g, Theme.subtext.b, 0.5)
                font.pointSize: Theme.fontSmall
            }
        }

        // Info bar at bottom
        Rectangle {
            id: infoBar
            width: parent.width
            height: previewColumn.previewFilePath !== ""
                ? Math.min(parent.height * 0.34, Math.max(54, infoBarContent.implicitHeight + 14))
                : 0
            visible: previewColumn.previewFilePath !== ""
            color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.5)
            border.width: 0

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
            }

            Flickable {
                id: infoBarFlick
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                anchors.topMargin: 7
                anchors.bottomMargin: 7
                clip: true
                interactive: contentHeight > height
                boundsMovement: Flickable.StopAtBounds
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: infoBarContent.implicitHeight

                Column {
                    id: infoBarContent
                    width: infoBarFlick.width
                    spacing: 4

                    Text {
                        width: parent.width
                        text: previewColumn.previewFileName
                        color: Theme.text
                        font.pointSize: Theme.fontSmall
                        font.bold: true
                        elide: Text.ElideMiddle
                    }

                    Text {
                        width: parent.width
                        text: {
                            var parts = []
                            parts.push(previewColumn.detailKind)
                            if (previewColumn.fileProps.sizeText)
                                parts.push(previewColumn.fileProps.sizeText)
                            if (previewColumn.previewIsDir && previewColumn.fileProps.contentText)
                                parts.push(previewColumn.fileProps.contentText)
                            if (previewColumn.pdfPageLabel !== "")
                                parts.push(previewColumn.pdfPageLabel)
                            if (previewColumn.fileProps.modified)
                                parts.push(previewColumn.fileProps.modified)
                            return parts.join(" \u00b7 ")
                        }
                        color: Theme.subtext
                        font.pointSize: Theme.fontSmall - 1
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    Text {
                        width: parent.width
                        visible: !!(previewColumn.fileProps.originalPath || previewColumn.fileProps.parentDir)
                        text: (previewColumn.fileProps.originalPath ? "Original Location: " : "Location: ")
                            + (previewColumn.fileProps.originalPath || previewColumn.fileProps.parentDir || "")
                        color: Theme.subtext
                        font.pointSize: Theme.fontSmall - 1
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    Text {
                        width: parent.width
                        visible: !previewColumn.previewIsDir && !!previewColumn.fileProps.contentText
                        text: "Contents: " + previewColumn.fileProps.contentText
                        color: Theme.subtext
                        font.pointSize: Theme.fontSmall - 1
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    Text {
                        width: parent.width
                        visible: !!previewColumn.fileProps.deleted
                        text: "Deleted: " + previewColumn.fileProps.deleted
                        color: Theme.subtext
                        font.pointSize: Theme.fontSmall - 1
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    Repeater {
                        model: previewColumn.metadataEntries

                        delegate: Text {
                            width: infoBarContent.width
                            text: modelData.label + ": " + modelData.value
                            color: Theme.subtext
                            font.pointSize: Theme.fontSmall - 1
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }
                    }

                    Text {
                        width: parent.width
                        visible: previewColumn.metadataLoading
                        text: "Reading metadata…"
                        color: Theme.muted
                        font.pointSize: Theme.fontSmall - 1
                        font.italic: true
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    Text {
                        width: parent.width
                        visible: previewColumn.metadataHint !== ""
                        text: previewColumn.metadataHint
                        color: Theme.muted
                        font.pointSize: Theme.fontSmall - 1
                        font.italic: true
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    Text {
                        width: parent.width
                        visible: previewColumn.isText && previewColumn.textPreview.truncated
                        text: "Showing a shortened text preview for quick browsing."
                        color: Theme.subtext
                        font.pointSize: Theme.fontSmall - 1
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    Text {
                        width: parent.width
                        visible: (previewColumn.previewIsDir || previewColumn.isArchive) && previewColumn.directoryPreview.truncated
                        text: "Only the first items are shown here."
                        color: Theme.subtext
                        font.pointSize: Theme.fontSmall - 1
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }
                }

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }
        }
    }
}
