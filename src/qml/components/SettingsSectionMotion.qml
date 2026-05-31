import QtQuick
import QtQuick.Layouts
import Heimdall
import Quill as Q

// Motion settings page — animation timing and easing curves.
// Extracted from SettingsPanel.qml. All draft state and helpers live on
// the typed `panel` (a SettingsPanel), so reads stay reactive.
ColumnLayout {
    property SettingsPanel panel
    spacing: 6


    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        spacing: 12

        Text {
            text: "Animations"
            color: Theme.text
            font.pointSize: Theme.fontNormal + 2
            font.bold: true
        }

        Item { Layout.fillWidth: true }

        Q.Toggle {
            label: ""
            checked: panel.draftAnimationsEnabled
            onToggled: (value) => {
                panel.draftAnimationsEnabled = value
                panel.applySettingsNow()
            }
        }
    }

    SettingDescription {
        text: "Enable interface animations; turn off for instant, motion-free transitions."
    }

    Q.Separator { Layout.bottomMargin: 8 }

    Text {
        text: "Timing"
        color: Theme.accent
        font.pointSize: Theme.fontSmall
        font.bold: true
        Layout.bottomMargin: 4
    }

    Q.Slider {
        Layout.fillWidth: true
        label: "Fast"
        from: 0
        to: 500
        stepSize: 10
        showValue: true
        enabled: panel.draftAnimationsEnabled
        value: panel.draftAnimDurationFast
        onMoved: (value) => {
            panel.draftAnimDurationFast = Math.round(value)
            panel.queueSettingsApply()
        }
    }

    SettingDescription {
        enabled: panel.draftAnimationsEnabled
        text: "Duration in milliseconds for quick animations like hovers and toggles."
    }

    Q.Slider {
        Layout.fillWidth: true
        label: "Normal"
        from: 0
        to: 1000
        stepSize: 10
        showValue: true
        enabled: panel.draftAnimationsEnabled
        value: panel.draftAnimDuration
        onMoved: (value) => {
            panel.draftAnimDuration = Math.round(value)
            panel.queueSettingsApply()
        }
    }

    SettingDescription {
        enabled: panel.draftAnimationsEnabled
        text: "Duration in milliseconds for standard animations like panel transitions."
    }

    Q.Slider {
        Layout.fillWidth: true
        label: "Slow"
        from: 0
        to: 1500
        stepSize: 10
        showValue: true
        enabled: panel.draftAnimationsEnabled
        value: panel.draftAnimDurationSlow
        onMoved: (value) => {
            panel.draftAnimDurationSlow = Math.round(value)
            panel.queueSettingsApply()
        }
    }

    SettingDescription {
        enabled: panel.draftAnimationsEnabled
        text: "Duration in milliseconds for slow, emphasis animations."
    }

    Text {
        text: "Curves"
        color: Theme.accent
        font.pointSize: Theme.fontSmall
        font.bold: true
        Layout.topMargin: 12
        Layout.bottomMargin: 4
    }

    Q.Dropdown {
        Layout.fillWidth: true
        label: "Enter"
        enabled: panel.draftAnimationsEnabled
        model: panel.curveOptions
        currentIndex: Math.max(0, panel.curveOptions.indexOf(panel.draftAnimCurveEnter))
        onSelected: (_, value) => {
            panel.draftAnimCurveEnter = value
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        enabled: panel.draftAnimationsEnabled
        text: "Easing curve used when elements appear or expand into view."
    }

    Q.Dropdown {
        Layout.fillWidth: true
        label: "Exit"
        enabled: panel.draftAnimationsEnabled
        model: panel.curveOptions
        currentIndex: Math.max(0, panel.curveOptions.indexOf(panel.draftAnimCurveExit))
        onSelected: (_, value) => {
            panel.draftAnimCurveExit = value
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        enabled: panel.draftAnimationsEnabled
        text: "Easing curve used when elements disappear or collapse out of view."
    }

    Q.Dropdown {
        Layout.fillWidth: true
        label: "Transition"
        enabled: panel.draftAnimationsEnabled
        model: panel.curveOptions
        currentIndex: Math.max(0, panel.curveOptions.indexOf(panel.draftAnimCurveTransition))
        onSelected: (_, value) => {
            panel.draftAnimCurveTransition = value
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        enabled: panel.draftAnimationsEnabled
        text: "Easing curve used for in-place changes like value and position updates."
    }
}
