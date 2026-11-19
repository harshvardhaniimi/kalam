import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Item {
    id: page
    Material.roundedScale: theme.radius

    readonly property var downloading: {
        for (const model of backend.models)
            if (model.downloading) return model
        return null
    }
    readonly property string status: {
        if (backend.recording) return qsTr("Recording")
        if (backend.processing) return qsTr("Transcribing…")
        if (downloading) return qsTr("Downloading the %1 model… %2%").arg(downloading.name).arg(Math.round(downloading.progress * 100))
        if (!backend.canTranscribe) return backend.notReadyMessage
        return qsTr("Ready")
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        anchors.topMargin: 8
        spacing: 14

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 12
            spacing: 12

            // The record button is a true circle whatever the theme's corners.
            Rectangle {
                id: button
                Layout.alignment: Qt.AlignHCenter
                width: 104
                height: 104
                radius: 52
                color: backend.recording ? win.recordingRed : theme.accent
                opacity: backend.processing || !backend.canTranscribe ? 0.45 : buttonHover.hovered ? 0.9 : 1
                scale: backend.recording ? 1 + backend.level * 0.12 : 1
                Behavior on scale { NumberAnimation { duration: 90 } }
                Behavior on color { ColorAnimation { duration: 150 } }

                // A stop square while recording, otherwise a microphone.
                Rectangle {
                    anchors.centerIn: parent
                    visible: backend.recording
                    width: 30
                    height: 30
                    radius: Math.min(4, theme.radius)
                    color: "white"
                }
                Item {
                    anchors.centerIn: parent
                    visible: !backend.recording
                    width: 40
                    height: 52
                    readonly property color ink: theme.accentForeground
                    Rectangle { x: 11; y: 0; width: 18; height: 30; radius: 9; color: parent.ink }
                    Rectangle {
                        x: 4; y: 14; width: 32; height: 26; radius: 16
                        color: "transparent"; border.color: parent.ink; border.width: 3
                        // Hide the top half, leaving the cradle under the capsule.
                        Rectangle { x: -1; y: -1; width: 34; height: 12; color: button.color }
                    }
                    Rectangle { x: 11; y: 0; width: 18; height: 30; radius: 9; color: parent.ink }
                    Rectangle { x: 18.5; y: 39; width: 3; height: 9; color: parent.ink }
                    Rectangle { x: 10; y: 48; width: 20; height: 3; radius: 1.5; color: parent.ink }
                }

                HoverHandler { id: buttonHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: backend.toggleRecording() }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: page.width - 64
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: backend.recording ? page.status + "  " + backend.durationText : page.status
                font.pixelSize: 15
                color: backend.recording ? win.recordingRed : "#d8d8de"
            }

            LevelBars {
                Layout.alignment: Qt.AlignHCenter
                live: backend.recording
                color: backend.recording ? win.recordingRed : win.muted
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: theme.radius
            color: win.surface
            border.color: win.line

            ScrollView {
                id: scroll
                anchors.fill: parent
                anchors.margins: 4
                visible: backend.transcript !== ""
                TextArea {
                    text: backend.transcript
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    font.pixelSize: 16
                    background: null
                    // Reading text is not typing: keep the single-key
                    // shortcuts alive.
                    activeFocusOnPress: false
                }
            }

            Label {
                anchors.centerIn: parent
                width: parent.width - 48
                visible: backend.transcript === ""
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: win.muted
                font.pixelSize: 14
                lineHeight: 1.35
                text: qsTr("Press Alt + Space anywhere to dictate, or hold Alt + Right Alt and talk. The text lands at your cursor.\n\nHere, press Space to record, or drop an audio file to transcribe it.")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            KButton {
                text: qsTr("Copy")
                enabled: backend.transcript !== ""
                onClicked: backend.copyTranscript()
            }
            KButton {
                text: qsTr("Transcribe a File…")
                flat: true
                enabled: !backend.recording && !backend.processing
                onClicked: backend.pickFile()
            }
            Item { Layout.fillWidth: true }
            Label {
                color: win.muted
                font.pixelSize: 12
                text: backend.engine === "sarvam" ? qsTr("Sarvam AI") : qsTr("Local Whisper")
            }
        }
    }
}
