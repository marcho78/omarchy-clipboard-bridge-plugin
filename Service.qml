import QtQuick
import Quickshell
import Quickshell.Io

// Owns the clipboard-bridge guest daemon for the lifetime of the plugin.
// Enabling the plugin starts it, disabling the plugin stops it (the shell
// destroys this object, which kills the child process).
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")

  property string binary: ""
  property bool managedBySystemd: false
  property int restartDelayMs: 2000
  property string lastLine: ""

  function log(msg) {
    console.log("[clipboard-bridge] " + msg)
  }

  // 1. Refuse to double-run if the user installed the systemd service.
  Process {
    id: systemdProbe
    command: ["systemctl", "--user", "is-active", "--quiet", "clipboard-bridge.service"]
    running: true
    onExited: function(code) {
      root.managedBySystemd = (code === 0)
      if (root.managedBySystemd) {
        root.log("clipboard-bridge.service is active under systemd; the plugin will not start a second daemon. "
                 + "Run `clipboard-bridge uninstall` to let the plugin manage it.")
        return
      }
      ensureBinary.running = true
    }
  }

  // 2. Locate or fetch the pinned release binary.
  Process {
    id: ensureBinary
    command: ["bash", root.pluginDir + "/bin/ensure-binary.sh"]
    stdout: StdioCollector {
      onStreamFinished: root.binary = text.trim()
    }
    stderr: SplitParser {
      onRead: function(line) { root.log(line) }
    }
    onExited: function(code) {
      if (code !== 0 || root.binary === "") {
        root.log("could not obtain the clipboard-bridge binary (exit " + code + "); retrying in 60s")
        retry.interval = 60000
        retry.restart()
        return
      }
      root.log("using " + root.binary)
      daemon.running = true
    }
  }

  // 3. The daemon itself. It discovers the Mac, pairs with a dialog on the
  //    host, and shows the pairing code as a desktop notification here.
  Process {
    id: daemon
    command: [root.binary, "connect"]
    stderr: SplitParser {
      onRead: function(line) {
        root.lastLine = line
        root.log(line)
      }
    }
    onExited: function(code) {
      if (!root.managedBySystemd) {
        root.log("daemon exited (" + code + "); restarting in " + (root.restartDelayMs / 1000) + "s")
        retry.interval = root.restartDelayMs
        root.restartDelayMs = Math.min(root.restartDelayMs * 2, 30000)
        retry.restart()
      }
    }
    onStarted: root.restartDelayMs = 2000
  }

  Timer {
    id: retry
    repeat: false
    onTriggered: {
      if (root.binary === "") ensureBinary.running = true
      else daemon.running = true
    }
  }

  // `omarchy-shell clipboard-bridge status` / `pair` / `restart`
  IpcHandler {
    target: "clipboard-bridge"

    function status(): string {
      return JSON.stringify({
        binary: root.binary,
        running: daemon.running,
        managedBySystemd: root.managedBySystemd,
        lastLine: root.lastLine
      })
    }

    function pair(): string {
      if (root.binary === "") return "binary not available yet"
      Quickshell.execDetached([root.binary, "pair"])
      return "pairing started; watch for a dialog on the Mac"
    }

    function restart(): string {
      daemon.running = false
      return "restarting"
    }
  }
}
