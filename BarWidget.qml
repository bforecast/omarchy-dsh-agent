import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// DSH Launcher bar widget (marketplace-safe).
//
// Works after a plain `omarchy plugin add`: the DSH logo and the balance helper
// are both loaded from this plugin's own files/ via Qt.resolvedUrl - nothing is
// taken from earlier/leftover installs. A left click re-checks on the spot
// whether ~/.local/bin/dsh-web exists: if yes it launches DSH, otherwise it
// shows a notification telling the user to run install.sh first.
BarWidget {
  id: root
  moduleName: "dsh-launcher"

  readonly property string home: Quickshell.env("HOME")
  property string balance: ""

  function localPath(relativeUrl) {
    var u = Qt.resolvedUrl(relativeUrl).toString()
    return u.indexOf("file://") === 0 ? u.slice(7) : u
  }

  readonly property string pluginIcon: localPath("files/icons/hicolor/64x64/apps/dsh.png")
  readonly property string themeIcon: root.home + "/.local/share/icons/hicolor/64x64/apps/dsh.png"

  function launchDsh() {
    // Re-probe on every click so installing install.sh later takes effect
    // without a shell/plugin reload.
    launchProbe.command = ["test", "-x", root.home + "/.local/bin/dsh-web"]
    launchProbe.running = true
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
          source: root.pluginIcon
          sourceSize.width: 20
          sourceSize.height: 20
          fillMode: Image.PreserveAspectFit
          onStatusChanged: {
            if (Image.Error === status && source !== root.themeIcon) {
              source = root.themeIcon
            }
          }
        }
      }
    }
    tooltipText: "DSH (DeepSeek Harness) — balance: " + (root.balance === "" ? "unavailable" : root.balance)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.launchDsh()
    }
  }

  Process {
    id: launchProbe
    running: false
    onExited: function(exitCode) {
      if (!root.bar) return
      if (exitCode === 0) {
        root.bar.run("dsh-web")
      } else {
        root.bar.run('omarchy-notification-send --urgency normal "DSH Launcher" "DeepSeek Harness is not fully installed. Run install.sh of the omarchy-dsh-agent repository to enable launching."')
      }
    }
  }

  Process {
    id: balProc
    command: [localPath("files/dsh-balance")]
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
