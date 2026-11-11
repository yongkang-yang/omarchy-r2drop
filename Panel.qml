import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "ykyan.r2drop"
  ipcTarget: "ykyan.r2drop"
  manageIpc: false

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  readonly property string bundledBin: String(Qt.resolvedUrl("bin/r2drop")).replace(/^file:\/\//, "")
  property string pathBin: ""
  readonly property string r2dropBin: pathBin !== "" ? pathBin : bundledBin

  readonly property Item panelFlick: panel.loadedContent ? panel.loadedContent.panelFlick : null
  readonly property Item recentColumn: panel.loadedContent ? panel.loadedContent.recentColumn : null

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var recentItems: []
  property string focusSection: "recent"
  property int selectedIndex: 0
  property int actionIndex: 0
  property bool cursorActive: false
  property int nowTick: 0
  property string _whichOut: ""
  property string _recentOut: ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: {
    resolveBinary()
    refresh()
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      focusSection = recentItems.length > 0 ? "recent" : "actions"
      selectedIndex = 0
      actionIndex = 0
      nowTick += 1
      if (panelFlick) panelFlick.contentY = 0
      refresh()
      Qt.callLater(function() {
        if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
      })
    }
  }

  onSelectedIndexChanged: scrollCursorIntoView()

  function resolveBinary() {
    if (whichProcess.running) return
    root._whichOut = ""
    whichProcess.command = ["bash", "-lc", "command -v r2drop"]
    whichProcess.running = true
  }

  function refresh() {
    if (pathBin === "" && !whichProcess.running) resolveBinary()
    if (recentProcess.running) return
    root._recentOut = ""
    recentProcess.command = [root.r2dropBin, "recent", "--json", "12"]
    recentProcess.running = true
  }

  function boundedString(value, maxLen) {
    var s = String(value === undefined || value === null ? "" : value)
    return s.length > maxLen ? s.slice(0, maxLen) : s
  }

  function applyRecentJson(raw) {
    var text = String(raw || "").trim()
    if (text === "") {
      root.recentItems = []
      root.ensureCursor()
      return
    }
    try {
      var parsed = JSON.parse(text)
      if (!Array.isArray(parsed)) {
        root.recentItems = []
        root.ensureCursor()
        return
      }
      var items = []
      var limit = Math.min(12, parsed.length)
      for (var i = 0; i < limit; i++) {
        var entry = parsed[i]
        if (!entry || typeof entry !== "object") continue
        var key = boundedString(entry.key, 256)
        var url = boundedString(entry.url, 1024)
        if (key === "" || url === "") continue
        items.push({
          key: key,
          url: url,
          name: boundedString(entry.name || key, 200),
          time: boundedString(entry.time, 64),
          thumb: boundedString(entry.thumb, 1024)
        })
      }
      root.recentItems = items
    } catch (e) {
      root.recentItems = []
    }
    root.ensureCursor()
  }

  function ensureCursor() {
    if (root.recentItems.length === 0) {
      root.focusSection = "actions"
      root.selectedIndex = 0
    } else {
      if (root.selectedIndex >= root.recentItems.length) {
        root.selectedIndex = Math.max(0, root.recentItems.length - 1)
      }
      if (root.selectedIndex < 0) root.selectedIndex = 0
    }
    if (root.actionIndex < 0 || root.actionIndex > 2) root.actionIndex = 0
  }

  function moveCursor(dx, dy) {
    if (!root.cursorActive) {
      root.cursorActive = true
      if (dx !== 0 || root.recentItems.length === 0) {
        root.focusSection = "actions"
        root.actionIndex = 0
      } else {
        root.focusSection = "recent"
        root.selectedIndex = dy < 0 ? root.recentItems.length - 1 : 0
        root.scrollCursorIntoView()
      }
      return
    }

    root.ensureCursor()

    if (dx !== 0) {
      root.focusSection = "actions"
      root.actionIndex = (root.actionIndex + (dx > 0 ? 1 : -1) + 3) % 3
      if (panelFlick) panelFlick.contentY = 0
      return
    }

    if (dy !== 0) {
      if (root.focusSection === "actions") {
        if (dy > 0 && root.recentItems.length > 0) {
          root.focusSection = "recent"
          root.selectedIndex = 0
          root.scrollCursorIntoView()
        }
        return
      }
      if (root.focusSection === "recent") {
        if (dy < 0 && root.selectedIndex === 0) {
          root.focusSection = "actions"
          if (panelFlick) panelFlick.contentY = 0
          return
        }
        if (root.recentItems.length > 0) {
          root.selectedIndex = Math.max(0, Math.min(root.recentItems.length - 1, root.selectedIndex + dy))
          root.scrollCursorIntoView()
        }
      }
    }
  }

  function activateCursor() {
    root.ensureCursor()
    if (root.focusSection === "actions") {
      if (root.actionIndex === 0) root.runCapture()
      else if (root.actionIndex === 1) root.runClipboard()
      else root.runPick()
      return
    }
    if (root.focusSection === "recent" && root.recentItems.length > 0) {
      var item = root.recentItems[Math.max(0, Math.min(root.selectedIndex, root.recentItems.length - 1))]
      if (item && item.key) root.copyKey(item.key)
    }
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item || !panelFlick) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "recent" && recentColumn && selectedIndex >= 0 && selectedIndex < recentColumn.children.length) {
      scrollItemIntoView(recentColumn.children[selectedIndex])
    }
  }

  function runDetached(args) {
    Quickshell.execDetached([root.r2dropBin].concat(args))
  }

  function runCapture() {
    root.close()
    captureDelayTimer.restart()
  }

  function runClipboard() {
    root.close()
    root.runDetached(["clipboard"])
  }

  function runPick() {
    root.close()
    root.runDetached(["pick"])
  }

  function copyKey(key) {
    var k = String(key || "")
    if (k === "") return
    root.close()
    root.runDetached(["copy", k])
  }

  function uploadFiles(paths) {
    if (!paths || paths.length === 0) return
    root.close()
    root.runDetached(["upload"].concat(paths))
  }

  function decodeFileUri(uriStr) {
    var s = String(uriStr || "").replace(/\r?\n$/, "").trim()
    if (s.indexOf("file://") !== 0) return ""
    var rest = s.slice(7)
    if (rest.indexOf("localhost/") === 0) rest = rest.slice(9)
    try {
      return decodeURIComponent(rest)
    } catch (e) {
      return rest
    }
  }

  function extractDropPaths(drop) {
    var paths = []
    if (!drop) return paths
    if (drop.urls && drop.urls.length > 0) {
      for (var i = 0; i < drop.urls.length; i++) {
        var p = decodeFileUri(drop.urls[i])
        if (p !== "") paths.push(p)
      }
    }
    if (paths.length === 0 && drop.text) {
      var lines = String(drop.text).split(/\r?\n/)
      for (var j = 0; j < lines.length; j++) {
        var lp = decodeFileUri(lines[j])
        if (lp !== "") paths.push(lp)
      }
    }
    return paths
  }

  function relativeTime(isoString, tick, lang) {
    void(tick)
    void(lang)
    var s = String(isoString || "").trim()
    if (s === "") return ""
    var parsedMs = Date.parse(s)
    if (isNaN(parsedMs)) return s
    var diffSec = Math.max(0, Math.floor((Date.now() - parsedMs) / 1000))
    if (diffSec < 60) return strings.t("r2drop.justNow")
    var minutes = Math.floor(diffSec / 60)
    if (minutes < 60) return strings.t("r2drop.minutesAgo").arg(Commons.I18n.formatNumber(minutes))
    var hours = Math.floor(minutes / 60)
    if (hours < 24) return strings.t("r2drop.hoursAgo").arg(Commons.I18n.formatNumber(hours))
    var days = Math.floor(hours / 24)
    if (days < 30) return strings.t("r2drop.daysAgo").arg(Commons.I18n.formatNumber(days))
    if (days < 365) return strings.t("r2drop.monthsAgo").arg(Commons.I18n.formatNumber(Math.min(11, Math.floor(days / 30))))
    return strings.t("r2drop.yearsAgo").arg(Commons.I18n.formatNumber(Math.floor(days / 365)))
  }

  Timer {
    id: captureDelayTimer
    interval: Math.max(50, Style.duration(150))
    repeat: false
    onTriggered: root.runDetached(["capture"])
  }

  Timer {
    id: relativeTimeTimer
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowTick += 1
  }

  Process {
    id: whichProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: whichStdout
      waitForEnd: true
      onStreamFinished: root._whichOut = text
    }
    onExited: function(exitCode) {
      var found = String(whichStdout.text || root._whichOut || "").trim()
      if (exitCode === 0 && found !== "") {
        root.pathBin = found.split("\n")[0].trim()
      }
    }
  }

  Process {
    id: recentProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: recentStdout
      waitForEnd: true
      onStreamFinished: root._recentOut = text
    }
    onExited: function(exitCode) {
      var out = String(recentStdout.text || root._recentOut || "")
      if (exitCode === 0) root.applyRecentJson(out)
    }
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Style.hoverFillFor(root.barForeground, Commons.Color.accent)
    border.width: iconDropArea.containsDrag ? 1 : 0
    border.color: Commons.Color.accent
    opacity: iconDropArea.containsDrag ? 1 : 0

    Behavior on opacity {
      NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰅧"
    active: iconDropArea.containsDrag
    activeColor: Commons.Color.accent
    tooltipText: strings.t("r2drop.tooltip")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.runCapture()
      else if (buttonCode === Qt.MiddleButton) root.runClipboard()
      else root.toggle()
    }
  }

  DropArea {
    id: iconDropArea
    anchors.fill: parent
    onDropped: function(drop) {
      var paths = root.extractDropPaths(drop)
      if (paths.length > 0) {
        drop.acceptProposedAction()
        root.uploadFiles(paths)
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(520))

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias panelFlick: panelFlick
      property alias recentColumn: recentColumn
      implicitHeight: column.implicitHeight
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        root.moveCursor(dx, dy)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          Row {
            id: actionRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing * 2) / 3

            Button {
              width: actionRow.cellWidth
              bordered: true
              iconText: "󰄀"
              text: strings.t("r2drop.capture")
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "actions" && root.actionIndex === 0
              onHovered: function(on) {
                if (on) {
                  root.cursorActive = true
                  root.focusSection = "actions"
                  root.actionIndex = 0
                }
              }
              onClicked: root.runCapture()
            }

            Button {
              width: actionRow.cellWidth
              bordered: true
              iconText: "󰅌"
              text: strings.t("r2drop.uploadClipboard")
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "actions" && root.actionIndex === 1
              onHovered: function(on) {
                if (on) {
                  root.cursorActive = true
                  root.focusSection = "actions"
                  root.actionIndex = 1
                }
              }
              onClicked: root.runClipboard()
            }

            Button {
              width: actionRow.cellWidth
              bordered: true
              iconText: "󰉋"
              text: strings.t("r2drop.pickFiles")
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "actions" && root.actionIndex === 2
              onHovered: function(on) {
                if (on) {
                  root.cursorActive = true
                  root.focusSection = "actions"
                  root.actionIndex = 2
                }
              }
              onClicked: root.runPick()
            }
          }

          PanelSeparator {
            foreground: root.foreground
          }

          PanelSectionHeader {
            text: strings.t("r2drop.recentUploads")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          PlainText {
            visible: root.recentItems.length === 0
            width: parent.width
            topPadding: Style.space(8)
            bottomPadding: Style.space(8)
            text: strings.t("r2drop.empty")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            id: recentColumn
            visible: root.recentItems.length > 0
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.recentItems

              UploadRow {
                required property var modelData
                required property int index
                width: recentColumn.width
                itemData: modelData
                rowIndex: index
              }
            }
          }
        }
      }

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Style.hoverFillFor(root.foreground, Commons.Color.accent)
        border.width: panelDropArea.containsDrag ? 2 : 0
        border.color: Commons.Color.accent
        opacity: panelDropArea.containsDrag ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
          NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
        }

        PlainText {
          anchors.centerIn: parent
          text: strings.t("r2drop.dropHint")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }

      DropArea {
        id: panelDropArea
        anchors.fill: parent
        onDropped: function(drop) {
          var paths = root.extractDropPaths(drop)
          if (paths.length > 0) {
            drop.acceptProposedAction()
            root.uploadFiles(paths)
          }
        }
      }
    }
  }

  component PlainText: Text {
    textFormat: Text.PlainText
  }

  component UploadRow: CursorSurface {
    id: uploadRow
    property var itemData: null
    property int rowIndex: 0

    readonly property string itemKey: itemData ? String(itemData.key || "") : ""
    readonly property string itemName: itemData && itemData.name ? String(itemData.name) : strings.t("r2drop.untitled")
    readonly property string itemTime: itemData ? String(itemData.time || "") : ""
    readonly property string itemThumb: itemData ? String(itemData.thumb || "") : ""
    readonly property url thumbUrl: itemThumb !== "" ? Util.fileUrl(itemThumb) : ""

    hasCursor: root.cursorActive && root.focusSection === "recent" && root.selectedIndex === rowIndex
    foreground: root.foreground
    implicitHeight: Math.max(Style.space(44), rowLayout.implicitHeight + Style.spacing.rowPaddingX)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "recent"
        root.selectedIndex = uploadRow.rowIndex
      }
      onClicked: root.copyKey(uploadRow.itemKey)
    }

    RowLayout {
      id: rowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(10)

      Rectangle {
        Layout.preferredWidth: Style.space(34)
        Layout.preferredHeight: Style.space(34)
        Layout.alignment: Qt.AlignVCenter
        radius: Math.max(2, Math.round(Style.cornerRadius * 0.6))
        color: Style.hoverFillFor(root.foreground, root.foreground)
        clip: true

        SizedImage {
          id: thumbImage
          anchors.fill: parent
          url: uploadRow.thumbUrl
          crop: true
          visible: uploadRow.itemThumb !== "" && status === Image.Ready
        }

        PlainText {
          anchors.centerIn: parent
          visible: !thumbImage.visible
          text: "󰋩"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(2)

        PlainText {
          Layout.fillWidth: true
          text: uploadRow.itemName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        PlainText {
          Layout.fillWidth: true
          text: root.relativeTime(uploadRow.itemTime, root.nowTick, strings.language)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PlainText {
        Layout.alignment: Qt.AlignVCenter
        text: "󰆏"
        color: uploadRow.hasCursor ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }
    }
  }
}
