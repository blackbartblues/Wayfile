import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Wayfile
import Quill as Q

Window {
    id: root
    title: "Wayfile Settings"
    flags: Qt.Dialog | Qt.FramelessWindowHint
    color: "transparent"

    width: dialogWidth
    height: dialogHeight
    minimumWidth: dialogWidth
    // Fixed height regardless of the active tab. A content-driven height made
    // the Wayland surface fight the compositor — it would not shrink for a
    // short tab, leaving a transparent strip below the painted content. A
    // constant size sidesteps that entirely: short tabs simply leave empty
    // space and the background always fills the window. min == max pins it so
    // neither the compositor nor the user resizes it; clamped to the parent so
    // it never overflows a small display.
    minimumHeight: dialogHeight
    maximumHeight: dialogHeight

    readonly property int dialogWidth: Math.min(920, (transientParent ? transientParent.width : 920) - 32)
    readonly property int dialogHeight: Math.min(640, (transientParent ? transientParent.height - 80 : 640))
    readonly property int dialogRadius: draftRadiusLarge + 6

    function syncHyprlandRounding() {
        fileOps.setHyprlandRounding(root.title, root.dialogRadius)
        fileOps.setHyprlandBorder(root.title, 0)
    }

    onDialogRadiusChanged: {
        if (root.visible)
            syncHyprlandRounding()
    }

    readonly property color sectionBorderColor: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
    readonly property string defaultThemeName: "bifrost"
    readonly property string defaultIconThemeName: "Adwaita"
    readonly property string defaultSidebarPosition: "left"
    readonly property int defaultSidebarWidth: 220
    readonly property int defaultRadiusSmall: 4
    readonly property int defaultRadiusMedium: 6
    readonly property int defaultRadiusLarge: 10
    readonly property bool defaultTransparencyEnabled: true
    readonly property real defaultTransparencyLevel: 1.0
    readonly property bool defaultAnimationsEnabled: true
    readonly property int defaultAnimDurationFast: 100
    readonly property int defaultAnimDuration: 200
    readonly property int defaultAnimDurationSlow: 350
    readonly property string defaultAnimCurveEnter: "OutCubic"
    readonly property string defaultAnimCurveExit: "InCubic"
    readonly property string defaultAnimCurveTransition: "Bezier"
    readonly property bool defaultShowWindowControls: false
    readonly property string defaultWindowButtonLayout: ":minimize,maximize,close"
    readonly property bool defaultBuiltinIcons: true
    readonly property string defaultView: "hybrid"
    readonly property string defaultSortBy: "name"
    readonly property bool defaultSortAscending: true

    property bool currentShowHidden: false
    property bool currentSidebarVisible: true
    property int currentSidebarWidth: 220

    property var fontOptions: []
    property var iconThemeOptions: []
    property var availableFontValues: []
    property var availableIconThemeValues: []
    property bool optionSourcesPrimed: false
    property bool syncingFromConfig: false
    property bool pendingSettingsDirty: false
    property bool confirmReset: false

    property string draftTheme: config.theme
    property string draftFontFamily: config.fontFamily
    property string draftIconTheme: config.iconTheme
    property bool draftBuiltinIcons: config.builtinIcons
    property string draftDefaultView: config.defaultView
    property bool draftRememberFolderView: config.rememberFolderView
    property string draftSortBy: config.sortBy
    property bool draftSortAscending: config.sortAscending
    property bool draftShowHidden: currentShowHidden
    property bool draftSidebarVisible: currentSidebarVisible
    property string draftSidebarPosition: config.sidebarPosition
    property int draftSidebarWidth: currentSidebarWidth
    property real draftScrollSpeed: config.scrollSpeed
    property int draftRadiusSmall: config.radiusSmall
    property int draftRadiusMedium: config.radiusMedium
    property int draftRadiusLarge: config.radiusLarge
    property bool draftTransparencyEnabled: config.transparencyEnabled
    property real draftTransparencyLevel: config.transparencyLevel
    property bool draftAnimationsEnabled: config.animationsEnabled
    property int draftAnimDurationFast: config.animDurationFast
    property int draftAnimDuration: config.animDuration
    property int draftAnimDurationSlow: config.animDurationSlow
    property string draftAnimCurveEnter: config.animCurveEnter
    property string draftAnimCurveExit: config.animCurveExit
    property string draftAnimCurveTransition: config.animCurveTransition

    readonly property var curveOptions: ["OutCubic", "InOutCubic", "InCubic", "OutQuad", "InOutQuad", "OutExpo", "InOutExpo", "OutBack", "Linear", "Bezier"]

    readonly property var viewModeValues: ["hybrid", "grid", "miller", "detailed"]
    readonly property var viewModeLabels: ["Hybrid", "Grid", "Miller columns", "Detailed list"]
    readonly property var sortByValues: ["name", "size", "modified", "type"]
    readonly property var sortByLabels: ["Name", "Size", "Date modified", "Type"]

    property bool draftShowWindowControls: config.showWindowControls
    property string draftWindowButtonLayout: config.windowButtonLayout

    // Helpers to decompose the layout string for the UI
    readonly property var _layoutParts: {
        var layout = draftWindowButtonLayout || ":minimize,maximize,close"
        var parts = layout.split(":")
        var leftStr = parts[0] || ""
        var rightStr = parts.length > 1 ? parts[1] : ""
        var allButtons = []
        if (leftStr) allButtons = allButtons.concat(leftStr.split(",").filter(function(s) { return s.trim() !== "" }))
        if (rightStr) allButtons = allButtons.concat(rightStr.split(",").filter(function(s) { return s.trim() !== "" }))
        return {
            side: leftStr && !rightStr ? "left" : "right",
            hasClose: allButtons.indexOf("close") >= 0,
            hasMinimize: allButtons.indexOf("minimize") >= 0,
            hasMaximize: allButtons.indexOf("maximize") >= 0
        }
    }

    function rebuildButtonLayout(side, hasClose, hasMinimize, hasMaximize) {
        var buttons = []
        if (hasMinimize) buttons.push("minimize")
        if (hasMaximize) buttons.push("maximize")
        if (hasClose) buttons.push("close")
        var str = buttons.join(",")
        draftWindowButtonLayout = side === "left" ? (str + ":") : (":" + str)
        applySettingsNow()
    }

    signal remoteConnectRequested()
    signal keyboardShortcutsRequested()
    signal dependencyCheckRequested()
    signal closed()

    readonly property string systemFontLabel: "System Default"

    Component { id: paletteSectionIcon; IconSettings {} }
    Component { id: coloursSectionIcon; IconPalette {} }
    Component { id: layoutSectionIcon; IconPanelLeft {} }
    Component { id: motionSectionIcon; IconClock {} }
    Component { id: toolsSectionIcon; IconFolder {} }

    property int currentSectionIndex: 0
    readonly property bool compactNavigation: dialogWidth < 860
    readonly property var sectionNavItems: [
        { title: "Look & Feel", iconComponent: paletteSectionIcon },
        { title: "Colours", iconComponent: coloursSectionIcon },
        { title: "Layout", iconComponent: layoutSectionIcon },
        { title: "Motion", iconComponent: motionSectionIcon },
        { title: "Tools", iconComponent: toolsSectionIcon }
    ]
    readonly property var sectionItems: [
        { title: "Look & Feel", subtitle: "Theme, typography, icons, and surface styling.", iconComponent: paletteSectionIcon },
        { title: "Colours", subtitle: "Edit the palette token by token; saved as a custom theme.", iconComponent: coloursSectionIcon },
        { title: "Layout", subtitle: "Sidebar behavior, file visibility, and toolbar controls.", iconComponent: layoutSectionIcon },
        { title: "Motion", subtitle: "Animation timing and easing across the interface.", iconComponent: motionSectionIcon },
        { title: "Tools", subtitle: "Shortcuts, remote locations, and config behavior.", iconComponent: toolsSectionIcon }
    ]

    function showSection(index) {
        currentSectionIndex = index
        if (sideTabs)
            sideTabs.currentIndex = index
        if (compactSectionNav)
            compactSectionNav.currentIndex = index
        if (contentFlick)
            contentFlick.contentY = 0
    }

    function primeOptionSources() {
        if (optionSourcesPrimed)
            return

        availableFontValues = config.availableFonts
        availableIconThemeValues = config.availableIconThemes
        optionSourcesPrimed = true
    }

    function buildOptions(values, currentValue, fallbackValue) {
        var options = []
        for (var i = 0; i < values.length; ++i)
            options.push(values[i])

        var preferredValue = currentValue !== "" ? currentValue : fallbackValue
        if (preferredValue && options.indexOf(preferredValue) === -1)
            options.unshift(preferredValue)

        if (options.length === 0 && fallbackValue)
            options.push(fallbackValue)

        return options
    }

    function buildFontOptions() {
        var options = [systemFontLabel]
        for (var i = 0; i < availableFontValues.length; ++i)
            options.push(availableFontValues[i])

        if (draftFontFamily !== "" && options.indexOf(draftFontFamily) === -1)
            options.push(draftFontFamily)

        return options
    }

    function optionIndex(options, value, fallbackIndex) {
        var index = options.indexOf(value)
        return index >= 0 ? index : fallbackIndex
    }

    function setDraftTheme(themeName) {
        draftTheme = themeName
    }

    function bindAppearancePreview() {
        Theme.radiusSmall = Qt.binding(function() {
            return root.visible ? root.draftRadiusSmall : config.radiusSmall
        })
        Theme.radiusMedium = Qt.binding(function() {
            return root.visible ? root.draftRadiusMedium : config.radiusMedium
        })
        Theme.radiusLarge = Qt.binding(function() {
            return root.visible ? root.draftRadiusLarge : config.radiusLarge
        })
        Theme.transparencyEnabled = Qt.binding(function() {
            return root.visible ? root.draftTransparencyEnabled : config.transparencyEnabled
        })
        Theme.transparencyLevel = Qt.binding(function() {
            return root.visible ? root.draftTransparencyLevel : Math.max(0, Math.min(1, config.transparencyLevel))
        })
        Theme.animationsEnabled = Qt.binding(function() {
            return root.visible ? root.draftAnimationsEnabled : config.animationsEnabled
        })
    }

    function resetToDefaults() {
        setDraftTheme(defaultThemeName)
        draftFontFamily = ""
        draftIconTheme = defaultIconThemeName
        draftBuiltinIcons = defaultBuiltinIcons
        draftShowHidden = false
        draftDefaultView = defaultView
        draftSortBy = defaultSortBy
        draftSortAscending = defaultSortAscending
        draftSidebarVisible = true
        draftSidebarPosition = defaultSidebarPosition
        draftSidebarWidth = defaultSidebarWidth
        draftScrollSpeed = 3.0
        draftRadiusSmall = defaultRadiusSmall
        draftRadiusMedium = defaultRadiusMedium
        draftRadiusLarge = defaultRadiusLarge
        draftTransparencyEnabled = defaultTransparencyEnabled
        draftTransparencyLevel = defaultTransparencyLevel
        draftAnimationsEnabled = defaultAnimationsEnabled
        draftAnimDurationFast = defaultAnimDurationFast
        draftAnimDuration = defaultAnimDuration
        draftAnimDurationSlow = defaultAnimDurationSlow
        draftAnimCurveEnter = defaultAnimCurveEnter
        draftAnimCurveExit = defaultAnimCurveExit
        draftAnimCurveTransition = defaultAnimCurveTransition
        draftShowWindowControls = defaultShowWindowControls
        draftWindowButtonLayout = defaultWindowButtonLayout
        applySettingsNow()
    }

    function syncFromCurrentState() {
        primeOptionSources()
        syncingFromConfig = true
        try {
            draftTheme = config.theme

            draftFontFamily = config.fontFamily
            fontOptions = buildFontOptions()

            draftIconTheme = config.iconTheme
            iconThemeOptions = buildOptions(availableIconThemeValues, draftIconTheme, "Adwaita")
            draftBuiltinIcons = config.builtinIcons

            draftShowHidden = currentShowHidden
            draftDefaultView = config.defaultView
            draftRememberFolderView = config.rememberFolderView
            draftSortBy = config.sortBy
            draftSortAscending = config.sortAscending
            draftSidebarVisible = currentSidebarVisible
            draftSidebarPosition = config.sidebarPosition
            draftSidebarWidth = currentSidebarWidth
            draftScrollSpeed = config.scrollSpeed
            draftRadiusSmall = config.radiusSmall
            draftRadiusMedium = Math.max(config.radiusMedium, draftRadiusSmall)
            draftRadiusLarge = Math.max(config.radiusLarge, draftRadiusMedium)
            draftTransparencyEnabled = config.transparencyEnabled
            draftTransparencyLevel = config.transparencyLevel
            draftAnimationsEnabled = config.animationsEnabled
            draftAnimDurationFast = config.animDurationFast
            draftAnimDuration = config.animDuration
            draftAnimDurationSlow = config.animDurationSlow
            draftAnimCurveEnter = config.animCurveEnter
            draftAnimCurveExit = config.animCurveExit
            draftAnimCurveTransition = config.animCurveTransition
            draftShowWindowControls = config.showWindowControls
            draftWindowButtonLayout = config.windowButtonLayout
        } finally {
            syncingFromConfig = false
        }
    }

    function openPanel() {
        syncFromCurrentState()
        showSection(0)
        // Center over the parent window
        if (transientParent) {
            root.x = transientParent.x + Math.round((transientParent.width - root.width) / 2)
            root.y = transientParent.y + Math.round((transientParent.height - root.height) / 2)
        }
        root.show()
        root.raise()
        root.requestActivate()
        root.syncHyprlandRounding()
    }

    function closePanel() {
        confirmReset = false
        resetConfirmTimer.stop()
        flushPendingChanges()
        root.hide()
        root.closed()
    }

    function openRemoteConnect() {
        closePanel()
        remoteConnectRequested()
    }

    function openKeyboardShortcuts() {
        closePanel()
        keyboardShortcutsRequested()
    }

    function openDependencyCheck() {
        closePanel()
        dependencyCheckRequested()
    }

    function currentSettings() {
        return {
            theme: draftTheme,
            fontFamily: draftFontFamily,
            iconTheme: draftIconTheme,
            builtinIcons: draftBuiltinIcons,
            showHidden: draftShowHidden,
            defaultView: draftDefaultView,
            rememberFolderView: draftRememberFolderView,
            sortBy: draftSortBy,
            sortAscending: draftSortAscending,
            sidebarVisible: draftSidebarVisible,
            sidebarPosition: draftSidebarPosition,
            sidebarWidth: draftSidebarWidth,
            scrollSpeed: draftScrollSpeed,
            radiusSmall: draftRadiusSmall,
            radiusMedium: draftRadiusMedium,
            radiusLarge: draftRadiusLarge,
            transparencyEnabled: draftTransparencyEnabled,
            transparencyLevel: draftTransparencyLevel,
            animationsEnabled: draftAnimationsEnabled,
            animDurationFast: draftAnimDurationFast,
            animDuration: draftAnimDuration,
            animDurationSlow: draftAnimDurationSlow,
            animCurveEnter: draftAnimCurveEnter,
            animCurveExit: draftAnimCurveExit,
            animCurveTransition: draftAnimCurveTransition,
            showWindowControls: draftShowWindowControls,
            windowButtonLayout: draftWindowButtonLayout
        }
    }

    function queueSettingsApply() {
        if (syncingFromConfig)
            return

        pendingSettingsDirty = true
        settingsApplyTimer.restart()
    }

    function applyPendingSettings() {
        if (!pendingSettingsDirty)
            return

        pendingSettingsDirty = false
        settingsApplyTimer.stop()
        config.saveSettings(currentSettings())
    }

    function applySettingsNow() {
        if (syncingFromConfig)
            return

        pendingSettingsDirty = true
        applyPendingSettings()
    }

    function flushPendingChanges() {
        applyPendingSettings()
    }

    // ── Shared dropdown overlay API (used by SettingsDropdown on the pages) ──
    // openDropdownAnchor reports which trigger is currently open (so triggers
    // can rotate their chevron); openDropdown() opens the shared overlay for a
    // given trigger. See settingsDropdownPopup in pageContainer for why the
    // Quill Q.Dropdown can't be used on Wayland.
    property alias openDropdownAnchor: settingsDropdownPopup.openAnchor
    function openDropdown(item, options, currentIndex, pick) {
        settingsDropdownPopup.openFor(item, options, currentIndex, pick)
    }

    onClosing: {
        root.flushPendingChanges()
        root.closed()
    }

    Component.onCompleted: {
        root.primeOptionSources()
        root.bindAppearancePreview()
    }

    Timer {
        id: settingsApplyTimer
        interval: 140
        onTriggered: root.applyPendingSettings()
    }

    Timer {
        id: resetConfirmTimer
        interval: 3000
        repeat: false
        onTriggered: root.confirmReset = false
    }

    // Close on Escape
    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        onActivated: root.closePanel()
    }

    // Each settings page lives in its own SettingsSection*.qml; these thin
    // wrappers feed it the typed `panel` (reactive) and the loader width.
    Component { id: lookPageComponent; SettingsSectionLook { width: pageLoader.width; panel: root } }
    Component { id: coloursPageComponent; SettingsSectionColors { width: pageLoader.width; panel: root } }
    Component { id: layoutPageComponent; SettingsSectionLayout { width: pageLoader.width; panel: root } }
    Component { id: motionPageComponent; SettingsSectionMotion { width: pageLoader.width; panel: root } }
    Component { id: toolsPageComponent; SettingsSectionTools { width: pageLoader.width; panel: root } }

    Item {
        id: pageContainer
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: Theme.containerColor(Theme.mantle, 0.9)
            border.width: 1
            border.color: root.sectionBorderColor

            Rectangle {
                id: closeButton
                z: 10
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 8
                anchors.rightMargin: 8
                width: 28
                height: 28
                radius: Theme.radiusSmall
                color: closeHover.hovered
                    ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)
                    : "transparent"

                IconX {
                    anchors.centerIn: parent
                    size: 16
                    color: Theme.text
                }

                HoverHandler { id: closeHover }
                TapHandler { onTapped: root.closePanel() }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    Rectangle {
                        visible: !root.compactNavigation
                        Layout.fillHeight: true
                        Layout.preferredWidth: 184
                        color: Theme.containerColor(Theme.crust, 0.96)

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            anchors.topMargin: 16
                            spacing: 2

                            Row {
                                Layout.leftMargin: 12
                                Layout.bottomMargin: 12
                                spacing: 6

                                IconSettings {
                                    size: 16
                                    color: Theme.text
                                }

                                Text {
                                    text: "Settings"
                                    color: Theme.text
                                    font.pointSize: Theme.fontNormal + 1
                                    font.bold: true
                                }
                            }

                            Q.Tabs {
                                id: sideTabs
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                orientation: Qt.Vertical
                                model: root.sectionNavItems
                                labelRole: "title"
                                iconComponentRole: "iconComponent"
                                currentIndex: root.currentSectionIndex
                                sideTabHeight: 36
                                sideTabWidth: 168
                                onTabChanged: (index) => root.showSection(index)
                            }

                            Q.Button {
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                Layout.rightMargin: 12
                                Layout.topMargin: 8
                                text: root.confirmReset
                                    ? "Click again to confirm reset"
                                    : "Reset to Defaults"
                                variant: "ghost"
                                onClicked: {
                                    if (root.confirmReset) {
                                        root.confirmReset = false
                                        resetConfirmTimer.stop()
                                        root.resetToDefaults()
                                    } else {
                                        root.confirmReset = true
                                        resetConfirmTimer.restart()
                                    }
                                }
                            }
                        }
                    }

                    Q.Separator {
                        visible: !root.compactNavigation
                        orientation: Qt.Vertical
                        Layout.fillHeight: true
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 20
                            spacing: 12

                            Q.Tabs {
                                id: compactSectionNav
                                visible: root.compactNavigation
                                Layout.fillWidth: true
                                model: root.sectionNavItems
                                labelRole: "title"
                                currentIndex: root.currentSectionIndex
                                onTabChanged: (index) => root.showSection(index)
                            }

                            Text {
                                text: root.sectionItems[root.currentSectionIndex].title
                                color: Theme.text
                                font.pointSize: Theme.fontLarge + 2
                                font.bold: true
                            }

                            // A section page may pin a fixed header above the
                            // scroll area via `property Component pinnedHeader`.
                            // The Component is declared inside the page, so it
                            // resolves the page's ids/state through its creation
                            // context even though it is instantiated here. Only
                            // the Colours page uses it (the preset picker).
                            Loader {
                                id: pinnedHeaderLoader
                                Layout.fillWidth: true
                                active: pageLoader.item
                                        ? ((pageLoader.item.pinnedHeader || null) !== null)
                                        : false
                                sourceComponent: active ? pageLoader.item.pinnedHeader : null
                            }

                            Flickable {
                                id: contentFlick
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                contentWidth: width
                                contentHeight: pageLoader.item ? pageLoader.item.implicitHeight : 0
                                boundsBehavior: Flickable.StopAtBounds
                                interactive: contentHeight > height

                                Loader {
                                    id: pageLoader
                                    width: contentFlick.width
                                    sourceComponent: root.currentSectionIndex === 0
                                        ? lookPageComponent
                                        : root.currentSectionIndex === 1
                                            ? coloursPageComponent
                                            : root.currentSectionIndex === 2
                                                ? layoutPageComponent
                                                : root.currentSectionIndex === 3
                                                    ? motionPageComponent
                                                    : toolsPageComponent
                                }
                            }
                        }
                    }
                }

            }
        }

        // ── Shared in-scene dropdown overlay ──────────────────────────────
        // The Settings pages live inside the clipped `contentFlick` Flickable,
        // so a popup parented to a section/trigger would be culled by that
        // clip. Instead every Settings dropdown shares ONE overlay declared
        // here in pageContainer (above the Flickable, z:1000) and positions
        // itself with plain QML coords via mapToItem. This replaces Quill's
        // Q.Dropdown, whose native Qt.Popup window is mispositioned and won't
        // dismiss on Wayland (Hyprland). Same pattern as PropertiesDialog's
        // accessPopup.
        Item {
            id: settingsDropdownPopup
            anchors.fill: parent
            z: 1000
            visible: openAnchor !== null

            property var openAnchor: null     // the open trigger Rectangle; null = closed
            property var options: []
            property int selectedIndex: 0
            property var picker: null          // function(index, value)
            property real anchorX: 0
            property real anchorTopY: 0        // trigger top, in pageContainer coords
            property real anchorBottomY: 0     // trigger bottom, in pageContainer coords
            property real anchorWidth: 0

            function openFor(item, opts, currentIndex, pick) {
                var top = item.mapToItem(pageContainer, 0, 0)
                var bottom = item.mapToItem(pageContainer, 0, item.height)
                settingsDropdownPopup.anchorX = top.x
                settingsDropdownPopup.anchorTopY = top.y
                settingsDropdownPopup.anchorBottomY = bottom.y
                settingsDropdownPopup.anchorWidth = item.width
                settingsDropdownPopup.options = opts
                settingsDropdownPopup.selectedIndex = currentIndex
                settingsDropdownPopup.picker = pick
                settingsDropdownPopup.openAnchor = item
                Qt.callLater(function () {
                    dropdownListView.positionViewAtIndex(Math.max(0, currentIndex), ListView.Center)
                })
            }
            function dismiss() {
                settingsDropdownPopup.openAnchor = null
                settingsDropdownPopup.picker = null
            }

            // Outside-click catcher (only active while the overlay is visible).
            MouseArea { anchors.fill: parent; onClicked: settingsDropdownPopup.dismiss() }

            Rectangle {
                id: dropdownList
                readonly property int rowHeight: 30
                // Full height if every row were shown (4px top+bottom padding).
                readonly property real fullHeight: settingsDropdownPopup.options.length * rowHeight + 8
                // Vertical room available below / above the trigger (leaving an
                // 8px margin to the page edge and a 4px gap to the trigger).
                readonly property real spaceBelow: pageContainer.height - settingsDropdownPopup.anchorBottomY - 12
                readonly property real spaceAbove: settingsDropdownPopup.anchorTopY - 12
                // Open below; flip above only if it won't fit below AND there is
                // more room above. Long lists are capped to the available room
                // and scroll inside the ListView.
                readonly property bool flipUp: fullHeight > spaceBelow && spaceAbove > spaceBelow
                readonly property real avail: flipUp ? spaceAbove : spaceBelow
                width: settingsDropdownPopup.anchorWidth
                height: Math.min(fullHeight, Math.max(rowHeight + 8, avail))
                x: Math.max(8, Math.min(settingsDropdownPopup.anchorX, pageContainer.width - width - 8))
                y: flipUp
                    ? Math.max(8, settingsDropdownPopup.anchorTopY - 4 - height)
                    : settingsDropdownPopup.anchorBottomY + 4
                radius: Theme.radiusSmall
                color: Theme.surface
                border.width: 1
                border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.15)

                ListView {
                    id: dropdownListView
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: settingsDropdownPopup.options
                    currentIndex: settingsDropdownPopup.selectedIndex
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        width: dropdownListView.width
                        height: dropdownList.rowHeight
                        radius: Theme.radiusSmall
                        color: index === settingsDropdownPopup.selectedIndex
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                            : itemMa.containsMouse
                                ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                                : "transparent"
                        Text {
                            text: modelData
                            color: index === settingsDropdownPopup.selectedIndex ? Theme.accent : Theme.text
                            font.pointSize: Theme.fontSmall
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            id: itemMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var pick = settingsDropdownPopup.picker
                                var opts = settingsDropdownPopup.options
                                settingsDropdownPopup.dismiss()
                                if (pick) pick(index, opts[index])
                            }
                        }
                    }
                }
            }
        }
    }
}
