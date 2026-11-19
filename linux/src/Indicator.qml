import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Window

// The pill shown while dictating: red with the timer and voice level while
// recording, the accent while transcribing.
Window {
    id: pill
    width: row.implicitWidth + 36
    height: 44
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.WindowStaysOnTopHint

    Material.theme: Material.Dark

    Rectangle {
        anchors.fill: parent
        radius: Math.min(height / 2, theme.radius * 2)
        color: "#f0101012"
        border.color: backend.recording ? "#FF3B30" : theme.accent
        border.width: 1

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 10

            Rectangle {
                id: dot
                width: 10
                height: 10
                radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: backend.recording ? "#FF3B30" : theme.accent
                SequentialAnimation on opacity {
                    running: pill.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 600 }
                    NumberAnimation { to: 1; duration: 600 }
                }
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: backend.recording ? backend.durationText : qsTr("Transcribing…")
                color: "white"
                font.pixelSize: 14
                font.features: { "tnum": 1 }
            }

            LevelBars {
                visible: backend.recording
                anchors.verticalCenter: parent.verticalCenter
                count: 14
                height: 24
                live: backend.recording
                color: "white"
            }
        }
    }
}
