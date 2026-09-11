import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root

  required property var service
  required property color foreground
  property string articleId: ""

  readonly property var article: service && service.article && service.article.id === articleId
    ? service.article
    : null
  readonly property bool loading: service && service.articleId === articleId && service.articleLoading
  readonly property string errorText: service && service.articleId === articleId ? service.articleError : ""

  signal backRequested()
  signal openBrowserRequested()
  signal retryRequested()

  onArticleIdChanged: resetScroll()
  onArticleChanged: resetScroll()

  function maxContentY() {
    return Math.max(0, articleFlick.contentHeight - articleFlick.height)
  }

  function clampContentY(y) {
    return Math.max(0, Math.min(maxContentY(), y))
  }

  function resetScroll() {
    scrollAnim.stop()
    articleFlick.contentY = 0
  }

  function animateContentY(next) {
    next = clampContentY(next)
    articleFlick.cancelFlick()
    if (Math.abs(next - articleFlick.contentY) < 0.5) {
      scrollAnim.stop()
      articleFlick.contentY = next
      return
    }
    scrollAnim.stop()
    scrollAnim.from = articleFlick.contentY
    scrollAnim.to = next
    scrollAnim.start()
  }

  function scrollBy(direction) {
    var base = scrollAnim.running ? scrollAnim.to : articleFlick.contentY
    animateContentY(base + direction * Style.space(48))
  }

  NumberAnimation {
    id: scrollAnim
    target: articleFlick
    property: "contentY"
    duration: 140
    easing.type: Easing.OutCubic
  }

  Item {
    id: readerHeader
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(backButton.implicitHeight, browserButton.implicitHeight, readerLabel.implicitHeight)

    PanelActionButton {
      id: backButton
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      iconText: ""
      tooltipText: "Back to news"
      foreground: root.foreground
      fontFamily: Style.font.family
      fontSize: Style.font.bodySmall
      size: Style.space(20)
      onClicked: root.backRequested()
    }

    Text {
      id: readerLabel
      anchors.left: backButton.right
      anchors.leftMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      text: "ARTICLE"
      textFormat: Text.PlainText
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      font.letterSpacing: 1.1
    }

    PanelActionButton {
      id: browserButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      enabled: root.articleId !== ""
      iconText: ""
      tooltipText: "Open in browser"
      foreground: root.foreground
      fontFamily: Style.font.family
      fontSize: Style.font.bodySmall
      size: Style.space(20)
      onClicked: root.openBrowserRequested()
    }
  }

  PanelSeparator {
    id: readerRule
    anchors.top: readerHeader.bottom
    anchors.topMargin: Style.spacing.lg
    foreground: root.foreground
  }

  Flickable {
    id: articleFlick
    anchors.top: readerRule.bottom
    anchors.topMargin: Style.spacing.xl
    anchors.bottom: readerHint.top
    anchors.bottomMargin: Style.spacing.sm
    anchors.left: parent.left
    anchors.right: parent.right
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    contentWidth: width
    contentHeight: articleColumn.implicitHeight
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    WheelHandler {
      onWheel: function(event) {
        if (event.pixelDelta.y !== 0) {
          scrollAnim.stop()
          articleFlick.cancelFlick()
          articleFlick.contentY = root.clampContentY(articleFlick.contentY - event.pixelDelta.y)
          event.accepted = true
          return
        }
        if (event.angleDelta.y === 0) return
        var base = scrollAnim.running ? scrollAnim.to : articleFlick.contentY
        root.animateContentY(base - event.angleDelta.y / 120 * Style.space(48))
        event.accepted = true
      }
    }

    Column {
      id: articleColumn
      width: articleFlick.width - Style.spacing.lg
      spacing: Style.spacing.lg
      visible: root.article !== null

      Text {
        width: parent.width
        text: root.article ? root.article.title : ""
        textFormat: Text.PlainText
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        text: root.article ? root.article.meta : ""
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.56
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      PanelSeparator {
        width: parent.width
        foreground: root.foreground
        strength: 0.10
      }

      Text {
        width: parent.width
        text: root.article ? root.article.body : ""
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.88
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        lineHeight: 1.38
        lineHeightMode: Text.ProportionalHeight
      }
    }
  }

  Text {
    id: readerHint
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    text: "j/k scroll  ·  h back  ·  o browser"
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.34
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  Text {
    anchors.centerIn: articleFlick
    visible: root.loading
    text: "Fetching article…"
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.58
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  Column {
    anchors.centerIn: articleFlick
    visible: !root.loading && root.article === null && root.errorText !== ""
    width: Math.min(articleFlick.width, Style.space(260))
    spacing: Style.spacing.lg

    Text {
      width: parent.width
      text: root.errorText
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.64
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    Button {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Try again"
      foreground: root.foreground
      fontFamily: Style.font.family
      fontSize: Style.font.bodySmall
      horizontalPadding: Style.spacing.lg
      verticalPadding: Style.spacing.sm
      onClicked: root.retryRequested()
    }
  }
}
