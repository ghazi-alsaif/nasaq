import QtQuick
import Quickshell
import Quickshell.Io
import "../nasaq.commons"
import "../nasaq.commons" as Nasaq

// NASAQ Settings window. Summon: omarchy-shell shell toggle nasaq.settings '{"page":"plugins"}'
Item {
  id: root
  property var shell: null
  property bool closingFromHost: false
  property string page: "general"
  property string query: ""

  readonly property var pages: [
    { id: "general", icon: "󰒓", file: "GeneralPage.qml", keys: "language arabic english rtl direction font snapshot save restore لغة عربي خط" },
    { id: "appearance", icon: "󰏘", file: "AppearancePage.qml", keys: "theme background wallpaper night light screensaver matrix text size ثيم خلفية" },
    { id: "bars", icon: "󰕮", file: "BarsPage.qml", keys: "bar position top bottom transparent widgets layout شريط" },
    { id: "widgets", icon: "󰖲", file: "WidgetsPage.qml", keys: "desktop widgets prayer island city reminder صلاة ودجات جزيرة" },
    { id: "launcher", icon: "󰍉", file: "LauncherPage.qml", keys: "spotlight menu search apps launcher بحث" },
    { id: "notifications", icon: "󰂚", file: "NotificationsPage.qml", keys: "notifications dnd do not disturb sound history إشعارات" },
    { id: "windows", icon: "󰖯", file: "WindowsPage.qml", keys: "windows transparency blur rounding gaps border shadow dim mission control نوافذ شفافية" },
    { id: "system", icon: "󰍹", file: "SystemPage.qml", keys: "power profile idle lock screensaver stay awake display scale wifi bluetooth sound طاقة شاشة قفل" },
    { id: "shortcuts", icon: "󰌌", file: "ShortcutsPage.qml", keys: "shortcuts keybindings keys اختصارات" },
    { id: "ai", icon: "󰚩", file: "AiPage.qml", keys: "ai agent claude codex ذكاء وكيل" },
    { id: "plugins", icon: "󰏗", file: "PluginsPage.qml", keys: "plugins extensions enable disable إضافات" },
    { id: "advanced", icon: "󰘦", file: "AdvancedPage.qml", keys: "advanced restart reload clone check folder متقدم" }
  ]

  function matches(p) {
    if (!query) return true
    var hay = (Tr.t("page." + p.id) + " " + p.id + " " + p.keys).toLowerCase()
    return hay.indexOf(query) !== -1
  }
  function fileFor(id) {
    for (var i = 0; i < pages.length; i++) if (pages[i].id === id) return pages[i].file
    return pages[0].file
  }

  function open(payloadJson) {
    closingFromHost = false
    try { var p = JSON.parse(String(payloadJson || "{}")).page; if (p) page = p } catch (e) {}
    window.visible = true
    Qt.callLater(function() { keys.forceActiveFocus() })
  }
  function close() { closingFromHost = true; window.visible = false; closingFromHost = false }
  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("nasaq.settings")
    else window.visible = false
  }

  IpcHandler {
    target: "nasaq.settings"
    function page(id: string): void { root.page = id; root.open("{}") }
  }

  FloatingWindow {
    id: window
    visible: false
    title: "NASAQ Settings"
    color: "transparent"
    implicitWidth: 1100
    implicitHeight: 720
    minimumSize: Qt.size(820, 560)
    onVisibleChanged: if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function") root.shell.hide("nasaq.settings")

    Rectangle {
      id: bg
      anchors.fill: parent
      color: Theme.glassSolid
      LayoutMirroring.enabled: Tr.rtl
      LayoutMirroring.childrenInherit: true

      Item {
        id: keys
        focus: true
        Keys.onEscapePressed: root.requestClose()
        Keys.onPressed: function(e) {
          if (e.modifiers & Qt.ControlModifier && e.key === Qt.Key_F) { search.forceInput(); e.accepted = true }
        }
      }

      // ── Sidebar ──
      Rectangle {
        id: side
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 250
        color: Qt.alpha(Theme.text, 0.04)
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.divider; opacity: 0.6 }

        Column {
          x: 14; y: 18
          width: parent.width - 28
          spacing: 3
          Row {
            spacing: 10
            leftPadding: 6
            Rectangle {
              width: 30; height: 30; radius: 9; color: Theme.accent
              Text { anchors.centerIn: parent; text: "ن"; color: Theme.onAccent; font.family: "Noto Kufi Arabic"; font.pixelSize: 16; font.weight: Font.Bold }
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              NLabel { text: "NASAQ"; font.pixelSize: 15; font.weight: Font.Bold }
              NSub { text: Tr.t("settings.title") }
            }
          }
          Item { width: 1; height: 12 }
          NTextField {
            id: search
            width: parent.width
            placeholder: Tr.t("settings.search")
            onEdited: function(t) { root.query = t.toLowerCase().trim() }
            function forceInput() { children[0].forceActiveFocus() }
          }
          Item { width: 1; height: 8 }
          Repeater {
            model: root.pages
            delegate: Rectangle {
              required property var modelData
              visible: root.matches(modelData)
              width: parent.width
              height: visible ? 34 : 0
              radius: 8
              color: root.page === modelData.id ? Qt.alpha(Theme.text, 0.12) : (navMouse.containsMouse ? Theme.hover : "transparent")
              Behavior on color { Nasaq.NColour { duration: Nasaq.Motion.micro } }
              Row {
                anchors.left: parent.left; anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Rectangle {
                  width: 22; height: 22; radius: 6
                  color: root.page === modelData.id ? Theme.accent : Qt.alpha(Theme.text, 0.12)
                  NGlyph { anchors.centerIn: parent; text: modelData.icon; font.pixelSize: 13; color: root.page === modelData.id ? Theme.onAccent : "white" }
                }
                NLabel { anchors.verticalCenter: parent.verticalCenter; text: Tr.t("page." + modelData.id); font.weight: root.page === modelData.id ? Font.DemiBold : Font.Normal }
              }
              MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.page = modelData.id; keys.forceActiveFocus() } }
            }
          }
        }

        Column {
          anchors.bottom: parent.bottom; anchors.bottomMargin: 14
          x: 14; width: parent.width - 28
          spacing: 6
          NButton { width: parent.width; icon: "󰆓"; text: Tr.t("common.save"); onClicked: Sys.term("nasaq-settings save --ask") }
          NButton { width: parent.width; icon: "󰋚"; text: Tr.t("common.restore"); onClicked: Sys.term("nasaq-settings restore") }
        }
      }

      // ── Page ──
      // Two layers so the two motions never fight over one property: the box
      // fades out and slips left when the page changes, then (on a short
      // timer) the loader swaps the page and fades it in from the right.
      Item {
        id: pageBox
        anchors.left: side.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        transform: Translate { id: boxShift }
        Connections {
          target: root
          function onPageChanged() {
            if (!Nasaq.Motion.enabled || pageLoader.status !== Loader.Ready || !window.visible) { swap.stop(); pageLoader.shownPage = root.page; return }
            pageOut.restart(); swap.restart()
          }
        }
        Timer { id: swap; interval: Nasaq.Motion.fast + 10; onTriggered: pageLoader.shownPage = root.page }
        ParallelAnimation {
          id: pageOut
          Nasaq.NFade { target: pageBox; property: "opacity"; to: 0 }
          Nasaq.NAnim { target: boxShift; property: "x"; to: -8; kind: "fast" }
        }
        Loader {
          id: pageLoader
          anchors.fill: parent
          active: window.visible
          // Starts on the requested page, then only the swap timer moves it (a
          // live binding would load the new page at once, under the fade-out).
          property string shownPage: root.page
          Component.onCompleted: shownPage = String(root.page)
          source: "pages/" + root.fileFor(shownPage)
          transform: Translate { id: pageShift }
          onLoaded: {
            pageOut.stop(); pageBox.opacity = 1; boxShift.x = 0
            if (pageLoader.shownPage !== root.page) { swap.stop(); pageLoader.shownPage = root.page; return }
            pageLoader.opacity = 0; pageShift.x = 12; pageIn.restart()
          }
          ParallelAnimation {
            id: pageIn
            Nasaq.NFade { target: pageLoader; property: "opacity"; to: 1 }
            Nasaq.NAnim { target: pageShift; property: "x"; to: 0; kind: "fast" }
          }
        }
      }
    }
  }
}
