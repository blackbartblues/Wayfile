pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "showcase"

Scope {
    id: root

    property bool visible: false
    property int activePage: 0

    function toggle() {
        root.visible = !root.visible;
    }

    IpcHandler {
        target: "quill-showcase"
        function toggle(): void {
            root.toggle();
        }
    }

    GlobalShortcut {
        name: "quillShowcaseToggle"
        description: "Toggle Quill component showcase"
        onPressed: root.toggle()
    }

    property var pages: [
        { name: "Inputs", icon: "\uf11c" },
        { name: "Layout", icon: "\uf009" },
        { name: "Feedback", icon: "\uf0a2" },
        { name: "Display", icon: "\uf06e" }
    ]

    LazyLoader {
        active: root.visible

        PanelWindow {
            id: window

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quill-showcase"

            anchors {
                top: true; left: true; right: true; bottom: true
            }

            color: "transparent"

            // Backdrop
            Rectangle {
                anchors.fill: parent
                property real fadeIn: 0
                color: Qt.rgba(0, 0, 0, fadeIn * 0.25)

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.toggle()
                }

                NumberAnimation on fadeIn {
                    from: 0; to: 1
                    duration: Theme.animDuration
                    easing.type: Easing.OutCubic
                    running: true
                }
            }

            // Main panel — transparent bg so blur shows through (same pattern as Settings)
            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: 900
                height: 650
                color: Theme.bg(Theme.backgroundAlt, Theme.transparencyLevel)
                radius: 20
                border.color: Theme.surface1
                border.width: 1

                scale: 0.92; opacity: 0

                NumberAnimation on scale {
                    from: 0.92; to: 1.0; duration: 250
                    easing.type: Easing.OutCubic; running: true
                }
                NumberAnimation on opacity {
                    from: 0; to: 1.0; duration: 200
                    easing.type: Easing.OutCubic; running: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: (event) => event.accepted = true
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Sidebar (always opaque)
                    Rectangle {
                        Layout.fillHeight: true
                        Layout.preferredWidth: 180
                        color: Theme.backgroundDeep
                        radius: 20


                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 20
                            color: parent.color
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            anchors.topMargin: 16
                            spacing: 2

                            Text {
                                text: "\uf12e  Quill"
                                color: Theme.textPrimary
                                font.pixelSize: 16
                                font.family: Theme.fontFamily
                                font.bold: true
                                Layout.leftMargin: 12
                                Layout.bottomMargin: 12
                            }

                            Repeater {
                                model: root.pages

                                Rectangle {
                                    required property var modelData
                                    required property int index

                                    Layout.fillWidth: true
                                    height: 36; radius: 8
                                    color: root.activePage === index
                                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                        : navMouse.containsMouse ? Theme.surface0 : "transparent"
                                    Behavior on color { ColorAnimation { duration: 80 } }

                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        spacing: 10

                                        Text {
                                            text: modelData.icon
                                            color: root.activePage === index ? Theme.primary : Theme.overlay0
                                            font.pixelSize: 14; font.family: Theme.iconFont
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            text: modelData.name
                                            color: root.activePage === index ? Theme.primary : Theme.textPrimary
                                            font.pixelSize: 12; font.family: Theme.fontFamily
                                            font.bold: root.activePage === index
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: navMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activePage = index
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }

                    Rectangle {
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        color: Theme.surface0
                    }

                    // Content area (transparent — inherits blur from outer panel)
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        RowLayout {
                            id: pageHeader
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 20

                            Text {
                                text: root.pages[root.activePage].name
                                color: Theme.textPrimary
                                font.pixelSize: 18
                                font.family: Theme.fontFamily
                                font.bold: true
                            }
                        }

                        Flickable {
                            anchors.top: pageHeader.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 20
                            anchors.topMargin: 12
                            contentHeight: pageLoader.item?.implicitHeight ?? 0
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Loader {
                                id: pageLoader
                                width: parent.width
                                source: {
                                    let names = ["InputsSection", "LayoutSection",
                                                 "FeedbackSection", "DisplaySection"];
                                    return "showcase/" + names[root.activePage] + ".qml";
                                }
                            }
                        }
                    }
                }

                Shortcut {
                    sequence: "Escape"
                    onActivated: root.toggle()
                }
            }
        }
    }
}
