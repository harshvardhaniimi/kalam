import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 720
    height: 680
    minimumWidth: 520
    minimumHeight: 480
    visible: true
    title: "Kalam"
    color: "#0e0e10"

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    property bool helpVisible: false
    property int page: 0
    // Single-key shortcuts stand down while the user is typing in a field.
    readonly property bool typing: activeFocusItem !== null && activeFocusItem.hasOwnProperty("cursorPosition")
    readonly property color surface: "#17171a"
    readonly property color line: "#2a2a2f"
    readonly property color muted: "#8e8e96"
    readonly property color recordingRed: "#FF3B30"

    function flash(message) {
        toast.text = message
        toastTimer.restart()
    }

    Connections {
        target: backend
        function onFlashed(message) { win.flash(message) }
    }

    Shortcut { sequences: ["?", "F1"]; context: Qt.ApplicationShortcut; enabled: !win.typing; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; enabled: !win.typing; onActivated: win.close() }
    Shortcut { sequence: "Space"; context: Qt.ApplicationShortcut; enabled: !win.typing && !win.helpVisible; onActivated: backend.toggleRecording() }
    Shortcut { sequence: "C"; context: Qt.ApplicationShortcut; enabled: !win.typing && win.page === 0; onActivated: backend.copyTranscript() }
    Shortcut { sequence: "O"; context: Qt.ApplicationShortcut; enabled: !win.typing; onActivated: backend.pickFile() }
    Shortcut { sequence: "1"; context: Qt.ApplicationShortcut; enabled: !win.typing; onActivated: win.page = 0 }
    Shortcut { sequence: "2"; context: Qt.ApplicationShortcut; enabled: !win.typing; onActivated: win.page = 1 }
    Shortcut { sequence: "3"; context: Qt.ApplicationShortcut; enabled: !win.typing; onActivated: win.page = 2 }
    Shortcut { sequence: "/"; context: Qt.ApplicationShortcut; enabled: !win.typing; onActivated: { win.page = 1; historyPage.focusSearch() } }
    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        onActivated: {
            if (win.helpVisible) win.helpVisible = false
            else if (win.typing) content.forceActiveFocus()
            else if (backend.recording) backend.cancelRecording()
        }
    }

    // Right-to-left languages mirror the window; the Translator sets the
    // application's layout direction.
    Item {
        id: content
        anchors.fill: parent
        focus: true
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.bottomMargin: 8
                spacing: 4

                Label {
                    text: "Kalam"
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    Layout.rightMargin: 16
                }

                Repeater {
                    model: [qsTr("Dictate"), qsTr("History"), qsTr("Settings")]
                    delegate: Rectangle {
                        required property int index
                        required property string modelData
                        implicitWidth: tabLabel.implicitWidth + 28
                        implicitHeight: 34
                        radius: theme.radius
                        color: win.page === index ? theme.accent : tabHover.hovered ? win.surface : "transparent"

                        Label {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: parent.modelData
                            font.pixelSize: 14
                            color: win.page === parent.index ? theme.accentForeground : "#d8d8de"
                        }
                        HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: win.page = parent.index }
                    }
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: "?"
                    color: win.muted
                    font.pixelSize: 16
                    padding: 8
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: win.helpVisible = true }
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: win.page

                DictatePage {}
                HistoryPage { id: historyPage; active: win.page === 1 }
                SettingsPage {}
            }

            // The last error, until dismissed or the next recording starts.
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.topMargin: 0
                visible: backend.lastError !== ""
                implicitHeight: errorRow.implicitHeight + 20
                radius: theme.radius
                color: "#3a1512"
                border.color: win.recordingRed

                RowLayout {
                    id: errorRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 12
                    Label {
                        Layout.fillWidth: true
                        text: backend.lastError
                        wrapMode: Text.Wrap
                        color: "#ffd9d6"
                        font.pixelSize: 13
                    }
                    Label {
                        text: qsTr("Dismiss")
                        color: "#ffd9d6"
                        font.pixelSize: 13
                        font.underline: true
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: backend.dismissError() }
                    }
                }
            }
        }

        // Drop an audio or video file anywhere on the window.
        DropArea {
            id: drop
            anchors.fill: parent
            keys: ["text/uri-list"]
            onDropped: (event) => {
                if (event.hasUrls && event.urls.length > 0)
                    backend.transcribeUrl(event.urls[0])
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 8
            visible: drop.containsDrag
            color: "#cc0e0e10"
            radius: theme.radius
            border.color: theme.accent
            border.width: 2
            Label {
                anchors.centerIn: parent
                text: qsTr("Drop to transcribe")
                font.pixelSize: 20
            }
        }

        Rectangle {
            id: toastBox
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            width: toast.implicitWidth + 32
            height: 36
            radius: theme.radius
            color: theme.accent
            opacity: toastTimer.running ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Label {
                id: toast
                anchors.centerIn: parent
                color: theme.accentForeground
                font.pixelSize: 13
            }
            Timer { id: toastTimer; interval: 1400 }
        }

        HelpOverlay {
            anchors.fill: parent
            visible: win.helpVisible
            onDismissed: win.helpVisible = false
        }
    }
}
