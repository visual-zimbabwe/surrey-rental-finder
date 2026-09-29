import QtQuick
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

  readonly property int matchCount: matches ? matches.length : 0
  readonly property string runnerPath: "/home/juwimana/surrey-rental-finder/run.sh"

  // UI styling properties
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color accentColor: Color.accent
  readonly property color mutedColor: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int panelWidth: Style.space(440)

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
    openBrowserProcess.command = ["xdg-open", url]
    openBrowserProcess.running = true
  }

  function openTerminal() {
    openTerminalProcess.command = ["omarchy-launch-tui", "--app-id=org.omarchy.surrey-rentals", root.runnerPath, "scan", "--show-all"]
    openTerminalProcess.running = true
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

  Process {
    id: openBrowserProcess
  }

  Process {
    id: openTerminalProcess
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
        return "󰋜 " + root.matchCount + " Match" + (root.matchCount === 1 ? "" : "es")
      }
      return "󰋜 323 Rent"
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

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var k = t.toLowerCase()
        if (k === "s") root.triggerScan()
        else if (k === "r") root.fetchMatches()
        else if (k === "t") root.openTerminal()
        else if (k === "a") root.toggleAcRequired()
        else if (k === "h") root.toggleAllowApartments()
      }

      Column {
        id: mainColumn
        width: parent.width
        spacing: Style.space(12)

        // HEADER HERO
        PanelHero {
          width: parent.width
          title: "Surrey 323 Rentals"
          meta: root.isScanning ? "Scanning Craigslist Surrey..." : "Bus 323 Corridor · " + (root.configData.min_bedrooms || 2) + "-" + (root.configData.max_bedrooms || 3) + " Bed · Max $" + Math.round(root.configData.max_price || 2000)
          foreground: root.fg
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: "󰋜"
              color: root.matchCount > 0 ? Color.accent : root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          trailingControl: Component {
            Row {
              spacing: Style.space(8)

              // Settings Gear Button
              Rectangle {
                width: Style.space(30)
                height: Style.space(30)
                radius: Style.space(6)
                color: root.showSettings ? Color.accent : (gearMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08))

                Text {
                  anchors.centerIn: parent
                  text: "⚙"
                  color: root.showSettings ? Color.background : root.fg
                  font.pixelSize: Style.font.title
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
                width: Style.space(80)
                height: Style.space(30)
                radius: Style.space(6)
                color: scanMouseArea.containsPress ? Qt.darker(Color.accent, 1.2) : (scanMouseArea.containsMouse ? Qt.lighter(Color.accent, 1.1) : Color.accent)

                Text {
                  anchors.centerIn: parent
                  text: root.isScanning ? "Scanning..." : "Scan Now"
                  color: Color.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                MouseArea {
                  id: scanMouseArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.triggerScan()
                }
              }
            }
          }
        }

        // INTERACTIVE FILTER CHIPS (Click to toggle!)
        Row {
          width: parent.width
          spacing: Style.space(6)

          // A/C Toggle Chip
          Rectangle {
            height: Style.space(24)
            width: acChipText.implicitWidth + Style.space(14)
            radius: Style.space(4)
            color: root.configData.require_ac ? Qt.rgba(0.2, 0.8, 0.4, 0.25) : Qt.rgba(1, 1, 1, 0.08)
            border.color: root.configData.require_ac ? Qt.rgba(0.3, 0.9, 0.5, 0.6) : "transparent"
            border.width: 1

            Text {
              id: acChipText
              anchors.centerIn: parent
              text: root.configData.require_ac ? "❄ A/C Required" : "❄ A/C Optional"
              color: root.configData.require_ac ? Qt.rgba(0.3, 0.9, 0.5, 1.0) : root.mutedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: root.configData.require_ac
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleAcRequired()
            }
          }

          // Housing Type Toggle Chip
          Rectangle {
            height: Style.space(24)
            width: typeChipText.implicitWidth + Style.space(14)
            radius: Style.space(4)
            color: !root.configData.allow_apartments ? Qt.rgba(0.2, 0.6, 1.0, 0.25) : Qt.rgba(1, 1, 1, 0.08)
            border.color: !root.configData.allow_apartments ? Qt.rgba(0.4, 0.8, 1.0, 0.6) : "transparent"
            border.width: 1

            Text {
              id: typeChipText
              anchors.centerIn: parent
              text: !root.configData.allow_apartments ? "🏡 House/Suite Only" : "🏢 All Types (incl Apt)"
              color: !root.configData.allow_apartments ? Qt.rgba(0.4, 0.8, 1.0, 1.0) : root.mutedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: !root.configData.allow_apartments
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleAllowApartments()
            }
          }

          // Max Price Chip
          Rectangle {
            height: Style.space(24)
            width: priceChipText.implicitWidth + Style.space(14)
            radius: Style.space(4)
            color: Qt.rgba(1, 1, 1, 0.08)

            Text {
              id: priceChipText
              anchors.centerIn: parent
              text: "💰 ≤ $" + Math.round(root.configData.max_price || 2000)
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showSettings = !root.showSettings
            }
          }

          // Walk Distance Chip
          Rectangle {
            height: Style.space(24)
            width: walkChipText.implicitWidth + Style.space(14)
            radius: Style.space(4)
            color: Qt.rgba(1, 1, 1, 0.08)

            Text {
              id: walkChipText
              anchors.centerIn: parent
              text: "🚌 ≤ " + Math.round(root.configData.max_walk_mins || 5) + "m"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showSettings = !root.showSettings
            }
          }
        }

        // EXPANDABLE SETTINGS DRAWER
        Rectangle {
          visible: root.showSettings
          width: parent.width
          implicitHeight: settingsCol.implicitHeight + Style.space(20)
          radius: Style.space(8)
          color: Qt.rgba(1, 1, 1, 0.06)
          border.color: Qt.rgba(1, 1, 1, 0.15)
          border.width: 1

          Column {
            id: settingsCol
            anchors.fill: parent
            anchors.margins: Style.space(12)
            spacing: Style.space(10)

            Text {
              text: "⚙ Live Filter Criteria Controls"
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
                text: "Max Monthly Rent:"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(130)
              }

              Rectangle {
                width: Style.space(28)
                height: Style.space(24)
                radius: Style.space(4)
                color: Qt.rgba(1, 1, 1, 0.1)
                Text { anchors.centerIn: parent; text: "-"; color: root.fg; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustPrice(-100) }
              }

              Text {
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
                width: Style.space(28)
                height: Style.space(24)
                radius: Style.space(4)
                color: Qt.rgba(1, 1, 1, 0.1)
                Text { anchors.centerIn: parent; text: "+"; color: root.fg; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustPrice(100) }
              }
            }

            // Walk Time Adjuster
            Row {
              width: parent.width
              spacing: Style.space(10)

              Text {
                text: "Max Walk to Bus 323:"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(130)
              }

              Rectangle {
                width: Style.space(28)
                height: Style.space(24)
                radius: Style.space(4)
                color: Qt.rgba(1, 1, 1, 0.1)
                Text { anchors.centerIn: parent; text: "-"; color: root.fg; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustWalkMins(-1) }
              }

              Text {
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
                width: Style.space(28)
                height: Style.space(24)
                radius: Style.space(4)
                color: Qt.rgba(1, 1, 1, 0.1)
                Text { anchors.centerIn: parent; text: "+"; color: root.fg; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustWalkMins(1) }
              }
            }
          }
        }

        // STATS BAR
        Rectangle {
          width: parent.width
          height: Style.space(34)
          radius: Style.space(6)
          color: Qt.rgba(1, 1, 1, 0.04)

          Row {
            anchors.centerIn: parent
            spacing: Style.space(16)

            Text {
              text: "Scanned: " + root.stats.total_scanned
              color: root.mutedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              text: "Near Route 323: " + root.stats.near_bus_323
              color: root.mutedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              text: "Matches: " + root.matchCount
              color: root.matchCount > 0 ? Color.accent : root.fg
              font.bold: root.matchCount > 0
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // LISTINGS CONTENT OR EMPTY STATE
        Column {
          width: parent.width
          spacing: Style.space(10)

          // If there are matches, show each match in a card
          Repeater {
            model: root.matches
            delegate: Rectangle {
              width: parent.width
              implicitHeight: cardCol.implicitHeight + Style.space(20)
              radius: Style.space(8)
              color: cardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.05)
              border.color: Qt.rgba(1, 1, 1, 0.12)
              border.width: 1

              MouseArea {
                id: cardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openUrl(modelData.url)
              }

              Column {
                id: cardCol
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(6)

                // Top row: Price and Badges
                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    text: "$" + Math.round(modelData.price) + "/mo"
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  Rectangle {
                    height: Style.space(20)
                    width: bedBathLabel.implicitWidth + Style.space(8)
                    radius: Style.space(4)
                    color: Qt.rgba(0.2, 0.6, 1.0, 0.2)
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      id: bedBathLabel
                      anchors.centerIn: parent
                      text: modelData.bedrooms + " Bed · " + (modelData.bathrooms || "1") + " Bath"
                      color: Qt.rgba(0.4, 0.8, 1.0, 1.0)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  Rectangle {
                    height: Style.space(20)
                    width: typeLabel.implicitWidth + Style.space(8)
                    radius: Style.space(4)
                    color: Qt.rgba(1, 1, 1, 0.1)
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      id: typeLabel
                      anchors.centerIn: parent
                      text: modelData.housing_type
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Rectangle {
                    height: Style.space(20)
                    width: acLabel.implicitWidth + Style.space(8)
                    radius: Style.space(4)
                    color: modelData.has_ac ? Qt.rgba(0.2, 0.8, 0.4, 0.2) : Qt.rgba(1, 1, 1, 0.08)
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      id: acLabel
                      anchors.centerIn: parent
                      text: modelData.has_ac ? "❄ A/C" : "No AC"
                      color: modelData.has_ac ? Qt.rgba(0.3, 0.9, 0.5, 1.0) : root.mutedColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: modelData.has_ac
                    }
                  }
                }

                // Title
                Text {
                  width: parent.width
                  text: modelData.title
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                  maximumLineCount: 1
                }

                // Nearest Bus 323 Stop & Walk Time
                Row {
                  width: parent.width
                  spacing: Style.space(6)
                  Text {
                    text: "🚌 " + (modelData.nearest_stop_name || "Route 323 Stop") + " (" + (modelData.walk_time_minutes ? modelData.walk_time_minutes.toFixed(1) : "?") + " min walk · " + (modelData.distance_meters ? Math.round(modelData.distance_meters) : "?") + "m)"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width - Style.space(80)
                  }

                  Text {
                    text: "Open ↗"
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }
            }
          }

          // EMPTY STATE (when no matches found)
          Rectangle {
            visible: root.matchCount === 0
            width: parent.width
            height: Style.space(130)
            radius: Style.space(8)
            color: Qt.rgba(1, 1, 1, 0.03)
            border.color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1

            Column {
              anchors.centerIn: parent
              spacing: Style.space(6)
              width: parent.width - Style.space(30)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No Live Matches Found"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Scanned " + root.stats.total_scanned + " listings in Surrey. Current postings did not match the active criteria above."
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
                  height: Style.space(26)
                  width: Style.space(110)
                  radius: Style.space(4)
                  color: Color.accent

                  Text {
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
                  height: Style.space(26)
                  width: Style.space(110)
                  radius: Style.space(4)
                  color: Qt.rgba(1, 1, 1, 0.1)

                  Text {
                    anchors.centerIn: parent
                    text: "Open Terminal CLI"
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

        // FOOTER
        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: "Updated: " + root.lastUpdated
            color: root.mutedColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }

          Item {
            Layout.fillWidth: true
            width: parent.width - Style.space(220)
            height: 1
          }

          Rectangle {
            height: Style.space(24)
            width: Style.space(90)
            radius: Style.space(4)
            color: Qt.rgba(1, 1, 1, 0.08)

            Text {
              anchors.centerIn: parent
              text: "Terminal [T]"
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
