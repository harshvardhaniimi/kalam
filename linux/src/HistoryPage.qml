import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Item {
    id: page
    Material.roundedScale: theme.radius

    property bool active: false
    // Re-read whenever the history or the query changes.
    readonly property var entries: { backend.historyRevision; return backend.history(search.text) }

    function focusSearch() { search.forceActiveFocus() }
    function current() { return list.currentIndex >= 0 && list.currentIndex < entries.length ? entries[list.currentIndex] : null }

    Shortcut { sequence: "Down"; enabled: page.active; onActivated: list.incrementCurrentIndex() }
    Shortcut { sequence: "Up"; enabled: page.active; onActivated: list.decrementCurrentIndex() }
    Shortcut { sequences: ["Return", "Enter"]; enabled: page.active && page.current() !== null; onActivated: backend.copyHistory(page.current().id) }
    Shortcut { sequence: "Delete"; enabled: page.active && !win.typing && page.current() !== null; onActivated: backend.deleteHistory(page.current().id) }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        anchors.topMargin: 8
        spacing: 10

        KField {
            id: search
            Layout.fillWidth: true
            placeholderText: qsTr("Search history")
            selectByMouse: true
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: page.entries
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            delegate: Rectangle {
                id: card
                required property int index
                required property var modelData
                readonly property bool selected: ListView.isCurrentItem
                width: ListView.view.width
                height: body.implicitHeight + 24
                radius: theme.radius
                color: win.surface
                border.color: selected ? theme.accent : win.line

                TapHandler { onTapped: list.currentIndex = card.index }

                ColumnLayout {
                    id: body
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: win.muted
                        font.pixelSize: 12
                        text: card.modelData.date + "  ·  " + card.modelData.duration
                              + (card.modelData.sourceFile !== "" ? "  ·  " + card.modelData.sourceFile : "")
                    }
                    Label {
                        Layout.fillWidth: true
                        text: card.modelData.text
                        wrapMode: Text.Wrap
                        font.pixelSize: 14
                        // The selected entry shows in full.
                        maximumLineCount: card.selected ? 1000 : 3
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        visible: card.selected
                        spacing: 4
                        KButton {
                            text: qsTr("Copy")
                            flat: true
                            onClicked: backend.copyHistory(card.modelData.id)
                        }
                        KButton {
                            id: exportButton
                            text: qsTr("Export…")
                            flat: true
                            onClicked: exportMenu.open()
                            Menu {
                                id: exportMenu
                                y: exportButton.height
                                MenuItem { text: qsTr("Text"); onTriggered: backend.exportHistory(card.modelData.id, "text") }
                                MenuItem { text: "Markdown"; onTriggered: backend.exportHistory(card.modelData.id, "markdown") }
                                MenuItem { text: "JSON"; onTriggered: backend.exportHistory(card.modelData.id, "json") }
                                MenuItem { text: qsTr("SRT (Subtitles)"); onTriggered: backend.exportHistory(card.modelData.id, "srt") }
                            }
                        }
                        KButton {
                            text: qsTr("Delete")
                            flat: true
                            onClicked: backend.deleteHistory(card.modelData.id)
                        }
                    }
                }
            }

            Label {
                anchors.centerIn: parent
                visible: list.count === 0
                color: win.muted
                font.pixelSize: 14
                text: search.text !== "" ? qsTr("Nothing matches that search.") : qsTr("Transcripts you dictate show up here.")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Label {
                color: win.muted
                font.pixelSize: 12
                text: qsTr("%n transcriptions", "", backend.historyCount)
            }
            Item { Layout.fillWidth: true }
            KButton {
                text: qsTr("Clear All…")
                flat: true
                enabled: backend.historyCount > 0
                onClicked: confirmClear.open()
            }
        }
    }

    Dialog {
        id: confirmClear
        anchors.centerIn: parent
        modal: true
        title: qsTr("Delete all history?")
        standardButtons: Dialog.Cancel | Dialog.Ok
        Material.roundedScale: theme.radius
        Label {
            width: 320
            wrapMode: Text.Wrap
            text: qsTr("Every saved transcript will be removed. This can't be undone.")
        }
        onAccepted: backend.clearHistory()
    }
}
