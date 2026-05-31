import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Heimdall
import Quill as Q

// File properties dialog (General + Permissions tabs, rich metadata, disk
// usage, "Open with"). A top-level frameless Window — NOT an in-scene overlay.
//
// Why a Window: the Quill Dropdown used for the per-group permission selector
// renders its list as a native Qt.Popup window anchored in global coords
// relative to its host window. As an in-scene overlay the host was the main
// window, whose position the Wayland compositor controls, so the popup landed
// in the top-left corner. As its own client-positioned Window (mirroring
// SettingsPanel) the anchor math lines up and the popup opens under the row.
// A separate window also must NOT close on focus loss — opening the dropdown
// popup deactivates this window, and closing on deactivate would dismiss the
// dialog out from under it. Dismiss is via Escape + the Close button instead
// of a click-outside backdrop (a separate window has none).
//
// Wiring contract:
//   host                 — set to the root window; provides paneBaseModel(),
//                          activePaneIndex and isLocalPath().
//   transientParent      — set to the root window so this dialog centers over
//                          it and the dropdown popup anchors correctly.
//   chooseAppRequested   — emitted when the user picks "Other Application…";
//                          the host opens its app-chooser dialog.
//   closed               — emitted when the dialog hides; the host restores
//                          focus to the active pane.
// Globals used directly (context properties / singletons): config, fileOps,
// metadataExtractor, diskUsageService, fsModel, Theme.
//
// Public surface relied on by Main.qml / AppShortcuts.qml: props, apps,
// currentTab, fileModelRef, folderDiskUsage{Text,Pending,RequestId}, visible,
// showProperties(path), close(), refreshFolderDiskUsage(),
// cancelFolderDiskUsageRequest().
Window {
    id: propertiesDialog
    title: "File properties"
    flags: Qt.Dialog | Qt.FramelessWindowHint
    color: "transparent"

    // Fixed size on Wayland. A content-driven height makes the surface fight
    // the compositor — it won't shrink for a short tab, leaving a transparent
    // strip below the painted content. A constant size sidesteps that: short
    // content (Permissions tab) simply leaves empty space, tall content
    // (General tab with rich metadata) scrolls inside the Flickable below.
    // min == max pins the size; clamped to the parent so it never overflows a
    // small display.
    width: dialogWidth
    height: dialogHeight
    minimumWidth: dialogWidth
    maximumWidth: dialogWidth
    minimumHeight: dialogHeight
    maximumHeight: dialogHeight

    readonly property int dialogWidth: Math.min(420, (transientParent ? transientParent.width : 420) - 32)
    readonly property int dialogHeight: Math.min(540, (transientParent ? transientParent.height - 80 : 540))
    readonly property int dialogRadius: Theme.radiusMedium

    function syncHyprlandRounding() {
        fileOps.setHyprlandRounding(propertiesDialog.title, propertiesDialog.dialogRadius)
        fileOps.setHyprlandBorder(propertiesDialog.title, 0)
    }
    onDialogRadiusChanged: {
        if (propertiesDialog.visible)
            syncHyprlandRounding()
    }

    property var host: null
    signal chooseAppRequested(string path, string mimeType)
    signal closed()

    property var props: ({})
    property var apps: []
    property var fileModelRef: fsModel
    property int currentTab: 0  // 0=General, 1=Permissions
    property string folderDiskUsageText: ""
    property bool folderDiskUsagePending: false
    property int folderDiskUsageRequestId: -1

    function cancelFolderDiskUsageRequest() {
        if (folderDiskUsageRequestId >= 0)
            diskUsageService.cancelRequest(folderDiskUsageRequestId)
        folderDiskUsageRequestId = -1
    }

    function refreshFolderDiskUsage() {
        cancelFolderDiskUsageRequest()

        if (!props.isDir || props.isTrashItem || !host.isLocalPath(props.path)) {
            folderDiskUsageText = ""
            folderDiskUsagePending = false
            return
        }

        folderDiskUsagePending = true
        folderDiskUsageText = "Calculating..."
        folderDiskUsageRequestId = diskUsageService.requestSize([props.path])
    }

    property var _metadataKeys: []
    property string _metadataHint: ""
    property string _metadataPath: ""

    function showProperties(path) {
        fileModelRef = host.paneBaseModel(host.activePaneIndex) || fsModel
        props = fileModelRef.fileProperties(path)
        currentTab = 0
        propsTabs.currentIndex = 0
        refreshFolderDiskUsage()
        if (!props.isDir && props.mimeType)
            apps = fileModelRef.availableApps(props.mimeType)
        else
            apps = []

        // Extract rich metadata. exiftool/ffprobe/pdfinfo can block for
        // seconds; extract asynchronously and populate the metadata section
        // on metadataReady.
        _metadataPath = path
        _metadataKeys = []
        _metadataHint = fileOps.isRemotePath(path) ? "" : metadataExtractor.missingDepsHint(props.mimeType || "")
        if (!fileOps.isRemotePath(path))
            metadataExtractor.requestExtract(path)

        // Center over the parent window, then show (mirrors SettingsPanel).
        if (transientParent) {
            propertiesDialog.x = transientParent.x + Math.round((transientParent.width - propertiesDialog.width) / 2)
            propertiesDialog.y = transientParent.y + Math.round((transientParent.height - propertiesDialog.height) / 2)
        }
        propertiesDialog.show()
        propertiesDialog.raise()
        propertiesDialog.requestActivate()
        propertiesDialog.syncHyprlandRounding()
    }
    function close() {
        cancelFolderDiskUsageRequest()
        propertiesDialog.hide()
        propertiesDialog.closed()
    }

    // WM-initiated close (compositor close, Alt-F4): mirror close()'s cleanup.
    // hide() does not fire onClosing, so close() won't re-enter here.
    onClosing: {
        cancelFolderDiskUsageRequest()
        propertiesDialog.closed()
    }

    // Async metadata result. Guard on _metadataPath so a slow extraction for
    // a path the dialog is no longer showing doesn't overwrite the current.
    Connections {
        target: metadataExtractor
        function onMetadataReady(path, result) {
            if (path !== propertiesDialog._metadataPath)
                return
            var keys = Object.keys(result)
            var arr = []
            for (var i = 0; i < keys.length; ++i) {
                if (result[keys[i]] !== "")
                    arr.push({ label: keys[i], value: String(result[keys[i]]) })
            }
            propertiesDialog._metadataKeys = arr
        }
    }

    // Close on Escape (fires while this window is active).
    Shortcut {
        sequence: "Escape"
        enabled: propertiesDialog.visible
        onActivated: propertiesDialog.close()
    }

    Item {
        id: propsBox
        anchors.fill: parent

        // Access dropdown options (referenced by the permission PermGroup).
        property var accessOptions: ["None", "Read only", "Read & Write", "Read, Write & Execute"]

        Rectangle {
            anchors.fill: parent
            color: Theme.mantle
            radius: propertiesDialog.dialogRadius
            border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Scrollable body: the General tab can be tall (rich metadata),
            // the Permissions tab short. The window is a fixed size, so the
            // body scrolls when its content exceeds the available height.
            Flickable {
                id: propsFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: propsOuterCol.height
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: propsOuterCol
                    width: propsFlick.width
                    spacing: 0

                    // ── Hero: icon + name + kind + size ──
                    Item {
                        width: parent.width; height: 88
                        Rectangle {
                            id: propsIconBg; width: 52; height: 52; radius: Theme.radiusMedium
                            color: Theme.surface
                            anchors.left: parent.left; anchors.leftMargin: 24; anchors.verticalCenter: parent.verticalCenter
                            Image {
                                anchors.centerIn: parent; width: 32; height: 32
                                source: propertiesDialog.props.iconName
                                    ? ("image://icon/" + propertiesDialog.props.iconName + "?theme=" + config.iconTheme + "&builtin=" + (config.builtinIcons ? "1" : "0"))
                                    : ""
                                sourceSize: Qt.size(32, 32); smooth: true
                            }
                        }
                        Column {
                            anchors.left: propsIconBg.right; anchors.leftMargin: 14
                            anchors.right: parent.right; anchors.rightMargin: 24
                            anchors.verticalCenter: parent.verticalCenter; spacing: 2
                            Text {
                                text: propertiesDialog.props.name || ""; color: Theme.text
                                font.pixelSize: 15; font.weight: Font.DemiBold
                                elide: Text.ElideMiddle; width: parent.width
                            }
                            Text {
                                text: { var p = propertiesDialog.props; return !p.mimeDescription ? "" : p.isDir ? "Folder" : p.mimeDescription }
                                color: Theme.subtext; font.pointSize: Theme.fontSmall; elide: Text.ElideRight; width: parent.width
                            }
                        }
                    }

                    // ── Tab bar ──
                    Q.Tabs {
                        id: propsTabs
                        width: parent.width
                        model: propertiesDialog.props.canEditPermissions === false ? ["General"] : ["General", "Permissions"]
                        currentIndex: propertiesDialog.currentTab
                        onTabChanged: (index) => propertiesDialog.currentTab = index
                    }

                    // ── Tab content slider ──
                    Item {
                        id: tabSlider
                        width: parent.width
                        height: propertiesDialog.currentTab === 0 ? generalTab.height : permissionsTab.height
                        clip: true
                        Behavior on height { NumberAnimation { duration: Theme.animDurationSlow; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve } }

                        Row {
                            id: tabSliderRow
                            x: -propertiesDialog.currentTab * tabSlider.width
                            Behavior on x { NumberAnimation { duration: Theme.animDurationSlow; easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve } }

                    // ══════════════════════════════════════════════
                    // TAB 0: General
                    // ══════════════════════════════════════════════
                    Column {
                        id: generalTab
                        width: tabSlider.width; spacing: 0

                        // helper component for a property row
                        component PropRow: Item {
                            property string label
                            property string value
                            property bool show: true
                            width: parent.width; height: show ? 28 : 0; visible: show
                            Text { text: label; color: Theme.subtext; font.pointSize: Theme.fontSmall; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: 80 }
                            Text { text: value; color: Theme.text; font.pointSize: Theme.fontSmall; anchors.left: parent.left; anchors.leftMargin: 88; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideMiddle }
                        }

                        Item { width: 1; height: 8 }

                        // Info rows
                        Column {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.leftMargin: 24; anchors.rightMargin: 24; spacing: 0

                            PropRow { label: "Kind"; value: { var p = propertiesDialog.props; return p.isDir ? "Folder" : (p.mimeDescription || "") } }
                            PropRow { label: "Location"; value: propertiesDialog.props.parentDir || "" }
                            PropRow { label: "Deleted"; value: propertiesDialog.props.deleted || ""; show: (propertiesDialog.props.deleted || "") !== "" }
                            PropRow { label: "Link target"; value: propertiesDialog.props.symlinkTarget || ""; show: propertiesDialog.props.isSymlink || false }
                        }

                        // Separator
                        Q.Separator { width: parent.width - 48; anchors.horizontalCenter: parent.horizontalCenter }

                        // Timestamps
                        Column {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.leftMargin: 24; anchors.rightMargin: 24; spacing: 0

                            PropRow { label: "Created"; value: propertiesDialog.props.created || "" }
                            PropRow { label: "Modified"; value: propertiesDialog.props.modified || "" }
                            PropRow { label: "Accessed"; value: propertiesDialog.props.accessed || "" }
                        }

                        Q.Separator { width: parent.width - 48; anchors.horizontalCenter: parent.horizontalCenter }

                        // Size section
                        Column {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.leftMargin: 24; anchors.rightMargin: 24; spacing: 0

                            PropRow {
                                label: "Size"
                                value: propertiesDialog.props.sizeText || ""
                                show: !(propertiesDialog.props.isDir || false)
                            }
                            PropRow {
                                label: "Disk usage"
                                value: propertiesDialog.folderDiskUsageText
                                show: propertiesDialog.props.isDir || false
                            }
                            PropRow { label: "Content"; value: propertiesDialog.props.contentText || ""; show: propertiesDialog.props.isDir || false }
                        }

                        // Rich metadata (images, audio, video, PDF)
                        Q.Separator {
                            visible: propertiesDialog._metadataKeys.length > 0
                            width: parent.width - 48; anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Column {
                            visible: propertiesDialog._metadataKeys.length > 0
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.leftMargin: 24; anchors.rightMargin: 24; spacing: 0

                            Repeater {
                                model: propertiesDialog._metadataKeys
                                delegate: PropRow { label: modelData.label; value: modelData.value }
                            }

                            Text {
                                visible: propertiesDialog._metadataHint !== ""
                                width: parent.width
                                text: propertiesDialog._metadataHint
                                color: Theme.muted
                                font.pointSize: Theme.fontSmall
                                font.italic: true
                                wrapMode: Text.WordWrap
                                topPadding: 4; bottomPadding: 4
                            }
                        }

                        Q.Separator { width: parent.width - 48; anchors.horizontalCenter: parent.horizontalCenter }

                        // Disk usage
                        Column {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.leftMargin: 24; anchors.rightMargin: 24; spacing: 4
                            visible: propertiesDialog.props.diskTotal !== undefined

                            Item { width: 1; height: 4 }

                            PropRow { label: "Capacity"; value: propertiesDialog.props.diskTotal || "" }

                            // Usage bar
                            Item {
                                width: parent.width; height: 28
                                Text { text: "Usage"; color: Theme.subtext; font.pointSize: Theme.fontSmall; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: 80 }
                                Column {
                                    anchors.left: parent.left; anchors.leftMargin: 88
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 4

                                    // Bar
                                    Rectangle {
                                        width: parent.width; height: 6; radius: 3
                                        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                                        Rectangle {
                                            width: parent.width * (propertiesDialog.props.diskUsedPercent || 0)
                                            height: parent.height; radius: 3
                                            color: (propertiesDialog.props.diskUsedPercent || 0) > 0.9 ? "#e74c3c" : Theme.accent
                                        }
                                    }

                                    // Label
                                    Text {
                                        text: (propertiesDialog.props.diskUsed || "") + " used (" + (propertiesDialog.props.diskUsedPctText || "") + ")  |  " +
                                              (propertiesDialog.props.diskFree || "") + " free (" + (propertiesDialog.props.diskFreePctText || "") + ")"
                                        color: Theme.subtext; font.pixelSize: 10
                                    }
                                }
                            }

                            Item { width: 1; height: 4 }
                        }

                        // Open With (files only)
                        Q.Collapsible {
                            visible: !(propertiesDialog.props.isDir) && propertiesDialog.apps.length > 0
                            title: {
                                var apps = propertiesDialog.apps
                                for (var i = 0; i < apps.length; i++)
                                    if (apps[i].isDefault) return "Open with: " + apps[i].name
                                return apps.length > 0 ? "Open with: " + apps[0].name : "Open with"
                            }
                            width: parent.width

                            Repeater {
                                model: propertiesDialog.apps
                                delegate: Rectangle {
                                    width: parent ? parent.width : 0; height: 30; radius: Theme.radiusSmall
                                    color: owItemMa.containsMouse
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.1)
                                        : "transparent"
                                    Layout.fillWidth: true

                                    Image {
                                        id: owAppIcon
                                        source: modelData.iconName
                                            ? ("image://icon/" + modelData.iconName + "?theme=" + config.iconTheme + "&builtin=" + (config.builtinIcons ? "1" : "0"))
                                            : ""
                                        sourceSize: Qt.size(18, 18)
                                        width: 18; height: 18
                                        anchors.left: parent.left; anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: modelData.iconName && status === Image.Ready
                                    }

                                    Text {
                                        text: modelData.name
                                        color: modelData.isDefault ? Theme.accent : Theme.text
                                        font.pointSize: Theme.fontSmall
                                        font.weight: modelData.isDefault ? Font.DemiBold : Font.Normal
                                        anchors.left: owAppIcon.visible ? owAppIcon.right : parent.left
                                        anchors.leftMargin: owAppIcon.visible ? 8 : 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.right: owItemBadge.left; anchors.rightMargin: 4
                                        elide: Text.ElideRight
                                    }

                                    IconCheck {
                                        id: owItemBadge
                                        visible: modelData.isDefault
                                        size: 14; color: Theme.accent
                                        anchors.right: parent.right; anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    MouseArea {
                                        id: owItemMa; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!modelData.isDefault) {
                                                propertiesDialog.fileModelRef.setDefaultApp(propertiesDialog.props.mimeType, modelData.desktopFile)
                                                propertiesDialog.apps = propertiesDialog.fileModelRef.availableApps(propertiesDialog.props.mimeType)
                                            }
                                        }
                                    }
                                }
                            }

                            // "Other Application..." button
                            Rectangle {
                                width: parent ? parent.width : 0; height: 30; radius: Theme.radiusSmall
                                color: otherAppMa.containsMouse
                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.1)
                                    : "transparent"
                                Layout.fillWidth: true

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    spacing: 6

                                    IconSearch {
                                        size: 14
                                        color: Theme.muted
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: "Other Application…"
                                        color: Theme.muted
                                        font.pointSize: Theme.fontSmall
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    id: otherAppMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: propertiesDialog.chooseAppRequested(propertiesDialog.props.path || "", propertiesDialog.props.mimeType || "")
                                }
                            }
                        }
                    }

                    // ══════════════════════════════════════════════
                    // TAB 1: Permissions
                    // ══════════════════════════════════════════════
                    Column {
                        id: permissionsTab
                        width: tabSlider.width; spacing: 0

                        Item { width: 1; height: 12 }

                        // Helper component for permission group
                        component PermGroup: Column {
                            id: permGroup
                            property string groupLabel
                            property string userName
                            property int accessIdx: 0
                            property int groupId: 0
                            signal accessChanged(int newIdx)
                            width: parent.width; spacing: 4

                            // Group header
                            Text {
                                text: groupLabel
                                color: Theme.text; font.pointSize: Theme.fontSmall; font.weight: Font.DemiBold
                                leftPadding: 24
                            }

                            // User name (if any)
                            Text {
                                text: userName; visible: userName !== ""
                                color: Theme.subtext; font.pointSize: Theme.fontSmall
                                leftPadding: 36
                            }

                            // Access selector row. A custom in-scene dropdown
                            // button (NOT Q.Dropdown) that drives the shared
                            // accessPopup overlay below — see that overlay for
                            // why the Quill dropdown can't be used here.
                            Item {
                                width: parent.width; height: 34
                                Text {
                                    text: "Access"
                                    color: Theme.subtext; font.pointSize: Theme.fontSmall
                                    anchors.left: parent.left; anchors.leftMargin: 36
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Rectangle {
                                    id: accessButton
                                    anchors.left: parent.left; anchors.leftMargin: 100
                                    anchors.right: parent.right; anchors.rightMargin: 24
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 34; radius: Theme.radiusSmall
                                    color: Theme.surface
                                    border.width: 1
                                    border.color: accessPopup.openGroup === permGroup.groupId
                                        ? Theme.accent
                                        : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.15)

                                    Text {
                                        text: propsBox.accessOptions[permGroup.accessIdx] ?? ""
                                        color: Theme.text; font.pointSize: Theme.fontSmall
                                        anchors.left: parent.left; anchors.leftMargin: 10
                                        anchors.right: accessChevron.left; anchors.rightMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                    }
                                    IconChevronDown {
                                        id: accessChevron
                                        size: 14; color: Theme.subtext
                                        anchors.right: parent.right; anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        rotation: accessPopup.openGroup === permGroup.groupId ? 180 : 0
                                        Behavior on rotation { NumberAnimation { duration: Theme.animDurationFast } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: accessPopup.openFor(permGroup.groupId, accessButton,
                                                                       permGroup.accessIdx,
                                                                       (idx) => permGroup.accessChanged(idx))
                                    }
                                }
                            }

                            Item { width: 1; height: 4 }
                        }

                        PermGroup {
                            groupLabel: "Owner"
                            groupId: 0
                            userName: propertiesDialog.props.owner || ""
                            accessIdx: propertiesDialog.props.ownerAccess || 0
                            onAccessChanged: (idx) => {
                                propertiesDialog.fileModelRef.setFilePermissions(propertiesDialog.props.path, idx, propertiesDialog.props.groupAccess || 0, propertiesDialog.props.otherAccess || 0)
                                propertiesDialog.props = propertiesDialog.fileModelRef.fileProperties(propertiesDialog.props.path)
                            }
                        }

                        Q.Separator { width: parent.width - 48; anchors.horizontalCenter: parent.horizontalCenter }

                        PermGroup {
                            groupLabel: "Group"
                            groupId: 1
                            userName: propertiesDialog.props.group || ""
                            accessIdx: propertiesDialog.props.groupAccess || 0
                            onAccessChanged: (idx) => {
                                propertiesDialog.fileModelRef.setFilePermissions(propertiesDialog.props.path, propertiesDialog.props.ownerAccess || 0, idx, propertiesDialog.props.otherAccess || 0)
                                propertiesDialog.props = propertiesDialog.fileModelRef.fileProperties(propertiesDialog.props.path)
                            }
                        }

                        Q.Separator { width: parent.width - 48; anchors.horizontalCenter: parent.horizontalCenter }

                        PermGroup {
                            groupLabel: "Others"
                            groupId: 2
                            userName: ""
                            accessIdx: propertiesDialog.props.otherAccess || 0
                            onAccessChanged: (idx) => {
                                propertiesDialog.fileModelRef.setFilePermissions(propertiesDialog.props.path, propertiesDialog.props.ownerAccess || 0, propertiesDialog.props.groupAccess || 0, idx)
                                propertiesDialog.props = propertiesDialog.fileModelRef.fileProperties(propertiesDialog.props.path)
                            }
                        }

                        Item { width: 1; height: 8 }
                    }

                        } // Row (tabSliderRow)
                    } // Item (tabSlider)
                } // Column (propsOuterCol)
            } // Flickable (propsFlick)

            // ── Close button (pinned below the scrollable body) ──
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                Q.Button {
                    text: "Close"
                    variant: "primary"
                    size: "small"
                    anchors.right: parent.right; anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: propertiesDialog.close()
                }
            }
        }

        // In-scene "Access" dropdown overlay shared by the three permission
        // groups. Quill's Q.Dropdown renders its list in a SEPARATE Qt.Popup
        // window positioned by absolute screen coordinates; the Wayland
        // compositor ignores those coordinates, so the lists landed at the
        // wrong row, opened upward over their trigger, and never dismissed on
        // an outside click (so opening all three stacked them). Quill is a
        // submodule we can't edit, so the selector is reimplemented here as a
        // plain in-scene overlay: it lives inside this window above the
        // (clipped) Flickable, positions with ordinary QML coordinates so it
        // always opens under the invoking row, only one is ever open, and an
        // outside click closes it.
        Item {
            id: accessPopup
            anchors.fill: parent
            visible: openGroup >= 0
            z: 100

            property int openGroup: -1        // -1 = closed; else PermGroup.groupId
            property int selectedIndex: 0
            property real anchorX: 0
            property real anchorTopY: 0       // trigger top, in propsBox coords
            property real anchorBottomY: 0    // trigger bottom, in propsBox coords
            property real anchorWidth: 0
            property var picker: null         // function(index)

            function openFor(groupId, item, currentIndex, pick) {
                var top = item.mapToItem(propsBox, 0, 0)
                var bottom = item.mapToItem(propsBox, 0, item.height)
                accessPopup.anchorX = top.x
                accessPopup.anchorTopY = top.y
                accessPopup.anchorBottomY = bottom.y
                accessPopup.anchorWidth = item.width
                accessPopup.selectedIndex = currentIndex
                accessPopup.picker = pick
                accessPopup.openGroup = groupId
            }
            function dismiss() {
                accessPopup.openGroup = -1
                accessPopup.picker = null
            }

            // Outside-click catcher (only active while the overlay is visible).
            MouseArea { anchors.fill: parent; onClicked: accessPopup.dismiss() }

            Rectangle {
                id: accessList
                readonly property real listHeight: accessListCol.height + 8
                // Open below the trigger; flip above it only if opening below
                // would overflow the window bottom.
                readonly property bool flipUp: accessPopup.anchorBottomY + 4 + listHeight > propsBox.height - 8
                width: accessPopup.anchorWidth
                height: listHeight
                x: Math.max(8, Math.min(accessPopup.anchorX, propsBox.width - width - 8))
                y: flipUp
                    ? Math.max(8, accessPopup.anchorTopY - 4 - listHeight)
                    : accessPopup.anchorBottomY + 4
                radius: Theme.radiusSmall
                color: Theme.surface
                border.width: 1
                border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.15)

                Column {
                    id: accessListCol
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.margins: 4
                    spacing: 0

                    Repeater {
                        model: propsBox.accessOptions
                        delegate: Rectangle {
                            required property string modelData
                            required property int index
                            width: parent.width; height: 30; radius: Theme.radiusSmall
                            color: index === accessPopup.selectedIndex
                                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                                : accessItemMa.containsMouse
                                    ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                                    : "transparent"
                            Text {
                                text: modelData
                                color: index === accessPopup.selectedIndex ? Theme.accent : Theme.text
                                font.pointSize: Theme.fontSmall
                                anchors.left: parent.left; anchors.leftMargin: 10
                                anchors.right: parent.right; anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                            }
                            MouseArea {
                                id: accessItemMa
                                anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var pick = accessPopup.picker
                                    accessPopup.dismiss()
                                    if (pick) pick(index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
