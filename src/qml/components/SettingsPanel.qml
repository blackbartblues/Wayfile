import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Heimdall
import Quill as Q

Window {
    id: root
    title: "Heimdall Settings"
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
    readonly property string defaultThemeName: "catppuccin-mocha"
    readonly property string defaultIconThemeName: "Adwaita"
    readonly property string defaultSidebarPosition: "left"
    readonly property int defaultSidebarWidth: 200
    readonly property int defaultRadiusSmall: 4
    readonly property int defaultRadiusMedium: 8
    readonly property int defaultRadiusLarge: 12
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
    readonly property string defaultView: "grid"
    readonly property string defaultSortBy: "name"
    readonly property bool defaultSortAscending: true

    property bool currentShowHidden: false
    property bool currentSidebarVisible: true
    property int currentSidebarWidth: 200

    property var themeOptions: []
    property var fontOptions: []
    property var iconThemeOptions: []
    property var availableThemeValues: []
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
    property string draftSortBy: config.sortBy
    property bool draftSortAscending: config.sortAscending
    property bool draftDarkMode: true
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

    readonly property var viewModeValues: ["grid", "miller", "detailed"]
    readonly property var viewModeLabels: ["Grid", "Miller columns", "Detailed list"]
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
    Component { id: layoutSectionIcon; IconPanelLeft {} }
    Component { id: motionSectionIcon; IconClock {} }
    Component { id: toolsSectionIcon; IconFolder {} }

    property int currentSectionIndex: 0
    readonly property bool compactNavigation: dialogWidth < 860
    readonly property var sectionNavItems: [
        { title: "Look & Feel", iconComponent: paletteSectionIcon },
        { title: "Layout", iconComponent: layoutSectionIcon },
        { title: "Motion", iconComponent: motionSectionIcon },
        { title: "Tools", iconComponent: toolsSectionIcon }
    ]
    readonly property var sectionItems: [
        { title: "Look & Feel", subtitle: "Theme, typography, icons, and surface styling.", iconComponent: paletteSectionIcon },
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

        availableThemeValues = config.availableThemes
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

    function isDarkTheme(themeName) {
        return themeName !== "catppuccin-latte"
    }

    function setDraftTheme(themeName) {
        draftTheme = themeName
        draftDarkMode = isDarkTheme(themeName)
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
            draftDarkMode = isDarkTheme(draftTheme)
            themeOptions = buildOptions(availableThemeValues, draftTheme, "catppuccin-mocha")

            draftFontFamily = config.fontFamily
            fontOptions = buildFontOptions()

            draftIconTheme = config.iconTheme
            iconThemeOptions = buildOptions(availableIconThemeValues, draftIconTheme, "Adwaita")
            draftBuiltinIcons = config.builtinIcons

            draftShowHidden = currentShowHidden
            draftDefaultView = config.defaultView
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
                                            ? layoutPageComponent
                                            : root.currentSectionIndex === 2
                                                ? motionPageComponent
                                                : toolsPageComponent
                                }
                            }
                        }
                    }
                }

            }
        }
    }
}
