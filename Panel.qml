import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

KeyboardPanel {
  id: panel

  property var host: null
  readonly property var svc: host ? host.svc : null
  readonly property var stories: svc ? svc.items : []
  readonly property color foreground: Color.popups.text

  property int cursor: 0
  property bool cursorActive: false
  property real now: Date.now()
  property string readingId: ""
  readonly property bool showingArticle: readingId !== ""

  contentWidth: fittedContentWidth(Style.space(400))
  contentHeight: cappedContentHeight(Style.space(460))
  focusTarget: keyCatcher

  onOpenChanged: {
    if (!open) return
    panel.cursor = 0
    panel.cursorActive = false
    panel.readingId = ""
    panel.now = Date.now()
    storyList.positionViewAtBeginning()
  }

  onStoriesChanged: {
    if (stories.length === 0) panel.cursor = 0
    else if (panel.cursor >= stories.length) panel.cursor = stories.length - 1
  }

  function moveCursor(delta) {
    if (stories.length === 0) return
    panel.cursorActive = true
    panel.cursor = Math.max(0, Math.min(stories.length - 1, panel.cursor + delta))
    storyList.positionViewAtIndex(panel.cursor, ListView.Contain)
  }

  function openStory(index) {
    if (!panel.svc || index < 0 || index >= stories.length) return
    panel.cursor = index
    if (panel.svc.articleLoading) {
      panel.readingId = panel.svc.articleId
      return
    }
    var id = stories[index].id
    if (panel.svc.loadArticle(id)) panel.readingId = id
  }

  function showList() {
    panel.readingId = ""
    storyList.positionViewAtIndex(panel.cursor, ListView.Contain)
  }

  function openInBrowser() {
    if (panel.svc && panel.readingId !== "") panel.svc.openItem(panel.readingId)
  }

  function markAllRead() {
    if (panel.svc) panel.svc.markAllRead()
  }

  function refresh() {
    if (panel.svc) panel.svc.refresh()
  }

  function footerText() {
    if (!panel.svc) return "Starting…"
    if (panel.svc.refreshing) return "Refreshing…"
    if (panel.svc.lastError !== "") return panel.svc.lastError
    if (panel.svc.lastRefreshMs > 0) {
      var age = Model.relativeTime(panel.svc.lastRefreshMs, panel.now)
      return age === "now" ? "Updated just now" : "Updated " + age + " ago"
    }
    return "Waiting for the first refresh"
  }

  Item {
    anchors.fill: parent

    Timer {
      interval: 60000
      running: panel.open
      repeat: true
      onTriggered: panel.now = Date.now()
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (panel.showingArticle) {
          if (dx < 0) panel.showList()
          else if (dy !== 0) articleView.scrollBy(dy)
        } else if (dy !== 0) {
          panel.moveCursor(dy)
        } else if (dx > 0) {
          panel.openStory(panel.cursor)
        }
      }
      onActivateRequested: {
        if (panel.showingArticle) panel.openInBrowser()
        else panel.openStory(panel.cursor)
      }
      onCloseRequested: {
        if (panel.showingArticle) panel.showList()
        else panel.close()
      }
      onTabRequested: function(direction) {
        if (panel.host) panel.host.switchPanel(direction)
      }
      onTextKey: function(text) {
        if (panel.showingArticle) {
          if (text === "o" || text === "O") panel.openInBrowser()
          else if (text === "b" || text === "B") panel.showList()
        } else if (text === "r" || text === "R") {
          panel.refresh()
        } else if (text === "A") {
          panel.markAllRead()
        }
      }
    }

    Item {
      id: header
      anchors.top: parent.top
      visible: !panel.showingArticle
      anchors.left: parent.left
      anchors.right: parent.right
      height: Math.max(headerLabels.implicitHeight, markAllButton.implicitHeight)

      Column {
        id: headerLabels
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        Text {
          text: "NEWS"
          textFormat: Text.PlainText
          color: panel.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          font.letterSpacing: 1.1
        }

        Text {
          text: panel.svc ? panel.svc.unreadCount + " unread" : "Starting…"
          textFormat: Text.PlainText
          color: panel.foreground
          opacity: 0.58
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Button {
        id: markAllButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: panel.svc && panel.svc.unreadCount > 0
        text: "Mark all read"
        foreground: panel.foreground
        fontFamily: Style.font.family
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.spacing.lg
        verticalPadding: Style.spacing.sm
        onClicked: panel.markAllRead()
      }
    }

    PanelSeparator {
      id: headerRule
      anchors.top: header.bottom
      visible: !panel.showingArticle
      anchors.topMargin: Style.spacing.xl
      foreground: panel.foreground
    }

    ListView {
      id: storyList
      anchors.top: headerRule.bottom
      visible: !panel.showingArticle
      anchors.bottom: footerRule.top
      anchors.topMargin: Style.spacing.sm
      anchors.bottomMargin: Style.spacing.sm
      anchors.left: parent.left
      anchors.right: parent.right
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: panel.stories
      currentIndex: panel.cursor
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      delegate: Item {
        id: storyDelegate
        required property var modelData
        required property int index

        width: storyList.width
        height: storySurface.implicitHeight + storyRule.height

        CursorSurface {
          id: storySurface
          width: parent.width
          implicitHeight: storyContent.implicitHeight + Style.spacing.xl * 2
          hasCursor: panel.cursorActive && panel.cursor === storyDelegate.index
          foreground: panel.foreground

          Column {
            id: storyContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.xl
            anchors.rightMargin: Style.spacing.xl
            spacing: Style.spacing.sm

            Item {
              width: parent.width
              height: Math.max(storyTitle.implicitHeight, storyTime.implicitHeight)

              Text {
                id: storyTime
                anchors.top: parent.top
                anchors.right: parent.right
                text: Model.relativeTime(storyDelegate.modelData.publishedMs, panel.now)
                textFormat: Text.PlainText
                color: panel.foreground
                opacity: 0.52
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                id: storyTitle
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: storyTime.left
                anchors.rightMargin: Style.spacing.lg
                text: storyDelegate.modelData.title
                textFormat: Text.PlainText
                color: panel.foreground
                opacity: storyDelegate.modelData.read ? 0.76 : 1
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: !storyDelegate.modelData.read
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }
            }

            Text {
              visible: text !== ""
              width: parent.width
              text: storyDelegate.modelData.summary
              textFormat: Text.PlainText
              color: panel.foreground
              opacity: storyDelegate.modelData.read ? 0.46 : 0.60
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            onEntered: {
              panel.cursorActive = true
              panel.cursor = storyDelegate.index
            }
            onClicked: panel.openStory(storyDelegate.index)
          }
        }

        PanelSeparator {
          id: storyRule
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          foreground: panel.foreground
          strength: 0.08
        }
      }

      Text {
        anchors.centerIn: parent
        visible: storyList.count === 0
        text: panel.svc && panel.svc.lastError !== ""
          ? "No cached news"
          : "Fetching Omarchy News…"
        textFormat: Text.PlainText
        color: panel.foreground
        opacity: 0.56
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    PanelSeparator {
      id: footerRule
      anchors.bottom: footer.top
      visible: !panel.showingArticle
      anchors.bottomMargin: Style.spacing.sm
      foreground: panel.foreground
    }

    Item {
      id: footer
      anchors.left: parent.left
      visible: !panel.showingArticle
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Math.max(footerInfo.implicitHeight, refreshButton.implicitHeight)

      Column {
        id: footerInfo
        anchors.left: parent.left
        anchors.right: refreshButton.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        Text {
          id: footerStatus
          width: parent.width
          text: panel.footerText()
          textFormat: Text.PlainText
          color: panel.foreground
          opacity: 0.52
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: "j/k move  ·  l/Enter read  ·  A mark all  ·  r refresh"
          textFormat: Text.PlainText
          color: panel.foreground
          opacity: 0.34
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        id: refreshButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        enabled: panel.svc && !panel.svc.refreshing
        iconText: ""
        tooltipText: "Refresh"
        foreground: panel.foreground
        fontFamily: Style.font.family
        fontSize: Style.font.bodySmall
        size: Style.space(20)
        onClicked: panel.refresh()
      }
    }

    ArticleView {
      id: articleView
      anchors.fill: parent
      visible: panel.showingArticle
      service: panel.svc
      foreground: panel.foreground
      articleId: panel.readingId
      onBackRequested: panel.showList()
      onOpenBrowserRequested: panel.openInBrowser()
      onRetryRequested: {
        if (panel.svc) panel.svc.loadArticle(panel.readingId)
      }
    }
  }
}
