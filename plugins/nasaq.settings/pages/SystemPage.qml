import QtQuick
import Quickshell
import Quickshell.Io
import "../../nasaq.commons"
import "../../nasaq.commons" as Nasaq
import ".."

NPage {
  id: page
  title: Tr.t("page.system")
  subtitle: "Power, idle, lock and display."

  Cmd { id: autoB; script: "systemctl --user is-active nasaq-auto-brightness; nasaq-auto-brightness status" }
  Cmd { id: profile; script: "powerprofilesctl get 2>/dev/null" }
  // (scale shown per display below)
  Cmd { id: scale; script: "hyprctl monitors -j | python3 -c 'import json,sys; print(\", \".join(m[\"name\"]+\" \"+str(m[\"width\"])+\"×\"+str(m[\"height\"])+\" @\"+str(round(m[\"scale\"],2)) for m in json.load(sys.stdin)))'" }
  property var idle: ({})
  property bool awake: false
  Nasaq.GameMode { id: game }
  FileView {
    path: Sys.home + "/.config/omarchy/shell.json"; watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { page.idle = JSON.parse(text()).idle || {} } catch (e) {} }
  }
  FileView {
    path: Sys.home + "/.local/state/omarchy/indicators/stay-awake"; printErrors: false; watchChanges: true
    onFileChanged: reload()
    onLoaded: page.awake = true
    onLoadFailed: page.awake = false
  }
  function setIdle(key, secs) { Sys.jsonSet(Sys.home + "/.config/omarchy/shell.json", "idle." + key, String(Math.round(secs))) }
  function fmt(s) { s = Math.round(s); if (s < 60) return s + " s"; var m = s / 60; return (m % 1 ? m.toFixed(1) : m) + " min" }

  NSection {
    title: "POWER"
    NRow {
      title: "Power profile"
      subtitle: "Power saver = Low Power Mode (no blur or animations)."
      NDropdown {
        model: [{ value: "performance", label: "Performance" }, { value: "balanced", label: "Balanced" }, { value: "power-saver", label: "Power saver" }]
        value: profile.out
        onActivated: function(v) { Sys.run("omarchy powerprofiles set autodetect " + v); profile.out = v }
      }
    }
    NRow {
      title: "Game mode"
      subtitle: "Animations, blur and shadows off, notifications quiet, hot corners off. SUPER + ALT + G"
      NSwitch { checked: game.active; onToggled: function(c) { Sys.ipc("nasaq.gamemode", c ? "on" : "off") } }
    }
  }

  NSection {
    title: "IDLE AND LOCK"
    NRow {
      title: "Stay awake"
      subtitle: "Pause the screensaver and auto-lock. SUPER + CTRL + I"
      NSwitch { checked: page.awake; onToggled: function(c) { Sys.run("omarchy-toggle-idle " + (c ? "stay-awake" : "allow-idle")); page.awake = c } }
    }
    NRow {
      title: "Stay awake while media plays"
      subtitle: "While a video or music plays, or a window is fullscreen."
      NSwitch { checked: { void Settings.revision; return Settings.get("power.awakeForMedia", true) }
        onToggled: function(c) { Settings.set("power.awakeForMedia", c) } }
    }
    NRow {
      title: "Screensaver after"
      NSlider {
        width: 220; from: 30; to: 1800; stepSize: 30
        value: Number(page.idle.screensaver || 150)
        valueText: page.fmt(value)
        onMoved: function(v) { var c = Object.assign({}, page.idle); c.screensaver = v; page.idle = c }
        onCommitted: function(v) { page.setIdle("screensaver", v) }
      }
    }
    NRow {
      title: "Lock after"
      NSlider {
        width: 220; from: 60; to: 3600; stepSize: 60
        value: Number(page.idle.lock || 300)
        valueText: page.fmt(value)
        onMoved: function(v) { var c = Object.assign({}, page.idle); c.lock = v; page.idle = c }
        onCommitted: function(v) { page.setIdle("lock", v) }
      }
    }
    NRow { title: "Lock now"; subtitle: "SUPER + CTRL + L"; NButton { text: "Lock"; onClicked: Sys.run("omarchy-system-lock") } }
  }

  Cmd { id: displays; script: "nasaq-display list"; onDone: function(o) { try { page.mons = JSON.parse(o) } catch (e) { page.mons = [] } } }
  property var mons: []
  property var pick: ({})        // output -> {mode, scale, transform}
  property int countdown: 0
  Timer { id: tick; interval: 1000; repeat: true; running: page.countdown > 0
    onTriggered: { page.countdown--; if (page.countdown <= 0) displays.refresh() } }
  function sel(out, key, fallback) { return page.pick[out] && page.pick[out][key] !== undefined ? page.pick[out][key] : fallback }
  function choose(out, key, v) { var p = Object.assign({}, page.pick); p[out] = Object.assign({}, p[out] || {}); p[out][key] = v; page.pick = p }

  NSection {
    title: "DISPLAYS"
    note: page.countdown > 0 ? "" : "Apply shows the change right away and goes back automatically after 15 seconds unless you keep it."
    NRow {
      visible: page.countdown > 0
      title: "Keep these display settings?"
      subtitle: "Going back in " + page.countdown + " s"
      Row { spacing: 8
        NButton { text: "Keep"; primary: true; onClicked: { Sys.run("nasaq-display keep"); page.countdown = 0; displays.refresh() } }
        NButton { text: "Revert"; onClicked: { Sys.run("nasaq-display revert"); page.countdown = 0; rescanLater.restart() } } }
    }
    Repeater {
      model: page.mons
      delegate: Column {
        required property var modelData
        width: parent.width
        NRow {
          title: modelData.name + (modelData.overridden ? "  ·  set by NASAQ" : "")
          subtitle: modelData.description + "  ·  now " + modelData.mode + " @ " + modelData.scale
          NButton { visible: modelData.overridden; text: "Use monitors.lua"; onClicked: { Sys.run("nasaq-display reset " + modelData.name); rescanLater.restart() } }
        }
        NRow {
          title: "Resolution"
          NDropdown { width: 220; model: modelData.modes; value: page.sel(modelData.name, "mode", modelData.mode)
            onActivated: function(v) { page.choose(modelData.name, "mode", v) } }
        }
        NRow {
          title: "Scale"
          NDropdown { width: 220
            model: [1, 1.25, 1.333333, 1.5, 1.6, 1.666667, 1.75, 2, 2.5, 3].map(function(x) { return { value: x, label: (Math.round(x * 100)) + "%" } })
            value: page.sel(modelData.name, "scale", modelData.scale)
            onActivated: function(v) { page.choose(modelData.name, "scale", v) } }
        }
        NRow {
          title: "Rotation"
          NDropdown { width: 220
            model: [{ value: 0, label: "Normal" }, { value: 1, label: "90°" }, { value: 2, label: "180°" }, { value: 3, label: "270°" }]
            value: page.sel(modelData.name, "transform", modelData.transform)
            onActivated: function(v) { page.choose(modelData.name, "transform", v) } }
        }
        NRow {
          title: ""
          NButton { text: "Apply"; primary: true; enabled: page.countdown === 0
            onClicked: {
              Sys.run("nasaq-display apply " + modelData.name + " " + page.sel(modelData.name, "mode", modelData.mode) + " " +
                      page.sel(modelData.name, "scale", modelData.scale) + " " + page.sel(modelData.name, "transform", modelData.transform))
              page.countdown = 15
            } }
        }
      }
    }
    NRow {
      title: "Quick scale"
      subtitle: "SUPER + / and SUPER + ALT + /"
      Row { spacing: 8
        NButton { text: "Smaller"; onClicked: { Sys.run("omarchy-hyprland-monitor-scaling down"); rescanLater.restart() } }
        NButton { text: "Larger"; onClicked: { Sys.run("omarchy-hyprland-monitor-scaling up"); rescanLater.restart() } } }
    }
    NRow { title: "Arrange several displays"; subtitle: "Graphical editor (nwg-displays)"; NButton { text: "Open"; onClicked: Sys.run("nwg-displays") } }
    NRow {
      visible: autoB.out.indexOf("sensor") !== -1
      title: "Auto brightness"
      subtitle: "Follows the ambient light sensor."
      NSwitch { checked: autoB.out.indexOf("active") === 0; onToggled: function(c) { Sys.run("nasaq-auto-brightness " + (c ? "on" : "off")); autoB.out = (c ? "active" : "inactive") + "\nsensor" } }
    }
  }
  Timer { id: rescanLater; interval: 1500; onTriggered: displays.refresh() }

  Cmd {
    id: devices
    script: "python3 - <<'PY'\nimport json,subprocess,glob,os\nout={'usb':[],'drives':[],'cameras':[]}\nfor l in subprocess.run(['lsusb'],capture_output=True,text=True).stdout.splitlines():\n  n=l.split(' ',6)[-1].strip() if len(l.split(' ',6))>6 else ''\n  if n and 'root hub' not in n: out['usb'].append(n)\ntry:\n  d=json.loads(subprocess.run(['lsblk','-J','-o','NAME,LABEL,SIZE,MOUNTPOINT,HOTPLUG,RM,TYPE,MODEL'],capture_output=True,text=True).stdout)\n  for b in d['blockdevices']:\n    if b.get('hotplug') or b.get('rm'):\n      for p in (b.get('children') or [b]):\n        out['drives'].append({'dev':'/dev/'+p['name'],'label':p.get('label') or b.get('model') or p['name'],'size':p.get('size'),'mount':p.get('mountpoint')})\nexcept Exception: pass\nfor v in sorted(glob.glob('/sys/class/video4linux/video*')):\n  try: out['cameras'].append(open(v+'/name').read().strip())\n  except Exception: pass\nout['cameras']=sorted(set(out['cameras']))\nprint(json.dumps(out))\nPY"
    onDone: function(o) { try { page.dev = JSON.parse(o) } catch (e) {} }
  }
  property var dev: ({ usb: [], drives: [], cameras: [] })

  NSection {
    title: "DEVICES"
    note: "Removable drives mount automatically (udiskie). Eject before unplugging."
    NRow { title: "Refresh"; NButton { text: "Rescan"; onClicked: devices.refresh() } }
    Repeater {
      model: page.dev.drives
      delegate: NRow {
        required property var modelData
        title: "󰋊  " + modelData.label + "  ·  " + modelData.size
        subtitle: modelData.mount ? "Mounted at " + modelData.mount : modelData.dev + " · not mounted"
        Row { spacing: 8
          NButton { visible: !!modelData.mount; text: "Open"; onClicked: Sys.run("omarchy-launch-nautilus " + JSON.stringify(modelData.mount)) }
          NButton { text: "Eject"; onClicked: { Sys.run("udisksctl unmount -b " + modelData.dev + " ; udisksctl power-off -b " + modelData.dev.replace(/[0-9]+$/, "") + " && notify-send -a NASAQ 'Safe to unplug' " + JSON.stringify(modelData.label)); ejectLater.restart() } } }
      }
    }
    NRow { title: "USB devices"; subtitle: page.dev.usb.join("  ·  ") || "None" }
    NRow { title: "Cameras"; subtitle: page.dev.cameras.join("  ·  ") || "None" }
  }
  Timer { id: ejectLater; interval: 2500; onTriggered: devices.refresh() }

  NSection {
    title: "CONNECTIVITY AND SOUND"
    NRow { title: "Wi-Fi, Bluetooth, sound, brightness"; subtitle: "SUPER + ALT + C"; NButton { text: "Quick Settings"; onClicked: Sys.ipc("nasaq.control-center", "open") } }
  }

  Timer { id: rescan; interval: 900; onTriggered: scale.refresh() }
}
