import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Heimdall

// The left-hand preview content of QuickPreview — renders whichever per-kind
// pane (image/video poster, PDF, text, directory/archive, font, or the
// "no preview" fallback) matches the current PreviewState. Extracted verbatim
// from QuickPreview.qml.
//
// All rendering state comes from the TYPED `preview` (a PreviewState), so the
// mirror properties below stay reactive. They re-expose PreviewState's values
// under the same names the moved markup already used, so the markup is an
// untouched root.->pane. transform.
Item {
    id: pane

    property PreviewState preview

    readonly property var fileProps: preview ? preview.fileProps : ({})
    readonly property bool hasVisualPreview: preview ? preview.hasVisualPreview : false
    readonly property string visualSource: preview ? preview.visualSource : ""
    readonly property bool isImage: preview ? preview.isImage : false
    readonly property bool isVideo: preview ? preview.isVideo : false
    readonly property bool isAudio: preview ? preview.isAudio : false
    readonly property bool videoPreviewAvailable: preview ? preview.videoPreviewAvailable : false
    readonly property bool isPdf: preview ? preview.isPdf : false
    readonly property bool pdfPreviewAvailable: preview ? preview.pdfPreviewAvailable : false
    readonly property var pdfPreview: preview ? preview.pdfPreview : ({})
    readonly property string pdfImageSource: preview ? preview.pdfImageSource : ""
    readonly property bool isText: preview ? preview.isText : false
    readonly property var textPreview: preview ? preview.textPreview : ({})
    readonly property bool textHighlightAvailable: preview ? preview.textHighlightAvailable : false
    readonly property bool isDirectory: preview ? preview.isDir : false
    readonly property bool isArchive: preview ? preview.isArchive : false
    readonly property var directoryPreview: preview ? preview.directoryPreview : ({})
    readonly property bool isFont: preview ? preview.isFont : false
    readonly property var fontPreview: preview ? preview.fontPreview : ({})

    readonly property string visualStatusText: {
        if (isVideo)
            return "Video poster preview"
        if (isImage)
            return "Image preview"
        return "Preview"
    }

    function handlePdfWheel(wheel) {
        if (preview)
            preview.handlePdfWheel(wheel)
    }

    Image {
        id: visualPreview
        anchors.fill: parent
        visible: pane.hasVisualPreview
        source: pane.visualSource
        sourceSize: Qt.size(width, height)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }

    Image {
        id: pdfPreviewImage
        anchors.fill: parent
        visible: pane.isPdf && pane.pdfPreviewAvailable && pane.pdfPreview.localPath !== "" && pane.pdfPreview.error === ""
        source: pane.pdfImageSource
        sourceSize: Qt.size(width, height)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }

    MouseArea {
        anchors.fill: parent
        visible: pane.isPdf && pane.pdfPreviewAvailable && pane.pdfPreview.localPath !== "" && pane.pdfPreview.error === ""
        acceptedButtons: Qt.NoButton
        onWheel: (wheel) => pane.handlePdfWheel(wheel)
    }

    Column {
        anchors.centerIn: parent
        spacing: 10
        visible: (pane.hasVisualPreview && visualPreview.status === Image.Error)
            || (pane.isPdf && pane.pdfPreviewAvailable && pane.pdfPreview.localPath !== "" && pdfPreviewImage.status === Image.Error)

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 64
            height: 64
            source: "image://icon/" + (pane.fileProps.iconName || (pane.isPdf ? "application-pdf" : "image-x-generic")) + "?theme=" + config.iconTheme + "&builtin=" + (config.builtinIcons ? "1" : "0")
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectFit
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: pane.isPdf ? "PDF preview could not be loaded" : "Preview could not be loaded"
            color: Theme.subtext
            font.pointSize: Theme.fontNormal
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: pane.isPdf && pane.pdfPreview.error !== ""
            text: pane.pdfPreview.error
            color: Theme.muted
            font.pointSize: Theme.fontSmall
        }
    }

    Rectangle {
        anchors.centerIn: parent
        visible: (pane.hasVisualPreview && visualPreview.status === Image.Loading)
            || (pane.isPdf && pane.pdfPreviewAvailable && pane.pdfPreview.localPath !== "" && pdfPreviewImage.status === Image.Loading)
        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.72)
        radius: Theme.radiusMedium
        width: 180
        height: 44

        Text {
            anchors.centerIn: parent
            text: pane.isPdf ? "Rendering PDF..." : pane.visualStatusText
            color: Theme.text
            font.pointSize: Theme.fontNormal
        }
    }

    // Async pdfinfo placeholder: shown while the page count
    // is still being read (localPath/error not yet set).
    Text {
        anchors.centerIn: parent
        visible: pane.isPdf && pane.pdfPreview.loading === true
        text: "Reading PDF…"
        color: Theme.subtext
        font.pointSize: Theme.fontNormal
    }

    Flickable {
        id: textPreviewFlick
        anchors.fill: parent
        visible: pane.isText && !pane.hasVisualPreview && !pane.isPdf
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
            textFormat: textPreview.usesBat && textPreview.html !== ""
                ? TextEdit.RichText
                : TextEdit.PlainText
            text: textPreview.error !== ""
                ? textPreview.error
                : (textPreview.isBinary
                    ? "This file looks binary and cannot be previewed as text."
                    : (textPreview.usesBat && textPreview.html !== ""
                        ? textPreview.html
                        : textPreview.content))
            color: Theme.text
            wrapMode: TextEdit.NoWrap
            font.family: Fonts.mono
            font.pointSize: Theme.fontSmall

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

    KineticWheelScroller {
        anchors.fill: textPreviewFlick
        visible: textPreviewFlick.visible
        flickable: textPreviewFlick
        wheelStep: 28
        touchpadMultiplier: 1.35
        minVelocity: 90
        maxVelocity: 2600
        kineticGain: 0.68
    }

    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        visible: pane.isText && textPreview.error === "" && !textPreview.isBinary && !textPreview.usesBat && !pane.textHighlightAvailable
        text: runtimeFeatures.installHint("textHighlight")
        color: Theme.subtext
        font.pointSize: Theme.fontSmall
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 12
        visible: pane.isDirectory || pane.isArchive

        Text {
            Layout.fillWidth: true
            text: pane.isArchive ? "Archive contents" : (fileProps.contentText || "Folder contents")
            color: Theme.text
            font.pointSize: Theme.fontNormal
            font.bold: true
        }

        Text {
            Layout.fillWidth: true
            visible: directoryPreview.error !== ""
            text: directoryPreview.error
            color: Theme.error
            font.pointSize: Theme.fontNormal
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            visible: directoryPreview.loading === true
            text: "Listing archive…"
            color: Theme.subtext
            font.pointSize: Theme.fontNormal
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: directoryPreview.error === ""

            ListView {
                id: directoryPreviewList
                anchors.fill: parent
                model: directoryPreview.entries || []
                clip: true
                spacing: 4

                delegate: Text {
                    width: ListView.view.width
                    text: modelData
                    color: Theme.text
                    font.pointSize: Theme.fontNormal
                    elide: Text.ElideMiddle
                }

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }

            KineticWheelScroller {
                anchors.fill: parent
                flickable: directoryPreviewList
                wheelStep: 28
                touchpadMultiplier: 1.35
                minVelocity: 90
                maxVelocity: 2600
                kineticGain: 0.68
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 12
        visible: pane.isPdf && (!pane.pdfPreviewAvailable || pdfPreview.error !== "")

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96
            height: 96
            source: "image://icon/" + (pane.fileProps.iconName || "application-pdf") + "?theme=" + config.iconTheme + "&builtin=" + (config.builtinIcons ? "1" : "0")
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectFit
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: pane.pdfPreviewAvailable ? "PDF preview is unavailable for this file" : "PDF preview support is unavailable"
            color: Theme.text
            font.pointSize: Theme.fontNormal
            width: 280
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: pane.pdfPreview.error !== ""
                ? pane.pdfPreview.error
                : (pane.pdfPreviewAvailable
                    ? "Press Enter to open the file externally"
                    : runtimeFeatures.installHint("pdfPreview"))
            color: Theme.subtext
            font.pointSize: Theme.fontSmall
            wrapMode: Text.WordWrap
            width: 240
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Flickable {
        id: fontPreviewFlick
        anchors.fill: parent
        anchors.margins: 12
        visible: pane.isFont
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: fontPreviewColumn.implicitHeight

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: fontPreviewColumn
            width: fontPreviewFlick.width
            spacing: 14

            Text {
                width: parent.width
                visible: !pane.fontPreview.valid
                text: pane.fontPreview.error || "Unable to load this font"
                color: Theme.error
                font.pointSize: Theme.fontNormal
            }

            Text {
                width: parent.width
                visible: pane.fontPreview.valid
                text: pane.fontPreview.styleName && pane.fontPreview.styleName !== ""
                    ? (pane.fontPreview.family + " — " + pane.fontPreview.styleName)
                    : (pane.fontPreview.family || "")
                color: Theme.subtext
                font.pointSize: Theme.fontSmall
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Repeater {
                model: pane.fontPreview.valid ? [12, 18, 24, 32, 48] : []
                delegate: Text {
                    width: fontPreviewColumn.width
                    text: "The quick brown fox jumps over the lazy dog"
                    color: Theme.text
                    font.family: pane.fontPreview.family || ""
                    font.styleName: pane.fontPreview.styleName || ""
                    font.weight: pane.fontPreview.weight || Font.Normal
                    font.italic: pane.fontPreview.italic || false
                    font.pointSize: modelData
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }
            }

            Text {
                width: parent.width
                visible: pane.fontPreview.valid
                text: "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789  !@#$%^&*()"
                color: Theme.text
                font.family: pane.fontPreview.family || ""
                font.styleName: pane.fontPreview.styleName || ""
                font.weight: pane.fontPreview.weight || Font.Normal
                font.italic: pane.fontPreview.italic || false
                font.pointSize: 20
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }

            Text {
                width: parent.width
                visible: pane.fontPreview.valid
                text: "Glyphs & ligatures"
                color: Theme.subtext
                font.pointSize: Theme.fontSmall
                font.weight: Font.DemiBold
                topPadding: 6
            }

            Repeater {
                model: pane.fontPreview.valid
                    ? [
                        "~!@#$%^&* {} [] () I1l O0o",
                        "!== \\\\ <= #{ -> ~@ |> 0x12",
                        "|=>==<==>=|======|===|===>",
                        "<---|--|--------|-<->--<-|",
                        "[INFO] todo)) fixme))"
                      ]
                    : []
                delegate: Text {
                    width: fontPreviewColumn.width
                    text: modelData
                    color: Theme.text
                    font.family: pane.fontPreview.family || ""
                    font.styleName: pane.fontPreview.styleName || ""
                    font.weight: pane.fontPreview.weight || Font.Normal
                    font.italic: pane.fontPreview.italic || false
                    font.pointSize: 18
                    wrapMode: Text.NoWrap
                }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 12
        visible: !pane.hasVisualPreview && !pane.isText && !pane.isDirectory && !pane.isArchive && !pane.isPdf && !pane.isFont

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96
            height: 96
            source: "image://icon/" + (pane.fileProps.iconName || "text-x-generic") + "?theme=" + config.iconTheme + "&builtin=" + (config.builtinIcons ? "1" : "0")
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectFit
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: pane.isAudio
                ? "Audio preview is not available yet"
                : (pane.isVideo && !pane.videoPreviewAvailable
                    ? "Video preview support is unavailable"
                    : "Preview not available")
            color: Theme.text
            font.pointSize: Theme.fontNormal
            width: 280
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: pane.isVideo && !pane.videoPreviewAvailable
                ? runtimeFeatures.installHint("videoPreview")
                : "Press Enter to open externally"
            color: Theme.subtext
            font.pointSize: Theme.fontSmall
            width: 280
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
