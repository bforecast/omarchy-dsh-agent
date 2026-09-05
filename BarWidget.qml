import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// DSH Launcher bar widget.
//
// Shows the DeepSeek account balance reported by the dsh-balance helper (installed
// by install.sh) next to the DSH icon, refreshing every 10 minutes. Left click
// starts the local DeepSeek Harness if needed and opens its web UI. When the
// balance is unavailable the widget degrades to the plain launcher icon.
BarWidget {
  id: root
  moduleName: "dsh-launcher"

  readonly property string icon: "󰚩"   // Nerd Font robot glyph for the launcher
  property string balance: ""

  readonly property string labelText: root.balance === "" ? "󰚩" : "󰚩  " + root.balance

  function openDsh() {
    if (root.bar) root.bar.run("dsh-web")
  }

  function refreshBalance() {
    if (!balProc.running) balProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: balProc
    command: [Quickshell.env("HOME") + "/.local/bin/dsh-balance"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.balance = text.trim()
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.balance = ""
    }
  }

  Timer {
    interval: 600000          // 10 minutes
    running: true
    repeat: true
    onTriggered: root.refreshBalance()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? root.icon : root.labelText
    tooltipText: "DSH (DeepSeek Harness) — balance: " + (root.balance === "" ? "unavailable" : root.balance)
    labelVisible: !root.vertical
    hasVisualContent: true
    horizontalMargin: 8.75
    onPressed: function() {
      root.openDsh()
    }
  }
}
