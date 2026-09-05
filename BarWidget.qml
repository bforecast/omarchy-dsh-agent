import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// DSH Launcher bar widget (marketplace-safe).
//
// Works after a plain `omarchy plugin add`: the DSH logo is loaded from this
// plugin's own files/icons/... via Qt.resolvedUrl (theme copy is only a
// fallback), and the balance helper is invoked from the plugin's files/ too.
// Clicking runs ~/.local/bin/dsh-web when the companion install.sh has run;
// otherwise it shows a notification telling the user to run install.sh.
BarWidget {
  id: root
  moduleName: "dsh-launcher"

  readonly property string home: Quickshell.env("HOME")
  property string balance: ""
  property bool fullInstall: false

  function localPath(relativeUrl) {
    var u = Qt.resolvedUrl(relativeUrl).toString()
    return u.indexOf("file://") === 0 ? u.slice(7) : u
  }

  readonly property string pluginIcon: localPath("files/icons/hicolor/64x64/apps/dsh.png")
  readonly property string themeIcon: root.home + "/.local/share/icons/hicolor/64x64/apps/dsh.png"
  readonly property string pluginBalance: localPath("files/dsh-balance")
  readonly property string binBalance: root.home + "/.local/bin/dsh-balance"

  function openDsh() {
    if (!root.bar) return
    if (root.fullInstall) {
      root.bar.run("dsh-web")
    } else {
      root.bar.run('omarchy-notification-send --urgency normal "DSH Launcher" "DeepSeek Harness is not fully installed. Run install.sh of the omarchy-dsh-agent repository to enable launching."')
    }
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
      if (buttonCode === Qt.LeftButton) root.openDsh()
    }
  }

  Process {
    id: balProc
    command: [root.pluginBalance]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.balance = text.trim()
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        // fall back to the install.sh-placed helper, then mark unavailable
        if (command[0] !== root.binBalance) {
          command = [root.binBalance]
          running = true
        } else {
          root.balance = ""
        }
      }
    }
  }

  Process {
    id: probe
    command: ["sh", "-c", "test -x \"" + root.home + "/.local/bin/dsh-web\" && echo ready || echo missing"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.fullInstall = text.trim() === "ready"
    }
  }

  Timer {
    interval: 600000          // 10 minutes
    running: true
    repeat: true
    onTriggered: root.refreshBalance()
  }
}
