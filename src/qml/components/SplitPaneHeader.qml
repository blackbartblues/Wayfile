import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Heimdall

// 26 px path strip drawn at the top of each pane in split view.  Shows a status
// dot, the pane's current path (mono, tilde-collapsed) and a right-aligned item
// count.  The dot + text turn gold when the pane is the active one — handoff
// `.pane__strip` / `.pane__strip--active`.
//
// Phase 1 M6: lifted out of Main.qml's inline `component SplitPaneHeader`
// declaration so PaneFrame.qml (which lives in the Heimdall module) can
// instantiate it without falling outside its own scope.
// Phase 7 (handoff): re-skinned from a 34 px title strip to the 26 px obsidian
// path strip with status dot + item count.
Item {
    id: splitPaneHeader

    property string path: ""
    property int itemCount: 0
    property bool activePaneHeader: false

    // Tilde-collapse the home prefix for display (matches Breadcrumb's "Home"
    // convention). fsModel.homePath() is a constant Q_INVOKABLE so reading it
    // inside this binding is safe — only `path` is reactive and re-triggers it.
    readonly property string displayPath: {
        const home = fsModel.homePath()
        if (splitPaneHeader.path === home) return "~"
        if (home.length > 0 && splitPaneHeader.path.startsWith(home + "/"))
            return "~" + splitPaneHeader.path.substring(home.length)
        return splitPaneHeader.path
    }

    Layout.fillWidth: true
    Layout.preferredHeight: 26

    // Dark inset strip + bottom hairline glued to the content below.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.22)

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.hair
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 8

        // Status dot — gold with a soft glow when this is the active pane,
        // muted otherwise.
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            width: 6
            height: 6
            radius: 3
            color: splitPaneHeader.activePaneHeader ? Theme.gold : Theme.muted
            Behavior on color { ColorAnimation { duration: Theme.animDuration } }

            layer.enabled: splitPaneHeader.activePaneHeader
            layer.effect: MultiEffect {
                autoPaddingEnabled: true
                shadowEnabled: true
                shadowColor: Theme.goldGlow
                shadowBlur: 0.6
            }
        }

        // Current path (tilde-collapsed, mono); elides on the left so the
        // meaningful tail of a long path stays visible.
        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: splitPaneHeader.displayPath
            color: splitPaneHeader.activePaneHeader ? Theme.gold : Theme.muted
            font.family: Fonts.mono
            font.pointSize: Theme.fontSmall
            elide: Text.ElideLeft
            verticalAlignment: Text.AlignVCenter
            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
        }

        // Item count, right-aligned.
        Text {
            Layout.alignment: Qt.AlignVCenter
            text: splitPaneHeader.itemCount + " items"
            color: splitPaneHeader.activePaneHeader ? Theme.gold : Theme.muted
            font.family: Fonts.mono
            font.pointSize: Theme.fontSmall
            verticalAlignment: Text.AlignVCenter
            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
        }
    }
}
