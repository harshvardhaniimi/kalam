import QtQuick

// A scrolling strip of the microphone's recent levels. `live` freezes it
// when nothing is recording.
Item {
    id: bars
    property int count: 28
    property bool live: false
    property color color: "white"
    property var levels: []

    implicitHeight: 40
    implicitWidth: count * 6

    function reset() {
        const empty = []
        for (let i = 0; i < count; ++i) empty.push(0)
        levels = empty
    }

    Component.onCompleted: reset()
    onLiveChanged: if (live) reset()

    // Sampled on a steady clock so the strip scrolls evenly however the
    // audio buffers arrive.
    Timer {
        interval: 60
        repeat: true
        running: bars.live && bars.visible
        onTriggered: {
            const next = bars.levels.slice(1)
            next.push(backend.level)
            bars.levels = next
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 3
        Repeater {
            model: bars.count
            delegate: Rectangle {
                required property int index
                width: 3
                height: Math.max(3, (bars.levels[index] || 0) * bars.height)
                anchors.verticalCenter: parent.verticalCenter
                radius: Math.min(1.5, theme.radius)
                color: bars.color
                opacity: bars.live ? 1 : 0.35
                Behavior on height { NumberAnimation { duration: 60 } }
            }
        }
    }
}
