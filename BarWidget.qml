import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// DSH Launcher bar widget.
//
// Standard single-button bar widget: the official DeepSeek Harness icon (from
// the hicolor theme, installed by install.sh) fills the slot. Left click starts
// the local DeepSeek Harness if needed and opens its web UI. The DeepSeek
// account balance (dsh-balance helper) is refreshed every 10 minutes and shown
// in the tooltip.
BarWidget {
  id: root
  moduleName: "dsh-launcher"

  readonly property string home: Quickshell.env("HOME")
  property string balance: ""

  readonly property string iconUrl: root.home + "/.local/share/icons/hicolor/64x64/apps/dsh.png"

  function openDsh() {
    if (root.bar) root.bar.run("dsh-web")
  }

  function refreshBalance() {
    if (!balProc.running) balProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        Image {
          anchors.centerIn: parent
          source: root.iconUrl
          sourceSize.width: 20
          sourceSize.height: 20
          fillMode: Image.PreserveAspectFit
        }
      }
    }
    tooltipText: "DSH (DeepSeek Harness) — balance: " + (root.balance === "" ? "unavailable" : root.balance)
    onPressed: function() {
      root.openDsh()
    }
  }

  Process {
    id: balProc
    command: [root.home + "/.local/bin/dsh-balance"]
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
}
