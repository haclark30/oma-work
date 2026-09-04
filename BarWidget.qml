import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "oma-work"

  readonly property string scriptPath: Qt.resolvedUrl("work-mode.sh").toString().replace(/^file:\/\//, "")

  property bool isWorkMode: false
  property string vpnStatus: "disconnected"
  property string notesStatus: "unmounted"
  property string currentTheme: ""
  property string currentBrowser: ""
  property bool busy: false

  readonly property string tooltipMessage: busy
    ? "Work Mode: Launching session..."
    : (isWorkMode
        ? "Work Mode: ACTIVE\n• VPN: " + vpnStatus + "\n• Notes: " + notesStatus + "\n• Theme: " + currentTheme + "\n• Browser: " + currentBrowser + "\n\n(Left-click: deactivate in terminal, Right/Middle-click: VPN re-auth)"
        : "Work Mode: INACTIVE\n(Left-click: activate in terminal, Right/Middle-click: VPN re-auth)")

  function refresh() {
    statusProc.running = false
    statusProc.running = true
  }

  function launchTerminalSession(action) {
    var act = action || "toggle"
    var cmd = "omarchy-launch-floating-terminal-with-presentation \"" + root.scriptPath + "\" " + act
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run(cmd)
    } else {
      Quickshell.execDetached(["bash", "-lc", cmd])
    }

    // Refresh dynamically while terminal session runs
    postActionRefreshTimer.count = 0
    postActionRefreshTimer.restart()
  }

  function toggleWorkMode() {
    launchTerminalSession("toggle")
  }

  function enableWorkMode() {
    launchTerminalSession("on")
  }

  function disableWorkMode() {
    launchTerminalSession("off")
  }

  function launchInteractiveAuth() {
    launchTerminalSession("auth")
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: root.refresh()

  Process {
    id: statusProc
    command: [root.scriptPath, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var clean = text ? text.trim() : "{}"
          var res = JSON.parse(clean)
          root.isWorkMode = (res.active === true)
          root.vpnStatus = res.vpn || "disconnected"
          root.notesStatus = res.notes || "unmounted"
          root.currentTheme = res.theme || ""
          root.currentBrowser = res.browser || ""
        } catch (e) {
          console.warn("oma-work: failed to parse status output:", text, e)
        }
        root.busy = false
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.busy = false
      }
    }
  }

  Timer {
    id: postActionRefreshTimer
    interval: 2000
    repeat: true
    property int count: 0
    onTriggered: {
      root.refresh()
      count++
      if (count >= 10) {
        stop()
        count = 0
      }
    }
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "oma-work"

    function toggle(): void { root.toggleWorkMode() }
    function enable(): void { root.enableWorkMode() }
    function disable(): void { root.disableWorkMode() }
    function mount(): void { root.launchTerminalSession("mount") }
    function unmount(): void { root.launchTerminalSession("unmount") }
    function openAuth(): void { root.launchInteractiveAuth() }
    function refresh(): void { root.refresh() }
    function status(): string {
      return JSON.stringify({
        active: root.isWorkMode,
        vpn: root.vpnStatus,
        notes: root.notesStatus,
        theme: root.currentTheme,
        browser: root.currentBrowser,
        busy: root.busy
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.isWorkMode ? "󰢏" : "󰢓"
    active: root.isWorkMode
    useActiveColor: true
    dimmed: root.busy
    tooltipText: root.tooltipMessage

    onPressed: (button) => {
      if (button === Qt.RightButton || button === Qt.MiddleButton) {
        root.launchInteractiveAuth()
      } else {
        root.toggleWorkMode()
      }
    }
  }
}
