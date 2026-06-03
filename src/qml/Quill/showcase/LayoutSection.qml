import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    spacing: Theme.spacingXl

    // ── Card ──
    Text {
        text: "Card"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
    }

    Card {
        title: "User Profile"
        subtitle: "Account details and preferences"

        Text {
            text: "This card has a title and subtitle header. Card content goes here and can contain any QML elements."
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }

    Card {
        Text {
            text: "This card has no header — just raw content inside a styled container."
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }

    Card {
        title: "Nested Content"

        RowLayout {
            spacing: Theme.spacing
            Rectangle {
                width: 40; height: 40; radius: 20
                color: Theme.primary
                Text {
                    anchors.centerIn: parent
                    text: "A"
                    color: Theme.backgroundDeep
                    font.pixelSize: Theme.fontSize
                    font.family: Theme.fontFamily
                    font.bold: true
                }
            }
            ColumnLayout {
                spacing: 2
                Text {
                    text: "Alice Johnson"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSize
                    font.family: Theme.fontFamily
                    font.bold: true
                }
                Text {
                    text: "alice@example.com"
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.fontFamily
                }
            }
        }

        Separator {}

        Text {
            text: "Cards can hold nested layouts, separators, and any other components."
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }

    // ── Separator ──
    Text {
        text: "Separator"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
        Layout.topMargin: Theme.spacing
    }

    Text {
        text: "Horizontal"
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
    }
    Separator {}

    Text {
        text: "Vertical (in a row)"
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
    }
    RowLayout {
        spacing: Theme.spacingMd
        height: 40
        Text {
            text: "Left"
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        Separator { orientation: Qt.Vertical; Layout.preferredHeight: 24 }
        Text {
            text: "Center"
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        Separator { orientation: Qt.Vertical; Layout.preferredHeight: 24 }
        Text {
            text: "Right"
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
    }

    // ── Tabs ──
    Text {
        text: "Tabs"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
        Layout.topMargin: Theme.spacing
    }

    property int demoTabIndex: 0

    Tabs {
        model: ["Overview", "Settings", "Activity"]
        currentIndex: demoTabIndex
        onTabChanged: function(index) { demoTabIndex = index; }
    }

    Rectangle {
        Layout.fillWidth: true
        height: 60
        radius: Theme.radius
        color: Theme.surface0

        Text {
            visible: demoTabIndex === 0
            anchors.centerIn: parent
            text: "Overview — summary and stats go here"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        Text {
            visible: demoTabIndex === 1
            anchors.centerIn: parent
            text: "Settings — configuration options go here"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
        Text {
            visible: demoTabIndex === 2
            anchors.centerIn: parent
            text: "Activity — recent events go here"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
        }
    }

    // ── Collapsible ──
    Text {
        text: "Collapsible"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
        Layout.topMargin: Theme.spacing
    }

    Collapsible {
        title: "Click to expand"

        Text {
            text: "This content is hidden by default. Click the header to toggle visibility with a smooth animation."
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing
        }
    }

    Collapsible {
        title: "Initially expanded"
        expanded: true

        Text {
            text: "This section starts open so you can see its content right away."
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing
        }
    }

    Collapsible {
        title: "Nested collapsibles"
        expanded: true

        Collapsible {
            title: "Sub-section A"
            Layout.leftMargin: Theme.spacing

            Text {
                text: "Content inside sub-section A."
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize
                font.family: Theme.fontFamily
                Layout.leftMargin: Theme.spacing
            }
        }

        Collapsible {
            title: "Sub-section B"
            Layout.leftMargin: Theme.spacing

            Text {
                text: "Content inside sub-section B."
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize
                font.family: Theme.fontFamily
                Layout.leftMargin: Theme.spacing
            }
        }
    }

    // ── ScrollableList ──
    Text {
        text: "ScrollableList"
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeLarge
        font.family: Theme.fontFamily
        font.bold: true
        Layout.topMargin: Theme.spacing
    }

    Text {
        text: "With items"
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
    }

    property var sampleColors: [
        "#89b4fa", "#b4befe", "#cba6f7", "#f5c2e7", "#eba0ac",
        "#f38ba8", "#fab387", "#f9e2af", "#a6e3a1", "#94e2d5",
        "#89dceb", "#74c7ec", "#89b4fa", "#b4befe", "#cba6f7",
        "#f5c2e7", "#eba0ac", "#f38ba8"
    ]

    ScrollableList {
        implicitHeight: 240
        model: 18
        delegate: Rectangle {
            required property int index
            width: ListView.view ? ListView.view.width - 8 : 100
            height: 36
            radius: Theme.radiusSm
            color: sampleColors[index % sampleColors.length]
            opacity: 0.7

            Text {
                anchors.centerIn: parent
                text: "Item " + (index + 1)
                color: Theme.backgroundDeep
                font.pixelSize: Theme.fontSize
                font.family: Theme.fontFamily
                font.bold: true
            }
        }
    }

    Text {
        text: "Empty list"
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
    }

    ScrollableList {
        implicitHeight: 80
        model: 0
        emptyText: "Nothing to display"
        delegate: Item {}
    }
}
