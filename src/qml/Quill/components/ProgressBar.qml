import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    property real value: 0.0
    property string variant: "primary"
    property bool indeterminate: false
    property bool monotonic: false
    implicitHeight: 6
    Layout.fillWidth: true
    radius: Theme.radiusFull
    color: Theme.surface1
    Accessible.role: Accessible.ProgressBar
    Accessible.name: root.indeterminate ? "Loading" : Math.round(root.value * 100) + " percent"

    // Animated display value; monotonic mode ignores transient backward updates.
    readonly property real _clampedValue: {
        if (value <= 0)
            return 0.0
        if (value >= 1)
            return 1.0
        return value
    }
    property real _displayValue: monotonic ? 0.0 : _clampedValue
    property bool _snapDisplayValue: false

    function syncDisplayValue() {
        if (root.indeterminate)
            return

        if (!root.monotonic) {
            root._displayValue = root._clampedValue
            return
        }

        if (root._clampedValue <= 0.001) {
            root._snapDisplayValue = true
            root._displayValue = 0.0
            root._snapDisplayValue = false
            return
        }

        if (root._clampedValue > root._displayValue)
            root._displayValue = root._clampedValue
    }

    Component.onCompleted: syncDisplayValue()
    onValueChanged: syncDisplayValue()

    onIndeterminateChanged: {
        if (!root.indeterminate)
            syncDisplayValue()
    }

    onMonotonicChanged: {
        root._snapDisplayValue = true
        root._displayValue = root.monotonic ? 0.0 : root._clampedValue
        root._snapDisplayValue = false
        syncDisplayValue()
    }

    Behavior on _displayValue {
        enabled: !root._snapDisplayValue && !root.indeterminate
        NumberAnimation {
            duration: Theme.animDuration
            easing.type: Easing.OutCubic
        }
    }

    property color _fillColor: {
        switch (variant) {
            case "success": return Theme.success;
            case "warning": return Theme.warning;
            case "error": return Theme.error;
            default: return Theme.primary;
        }
    }
    Rectangle {
        visible: !root.indeterminate
        width: parent.width * root._displayValue
        height: parent.height
        radius: Theme.radiusFull
        color: root._fillColor
    }
    Rectangle {
        id: indeterminateBar
        visible: root.indeterminate
        width: parent.width * 0.3
        height: parent.height
        radius: Theme.radiusFull
        color: root._fillColor
        SequentialAnimation on x {
            running: root.indeterminate
            loops: Animation.Infinite
            NumberAnimation {
                from: -indeterminateBar.width
                to: root.width
                duration: 1200
                easing.type: Easing.InOutCubic
            }
        }
    }
    clip: true
}
