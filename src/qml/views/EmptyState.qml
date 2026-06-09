import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Wayfile

// Empty-folder hero state (handoff §8 / system jsx 162-175). A big gold
// folder glyph over a soft radial gold halo, a title + subtitle, and three
// actions: New folder (primary gold), New file (secondary), Show hidden (ghost).
//
// Shown by a view when the current directory lists zero visible items. Purely
// visual + the three buttons — every other pixel is click-through, so the host
// view's background MouseArea still handles deselect / directory context menu.
Item {
    id: root

    signal newFolderClicked()
    signal newFileClicked()
    signal showHiddenClicked()

    // True while the pane's directory is showing hidden (dot-)files, so the
    // "Show hidden" toggle can render lit.
    property bool hiddenShown: false

    // ── ubtn (handoff): primary gold / secondary raise / ghost ──────────────
    component UButton: Rectangle {
        id: btn
        property string kind: "secondary"   // "primary" | "secondary" | "ghost"
        property string iconName: ""
        property string label: ""
        // A lit/on state (used by the "Show hidden" toggle): gold-wash fill +
        // gold ring + gold content, regardless of kind.
        property bool active: false
        signal clicked()

        readonly property bool isPrimary: kind === "primary"
        readonly property bool isGhost: kind === "ghost"

        implicitHeight: 32
        implicitWidth: btnRow.implicitWidth + 26
        radius: Theme.radiusButton
        border.width: isPrimary ? 0 : 1
        border.color: active ? Theme.goldLine
             : isGhost ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.10)
             : Theme.line
        color: isPrimary ? "transparent"
             : active ? Theme.goldWash
             : isGhost ? (btnMa.containsMouse ? Theme.raise : "transparent")
             : (btnMa.containsMouse ? Theme.raise2 : Theme.raise)
        Behavior on color { ColorAnimation { duration: 100 } }

        // Primary gold gradient fill (goldLight→gold→goldMid), beneath
        // the label so the dark ink stays legible.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: btn.isPrimary
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.goldLight }
                GradientStop { position: 0.6; color: Theme.gold }
                GradientStop { position: 1.0; color: Theme.goldMid }
            }
            layer.enabled: btn.isPrimary
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.goldGlow
                shadowBlur: 0.6
                shadowVerticalOffset: 0
                autoPaddingEnabled: true
            }
        }

        RowLayout {
            id: btnRow
            anchors.centerIn: parent
            spacing: 7
            Loader {
                Layout.preferredWidth: 15
                Layout.preferredHeight: 15
                Layout.alignment: Qt.AlignVCenter
                active: btn.iconName !== ""
                source: btn.iconName !== "" ? "../icons/Icon" + btn.iconName + ".qml" : ""
                onLoaded: {
                    item.size = 15
                    item.color = Qt.binding(() => btn.isPrimary ? Theme.goldInk
                        : (btn.active ? Theme.gold : (btn.isGhost ? Theme.muted : Theme.gold)))
                }
            }
            Text {
                text: btn.label
                font.pointSize: Theme.fontSmall
                font.weight: btn.isPrimary ? Font.DemiBold : Font.Medium
                color: btn.isPrimary ? Theme.goldInk : (btn.active ? Theme.goldLight : Theme.text)
                verticalAlignment: Text.AlignVCenter
            }
        }

        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 380)
        spacing: 0

        // Art: the same gold folder glyph the grid/rows use (FileTypeColors.folder
        // + thinned stroke), over a soft radial gold halo — consistent with the
        // rest of the app.
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 104
            implicitHeight: 104

            Rectangle {
                anchors.centerIn: folderArt
                width: 156
                height: 156
                radius: 78
                color: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.14)
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 48
                    autoPaddingEnabled: true
                }
            }
            IconFolder {
                id: folderArt
                anchors.centerIn: parent
                size: 96
                color: FileTypeColors.folder
                strokeWidth: Math.max(1.5, size / 28)
            }
        }

        Item { Layout.preferredHeight: 20; Layout.fillWidth: true }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "This folder is empty"
            color: Theme.text
            font.pointSize: Theme.fontLarge
            font.weight: Font.DemiBold
        }

        Item { Layout.preferredHeight: 6; Layout.fillWidth: true }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "Drop files here, or create something new. Hidden items aren’t shown — use Show hidden to reveal dot-files."
            color: Theme.muted
            font.pointSize: Theme.fontSmall
            lineHeight: 1.3
        }

        Item { Layout.preferredHeight: 22; Layout.fillWidth: true }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            UButton {
                kind: "primary"
                iconName: "Folder"
                label: "New folder"
                onClicked: root.newFolderClicked()
            }
            UButton {
                kind: "secondary"
                iconName: "FileText"
                label: "New file"
                onClicked: root.newFileClicked()
            }
            UButton {
                kind: "ghost"
                iconName: "EyeOff"
                label: "Show hidden"
                active: root.hiddenShown
                onClicked: root.showHiddenClicked()
            }
        }
    }
}
