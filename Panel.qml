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
  readonly property Item browseFlick: panel.loadedContent ? panel.loadedContent.browseFlick : null
  readonly property Item browseGrid: panel.loadedContent ? panel.loadedContent.browseGrid : null
  readonly property Item nameField: panel.loadedContent ? panel.loadedContent.nameField : null

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property string viewMode: "main"
  property var recentItems: []
  property var browseItems: []
  property var selectedPaths: []
  property string customName: ""
  property int browseIndex: 0
  readonly property int gridColumns: 3

  property string focusSection: "recent"
  property int selectedIndex: 0
  property int actionIndex: 0
  property bool cursorActive: false
  property int nowTick: 0
  property string _whichOut: ""
  property string _recentOut: ""
  property string _imagesOut: ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: {
    resolveBinary()
    refresh()
  }

  onOpenedChanged: {
    if (opened) {
      viewMode = "main"
      selectedPaths = []
      customName = ""
      if (nameField) nameField.text = ""
      cursorActive = false
      focusSection = recentItems.length > 0 ? "recent" : "actions"
      selectedIndex = 0
      actionIndex = 0
      browseIndex = 0
      nowTick += 1
      if (panelFlick) panelFlick.contentY = 0
      if (browseFlick) browseFlick.contentY = 0
      refresh()
      Qt.callLater(function() {
        if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
      })
    }
  }

  onSelectedIndexChanged: scrollCursorIntoView()
  onBrowseIndexChanged: scrollBrowseCursorIntoView()

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

  function loadBrowseImages() {
    if (pathBin === "" && !whichProcess.running) resolveBinary()
    if (imagesProcess.running) return
    root._imagesOut = ""
    imagesProcess.command = [root.r2dropBin, "images", "--json", "60"]
    imagesProcess.running = true
  }

  function enterBrowseView() {
    root.viewMode = "browse"
    root.selectedPaths = []
    root.customName = ""
    if (nameField) nameField.text = ""
    root.browseIndex = 0
    root.cursorActive = true
    if (browseFlick) browseFlick.contentY = 0
    root.loadBrowseImages()
    Qt.callLater(function() {
      if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
    })
  }

  function exitBrowseView() {
    root.viewMode = "main"
    root.selectedPaths = []
    root.customName = ""
    if (nameField) nameField.text = ""
    root.focusSection = "actions"
    root.actionIndex = 2
    Qt.callLater(function() {
      if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
    })
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

  function applyImagesJson(raw) {
    var text = String(raw || "").trim()
    if (text === "") {
      root.browseItems = []
      root.ensureBrowseCursor()
      return
    }
    try {
      var parsed = JSON.parse(text)
      if (!Array.isArray(parsed)) {
        root.browseItems = []
        root.ensureBrowseCursor()
        return
      }
      var items = []
      var limit = Math.min(60, parsed.length)
      for (var i = 0; i < limit; i++) {
        var entry = parsed[i]
        if (!entry || typeof entry !== "object") continue
        var path = boundedString(entry.path, 4096)
        if (path === "") continue
        var name = boundedString(entry.name || path.split("/").pop(), 512)
        items.push({
          path: path,
          name: name,
          mtime: Number(entry.mtime) || 0,
          size: Number(entry.size) || 0
        })
      }
      root.browseItems = items
    } catch (e) {
      root.browseItems = []
    }
    root.ensureBrowseCursor()
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

  function ensureBrowseCursor() {
    if (root.browseItems.length === 0) {
      root.browseIndex = 0
    } else {
      if (root.browseIndex >= root.browseItems.length) {
        root.browseIndex = Math.max(0, root.browseItems.length - 1)
      }
      if (root.browseIndex < 0) root.browseIndex = 0
    }
  }

  function isPathSelected(path) {
    return root.selectedPaths.indexOf(String(path || "")) !== -1
  }

  function toggleSelectPath(path) {
    var p = String(path || "")
    if (p === "") return
    var next = root.selectedPaths.slice()
    var idx = next.indexOf(p)
    if (idx >= 0) next.splice(idx, 1)
    else next.push(p)
    root.selectedPaths = next
    if (next.length !== 1) {
      root.customName = ""
      if (nameField) nameField.text = ""
      if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
    }
  }

  function toggleBrowseFocused() {
    root.cursorActive = true
    root.ensureBrowseCursor()
    if (root.browseItems.length === 0) return
    var item = root.browseItems[root.browseIndex]
    if (item && item.path) root.toggleSelectPath(item.path)
  }

  function moveBrowseCursor(dx, dy) {
    root.ensureBrowseCursor()
    if (root.browseItems.length === 0) return
    if (!root.cursorActive) {
      root.cursorActive = true
      root.scrollBrowseCursorIntoView()
      return
    }
    var count = root.browseItems.length
    var next = root.browseIndex
    if (dx !== 0) {
      next = Math.max(0, Math.min(count - 1, next + (dx > 0 ? 1 : -1)))
    } else if (dy !== 0) {
      var step = (dy > 0 ? 1 : -1) * root.gridColumns
      var candidate = next + step
      if (candidate >= 0 && candidate < count) {
        next = candidate
      } else if (dy > 0) {
        var currentRow = Math.floor(next / root.gridColumns)
        var lastRow = Math.floor((count - 1) / root.gridColumns)
        if (currentRow < lastRow) next = count - 1
      }
    }
    root.browseIndex = next
  }

  function moveCursor(dx, dy) {
    if (root.viewMode === "browse") {
      root.moveBrowseCursor(dx, dy)
      return
    }

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
      else root.enterBrowseView()
      return
    }
    if (root.focusSection === "recent" && root.recentItems.length > 0) {
      var item = root.recentItems[Math.max(0, Math.min(root.selectedIndex, root.recentItems.length - 1))]
      if (item && item.key) root.copyKey(item.key)
    }
  }

  function scrollFlickItemIntoView(flick, item) {
    if (!flick || !item) return
    Qt.callLater(function() {
      if (!item || !flick) return
      var margin = Style.space(6)
      var point = item.mapToItem(flick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = flick.contentY
      var viewBottom = viewTop + flick.height
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) flick.contentY = Math.min(maxY, bottom + margin - flick.height)
    })
  }

  function scrollCursorIntoView() {
    if (viewMode === "main" && focusSection === "recent" && recentColumn && selectedIndex >= 0 && selectedIndex < recentColumn.children.length) {
      scrollFlickItemIntoView(panelFlick, recentColumn.children[selectedIndex])
    }
  }

  function scrollBrowseCursorIntoView() {
    if (viewMode === "browse" && browseGrid && browseIndex >= 0 && browseIndex < browseGrid.children.length) {
      scrollFlickItemIntoView(browseFlick, browseGrid.children[browseIndex])
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

  function copyKey(key) {
    var k = String(key || "")
    if (k === "") return
    root.close()
    root.runDetached(["copy", k])
  }

  function uploadFiles(paths, nameOpt) {
    if (!paths || paths.length === 0) return
    var args = ["upload"]
    var trimmedName = String(nameOpt || "").trim()
    if (paths.length === 1 && trimmedName !== "") {
      args.push("--name", trimmedName)
    }
    args.push("--")
    args = args.concat(paths)
    root.close()
    root.runDetached(args)
  }

  function uploadBrowse(allowFocusedFallback) {
    var paths = []
    if (root.selectedPaths.length > 0) {
      paths = root.selectedPaths.slice()
    } else if (allowFocusedFallback && root.browseItems.length > 0) {
      root.ensureBrowseCursor()
      var focused = root.browseItems[root.browseIndex]
      if (focused && focused.path) paths = [focused.path]
    }
    if (paths.length === 0) return
    var custom = paths.length === 1 && nameField ? nameField.text : root.customName
    root.uploadFiles(paths, custom)
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

  Process {
    id: imagesProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: imagesStdout
      waitForEnd: true
      onStreamFinished: root._imagesOut = text
    }
    onExited: function(exitCode) {
      var out = String(imagesStdout.text || root._imagesOut || "")
      if (exitCode === 0) root.applyImagesJson(out)
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
        root.uploadFiles(paths, "")
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(540))

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias panelFlick: panelFlick
      property alias recentColumn: recentColumn
      property alias browseFlick: browseFlick
      property alias browseGrid: browseGrid
      property alias nameField: nameField
      property bool returnHandled: false

      implicitHeight: root.viewMode === "browse" ? browseViewColumn.implicitHeight : mainColumn.implicitHeight
      anchors.fill: parent
      blocked: nameField.activeFocus

      onMoveRequested: function(dx, dy) {
        root.moveCursor(dx, dy)
      }
      onReturnRequested: returnHandled = true
      onActivateRequested: {
        var fromReturn = returnHandled
        returnHandled = false
        if (root.viewMode === "browse") {
          if (fromReturn) root.uploadBrowse(true)
          else root.toggleBrowseFocused()
        } else {
          root.activateCursor()
        }
      }
      onCloseRequested: {
        if (root.viewMode === "browse") root.exitBrowseView()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Keys.onBackspacePressed: function(event) {
        if (!keyCatcher.blocked && root.viewMode === "browse") {
          root.exitBrowseView()
          event.accepted = true
        }
      }

      // Main view
      Flickable {
        id: panelFlick
        visible: root.viewMode === "main"
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: mainColumn
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
              text: strings.t("r2drop.browse")
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
              onClicked: root.enterBrowseView()
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

      // Browse view
      Column {
        id: browseViewColumn
        visible: root.viewMode === "browse"
        width: parent.width
        spacing: Style.space(8)

        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Button {
            bordered: true
            iconText: Commons.I18n.rightToLeft ? "󰁔" : "󰁍"
            text: strings.t("r2drop.back")
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.exitBrowseView()
          }

          PlainText {
            Layout.fillWidth: true
            text: strings.t("r2drop.browseTitle")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        PlainText {
          visible: root.browseItems.length === 0
          width: parent.width
          topPadding: Style.space(16)
          bottomPadding: Style.space(16)
          text: strings.t("r2drop.browseEmpty")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
        }

        Flickable {
          id: browseFlick
          visible: root.browseItems.length > 0
          width: parent.width
          height: Math.min(browseGrid.implicitHeight, Style.space(320))
          contentWidth: width
          contentHeight: browseGrid.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Grid {
            id: browseGrid
            width: browseFlick.width
            columns: root.gridColumns
            spacing: Style.space(6)
            readonly property real cellWidth: Math.max(Style.space(60), Math.floor((width - spacing * (columns - 1)) / columns))

            Repeater {
              model: root.browseItems

              BrowseCell {
                required property var modelData
                required property int index
                width: browseGrid.cellWidth
                itemData: modelData
                cellIndex: index
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          TextField {
            id: nameField
            visible: root.selectedPaths.length === 1
            width: parent.width
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            placeholderText: strings.t("r2drop.namePlaceholder")
            onTextChanged: root.customName = text
            onAccepted: root.uploadBrowse(false)
            Keys.onEscapePressed: function(event) {
              keyCatcher.forceActiveFocus()
              event.accepted = true
            }
          }

          Button {
            width: parent.width
            bordered: true
            selected: root.selectedPaths.length > 0
            iconText: "󰅧"
            text: strings.t("r2drop.uploadCount").arg(Commons.I18n.formatNumber(root.selectedPaths.length))
            fontSize: Style.font.bodySmall
            foreground: root.selectedPaths.length > 0 ? root.foreground : root.dim
            fontFamily: root.fontFamily
            onClicked: root.uploadBrowse(false)
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
            root.uploadFiles(paths, "")
          }
        }
      }
    }
  }

  component PlainText: Text {
    textFormat: Text.PlainText
  }

  component BrowseCell: CursorSurface {
    id: cell
    property var itemData: null
    property int cellIndex: 0

    readonly property string itemPath: itemData ? String(itemData.path || "") : ""
    readonly property string itemName: itemData && itemData.name ? String(itemData.name) : strings.t("r2drop.untitled")
    readonly property url fileUrl: itemPath !== "" ? Util.fileUrl(itemPath) : ""
    readonly property bool isSelected: root.isPathSelected(itemPath)

    hasCursor: root.viewMode === "browse" && root.cursorActive && root.browseIndex === cellIndex
    current: isSelected
    bordered: true
    foreground: root.foreground
    implicitHeight: cellColumn.implicitHeight + Style.space(10)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.browseIndex = cell.cellIndex
      }
      onClicked: {
        root.cursorActive = true
        root.browseIndex = cell.cellIndex
        root.toggleSelectPath(cell.itemPath)
      }
    }

    Column {
      id: cellColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(5)
      spacing: Style.space(4)

      Rectangle {
        width: parent.width
        height: Math.round(width * 0.72)
        radius: Math.max(2, Math.round(Style.cornerRadius * 0.6))
        color: Style.hoverFillFor(root.foreground, root.foreground)
        clip: true

        Image {
          id: cellThumb
          anchors.fill: parent
          source: cell.fileUrl
          sourceSize.width: 160
          sourceSize.height: 160
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          visible: cell.itemPath !== "" && status === Image.Ready
        }

        PlainText {
          anchors.centerIn: parent
          visible: !cellThumb.visible
          text: "󰋩"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }

        Rectangle {
          width: Style.space(18)
          height: Style.space(18)
          radius: Style.space(9)
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.margins: Style.space(4)
          color: cell.isSelected ? Commons.Color.accent : Util.alpha(Commons.Color.popups.background, 0.75)
          border.width: 1
          border.color: cell.isSelected ? Commons.Color.accent : root.dim

          Behavior on color {
            ColorAnimation { duration: Style.duration(120) }
          }

          PlainText {
            anchors.centerIn: parent
            visible: cell.isSelected
            text: "󰄬"
            color: Commons.Color.popups.background
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      PlainText {
        width: parent.width
        text: cell.itemName
        color: cell.isSelected ? Commons.Color.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: cell.isSelected
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
      }
    }
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

    hasCursor: root.viewMode === "main" && root.cursorActive && root.focusSection === "recent" && root.selectedIndex === rowIndex
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
