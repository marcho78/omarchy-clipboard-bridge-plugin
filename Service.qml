import QtQuick
import Quickshell
import Quickshell.Io

// Runs the clipboard-bridge guest daemon for the lifetime of the plugin.
// The binary comes from the `clipboard-bridge` package (AUR); this plugin
// never downloads, verifies or installs anything. Enabling the plugin starts
// the daemon, disabling it stops it.
//
// Process identity: the daemon we start is recorded by pid and kernel start
// time in $XDG_RUNTIME_DIR. After a shell restart the previous daemon may
// still be running as an orphan; it is ended only if that exact pid still
// has the recorded start time and comm, never by matching a command line.
//
// Output: the daemon's stderr is read in chunks against a byte budget. A
// flood ends the daemon and it restarts with backoff.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null

  readonly property string binary: "/usr/bin/clipboard-bridge"
  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + Quickshell.env("UID")))
  readonly property string recordPath: runtimeDir + "/clipboard-bridge-plugin.json"
  readonly property int maxLine: 512          // longest line kept or logged
  readonly property int budgetPerMinute: 65536 // stderr bytes per minute before the daemon is restarted

  property bool installed: false
  property bool managedBySystemd: false
  property int restartDelayMs: 2000
  property string lastLine: ""
  property string lineBuf: ""
  property int bytesThisMinute: 0
  property int droppedLines: 0

  function log(msg) { console.log("[clipboard-bridge] " + String(msg).slice(0, root.maxLine)) }

  // ---- 1. Is the package installed? ----
  Process {
    id: installedProbe
    command: ["/usr/bin/test", "-x", root.binary]
    running: true
    onExited: function(code) {
      root.installed = (code === 0)
      if (!root.installed) {
        root.log("clipboard-bridge is not installed; install the clipboard-bridge package (AUR) and re-enable the plugin. Checking again in 60s.")
        retry.interval = 60000
        retry.restart()
        return
      }
      systemdProbe.running = true
    }
  }

  // ---- 2. Refuse to double-run if the user enabled the systemd unit. ----
  Process {
    id: systemdProbe
    command: ["/usr/bin/systemctl", "--user", "is-active", "--quiet", "clipboard-bridge.service"]
    onExited: function(code) {
      root.managedBySystemd = (code === 0)
      if (root.managedBySystemd) {
        root.log("clipboard-bridge.service is active under systemd; the plugin will not start a second daemon.")
        return
      }
      recordView.reload()
    }
  }

  // ---- 3. End the daemon a previous shell instance started, by identity. ----
  FileView {
    id: recordView
    path: root.recordPath
    atomicWrites: true
    printErrors: false
    onLoaded: root.checkPreviousDaemon(text())
    onLoadFailed: daemon.running = true
  }

  function parseStat(text) {
    // /proc/<pid>/stat: "pid (comm) state ppid ... starttime(22) ..."; comm may contain spaces.
    var s = String(text)
    var close = s.lastIndexOf(")")
    var open = s.indexOf("(")
    if (open < 0 || close < 0) return null
    var comm = s.substring(open + 1, close)
    var rest = s.substring(close + 2).trim().split(/\s+/)
    if (rest.length < 20) return null
    return { comm: comm, starttime: rest[19] }
  }

  property var previous: null
  function checkPreviousDaemon(text) {
    try {
      var rec = JSON.parse(String(text))
      if (rec && Number(rec.pid) > 1 && rec.starttime) {
        root.previous = { pid: Math.floor(Number(rec.pid)), starttime: String(rec.starttime) }
        statView.path = "/proc/" + root.previous.pid + "/stat"
        statView.reload()
        return
      }
    } catch (e) {}
    daemon.running = true
  }

  FileView {
    id: statView
    printErrors: false
    onLoaded: {
      var st = root.parseStat(text())
      var p = root.previous
      root.previous = null
      if (st && p && st.starttime === p.starttime && st.comm === "clipboard-bridg") {
        root.log("ending the daemon left by a previous shell instance (pid " + p.pid + ")")
        Quickshell.execDetached(["/usr/bin/kill", "-TERM", String(p.pid)])
        retry.interval = 1500
        retry.restart()
        return
      }
      daemon.running = true
    }
    onLoadFailed: { root.previous = null; daemon.running = true }
  }

  // ---- 4. The daemon itself. ----
  Process {
    id: daemon
    command: [root.binary, "connect"]
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(chunk) { root.consume(String(chunk)) }
    }
    onStarted: {
      root.restartDelayMs = 2000
      root.bytesThisMinute = 0
      root.lineBuf = ""
      ownStat.path = "/proc/" + daemon.processId + "/stat"
      ownStat.reload()
    }
    onExited: function(code) {
      if (!root.managedBySystemd && root.installed) {
        root.log("daemon exited (" + code + "); restarting in " + (root.restartDelayMs / 1000) + "s")
        retry.interval = root.restartDelayMs
        root.restartDelayMs = Math.min(root.restartDelayMs * 2, 30000)
        retry.restart()
      }
    }
  }

  // Record our own daemon's identity so the next shell instance can end it.
  FileView {
    id: ownStat
    printErrors: false
    onLoaded: {
      var st = root.parseStat(text())
      if (st && daemon.running) recordView.setText(JSON.stringify({ pid: daemon.processId, starttime: st.starttime }) + "\n")
    }
  }

  function consume(chunk) {
    root.bytesThisMinute += chunk.length
    if (root.bytesThisMinute > root.budgetPerMinute) {
      if (daemon.running) {
        root.log("daemon stderr exceeded " + root.budgetPerMinute + " bytes in a minute; restarting it")
        daemon.running = false
      }
      return
    }
    var buf = root.lineBuf + chunk
    var lines = buf.split("\n")
    root.lineBuf = lines.pop()
    if (root.lineBuf.length > root.maxLine) { root.lineBuf = ""; root.droppedLines++ }
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line.length === 0) continue
      if (line.length > root.maxLine) { root.droppedLines++; continue }
      root.lastLine = line
      root.log(line)
    }
  }

  Timer { interval: 60000; repeat: true; running: true; onTriggered: root.bytesThisMinute = 0 }

  Timer {
    id: retry
    repeat: false
    onTriggered: {
      if (!root.installed) installedProbe.running = true
      else daemon.running = true
    }
  }

  // `omarchy-shell clipboard-bridge status` / `pair` / `restart`
  IpcHandler {
    target: "clipboard-bridge"

    function status(): string {
      return JSON.stringify({
        installed: root.installed,
        binary: root.binary,
        running: daemon.running,
        pid: daemon.running ? daemon.processId : 0,
        managedBySystemd: root.managedBySystemd,
        droppedLines: root.droppedLines,
        lastLine: root.lastLine
      })
    }

    function pair(): string {
      if (!root.installed) return "clipboard-bridge is not installed"
      Quickshell.execDetached([root.binary, "pair"])
      return "pairing started; watch for a dialog on the Mac"
    }

    function restart(): string {
      daemon.running = false
      return "restarting"
    }
  }
}
