import QtQuick
import QtQuick.Layouts
import Heimdall
import Quill as Q

// File properties overlay dialog (General + Permissions tabs, rich metadata,
// disk usage, "Open with"). Extracted from Main.qml where it lived inline
// (~560 lines).
//
// Wiring contract:
//   host                 — set to the root window; provides paneBaseModel(),
//                          activePaneIndex and isLocalPath().
//   chooseAppRequested   — emitted when the user picks "Other Application…";
//                          the host opens its app-chooser dialog.
// Globals used directly (context properties / singletons): config, fileOps,
// metadataExtractor, diskUsageService, fsModel, Theme.
//
// Public surface relied on by Main.qml: props, apps, currentTab, fileModelRef,
// folderDiskUsage{Text,Pending,RequestId}, visible, showProperties(path),
// close(), refreshFolderDiskUsage(), cancelFolderDiskUsageRequest().
Item {
    id: propertiesDialog
    anchors.fill: parent
    visible: false
    z: 1000
    Accessible.role: Accessible.Dialog
    Accessible.name: "File properties"

    property var host: null
    signal chooseAppRequested(string path, string mimeType)

    property var props: ({})
    property var apps: []
    property var fileModelRef: fsModel
    property int currentTab: 0  // 0=General, 1=Permissions, 2=Open With
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

        visible = true
        propsBox.opacity = 0
        propsBox.scale = 0.88
        propsBox.yOffset = -8
        propsOpenAnim.start()
    }
    function close() {
        cancelFolderDiskUsageRequest()
        propsCloseAnim.start()
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

    ParallelAnimation {
        id: propsOpenAnim
        NumberAnimation {
            target: propsBox; property: "opacity"
            from: 0; to: 1; duration: Theme.animDurationFast
            easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve
        }
        NumberAnimation {
            target: propsBox; property: "scale"
            from: 0.88; to: 1; duration: Theme.animDurationSlow
            easing.type: Easing.OutBack
            easing.overshoot: 0.8
        }
        NumberAnimation {
            target: propsBox; property: "yOffset"
            from: -8; to: 0; duration: Theme.animDuration
            easing.type: Theme.animEasingEnter; easing.bezierCurve: Theme.animBezierCurve
        }
    }
    SequentialAnimation {
        id: propsCloseAnim
        ParallelAnimation {
            NumberAnimation {
                target: propsBox; property: "opacity"
                to: 0; duration: Theme.animDurationFast
                easing.type: Theme.animEasingExit; easing.bezierCurve: Theme.animBezierCurve
            }
            NumberAnimation {
                target: propsBox; property: "scale"
                to: 0.92; duration: Theme.animDurationFast
                easing.type: Theme.animEasingExit; easing.bezierCurve: Theme.animBezierCurve
            }
            NumberAnimation {
                target: propsBox; property: "yOffset"
                to: -4; duration: Theme.animDurationFast
                easing.type: Theme.animEasingExit; easing.bezierCurve: Theme.animBezierCurve
            }
        }
        ScriptAction { script: propertiesDialog.visible = false }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: propertiesDialog.close()
    }

    Item {
        id: propsBox
        width: 420
        height: propsOuterCol.height
        anchors.centerIn: parent
        opacity: 0; scale: 0.88; transformOrigin: Item.Center
        property real yOffset: 0
        transform: Translate { y: propsBox.yOffset }

        // Access dropdown options
        property var accessOptions: ["None", "Read only", "Read & Write", "Read, Write & Execute"]

        Rectangle {
            anchors.fill: parent
            color: Theme.mantle
            radius: Theme.radiusMedium
            border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)
            border.width: 1
        }

        Column {
            id: propsOuterCol
            width: parent.width
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
                    property string groupLabel
                    property string userName
                    property int accessIdx: 0
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

                    // Access selector row
                    Item {
                        width: parent.width; height: 34
                        Text {
                            text: "Access"
                            color: Theme.subtext; font.pointSize: Theme.fontSmall
                            anchors.left: parent.left; anchors.leftMargin: 36
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Q.Dropdown {
                            model: propsBox.accessOptions
                            currentIndex: accessIdx
                            label: ""
                            anchors.left: parent.left; anchors.leftMargin: 100
                            anchors.right: parent.right; anchors.rightMargin: 24
                            onSelected: (index, value) => accessChanged(index)
                        }
                    }

                    Item { width: 1; height: 4 }
                }

                PermGroup {
                    groupLabel: "Owner"
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

            // ── Close button ──
            Item {
                width: parent.width; height: 48
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
    }
}
