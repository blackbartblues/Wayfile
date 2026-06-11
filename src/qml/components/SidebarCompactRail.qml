import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Wayfile
import Quill as Quill

// 56px icon-only column shown when the sidebar is in Compact mode — extracted
// from Sidebar.qml (Phase 4). Renders the top-level visible entries (Favorites
// star · bookmarks · Home · Recents · Hidden · each existing XDG root · each
// mounted/known device · Network · Trash) as centred icon buttons with hover
// tooltips, active state, and navigation wired to the SAME handlers as the full
// rows. Respects the same hide filter.
//
// Non-visual container: it owns the rail's own icon glyph set + the reusable
// compactButton, and uses the global fsModel/fileOps/config/bookmarks/devices/
// networkModel/runtimeFeatures context props directly. The host (Sidebar) feeds
// reactive state via typed properties and forwards the four navigation signals;
// placesFolderModel is SidebarPlacesTree's resident FolderTreeModel, reused for
// XDG-existence checks rather than spinning up a second QFileSystemModel.
Item {
    id: root

    // ── Injected by the host (Sidebar) ─────────────────────────────────────
    property var host: null
    property string currentPath: ""
    property bool isRecentsView: false
    property bool isHiddenView: false
    property string trashPath: ""
    property bool networkHidden: false
    property bool trashHidden: false
    // = placesTree.folderModel (SidebarPlacesTree's resident FolderTreeModel).
    property var placesFolderModel: null

    // ── Forwarded up to the host (it re-emits its own same-named signals) ──
    signal bookmarkClicked(string path)
    signal recentsClicked()
    signal hiddenClicked()
    signal featureHintRequested(string message)

    readonly property bool compactMode: root.host && root.host.sidebarCompact
    visible: root.compactMode

    // Fixed width of the compact icon rail (icon column / Flickable / each button).
    readonly property int compactRailWidth: 56

    // XDG-existence checks reuse placesFolderModel — no second QFileSystemModel.
    readonly property var compactXdgRoots: {
        const home = fsModel.homePath()
        return [
            { label: "Desktop",   dir: home + "/Desktop"   },
            { label: "Documents", dir: home + "/Documents" },
            { label: "Downloads", dir: home + "/Downloads" },
            { label: "Pictures",  dir: home + "/Pictures"  },
            { label: "Music",     dir: home + "/Music"     },
            { label: "Videos",    dir: home + "/Videos"    }
        ]
    }

    // ── Glyphs ──────────────────────────────────────────────────────────────
    // Shared place/bookmark glyphs (the full sidebar keeps its own copies); the
    // loaders rebind the color to gold when their row is the active one.
    Component { id: iconHome; IconHome { size: 16; color: Theme.muted } }
    Component { id: iconEyeOff; IconEyeOff { size: 16; color: Theme.muted } }
    Component { id: iconClock; IconClock { size: 16; color: Theme.muted } }
    Component { id: iconTrash; IconTrash { size: 16; color: Theme.muted } }
    Component { id: iconGlobe; IconGlobe { size: 16; color: Theme.muted } }
    // Inline "network" glyph (Lucide network: three nodes + a connecting bus).
    // icons/ is a no-push submodule, so it lives here rather than as IconNetwork.qml.
    Component {
        id: iconNetwork
        Shape {
            id: netShape
            property real size: 16
            property color color: Theme.muted
            property real strokeWidth: Math.max(1, size / 12)
            width: size; height: size
            preferredRendererType: Shape.CurveRenderer
            // Three node boxes.
            ShapePath {
                strokeColor: netShape.color; strokeWidth: netShape.strokeWidth
                fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(netShape.size / 24, netShape.size / 24)
                PathSvg { path: "M9 2 H15 V8 H9 Z M2 16 H8 V22 H2 Z M16 16 H22 V22 H16 Z" }
            }
            // Connecting bus: centre drop, horizontal trunk, two leg drops.
            ShapePath {
                strokeColor: netShape.color; strokeWidth: netShape.strokeWidth
                fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                scale: Qt.size(netShape.size / 24, netShape.size / 24)
                PathSvg { path: "M12 8 V12 M5 12 H19 M5 12 V16 M19 12 V16" }
            }
        }
    }
    Component { id: iconFolder; IconFolder { size: 16; color: Theme.muted } }
    Component { id: iconStarGold; IconStar { size: 11; color: Theme.gold } }
    // FILLED star for the Favorites leading icon. IconStar (submodule) is a
    // stroke-only outline, so we inline a solid-fill variant here (same Lucide
    // path) — its `color` is rebound per-row to the bookmark's chosen color, or
    // Theme.gold by default. Keep this in the main repo; do not edit icons/.
    Component {
        id: iconStarFilled
        Shape {
            id: starShape
            property real size: 14
            property color color: Theme.gold
            width: size; height: size
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"; strokeWidth: 0
                fillColor: starShape.color
                joinStyle: ShapePath.RoundJoin
                scale: Qt.size(starShape.size / 24, starShape.size / 24)
                PathSvg { path: "M11.525 2.295a.53.53 0 0 1 .95 0l2.31 4.679a.53.53 0 0 0 .4.29l5.16.753a.53.53 0 0 1 .294.904l-3.733 3.638a.53.53 0 0 0-.152.469l.882 5.14a.53.53 0 0 1-.77.56l-4.614-2.426a.53.53 0 0 0-.494 0L7.14 18.728a.53.53 0 0 1-.77-.56l.882-5.14a.53.53 0 0 0-.152-.47L3.367 8.92a.53.53 0 0 1 .294-.905l5.16-.752a.53.53 0 0 0 .4-.29z" }
            }
        }
    }
    // Per-place icons for XDG roots in the compact rail (matching SidebarPlacesTree).
    Component { id: iconMonitor;  IconMonitor  { size: 16; color: Theme.muted } }
    Component { id: iconFileText; IconFileText { size: 16; color: Theme.muted } }
    Component { id: iconDownload; IconDownload { size: 16; color: Theme.muted } }
    Component { id: iconImage;    IconImage    { size: 16; color: Theme.muted } }
    Component { id: iconMusic;    IconMusic    { size: 16; color: Theme.muted } }
    Component { id: iconVideo;    IconVideo    { size: 16; color: Theme.muted } }
    // Drive glyphs for the compact device buttons (full rows use SidebarDeviceRow).
    Component { id: iconCompactDrive; IconHardDrive { size: 18; color: Theme.muted } }
    Component { id: iconCompactUsb;   IconUsb { size: 18; color: Theme.muted } }
    // Expand-to-full control glyph (the full sidebar's collapse button uses the
    // same IconPanelLeft — this is its counterpart while collapsed).
    Component { id: iconCompactPanel; IconPanelLeft { size: 16; color: Theme.muted } }

    // Reusable compact icon button. `iconKind` selects the glyph; `active` lights
    // the gold accent rail + wash; `tip` is the hover tooltip; onActivated runs
    // the navigation handler. XDG/device entries draw a folder/drive glyph.
    Component {
        id: compactButton
        Item {
            id: cbtn
            width: root.compactRailWidth
            height: 34
            property string iconKind: "folder"
            property bool active: false
            property string tip: ""
            // W8: optional fixed glyph color (used by colored favorite stars in
            // the rail). When unset (transparent), the active/muted rule applies.
            property color glyphColor: "transparent"
            signal activated()

            Rectangle {
                id: cbtnBg
                anchors.centerIn: parent
                width: 40
                height: 28
                radius: Theme.radiusRow
                color: cbtn.active
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10)
                    : (cbtnHover.hovered
                       ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
                       : "transparent")
                Behavior on color { ColorAnimation { duration: Theme.animDuration } }
            }

            // Active: 2px gold left rail with a soft glow (matches the full rows).
            Rectangle {
                visible: cbtn.active
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.topMargin: 5
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                width: 2
                color: Theme.gold
                topRightRadius: 3
                bottomRightRadius: 3
                layer.enabled: true
                layer.effect: MultiEffect {
                    autoPaddingEnabled: true
                    shadowEnabled: true
                    shadowColor: Theme.goldGlow
                    shadowBlur: 0.6
                }
            }

            Loader {
                anchors.centerIn: parent
                width: 16; height: 16
                sourceComponent: {
                    switch (cbtn.iconKind) {
                    case "star":      return iconStarGold
                    case "favstar":   return iconStarFilled
                    case "home":      return iconHome
                    case "clock":     return iconClock
                    case "eyeoff":    return iconEyeOff
                    case "globe":     return iconGlobe
                    case "network":   return iconNetwork
                    case "trash":     return iconTrash
                    case "harddrive": return iconCompactDrive
                    case "usb":       return iconCompactUsb
                    case "panel":     return iconCompactPanel
                    case "desktop":   return iconMonitor
                    case "documents": return iconFileText
                    case "downloads": return iconDownload
                    case "pictures":  return iconImage
                    case "music":     return iconMusic
                    case "videos":    return iconVideo
                    default:          return iconFolder
                    }
                }
                onLoaded: {
                    if (!item)
                        return
                    // The "star" section anchor is intrinsically gold; leave it.
                    if (cbtn.iconKind === "star")
                        return
                    // Bind reactively rather than branching at load time: a
                    // favorite sets glyphColor in its OWN onLoaded, which can run
                    // after this glyph has already reloaded (folder→favstar), so a
                    // load-time branch would lock in the muted/gold fallback and
                    // drop the bookmark colour. A fixed glyphColor wins; otherwise
                    // gold-when-active / muted.
                    item.color = Qt.binding(() => cbtn.glyphColor.a > 0
                        ? cbtn.glyphColor
                        : (cbtn.active ? Theme.gold : Theme.muted))
                }
            }

            HoverHandler { id: cbtnHover }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: cbtn.activated()
            }

            Quill.Tooltip {
                text: cbtn.tip
                visible: cbtnHover.hovered && cbtn.tip.length > 0
            }
        }
    }

    // Expand-to-full control pinned to the TOP of the rail. The full sidebar's
    // collapse button is hidden in compact mode, so this is the way back; kept
    // outside the Flickable so it never scrolls out of reach.
    Loader {
        id: compactExpandLoader
        z: 1
        anchors.top: parent.top
        anchors.topMargin: Theme.spacing
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.compactRailWidth
        active: root.compactMode
        visible: active
        height: active ? 34 : 0
        sourceComponent: compactButton
        onLoaded: {
            item.iconKind = "panel"
            item.tip = "Expand sidebar"
            item.active = false
            item.activated.connect(function() {
                if (root.host) root.host.setSidebarCompact(false)
            })
        }
    }

    // Compact Trash pinned to bottom of the rail. Rendered outside the Flickable
    // so it stays anchored to the bottom of the sidebar even when the scrollable
    // content is short. Height matches the rail button (34) + bottom padding.
    Loader {
        id: compactTrashLoader
        z: 1
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacing
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.compactRailWidth
        active: root.compactMode && !root.trashHidden
        visible: active
        height: active ? 34 : 0
        sourceComponent: compactButton
        onLoaded: {
            item.iconKind = "trash"
            item.tip = "Trash"
            item.active = Qt.binding(() =>
                !root.isRecentsView && !root.isHiddenView
                && fileOps.isTrashPath(root.currentPath))
            item.activated.connect(function() { root.bookmarkClicked(root.trashPath) })
        }
    }

    Flickable {
        id: compactRail
        anchors.fill: parent
        // Reserve room for the top-pinned Expand button so scrolled content never
        // slides under it: 34 (button height) + Theme.spacing (top anchor margin)
        // + 4 (gap below it).
        anchors.topMargin: root.compactMode ? (34 + Theme.spacing + 4) : 0
        // Reserve room for the bottom-pinned compact Trash button so scrolled
        // content never slides under it: 34 (compactTrashLoader height) +
        // Theme.spacing (its bottom anchor margin) + 4 (gap above it).
        anchors.bottomMargin: root.compactMode && !root.trashHidden
            ? (34 + Theme.spacing + 4) : 0
        visible: root.compactMode
        contentWidth: width
        contentHeight: compactColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: compactColumn
            width: root.compactRailWidth
            spacing: 2
            topPadding: Theme.spacing
            bottomPadding: Theme.spacing

            // Favorites star — purely a section anchor in compact mode; keeps it
            // simple (navigates Home like the wordmark used to).
            Loader {
                width: root.compactRailWidth
                sourceComponent: compactButton
                onLoaded: {
                    item.iconKind = "star"
                    item.tip = "Favorites"
                    item.active = false
                    item.activated.connect(function() {
                        root.bookmarkClicked(fsModel.homePath())
                    })
                }
            }

            // Bookmarked favorites (respect per-bookmark hide).
            Repeater {
                model: bookmarks
                delegate: Loader {
                    width: root.compactRailWidth
                    readonly property bool entryHidden:
                        config.hiddenSidebarEntries.indexOf(model.path) >= 0
                    active: !entryHidden
                    visible: active
                    height: active ? 34 : 0
                    sourceComponent: compactButton
                    onLoaded: {
                        // W8: filled star in the bookmark's chosen color (gold
                        // default), matching the full Favorites rows.
                        item.iconKind = "favstar"
                        item.glyphColor = Qt.binding(() =>
                            (model.color && model.color.length > 0)
                                ? model.color : Theme.gold)
                        item.tip = model.name
                        item.active = Qt.binding(() =>
                            !root.isRecentsView && !root.isHiddenView
                            && model.path === root.currentPath)
                        var p = model.path
                        item.activated.connect(function() { root.bookmarkClicked(p) })
                    }
                }
            }

            // Thin divider before Places.
            Rectangle {
                width: 36; height: 1; anchors.horizontalCenter: parent.horizontalCenter
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
            }

            // Home — always visible.
            Loader {
                width: root.compactRailWidth
                sourceComponent: compactButton
                onLoaded: {
                    item.iconKind = "home"
                    item.tip = "Home"
                    item.active = Qt.binding(() =>
                        !root.isRecentsView && !root.isHiddenView
                        && fsModel.homePath() === root.currentPath)
                    item.activated.connect(function() {
                        root.bookmarkClicked(fsModel.homePath())
                    })
                }
            }

            // Recents.
            Loader {
                width: root.compactRailWidth
                active: config.hiddenSidebarEntries.indexOf("places.recents") < 0
                visible: active
                height: active ? 34 : 0
                sourceComponent: compactButton
                onLoaded: {
                    item.iconKind = "clock"
                    item.tip = "Recents"
                    item.active = Qt.binding(() => root.isRecentsView)
                    item.activated.connect(function() { root.recentsClicked() })
                }
            }

            // Hidden.
            Loader {
                width: root.compactRailWidth
                active: config.hiddenSidebarEntries.indexOf("places.hidden") < 0
                visible: active
                height: active ? 34 : 0
                sourceComponent: compactButton
                onLoaded: {
                    item.iconKind = "eyeoff"
                    item.tip = "Hidden"
                    item.active = Qt.binding(() => root.isHiddenView)
                    item.activated.connect(function() { root.hiddenClicked() })
                }
            }

            // XDG roots — only those that exist (re-checked on directoryLoaded).
            Repeater {
                model: root.compactXdgRoots
                delegate: Loader {
                    width: root.compactRailWidth
                    required property var modelData
                    property bool dirExists: root.placesFolderModel.indexForPath(modelData.dir).valid
                    Connections {
                        target: root.placesFolderModel
                        function onDirectoryLoaded(p) {
                            dirExists = root.placesFolderModel.indexForPath(modelData.dir).valid
                        }
                    }
                    active: dirExists
                    visible: active
                    height: active ? 34 : 0
                    sourceComponent: compactButton
                    onLoaded: {
                        // Map each XDG root to its unique semantic icon kind
                        // (mirrors the per-place icons in SidebarPlacesTree).
                        var lbl = modelData.label
                        if      (lbl === "Desktop")   item.iconKind = "desktop"
                        else if (lbl === "Documents") item.iconKind = "documents"
                        else if (lbl === "Downloads") item.iconKind = "downloads"
                        else if (lbl === "Pictures")  item.iconKind = "pictures"
                        else if (lbl === "Music")     item.iconKind = "music"
                        else if (lbl === "Videos")    item.iconKind = "videos"
                        else                          item.iconKind = "folder"
                        item.tip = modelData.label
                        item.active = Qt.binding(() =>
                            !root.isRecentsView && !root.isHiddenView
                            && modelData.dir === root.currentPath)
                        var d = modelData.dir
                        item.activated.connect(function() {
                            if (root.host) root.host.navigateActivePaneTo(d)
                        })
                    }
                }
            }

            // Devices — same model the full Devices section iterates.
            Item {
                width: root.compactRailWidth; height: devices.count > 0 ? 9 : 0
                visible: devices.count > 0
                Rectangle {
                    anchors.centerIn: parent
                    width: 36; height: 1
                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                }
            }
            Repeater {
                model: devices
                delegate: Loader {
                    id: deviceCompact
                    width: root.compactRailWidth
                    // Stable index for devices.mount(); model.mounted / model.mountPoint
                    // must be read LIVE inside the handler (not captured at load), so an
                    // unmounted-at-load device still mounts on click.
                    required property int index
                    required property var model
                    sourceComponent: compactButton
                    onLoaded: {
                        item.iconKind = model.removable ? "usb" : "harddrive"
                        item.tip = model.deviceName
                        item.active = Qt.binding(() =>
                            !root.isRecentsView && !root.isHiddenView
                            && model.mounted && model.mountPoint === root.currentPath)
                        item.activated.connect(function() {
                            // Mirror SidebarDeviceRow: mounted → navigate; unmounted →
                            // mount (after the udisks2-availability guard).
                            if (deviceCompact.model.mounted)
                                root.bookmarkClicked(deviceCompact.model.mountPoint)
                            else if (deviceCompact.model.backend === "udisks2"
                                     && !runtimeFeatures.udisksctlAvailable)
                                root.featureHintRequested(runtimeFeatures.installHint("deviceMount"))
                            else
                                devices.mount(deviceCompact.index)
                        })
                    }
                }
            }

            // Network — one compact button per live GVFS mount (W8). Empty
            // model (or hidden) → no rows.
            Repeater {
                model: root.networkHidden ? null : networkModel
                delegate: Loader {
                    readonly property string entryName: model.name
                    readonly property string entryUri: model.uri
                    width: root.compactRailWidth
                    height: 34
                    sourceComponent: compactButton
                    onLoaded: {
                        item.iconKind = "network"
                        item.tip = entryName
                        item.active = Qt.binding(() =>
                            !root.isRecentsView && !root.isHiddenView
                            && root.currentPath.length > 0
                            && (root.currentPath === entryUri
                                || root.currentPath.indexOf(entryUri) === 0))
                        item.activated.connect(function() { root.bookmarkClicked(entryUri) })
                    }
                }
            }

        }
    }
}
