import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Wayfile

// Gallery view (5th mode). A narrow vertical thumbnail filmstrip (a single-column
// FileGridView over a media-only proxy) on the left, a large preview of the
// selected item on the right, and a full metadata bar along the bottom.
//
// Selection is exposed in SOURCE-model index space (mapped back from the proxy),
// matching HybridView, so Main.qml's selection plumbing works unchanged.
FocusScope {
    id: root
    Accessible.role: Accessible.Pane
    Accessible.name: "Gallery"
    focus: visible

    // The pane's source model (same object Main.qml uses as paneModel).
    property var viewModel: null
    property string currentPath: ""

    // Resizable filmstrip width (drag the splitter). In-memory only — resets to
    // the default on relaunch (persistence is an optional config follow-up).
    property real stripWidth: 200
    readonly property real minStripWidth: 120
    readonly property real maxStripWidth: 480

    signal fileActivated(string filePath, bool isDirectory)
    signal contextMenuRequested(string filePath, bool isDirectory, point position)
    signal selectionChanged()
    signal interactionStarted()
    signal transferRequested(var paths, string destinationPath, bool moveOperation)

    // ── Media-only proxy over the shared source model ───────────────────────
    DirFilterProxyModel {
        id: mediaProxy
        mode: DirFilterProxyModel.Media
    }
    onViewModelChanged: mediaProxy.switchSourceModel(viewModel)
    Component.onCompleted: {
        mediaProxy.switchSourceModel(viewModel)
        Qt.callLater(root._selectFirstIfNeeded)
    }

    // ── Selection (exposed in SOURCE index space) ───────────────────────────
    property var selectedIndices: []
    // Proxy row currently shown in the big preview (last-clicked); -1 if none.
    property int currentProxyRow: -1
    property string currentPreviewPath:
        currentProxyRow >= 0 ? mediaProxy.filePath(currentProxyRow) : ""

    function _sync() {
        var sel = strip.selectedIndices
        var out = []
        for (var i = 0; i < sel.length; ++i) {
            var sr = mediaProxy.mapRowToSource(sel[i])
            if (sr >= 0) out.push(sr)
        }
        root.selectedIndices = out
        root.currentProxyRow = sel.length > 0 ? sel[sel.length - 1] : -1
        root.selectionChanged()
    }

    // Auto-select the first media item when the list (re)populates and nothing is
    // selected, so the preview is never blank when media exists.
    function _selectFirstIfNeeded() {
        if (mediaProxy.count > 0 && strip.selectedIndices.length === 0)
            strip.focusPath(mediaProxy.filePath(0), false)
    }

    // Forwarders called by FileViewContainer / Main.qml on the active sub-view.
    function selectAll() { strip.selectAll() }
    function clearSelection() { strip.clearSelection() }
    function focusPath(path, reveal) { strip.focusPath(path, reveal) }

    Connections {
        target: strip
        function onSelectedIndicesChanged() { root._sync() }
    }
    Connections {
        target: mediaProxy
        function onCountChanged() { Qt.callLater(root._selectFirstIfNeeded) }
    }

    // ── Shared preview engine (same one Quick Preview uses) ─────────────────
    PreviewState {
        id: previewState
        filePath: root.currentPreviewPath
        isDir: false
        loadEnabled: root.visible
        fileModel: fsModel
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Filmstrip (left): a narrow, single-column FileGridView over the
        //    media proxy. Reuses its selection, context menu, drag & drop and
        //    keyboard nav; the narrow width forces one column (columnsPerRow =
        //    max(1, floor(width/cellSize))).
        FileGridView {
            id: strip
            Layout.fillHeight: true
            Layout.preferredWidth: root.stripWidth
            model: mediaProxy
            currentPath: root.currentPath
            // One column that fills the strip; iconSize = cellSize − padding, so
            // thumbnails grow with the bar. Min keeps cellSize sane at narrow widths.
            cellSize: Math.max(96, Math.round(root.stripWidth))
            zoomEnabled: false

            onFileActivated: (fp, isDir) => root.fileActivated(fp, isDir)
            onContextMenuRequested: (fp, isDir, pos) => root.contextMenuRequested(fp, isDir, pos)
            onInteractionStarted: root.interactionStarted()
            onTransferRequested: (paths, dst, move) => root.transferRequested(paths, dst, move)
        }

        // Drag-to-resize splitter between the filmstrip and the preview.
        Item {
            Layout.fillHeight: true
            Layout.preferredWidth: 6
            Rectangle {
                anchors.centerIn: parent
                width: (splitterHandle.containsMouse || splitterHandle.pressed) ? 2 : 1
                height: parent.height
                color: (splitterHandle.containsMouse || splitterHandle.pressed)
                       ? Theme.accent : Theme.line
                opacity: splitterHandle.pressed ? 0.9
                         : (splitterHandle.containsMouse ? 0.6 : 1.0)
            }
            MouseArea {
                id: splitterHandle
                anchors.fill: parent
                anchors.margins: -3                  // ~12px hit area
                hoverEnabled: true
                cursorShape: Qt.SizeHorCursor
                preventStealing: true
                property real startX: 0
                property real startW: 0
                onPressed: (mouse) => {
                    startX = mapToItem(root, mouse.x, 0).x
                    startW = root.stripWidth
                }
                onPositionChanged: (mouse) => {
                    if (!pressed)
                        return
                    var dx = mapToItem(root, mouse.x, 0).x - startX
                    root.stripWidth = Math.max(root.minStripWidth,
                                      Math.min(root.maxStripWidth, startW + dx))
                }
            }
        }

        // ── Preview + metadata (right) ──────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Item {
                id: previewArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Empty state — no previewable media in this directory.
                Text {
                    anchors.centerIn: parent
                    visible: mediaProxy.count === 0
                    text: "No photos or videos here"
                    color: Theme.subtext
                    font.pointSize: Theme.fontNormal
                }

                // Still visual: image, PDF page, or video poster.
                Image {
                    id: stillImage
                    anchors.fill: parent
                    anchors.margins: 16
                    visible: !videoLayer.playing
                             && (previewState.isImage || previewState.isPdf
                                 || (previewState.isVideo && previewState.hasVisualPreview))
                    source: previewState.isPdf ? previewState.pdfImageSource
                                               : previewState.visualSource
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                }

                // Audio / no-visual fallback card.
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: mediaProxy.count > 0 && !stillImage.visible && !videoLayer.playing
                    spacing: 8
                    IconImage {
                        Layout.alignment: Qt.AlignHCenter
                        size: 64
                        color: Theme.gold
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: previewState.fileName
                        color: Theme.text
                        font.pointSize: Theme.fontNormal
                    }
                }

                // ▶ play overlay (click-to-start) for videos.
                Rectangle {
                    id: playOverlay
                    anchors.centerIn: parent
                    visible: previewState.isVideo && !videoLayer.playing
                    width: 72; height: 72; radius: 36
                    color: Qt.rgba(0, 0, 0, 0.45)
                    border.color: Theme.gold
                    border.width: 2
                    Text {
                        anchors.centerIn: parent
                        text: "▶"
                        color: Theme.gold
                        font.pixelSize: 30
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: videoLayer.start()
                    }
                }

                // In-pane video playback (Qt Multimedia), started on demand.
                Item {
                    id: videoLayer
                    anchors.fill: parent
                    property bool playing: false
                    visible: playing

                    function start() {
                        mediaPlayer.source = "file://" + root.currentPreviewPath
                        mediaPlayer.play()
                        playing = true
                    }
                    function stop() {
                        mediaPlayer.stop()
                        mediaPlayer.source = ""
                        playing = false
                    }

                    VideoOutput {
                        id: videoOut
                        anchors.fill: parent
                        anchors.margins: 8
                        fillMode: VideoOutput.PreserveAspectFit
                    }
                    MediaPlayer {
                        id: mediaPlayer
                        videoOutput: videoOut
                        audioOutput: AudioOutput { id: audioOut }
                    }
                    // Click the video to toggle play/pause.
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mediaPlayer.playbackState === MediaPlayer.PlayingState
                                   ? mediaPlayer.pause() : mediaPlayer.play()
                    }
                }

                // Stop playback when the selected item changes.
                Connections {
                    target: root
                    function onCurrentPreviewPathChanged() {
                        if (videoLayer.playing) videoLayer.stop()
                    }
                }
            }

            // Metadata bar (bottom).
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                visible: mediaProxy.count > 0
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.raise }
                    GradientStop { position: 1.0; color: Theme.panel }
                }
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Theme.line
                }
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 18
                    Repeater {
                        model: previewState.metadataEntries
                        delegate: Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: modelData.label
                                color: Theme.muted
                                font.pixelSize: 9
                            }
                            Text {
                                text: modelData.value
                                color: Theme.text
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }
    }
}
