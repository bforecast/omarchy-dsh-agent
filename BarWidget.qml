import QtQuick
import Quickshell
import qs.Ui

// DSH Launcher bar widget.
//
// Left click starts the local DeepSeek Harness if it is not running and
// opens its web UI (delegated to ~/.local/bin/dsh-web, which is installed by
// this repository's install.sh). Right click also opens the UI; middle click
// only ensures the server is up without opening a window (dsh-web --no-open).
BarWidget {
  id: root
  moduleName: "dsh-launcher"

  function openDsh() {
    if (root.bar) root.bar.run("dsh-web")
  }

  function ensureRunning() {
    if (root.bar) root.bar.run("dsh-web --no-open")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰚩"
    tooltipText: "DSH (DeepSeek Harness) — open web UI"
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.ensureRunning()
      else root.openDsh()
    }
  }
}
