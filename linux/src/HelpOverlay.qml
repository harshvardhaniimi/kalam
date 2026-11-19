import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Every shortcut, on "?".
Rectangle {
    id: overlay
    signal dismissed()
    color: "#e60e0e10"

    TapHandler { onTapped: overlay.dismissed() }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 460)
        height: column.implicitHeight + 40
        radius: theme.radius
        color: "#17171a"
        border.color: "#2a2a2f"

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 20
            spacing: 10

            Label {
                text: qsTr("Shortcuts")
                font.pixelSize: 18
                font.weight: Font.DemiBold
                Layout.bottomMargin: 4
            }

            Repeater {
                model: [
                    ["Alt + Space", qsTr("Start or stop dictating, anywhere")],
                    ["Alt + Right Alt", qsTr("Hold to talk, anywhere")],
                    ["Space", qsTr("Record in this window")],
                    ["Esc", qsTr("Throw the recording away")],
                    ["C", qsTr("Copy the transcript")],
                    ["O", qsTr("Transcribe a file")],
                    ["1  2  3", qsTr("Dictate, History, Settings")],
                    ["/", qsTr("Search history")],
                    ["↑  ↓", qsTr("Move through history")],
                    ["Enter", qsTr("Copy the selected entry")],
                    ["Delete", qsTr("Delete the selected entry")],
                    ["Q", qsTr("Close the window (Kalam keeps listening)")],
                    ["?", qsTr("Show or hide this list")]
                ]
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 16
                    Label {
                        text: parent.modelData[0]
                        Layout.preferredWidth: 130
                        font.family: "monospace"
                        font.pixelSize: 13
                        color: theme.accent
                    }
                    Label {
                        text: parent.modelData[1]
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
