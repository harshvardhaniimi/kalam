import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Flickable {
    id: page
    Material.roundedScale: theme.radius

    contentWidth: width
    contentHeight: column.implicitHeight + 32
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    component Section: Label {
        Layout.topMargin: 14
        font.pixelSize: 13
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1
        color: win.muted
    }
    component Hint: Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: win.muted
        font.pixelSize: 12
    }
    component Card: Rectangle {
        default property alias content: inner.data
        Layout.fillWidth: true
        implicitHeight: inner.implicitHeight + 24
        radius: theme.radius
        color: win.surface
        border.color: win.line
        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6
        }
    }

    ColumnLayout {
        id: column
        x: 16
        y: 8
        width: page.width - 32
        spacing: 8

        Section { text: qsTr("Transcription engine"); Layout.topMargin: 0 }
        Card {
            RadioButton {
                text: qsTr("Sarvam AI (cloud, best for Hindi + English)")
                checked: backend.engine === "sarvam"
                onClicked: backend.engine = "sarvam"
            }
            RadioButton {
                text: qsTr("Local Whisper (offline, private)")
                checked: backend.engine === "local"
                onClicked: backend.engine = "local"
            }
            Hint {
                visible: backend.engine === "local" && !backend.whisperAvailable
                color: win.recordingRed
                text: qsTr("whisper-server is not installed. Install the whisper-cpp package.")
            }
            Hint {
                visible: backend.engine === "sarvam"
                text: qsTr("Audio is sent to Sarvam AI. If you also download a Whisper model, Kalam falls back to it when the network fails.")
            }
        }

        Section { text: qsTr("Sarvam AI"); visible: backend.engine === "sarvam" }
        Card {
            visible: backend.engine === "sarvam"
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                KField {
                    id: keyField
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    selectByMouse: true
                    placeholderText: backend.hasSarvamKey ? qsTr("API key saved. Enter a new one to replace it") : qsTr("API key")
                    onAccepted: saveKey.clicked()
                }
                KButton {
                    id: saveKey
                    text: qsTr("Save")
                    enabled: keyField.text.trim() !== ""
                    onClicked: if (backend.saveSarvamKey(keyField.text)) { keyField.clear(); win.flash(qsTr("Saved")) }
                }
                KButton {
                    text: qsTr("Remove")
                    flat: true
                    visible: backend.hasSarvamKey
                    onClicked: backend.saveSarvamKey("")
                }
            }
            Hint {
                text: backend.keyringAvailable
                      ? qsTr("Get a free key at dashboard.sarvam.ai. It is kept in your keyring, never in a plain file.")
                      : qsTr("secret-tool is not installed, so the key can't be saved. Set SARVAM_API_KEY instead.")
            }
            RadioButton {
                text: qsTr("Code-mixed (natural Hinglish)")
                checked: backend.sarvamMode === "codemix"
                onClicked: backend.sarvamMode = "codemix"
            }
            RadioButton {
                text: qsTr("Native script (Devanagari for Hindi)")
                checked: backend.sarvamMode === "transcribe"
                onClicked: backend.sarvamMode = "transcribe"
            }
        }

        Section { text: qsTr("Speech models") }
        Card {
            Repeater {
                model: backend.models
                delegate: ColumnLayout {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        RadioButton {
                            enabled: row.modelData.installed
                            checked: backend.model === row.modelData.id
                            onClicked: backend.model = row.modelData.id
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label {
                                text: row.modelData.name + "  ·  " + row.modelData.size
                                font.pixelSize: 14
                            }
                            Hint { text: row.modelData.description }
                        }
                        KButton {
                            flat: true
                            visible: !row.modelData.installed && !row.modelData.downloading
                            text: qsTr("Download")
                            onClicked: backend.downloadModel(row.modelData.id)
                        }
                        KButton {
                            flat: true
                            visible: row.modelData.downloading
                            text: qsTr("Cancel")
                            onClicked: backend.cancelDownload()
                        }
                        KButton {
                            flat: true
                            visible: row.modelData.installed
                            text: qsTr("Delete")
                            onClicked: backend.removeModel(row.modelData.id)
                        }
                    }
                    ProgressBar {
                        Layout.fillWidth: true
                        visible: row.modelData.downloading
                        value: row.modelData.progress
                    }
                }
            }
            Hint { text: qsTr("Only needed for Local Whisper, or as an offline fallback for Sarvam. For Hindi, use Large Turbo.") }
        }

        Section { text: qsTr("Language and microphone") }
        Card {
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Language"); Layout.fillWidth: true }
                ComboBox {
                    Layout.preferredWidth: 240
                    model: backend.languages
                    textRole: "name"
                    valueRole: "code"
                    currentIndex: indexOfValue(backend.language)
                    Component.onCompleted: currentIndex = indexOfValue(backend.language)
                    onActivated: backend.language = currentValue
                }
            }
            Hint { text: qsTr("The language applies to Local Whisper. Sarvam detects Hindi and English by itself.") }
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Microphone"); Layout.fillWidth: true }
                ComboBox {
                    id: microphones
                    Layout.preferredWidth: 240
                    model: [{ id: "", name: qsTr("System default") }].concat(backend.microphones)
                    textRole: "name"
                    valueRole: "id"
                    currentIndex: Math.max(0, indexOfValue(backend.microphone))
                    onModelChanged: currentIndex = Math.max(0, indexOfValue(backend.microphone))
                    onActivated: backend.microphone = currentValue
                }
            }
        }

        Section { text: qsTr("Personal dictionary") }
        Card {
            Hint { text: qsTr("Teach Kalam the words it keeps getting wrong. Corrections are whole-word and ignore case.") }
            Repeater {
                model: backend.dictionary
                delegate: RowLayout {
                    id: rule
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: rule.modelData.from + "  →  " + rule.modelData.to
                        font.pixelSize: 14
                    }
                    KButton {
                        flat: true
                        text: qsTr("Remove")
                        onClicked: backend.removeRule(rule.index)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                KField {
                    id: heard
                    Layout.fillWidth: true
                    placeholderText: qsTr("Heard as")
                    selectByMouse: true
                    onAccepted: meant.forceActiveFocus()
                }
                KField {
                    id: meant
                    Layout.fillWidth: true
                    placeholderText: qsTr("Should be")
                    selectByMouse: true
                    onAccepted: addRule.clicked()
                }
                KButton {
                    id: addRule
                    text: qsTr("Add")
                    enabled: heard.text.trim() !== "" && meant.text.trim() !== ""
                    onClicked: {
                        backend.addRule(heard.text, meant.text)
                        heard.clear()
                        meant.clear()
                        heard.forceActiveFocus()
                    }
                }
            }
        }

        Section { text: qsTr("General") }
        Card {
            Switch {
                text: qsTr("Paste at the cursor after dictating")
                checked: backend.autoPaste
                onToggled: backend.autoPaste = checked
            }
            Hint { text: qsTr("When off, the transcript is only copied to the clipboard.") }
            Switch {
                text: qsTr("Sound cues")
                checked: backend.sounds
                onToggled: backend.sounds = checked
            }
            Switch {
                text: qsTr("Start Kalam at login")
                checked: backend.launchAtLogin
                onToggled: { backend.launchAtLogin = checked; checked = Qt.binding(() => backend.launchAtLogin) }
            }
            Hint { text: qsTr("Change the dictation keys in Omarchy's keybindings; Kalam answers to \"omarchy dictation\".") }
        }
    }
}
