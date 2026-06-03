import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import ".."

Item {
    id: root
    property var model: []
    property int currentIndex: 0
    property string label: ""
    signal selected(int index, string value)
    implicitHeight: 34
    implicitWidth: 200
    Layout.fillWidth: true
    property bool dropdownOpen: false
    Accessible.role: Accessible.ComboBox
    Accessible.name: root.label !== "" ? root.label : (root.model[root.currentIndex] ?? "")
    Accessible.description: root.model[root.currentIndex] ?? ""

    // The host window the dropdown lives in. Close the popup whenever the
    // host moves, resizes, or loses focus so the popup never detaches from
    // its anchor.
    readonly property var _hostWindow: root.Window.window
    Connections {
        target: root._hostWindow
        ignoreUnknownSignals: true
        function onXChanged() { root.dropdownOpen = false }
        function onYChanged() { root.dropdownOpen = false }
        function onWidthChanged() { root.dropdownOpen = false }
        function onHeightChanged() { root.dropdownOpen = false }
        function onActiveChanged() {
            if (root._hostWindow && !root._hostWindow.active)
                root.dropdownOpen = false
        }
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        height: 34
        spacing: Theme.spacingMd
        Text {
            visible: root.label !== ""
            text: root.label
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
            Layout.preferredWidth: 140
        }
        Rectangle {
            id: buttonRect
            Layout.fillWidth: true
            height: 34
            radius: Theme.radius
            color: Theme.surface0
            border.color: root.dropdownOpen ? Theme.primary : Theme.surface1
            border.width: 1
            opacity: root.enabled ? 1.0 : 0.5
            Behavior on border.color { ColorAnimation { duration: Theme.animDurationFast } }
            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacing
                anchors.rightMargin: Theme.spacing
                Text {
                    text: root.model[root.currentIndex] ?? ""
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSize
                    font.family: Theme.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - chevron.width
                    elide: Text.ElideRight
                }
                Text {
                    id: chevron
                    text: root.dropdownOpen ? "\uf077" : "\uf078"
                    color: Theme.textTertiary
                    font.family: Theme.iconFont
                    font.pixelSize: 10
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (!root.enabled) return;
                    root.dropdownOpen = !root.dropdownOpen;
                }
            }
        }
    }

    // The popup is its own native Window. That avoids every class of
    // clipping / culling / z-order problem inside ancestor Flickables or
    // child Qt Windows (settings dialogs, frameless tool popups, etc.):
    // the compositor places it on top unconditionally. The earlier approach
    // of reparenting an Item to the window's contentItem was fragile — on
    // some hosts (notably a Qt.Dialog SettingsPanel) the popup children
    // got culled and the list never painted.
    Window {
        id: popupWindow
        flags: Qt.Popup | Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint
        color: "transparent"
        transientParent: root._hostWindow ? root._hostWindow : null
        visible: root.dropdownOpen

        width: buttonRect.width
        height: Math.min(root.model.length * 34 + 8, 208)

        // Anchor to the button in global screen coords. The explicit
        // geometry reads register buttonRect's x/y/w/h as dependencies, so
        // the binding re-evaluates when the button moves or is resized —
        // mapToItem() alone isn't reactive to geometry.
        readonly property point _anchor: {
            if (!buttonRect) return Qt.point(0, 0);
            var _bx = buttonRect.x, _by = buttonRect.y;
            var _bw = buttonRect.width, _bh = buttonRect.height;
            var hx = root._hostWindow ? root._hostWindow.x : 0;
            var hy = root._hostWindow ? root._hostWindow.y : 0;
            var local = buttonRect.mapToItem(null, 0, _bh + 4);
            return Qt.point(hx + local.x, hy + local.y);
        }
        x: _anchor.x
        y: _anchor.y

        Rectangle {
            id: dropdownList
            anchors.fill: parent
            radius: Theme.radius
            color: Theme.surface0
            border.color: Theme.surface1
            border.width: 1
            clip: true

            ListView {
                id: listView
                anchors.fill: parent
                anchors.margins: 4
                model: root.model
                currentIndex: root.currentIndex
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    required property string modelData
                    required property int index
                    width: listView.width
                    height: 30
                    radius: Theme.radiusSm
                    color: index === root.currentIndex
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        : itemMouse.containsMouse ? Theme.surface1 : "transparent"
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacing
                        text: modelData
                        color: index === root.currentIndex ? Theme.primary : Theme.textPrimary
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                    }
                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.currentIndex = index;
                            root.selected(index, modelData);
                            root.dropdownOpen = false;
                        }
                    }
                }
            }
        }

        // Qt.Popup normally auto-closes on outside click, but be explicit
        // so losing focus (Escape, Alt-Tab) also closes the popup.
        onActiveChanged: {
            if (!active)
                root.dropdownOpen = false
        }
    }

    onDropdownOpenChanged: { if (dropdownOpen) forceActiveFocus(); }
    Keys.onEscapePressed: dropdownOpen = false
    Keys.onUpPressed: { if (dropdownOpen && currentIndex > 0) currentIndex--; }
    Keys.onDownPressed: { if (dropdownOpen && currentIndex < model.length - 1) currentIndex++; }
    Keys.onReturnPressed: {
        if (dropdownOpen) {
            selected(currentIndex, model[currentIndex]);
            dropdownOpen = false;
        }
    }
}
