import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Wayfile

Item {
    id: root
    Accessible.role: Accessible.Pane
    Accessible.name: "Quick preview" + (root.filePath ? ": " + root.filePath.split("/").pop() : "")

    property string filePath: ""
    // [{ path, isDir }] for the items the user can browse with Left/Right.
    property var directoryFiles: []
    // Authoritative isDir for the current filePath, sourced externally (from the
    // model row) and set BEFORE filePath. PreviewState.refresh() reads isDir to
    // pick the preview type, so it must not be derived from fileProps (the async
    // refresh OUTPUT) — that fed the previous file's isDir into the first cycle
    // of every new selection.
    property bool fileIsDir: false
    property bool active: false
    property var fileModel: fsModel

    PreviewState {
        id: previewState
        filePath: root.filePath
        isDir: root.fileIsDir
        fileModel: root.fileModel
        loadEnabled: root.active
    }

    // Forward the shared preview state (PreviewState.qml) so the rendering
    // below can keep referring to these names unchanged.
    property alias fileProps: previewState.fileProps
    property alias textPreview: previewState.textPreview
    property alias directoryPreview: previewState.directoryPreview
    property alias pdfPreview: previewState.pdfPreview
    property alias fontPreview: previewState.fontPreview
    property alias fileMetadata: previewState.fileMetadata
    property alias metadataHint: previewState.metadataHint
    property alias metadataLoading: previewState.metadataLoading
    property alias pdfPageIndex: previewState.pdfPageIndex
    property alias fileName: previewState.fileName
    property alias detailKind: previewState.detailKind
    property alias isDirectory: previewState.isDir
    property alias isArchive: previewState.isArchive
    property alias isImage: previewState.isImage
    property alias isVideo: previewState.isVideo
    property alias isAudio: previewState.isAudio
    property alias isPdf: previewState.isPdf
    property alias isFont: previewState.isFont
    property alias isText: previewState.isText
    property alias hasVisualPreview: previewState.hasVisualPreview
    property alias visualSource: previewState.visualSource
    property alias pdfImageSource: previewState.pdfImageSource
    property alias pdfPageLabel: previewState.pdfPageLabel
    property alias pdfPreviewAvailable: previewState.pdfPreviewAvailable
    property alias videoPreviewAvailable: previewState.videoPreviewAvailable
    property alias textHighlightAvailable: previewState.textHighlightAvailable
    property bool closing: false

    signal closed()
    signal openRequested(string path, bool isDirectory)

    readonly property string visualStatusText: {
        if (isVideo)
            return "Video poster preview"
        if (isImage)
            return "Image preview"
        return "Preview"
    }
    readonly property string sidebarPathLabel: fileProps.originalPath || fileProps.parentDir || ""

    visible: active || closing
    focus: visible

    component InfoBlock: Column {
        property string label: ""
        property string value: ""
        property bool visibleWhenEmpty: false
        width: parent.width
        spacing: 4
        visible: visibleWhenEmpty || value !== ""

        Text {
            width: parent.width
            text: parent.label
            color: Theme.muted
            font.pointSize: Theme.fontSmall
            font.weight: Font.DemiBold
        }

        Text {
            width: parent.width
            text: parent.value
            color: Theme.text
            font.pointSize: Theme.fontNormal
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }
    }

    function closePreview() {
        if (!active)
            return

        active = false
    }

    function currentIndex() {
        if (directoryFiles.length === 0) return -1
        for (var i = 0; i < directoryFiles.length; i++) {
            if (directoryFiles[i].path === filePath) return i
        }
        return -1
    }

    function cycleFile(direction) {
        var files = directoryFiles
        if (files.length === 0) return
        var idx = currentIndex()
        if (idx < 0) idx = 0
        idx = (idx + direction + files.length) % files.length
        // isDir BEFORE filePath: PreviewState.refresh() (triggered by the filePath
        // change) reads isDir to choose the preview type.
        root.fileIsDir = files[idx].isDir || false
        root.filePath = files[idx].path
    }

    onActiveChanged: {
        if (active) {
            closeAnim.stop()
            closing = false
            overlay.opacity = 0
            card.opacity = 0
            card.scale = 0.88
            card.yOffset = -8
            openAnim.start()
            Qt.callLater(function() { root.forceActiveFocus() })
        } else if (visible) {
            openAnim.stop()
            closing = true
            closeAnim.start()
        }
    }

    function changePdfPage(delta) {
        previewState.changePdfPage(delta)
    }

    function handlePdfWheel(wheel) {
        previewState.handlePdfWheel(wheel)
    }

    Keys.onEscapePressed: (event) => {
        event.accepted = true
        closePreview()
    }
    Keys.onLeftPressed: (event) => {
        event.accepted = true
        cycleFile(-1)
    }
    Keys.onRightPressed: (event) => {
        event.accepted = true
        cycleFile(1)
    }
    Keys.onUpPressed: (event) => {
        if (!isPdf)
            return
        event.accepted = true
        changePdfPage(-1)
    }
    Keys.onDownPressed: (event) => {
        if (!isPdf)
            return
        event.accepted = true
        changePdfPage(1)
    }
    Keys.onPressed: (event) => {
        if (!isPdf)
            return
        if (event.key === Qt.Key_PageUp) {
            event.accepted = true
            changePdfPage(-1)
        } else if (event.key === Qt.Key_PageDown) {
            event.accepted = true
            changePdfPage(1)
        }
    }
    Keys.onSpacePressed: (event) => {
        event.accepted = true
        closePreview()
    }
    Keys.onReturnPressed: (event) => {
        event.accepted = true
        root.openRequested(filePath, isDirectory)
        closePreview()
    }

    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: overlay
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.animDurationFast
            easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve
        }

        NumberAnimation {
            target: card
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.animDurationFast
            easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve
        }

        NumberAnimation {
            target: card
            property: "scale"
            from: 0.88
            to: 1
            duration: Theme.animDurationSlow
            easing.type: Easing.OutBack
            easing.overshoot: 0.8
        }

        NumberAnimation {
            target: card
            property: "yOffset"
            from: -8
            to: 0
            duration: Theme.animDuration
            easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve
        }
    }

    SequentialAnimation {
        id: closeAnim

        ParallelAnimation {
            NumberAnimation {
                target: overlay
                property: "opacity"
                to: 0
                duration: Theme.animDurationFast
                easing.type: Theme.animEasingExit; easing.bezierCurve: Theme.animBezierCurve
            }

            NumberAnimation {
                target: card
                property: "opacity"
                to: 0
                duration: Theme.animDurationFast
                easing.type: Theme.animEasingExit; easing.bezierCurve: Theme.animBezierCurve
            }

            NumberAnimation {
                target: card
                property: "scale"
                to: 0.92
                duration: Theme.animDurationFast
                easing.type: Theme.animEasingExit; easing.bezierCurve: Theme.animBezierCurve
            }

            NumberAnimation {
                target: card
                property: "yOffset"
                to: -4
                duration: Theme.animDurationFast
                easing.type: Theme.animEasingExit; easing.bezierCurve: Theme.animBezierCurve
            }
        }

        ScriptAction {
            script: {
                root.closing = false
                root.closed()
            }
        }
    }

    Rectangle {
        id: overlay
        anchors.fill: parent
        color: Theme.scrim
        opacity: 0

        MouseArea {
            anchors.fill: parent
            onClicked: root.closePreview()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, 1080)
        height: Math.min(parent.height * 0.88, 760)
        opacity: 0
        scale: 0.88
        transformOrigin: Item.Center
        radius: Theme.radiusLarge
        color: Qt.rgba(Theme.mantle.r, Theme.mantle.g, Theme.mantle.b, 0.98)
        border.width: 1
        border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)

        property real yOffset: 0
        transform: Translate {
            y: card.yOffset
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function() {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        text: root.fileName
                        color: Theme.text
                        font.pointSize: Theme.fontLarge + 2
                        font.bold: true
                        elide: Text.ElideMiddle
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.detailKind
                            + (root.directoryFiles.length > 1
                                ? "  ·  " + (root.currentIndex() + 1) + " of " + root.directoryFiles.length
                                : "")
                            + (root.isPdf && root.pdfPageLabel !== ""
                                ? "  ·  " + root.pdfPageLabel
                                : "")
                        color: Theme.subtext
                        font.pointSize: Theme.fontNormal
                        elide: Text.ElideRight
                    }
                }

                Row {
                    spacing: 8
                    visible: root.isPdf && root.pdfPreview.pageCount > 1

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 17
                        enabled: root.pdfPageIndex > 0
                        opacity: enabled ? 1 : 0.45
                        color: pdfPrevMouse.containsMouse
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                            : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                        IconChevronUp {
                            anchors.centerIn: parent
                            size: 16
                            color: Theme.text
                        }

                        MouseArea {
                            id: pdfPrevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: parent.enabled
                            onClicked: root.changePdfPage(-1)
                        }
                    }

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 17
                        enabled: root.pdfPageIndex < root.pdfPreview.pageCount - 1
                        opacity: enabled ? 1 : 0.45
                        color: pdfNextMouse.containsMouse
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                            : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                        IconChevronDown {
                            anchors.centerIn: parent
                            size: 16
                            color: Theme.text
                        }

                        MouseArea {
                            id: pdfNextMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: parent.enabled
                            onClicked: root.changePdfPage(1)
                        }
                    }
                }

                Row {
                    spacing: 8
                    visible: root.directoryFiles.length > 1

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 17
                        color: prevMouse.containsMouse
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                            : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                        IconChevronLeft {
                            anchors.centerIn: parent
                            size: 16
                            color: Theme.text
                        }

                        MouseArea {
                            id: prevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.cycleFile(-1)
                        }
                    }

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 17
                        color: nextMouse.containsMouse
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                            : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                        IconChevronRight {
                            anchors.centerIn: parent
                            size: 16
                            color: Theme.text
                        }

                        MouseArea {
                            id: nextMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.cycleFile(1)
                        }
                    }
                }

                Rectangle {
                    width: 34
                    height: 34
                    radius: 17
                    color: closeMouse.containsMouse
                        ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.18)
                        : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                    IconX {
                        anchors.centerIn: parent
                        size: 16
                        color: Theme.error
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.closePreview()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusMedium
                    color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.52)
                    border.width: 1
                    border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                    QuickPreviewPane {
                        anchors.fill: parent
                        anchors.margins: 12
                        preview: previewState
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 300
                    Layout.minimumWidth: 280
                    Layout.fillHeight: true
                    radius: Theme.radiusMedium
                    color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.7)
                    border.width: 1
                    border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                    Flickable {
                        id: sidebarFlick
                        anchors.fill: parent
                        anchors.margins: 12
                        clip: true
                        interactive: true
                        boundsMovement: Flickable.StopAtBounds
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: width
                        contentHeight: sidebarColumn.implicitHeight

                        Column {
                            id: sidebarColumn
                            width: sidebarFlick.width
                            spacing: 12

                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 72
                                height: 72
                                source: "image://icon/" + (root.fileProps.iconName || "text-x-generic") + "?theme=" + config.iconTheme + "&builtin=" + (config.builtinIcons ? "1" : "0")
                                sourceSize: Qt.size(width, height)
                                fillMode: Image.PreserveAspectFit
                            }

                            InfoBlock { label: "Kind"; value: root.detailKind; visibleWhenEmpty: true }
                            InfoBlock { label: "Size"; value: fileProps.sizeText || "" }

                            // Dynamic metadata from MetadataExtractor
                            Repeater {
                                model: {
                                    var result = []
                                    var md = root.fileMetadata || {}
                                    var keys = Object.keys(md)
                                    for (var i = 0; i < keys.length; ++i) {
                                        if (md[keys[i]] !== "")
                                            result.push({ label: keys[i], value: String(md[keys[i]]) })
                                    }
                                    return result
                                }
                                delegate: InfoBlock { label: modelData.label; value: modelData.value }
                            }

                            Text {
                                width: parent.width
                                visible: root.metadataLoading
                                text: "Reading metadata…"
                                color: Theme.muted
                                font.pointSize: Theme.fontSmall
                                font.italic: true
                                wrapMode: Text.WordWrap
                            }

                            InfoBlock { label: root.fileProps.originalPath ? "Original Location" : "Location"; value: root.sidebarPathLabel }
                            InfoBlock { label: "Deleted"; value: fileProps.deleted || "" }
                            InfoBlock { label: "Modified"; value: fileProps.modified || "" }
                            InfoBlock { label: "Contents"; value: fileProps.contentText || "" }

                            // Missing dependency hint
                            Text {
                                width: parent.width
                                visible: root.metadataHint !== ""
                                text: root.metadataHint
                                color: Theme.muted
                                font.pointSize: Theme.fontSmall
                                font.italic: true
                                wrapMode: Text.WordWrap
                                topPadding: 8
                            }

                            Text {
                                width: parent.width
                                visible: root.isText && textPreview.truncated
                                text: "Showing a shortened text preview for quick browsing."
                                color: Theme.subtext
                                font.pointSize: Theme.fontSmall
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                width: parent.width
                                visible: (root.isDirectory || root.isArchive) && directoryPreview.truncated
                                text: "Only the first items are shown here."
                                color: Theme.subtext
                                font.pointSize: Theme.fontSmall
                                wrapMode: Text.WordWrap
                            }
                        }

                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    }

                    KineticWheelScroller {
                        anchors.fill: sidebarFlick
                        flickable: sidebarFlick
                        wheelStep: 28
                        touchpadMultiplier: 1.35
                        minVelocity: 90
                        maxVelocity: 2600
                        kineticGain: 0.68
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.directoryFiles.length > 1
                    ? "Use Space or Esc to close, Return to open, and Left/Right to browse nearby items"
                    : "Use Space or Esc to close, and Return to open externally"
                color: Theme.muted
                font.pointSize: Theme.fontSmall
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.WordWrap
            }
        }
    }
}
