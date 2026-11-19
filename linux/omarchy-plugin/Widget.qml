import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Kalam's place in the bar. The icon mirrors what Kalam is doing (it turns
// the bar's active colour while recording), a click opens the window, and
// a right-click starts or stops dictating. The recording itself happens in
// the kalam service, never in the shell.
BarWidget {
  id: root
  moduleName: "kalam.dictation"

  // "idle", "recording", "transcribing", or "stopped" when Kalam isn't
  // running. Kalam writes it to a file in the runtime directory.
  property string phase: "stopped"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function read(text) {
    const value = String(text || "").trim()
    // Only the words Kalam writes; anything else is treated as not running.
    return ["idle", "recording", "transcribing"].indexOf(value) >= 0 ? value : "stopped"
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  FileView {
    id: stateFile
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/kalam.state"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.phase = root.read(text())
    onLoadFailed: root.phase = "stopped"
  }

  // The watch can't see a file that didn't exist when the shell started, so
  // look again now and then; the file is a few bytes in memory.
  Timer {
    interval: 3000
    repeat: true
    running: true
    onTriggered: stateFile.reload()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.phase === "transcribing" ? "󰇘" : "󰴒"
    active: root.phase === "recording"
    dimmed: root.phase === "stopped"
    tooltipText: root.phase === "recording" ? strings.t("tooltip.recording")
               : root.phase === "transcribing" ? strings.t("tooltip.transcribing")
               : root.phase === "stopped" ? strings.t("tooltip.stopped")
               : strings.t("tooltip.idle")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) Util.execArgv(["kalam", "toggle"])
      else if (buttonCode === Qt.MiddleButton) Util.execArgv(["kalam", "cancel"])
      else Util.execArgv(["kalam", "open"])
    }
  }
}
