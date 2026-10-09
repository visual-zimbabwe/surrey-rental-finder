import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "juwimana.surrey-rentals"
  ipcTarget: "juwimana.surrey-rentals"

  // Data properties
  property var matches: []
  property var stats: ({ total_scanned: 0, full_matches: 0, has_ac: 0, near_bus_323: 0 })
  property var configData: ({
    max_price: 2000,
    min_bedrooms: 2,
    max_bedrooms: 3,
    require_ac: true,
    allow_apartments: false,
    max_walk_mins: 5.0
  })

  property bool isScanning: false
  property bool showSettings: false
  property string lastError: ""
  property string lastUpdated: "Just now"

  // Search, Sorting & Selection
  property string sortBy: "newest" // "newest", "price", "walk"
  property int selectedIndex: 0
  property string searchQuery: ""
  property bool searching: false

  readonly property int matchCount: matches ? matches.length : 0
  readonly property string runnerPath: "/home/juwimana/surrey-rental-finder/run.sh"

  function formatRelativeTime(dateStr) {
    if (!dateStr || dateStr === "") return ""
    try {
      var d = new Date(dateStr)
      if (isNaN(d.getTime())) return ""
      var now = new Date()
      var diffMs = now.getTime() - d.getTime()
      if (diffMs < 0) diffMs = 0
      var diffSec = Math.floor(diffMs / 1000)
      if (diffSec < 60) return "Just now"
      var diffMin = Math.floor(diffSec / 60)
      if (diffMin < 60) return diffMin + "m ago"
      var diffHr = Math.floor(diffMin / 60)
      if (diffHr < 24) return diffHr + "h ago"
      var diffDays = Math.floor(diffHr / 24)
      if (diffDays === 1) return "Yesterday"
      if (diffDays < 7) return diffDays + "d ago"
      var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
      return months[d.getMonth()] + " " + d.getDate()
    } catch (e) {
      return ""
    }
  }

  readonly property var sortedMatches: {
    if (!root.matches || root.matches.length === 0) return []
    var list = root.matches.slice(0)

    // Filter by search query if active
    if (root.searchQuery && root.searchQuery.trim() !== "") {
      var q = root.searchQuery.trim().toLowerCase()
      list = list.filter(function(item) {
        var t = (item.title || "").toLowerCase()
        var s = (item.nearest_stop_name || "").toLowerCase()
        var h = (item.housing_type || "").toLowerCase()
        return t.indexOf(q) !== -1 || s.indexOf(q) !== -1 || h.indexOf(q) !== -1
      })
    }

    // Sort
    if (root.sortBy === "newest" || root.sortBy === "latest") {
      list.sort(function(a, b) {
        var da = a.posted_at || a.first_seen_at || a.last_seen_at || ""
        var db = b.posted_at || b.first_seen_at || b.last_seen_at || ""
        var timeA = da ? (new Date(da).getTime() || 0) : 0
        var timeB = db ? (new Date(db).getTime() || 0) : 0
        if (timeA !== timeB) return timeB - timeA
        return (db || "").localeCompare(da || "")
      })
    } else if (root.sortBy === "price") {
      list.sort(function(a, b) {
        var pa = (a.price !== undefined && a.price !== null) ? a.price : 999999
        var pb = (b.price !== undefined && b.price !== null) ? b.price : 999999
        if (pa !== pb) return pa - pb
        var da = a.posted_at || a.first_seen_at || ""
        var db = b.posted_at || b.first_seen_at || ""
        return (new Date(db).getTime() || 0) - (new Date(da).getTime() || 0)
      })
    } else if (root.sortBy === "walk") {
      list.sort(function(a, b) {
        var wa = (a.walk_time_minutes !== undefined && a.walk_time_minutes !== null) ? a.walk_time_minutes : 999
        var wb = (b.walk_time_minutes !== undefined && b.walk_time_minutes !== null) ? b.walk_time_minutes : 999
        if (wa !== wb) return wa - wb
        var da = a.posted_at || a.first_seen_at || ""
        var db = b.posted_at || b.first_seen_at || ""
        return (new Date(db).getTime() || 0) - (new Date(da).getTime() || 0)
      })
    }
    return list
  }

  // UI styling properties - pure theme colors
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color accentColor: Color.accent
  readonly property color mutedColor: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int panelWidth: Style.space(460)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function fetchMatches() {
    if (matchesProcess.running) return
    matchesProcess.running = true
  }

  function triggerScan() {
    if (scanProcess.running || root.isScanning) return
    root.isScanning = true
    root.lastError = ""
    scanProcess.running = true
  }

  function setConfigValue(key, val) {
    configSetProcess.command = [root.runnerPath, "config", "set", key, String(val)]
    configSetProcess.running = true
  }

  function toggleAcRequired() {
    var nextVal = !root.configData.require_ac
    root.configData.require_ac = nextVal
    setConfigValue("require_ac", nextVal ? "true" : "false")
  }

  function toggleAllowApartments() {
    var nextVal = !root.configData.allow_apartments
    root.configData.allow_apartments = nextVal
    setConfigValue("allow_apartments", nextVal ? "true" : "false")
  }

  function adjustPrice(delta) {
    var nextPrice = Math.max(1000, Math.min(5000, Math.round(root.configData.max_price + delta)))
    root.configData.max_price = nextPrice
    setConfigValue("max_price", String(nextPrice))
  }

  function adjustWalkMins(delta) {
    var nextMins = Math.max(1, Math.min(20, Math.round(root.configData.max_walk_mins + delta)))
    root.configData.max_walk_mins = nextMins
    setConfigValue("max_walk_mins", String(nextMins))
  }

  function openUrl(url) {
    if (!url || url === "") return
    var opened = false
    try {
      opened = Qt.openUrlExternally(url)
    } catch (e) {
      opened = false
    }
    if (!opened) {
      Quickshell.execDetached(["xdg-open", url])
    }
  }

  function openTerminal() {
    Quickshell.execDetached(["omarchy-launch-tui", "--app-id=org.omarchy.surrey-rentals", root.runnerPath, "scan", "--show-all"])
  }

  function parseMatches(raw) {
    try {
      var data = JSON.parse((raw || "").trim())
      if (data && data.matches !== undefined) {
        root.matches = data.matches || []
      }
      if (data && data.stats) {
        root.stats = data.stats
      }
      if (data && data.config) {
        root.configData = data.config
      }
      var now = new Date()
      root.lastUpdated = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
      root.lastError = ""
    } catch (e) {
      // ignore
    }
  }

  onMatchesChanged: {
    if (root.selectedIndex >= root.matches.length) {
      root.selectedIndex = Math.max(0, root.matches.length - 1)
    }
  }

  onOpenedChanged: {
    if (root.opened) {
      root.selectedIndex = 0
      root.fetchMatches()
    }
  }

  Component.onCompleted: {
    root.fetchMatches()
  }

  // Periodic check
  Timer {
    interval: root.opened ? 8000 : 25000
    running: true
    repeat: true
    onTriggered: root.fetchMatches()
  }

  // Background processes
  Process {
    id: matchesProcess
    command: [root.runnerPath, "json-matches"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseMatches(text)
    }
  }

  Process {
    id: scanProcess
    command: [root.runnerPath, "json-scan", "--limit", "25"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.isScanning = false
        root.parseMatches(text)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && text.trim() !== "") root.lastError = text.trim()
      }
    }
    onExited: {
      root.isScanning = false
      root.fetchMatches()
    }
  }

  Process {
    id: configSetProcess
    onExited: {
      root.fetchMatches()
    }
  }

  // -------------------------------------------------------------
  // BAR WIDGET BUTTON
  // -------------------------------------------------------------
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: {
      if (root.matchCount > 0) {
        return "\uf015 " + root.matchCount + " Match" + (root.matchCount === 1 ? "" : "es")
      }
      return "\uf015 323 Rent"
    }
    fontSize: Style.bar.iconFont
    foreground: root.matchCount > 0 ? Color.accent : (bar ? bar.barForeground : Color.foreground)
    tooltipText: "Surrey Route 323 Rental Finder · " + root.matchCount + " matches found (" + root.stats.total_scanned + " scanned)"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) {
        root.toggle()
      } else if (buttonCode === Qt.MiddleButton) {
        root.triggerScan()
      }
    }
  }

  // -------------------------------------------------------------
  // POPUP KEYBOARD PANEL
  // -------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.panelWidth)
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.searching

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (!root.sortedMatches || root.sortedMatches.length === 0) return
        if (dy > 0) {
          root.selectedIndex = Math.min(root.sortedMatches.length - 1, Math.max(0, root.selectedIndex + 1))
          listingsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
        } else if (dy < 0) {
          root.selectedIndex = Math.max(0, root.selectedIndex - 1)
          listingsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
        }
      }
      onTextKey: function(t) {
        var k = t.toLowerCase()
        if (k === "s") root.triggerScan()
        else if (k === "r") root.fetchMatches()
        else if (k === "t") root.openTerminal()
        else if (k === "a") root.toggleAcRequired()
        else if (k === "h") root.toggleAllowApartments()
        else if (k === "/") {
          root.searching = true
          Qt.callLater(function() { if (root.searching) searchField.forceActiveFocus() })
        }
        else if (k === "j") {
          if (root.sortedMatches && root.sortedMatches.length > 0) {
            root.selectedIndex = Math.min(root.sortedMatches.length - 1, Math.max(0, root.selectedIndex + 1))
            listingsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
          }
        }
        else if (k === "k") {
          if (root.sortedMatches && root.sortedMatches.length > 0) {
            root.selectedIndex = Math.max(0, root.selectedIndex - 1)
            listingsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
          }
        }
        else if (k === "o" || k === "\r" || k === "\n") {
          if (root.selectedIndex >= 0 && root.selectedIndex < root.sortedMatches.length) {
            root.openUrl(root.sortedMatches[root.selectedIndex].url)
          }
        }
        else if (k === "1" || k === "l" || k === "n") {
          root.sortBy = "newest"
        }
        else if (k === "2" || k === "p") {
          root.sortBy = "price"
        }
        else if (k === "3" || k === "w") {
          root.sortBy = "walk"
        }
      }

      Column {
        id: mainColumn
        width: parent.width
        spacing: Style.space(10)

        // --------------------------------------------------------
        // HEADER HERO
        // --------------------------------------------------------
        PanelHero {
          width: parent.width
          title: "Surrey 323 Rentals"
          meta: root.isScanning ? "Scanning Craigslist Surrey..." : "Route 323 Corridor · " + (root.configData.min_bedrooms || 2) + "-" + (root.configData.max_bedrooms || 3) + " Bed · Max $" + Math.round(root.configData.max_price || 2000)
          foreground: root.fg
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: "\uf015"
              color: root.matchCount > 0 ? Color.accent : root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          trailingControl: Component {
            Row {
              spacing: Style.space(6)

              // Settings Gear Button
              Rectangle {
                width: Style.space(28)
                height: Style.space(28)
                radius: Style.space(4)
                color: root.showSettings
                  ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
                  : (gearMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05))

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: "\uf013"
                  color: root.showSettings ? Color.accent : root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: gearMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showSettings = !root.showSettings
                }
              }

              // Scan Now Button
              Rectangle {
                width: Style.space(78)
                height: Style.space(28)
                radius: Style.space(4)
                color: Color.accent

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: root.isScanning ? "Scanning..." : "Scan Now"
                  color: Color.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.triggerScan()
                }
              }
            }
          }
        }

        // --------------------------------------------------------
        // INTERACTIVE FILTER ROW (Clean Typography, No Badges)
        // --------------------------------------------------------
        Row {
          width: parent.width
          spacing: Style.space(8)

          // A/C Toggle
          Text {
            textFormat: Text.PlainText
            text: root.configData.require_ac ? "AC: Required" : "AC: Optional"
            color: root.configData.require_ac ? Color.accent : root.mutedColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: root.configData.require_ac

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleAcRequired()
            }
          }

          Text {
            textFormat: Text.PlainText
            text: "·"
            color: root.mutedColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // Housing Type Toggle
          Text {
            textFormat: Text.PlainText
            text: !root.configData.allow_apartments ? "Type: House/Suite" : "Type: All Types"
            color: !root.configData.allow_apartments ? Color.accent : root.mutedColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: !root.configData.allow_apartments

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleAllowApartments()
            }
          }

          Text {
            textFormat: Text.PlainText
            text: "·"
            color: root.mutedColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // Max Price
          Text {
            textFormat: Text.PlainText
            text: "Max: $" + Math.round(root.configData.max_price || 2000)
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showSettings = !root.showSettings
            }
          }

          Text {
            textFormat: Text.PlainText
            text: "·"
            color: root.mutedColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // Walk Distance
          Text {
            textFormat: Text.PlainText
            text: "Walk: \u2264 " + Math.round(root.configData.max_walk_mins || 5) + " min"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showSettings = !root.showSettings
            }
          }
        }

        // --------------------------------------------------------
        // EXPANDABLE SETTINGS DRAWER
        // --------------------------------------------------------
        Rectangle {
          visible: root.showSettings
          width: parent.width
          implicitHeight: settingsCol.implicitHeight + Style.space(16)
          radius: Style.space(6)
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
          border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
          border.width: 1

          Column {
            id: settingsCol
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: "Filter Criteria Settings"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            // Max Price Adjuster
            Row {
              width: parent.width
              spacing: Style.space(10)

              Text {
                textFormat: Text.PlainText
                text: "Max Monthly Rent:"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(130)
              }

              Rectangle {
                width: Style.space(26)
                height: Style.space(22)
                radius: Style.space(4)
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
                Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "-"; color: root.fg; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustPrice(-100) }
              }

              Text {
                textFormat: Text.PlainText
                text: "$" + Math.round(root.configData.max_price || 2000)
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                width: Style.space(60)
              }

              Rectangle {
                width: Style.space(26)
                height: Style.space(22)
                radius: Style.space(4)
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
                Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "+"; color: root.fg; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustPrice(100) }
              }
            }

            // Walk Time Adjuster
            Row {
              width: parent.width
              spacing: Style.space(10)

              Text {
                textFormat: Text.PlainText
                text: "Max Walk to Bus 323:"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(130)
              }

              Rectangle {
                width: Style.space(26)
                height: Style.space(22)
                radius: Style.space(4)
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
                Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "-"; color: root.fg; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustWalkMins(-1) }
              }

              Text {
                textFormat: Text.PlainText
                text: Math.round(root.configData.max_walk_mins || 5) + " min"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                width: Style.space(60)
              }

              Rectangle {
                width: Style.space(26)
                height: Style.space(22)
                radius: Style.space(4)
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
                Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "+"; color: root.fg; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustWalkMins(1) }
              }
            }
          }
        }

        // --------------------------------------------------------
        // SEARCH INPUT (When active)
        // --------------------------------------------------------
        Row {
          visible: root.searching
          width: parent.width
          spacing: Style.space(6)

          Rectangle {
            width: parent.width - Style.space(34)
            height: Style.space(28)
            radius: Style.space(4)
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
            border.color: Color.accent
            border.width: 1

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                text: "\uf002"
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }

              TextInput {
                id: searchField
                width: parent.width - Style.space(24)
                anchors.verticalCenter: parent.verticalCenter
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                selectByMouse: true
                text: root.searchQuery
                onTextChanged: {
                  root.searchQuery = text
                  root.selectedIndex = 0
                }
                Keys.onEscapePressed: {
                  root.searchQuery = ""
                  root.searching = false
                  keyCatcher.forceActiveFocus()
                }
                Keys.onDownPressed: {
                  if (root.sortedMatches && root.sortedMatches.length > 0) {
                    root.selectedIndex = Math.min(root.sortedMatches.length - 1, root.selectedIndex + 1)
                    listingsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
                  }
                }
                Keys.onUpPressed: {
                  if (root.sortedMatches && root.sortedMatches.length > 0) {
                    root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                    listingsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
                  }
                }
                Keys.onReturnPressed: {
                  if (root.selectedIndex >= 0 && root.selectedIndex < root.sortedMatches.length) {
                    root.openUrl(root.sortedMatches[root.selectedIndex].url)
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.fill: parent
                  text: "Filter listings by title, street, or type..."
                  color: root.mutedColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  verticalAlignment: Text.AlignVCenter
                  visible: !searchField.text && !searchField.activeFocus
                }
              }
            }
          }

          // Close Search button
          Rectangle {
            width: Style.space(28)
            height: Style.space(28)
            radius: Style.space(4)
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: "\uf00d"
              color: root.mutedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.searchQuery = ""
                root.searching = false
                keyCatcher.forceActiveFocus()
              }
            }
          }
        }

        // --------------------------------------------------------
        // STATS & SORTING ROW (Clean Text Controls)
        // --------------------------------------------------------
        Item {
          width: parent.width
          height: Style.space(24)

          // Left: Count & Status
          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Text {
              textFormat: Text.PlainText
              text: (root.searchQuery ? (root.sortedMatches.length + " of " + root.matchCount) : root.matchCount) + " Match" + (root.matchCount === 1 ? "" : "es")
              color: root.matchCount > 0 ? Color.accent : root.fg
              font.bold: true
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              textFormat: Text.PlainText
              text: "· " + root.stats.total_scanned + " scanned"
              color: root.mutedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // Right: Sort Actions & Search Toggle
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: "Sort:"
              color: root.mutedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              textFormat: Text.PlainText
              text: "Latest"
              color: (root.sortBy === "newest" || root.sortBy === "latest") ? Color.accent : root.mutedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: (root.sortBy === "newest" || root.sortBy === "latest")
              anchors.verticalCenter: parent.verticalCenter

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.sortBy = "newest"
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "·"
              color: root.mutedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              textFormat: Text.PlainText
              text: "Price"
              color: root.sortBy === "price" ? Color.accent : root.mutedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: root.sortBy === "price"
              anchors.verticalCenter: parent.verticalCenter

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.sortBy = "price"
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "·"
              color: root.mutedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              textFormat: Text.PlainText
              text: "Walk"
              color: root.sortBy === "walk" ? Color.accent : root.mutedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: root.sortBy === "walk"
              anchors.verticalCenter: parent.verticalCenter

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.sortBy = "walk"
              }
            }

            // Search Icon Toggle
            Text {
              textFormat: Text.PlainText
              text: "\uf002"
              color: root.searching ? Color.accent : root.mutedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.searching = !root.searching
                  if (root.searching) {
                    Qt.callLater(function() { searchField.forceActiveFocus() })
                  }
                }
              }
            }
          }
        }

        // --------------------------------------------------------
        // SCROLLABLE LISTVIEW FOR LISTINGS
        // --------------------------------------------------------
        ListView {
          id: listingsList
          width: parent.width
          height: Math.min(contentHeight, root.showSettings ? Style.space(240) : (root.searching ? Style.space(330) : Style.space(370)))
          visible: root.sortedMatches.length > 0
          clip: true
          model: root.sortedMatches
          spacing: Style.space(6)
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          currentIndex: root.selectedIndex

          ScrollBar.vertical: ScrollBar {
            id: listScroll
            policy: ScrollBar.AsNeeded
          }

          delegate: Rectangle {
            id: cardRect
            width: listingsList.width - (listingsList.interactive ? Style.space(8) : 0)
            implicitHeight: cardCol.implicitHeight + Style.space(16)
            radius: Style.space(6)
            color: (root.selectedIndex === index)
              ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
              : (cardMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.02))
            border.color: (root.selectedIndex === index)
              ? Color.accent
              : (cardMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.16) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08))
            border.width: 1

            MouseArea {
              id: cardMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: {
                root.selectedIndex = index
              }
              onClicked: root.openUrl(modelData.url)
            }

            Column {
              id: cardCol
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(4)

              // Line 1: Primary Metrics & Metadata (Plain Text, No Badges)
              Row {
                width: parent.width
                spacing: Style.space(6)

                Text {
                  textFormat: Text.PlainText
                  text: "$" + Math.round(modelData.price) + "/mo"
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: "·"
                  color: root.mutedColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: modelData.bedrooms + " Bed" + (modelData.bathrooms ? ", " + modelData.bathrooms + " Bath" : "")
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: "·"
                  color: root.mutedColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: modelData.housing_type
                  color: root.mutedColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: "·"
                  color: root.mutedColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: modelData.has_ac ? "AC" : "No AC"
                  color: modelData.has_ac ? Color.accent : root.mutedColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: modelData.has_ac
                  anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                  Layout.fillWidth: true
                  width: Style.space(4)
                  height: 1
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: (root.selectedIndex === index) ? "[Enter] Open" : "Open \uf08e"
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openUrl(modelData.url)
                  }
                }
              }

              // Line 2: Title (Full text, easy to read)
              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: modelData.title
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
                maximumLineCount: 1
              }

              // Line 3: Transit Stop & Walk Time + Posting Age
              Item {
                width: parent.width
                implicitHeight: line3TransitRow.implicitHeight

                Row {
                  id: line3TransitRow
                  anchors.left: parent.left
                  anchors.right: line3TimeText.visible ? line3TimeText.left : parent.right
                  anchors.rightMargin: line3TimeText.visible ? Style.space(8) : 0
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(6)

                  Text {
                    textFormat: Text.PlainText
                    text: "\uf207"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: (modelData.nearest_stop_name || "Route 323 Stop") + " (" + (modelData.walk_time_minutes ? modelData.walk_time_minutes.toFixed(1) : "?") + " min walk · " + (modelData.distance_meters ? Math.round(modelData.distance_meters) : "?") + " m)"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width - Style.space(16)
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Text {
                  id: line3TimeText
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  readonly property string timeStr: root.formatRelativeTime(modelData.posted_at || modelData.first_seen_at)
                  visible: timeStr !== ""
                  textFormat: Text.PlainText
                  text: "\uf017 " + timeStr
                  color: (timeStr.indexOf("m ago") !== -1 || timeStr === "Just now" || timeStr.indexOf("h ago") !== -1) ? Color.accent : root.mutedColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: (timeStr.indexOf("m ago") !== -1 || timeStr === "Just now")
                }
              }
            }
          }
        }

        // --------------------------------------------------------
        // EMPTY / NO-MATCH STATE
        // --------------------------------------------------------
        Rectangle {
          visible: root.sortedMatches.length === 0
          width: parent.width
          height: Style.space(120)
          radius: Style.space(6)
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)
          border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
          border.width: 1

          Column {
            anchors.centerIn: parent
            spacing: Style.space(6)
            width: parent.width - Style.space(30)

            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.searchQuery ? "No Matching Listings for Filter" : "No Live Matches Found"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.searchQuery
                ? "No listings match '" + root.searchQuery + "'. Try clearing the filter."
                : "Scanned " + root.stats.total_scanned + " listings in Surrey. Current postings did not match the active criteria above."
              color: root.mutedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              width: parent.width
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(8)

              Rectangle {
                visible: !root.searchQuery
                height: Style.space(24)
                width: Style.space(100)
                radius: Style.space(4)
                color: Color.accent

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: root.isScanning ? "Scanning..." : "Scan Craigslist"
                  color: Color.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.triggerScan()
                }
              }

              Rectangle {
                visible: !root.searchQuery
                height: Style.space(24)
                width: Style.space(110)
                radius: Style.space(4)
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: "\uf120 Open CLI"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openTerminal()
                }
              }

              Rectangle {
                visible: root.searchQuery !== ""
                height: Style.space(24)
                width: Style.space(100)
                radius: Style.space(4)
                color: Color.accent

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: "Clear Filter"
                  color: Color.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.searchQuery = ""
                    root.searching = false
                    keyCatcher.forceActiveFocus()
                  }
                }
              }
            }
          }
        }

        // --------------------------------------------------------
        // FOOTER
        // --------------------------------------------------------
        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            text: "Updated: " + root.lastUpdated + (root.matchCount > 3 ? " · [j/k] Navigate · [Enter] Open" : "")
            color: root.mutedColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }

          Item {
            Layout.fillWidth: true
            width: parent.width - Style.space(210)
            height: 1
          }

          Rectangle {
            height: Style.space(24)
            width: Style.space(90)
            radius: Style.space(4)
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: "\uf120 Terminal [T]"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openTerminal()
            }
          }
        }
      }
    }
  }
}
