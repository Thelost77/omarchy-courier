import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: ""

  readonly property string moduleId: "io.github.thelost77.omacourier"
  readonly property int maxItems: 20
  readonly property int refreshMinutes: 30

  property string stateDir: ""
  property string helperPath: ""
  property string articleHelperPath: ""
  property var items: []
  property bool initialized: false
  property bool ready: false
  property bool refreshing: false
  property real lastRefreshMs: 0
  property string lastError: ""

  property string articleId: ""
  property bool articleLoading: false
  property string articleError: ""
  property var article: null

  readonly property int unreadCount: Model.unreadCount(items)

  Component.onCompleted: bootstrapTimer.start()

  function pluginDir() {
    if (root.manifest && root.manifest.__sourceDir)
      return String(root.manifest.__sourceDir).replace(/\/$/, "")
    return (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/" + root.moduleId
  }

  function bootstrap() {
    var home = Quickshell.env("HOME") || ""
    var stateHome = Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
    root.stateDir = stateHome + "/omacourier"
    root.helperPath = pluginDir() + "/bin/omarchy-news-feed"
    root.articleHelperPath = pluginDir() + "/bin/omarchy-news-article"
    mkdirProc.command = ["bash", "-c", "umask 077; mkdir -p \"$1\"; chmod 700 \"$1\"", "_", root.stateDir]
    mkdirProc.running = true
  }

  function finishCacheLoad() {
    if (root.ready || root.stateDir === "") return
    root.ready = true
    Qt.callLater(root.refresh)
  }

  function refresh() {
    if (!root.ready || root.refreshing || root.helperPath === "") return
    root.refreshing = true
    refreshProc.running = true
  }

  function saveNow() {
    if (!root.ready || root.stateDir === "") return
    cacheFile.setText(JSON.stringify({
      version: 1,
      initialized: root.initialized,
      lastRefreshMs: root.lastRefreshMs,
      items: root.items
    }) + "\n")
    secureTimer.restart()
  }

  function markRead(id) {
    var item = Model.itemById(root.items, id)
    if (!item || item.read === true) return
    root.items = Model.markRead(root.items, id)
    root.saveNow()
  }

  function markAllRead() {
    if (root.unreadCount === 0) return
    root.items = Model.markAllRead(root.items)
    root.saveNow()
  }

  function openItem(id) {
    var item = Model.itemById(root.items, id)
    if (!item || !Model.safeNewsLink(item.link)) return false
    Quickshell.execDetached(["omarchy-launch-browser", item.link])
    root.markRead(id)
    return true
  }

  function loadArticle(id) {
    var item = Model.itemById(root.items, id)
    if (!item || !Model.safeNewsLink(item.link) || root.articleHelperPath === "") return false
    if (root.articleLoading) return root.articleId === id

    root.markRead(id)
    root.articleId = id
    root.articleError = ""
    if (root.article && root.article.id === id) return true

    root.article = null
    root.articleLoading = true
    articleProc.command = [root.articleHelperPath, item.link]
    articleProc.running = true
    return true
  }

  Timer {
    id: bootstrapTimer
    interval: 0
    repeat: false
    onTriggered: root.bootstrap()
  }

  Process {
    id: mkdirProc
    running: false
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = "Could not create the news cache"
        return
      }
      cacheFile.path = root.stateDir + "/cache.json"
      cacheFile.reload()
    }
  }

  FileView {
    id: cacheFile
    path: ""
    watchChanges: false
    atomicWrites: true
    printErrors: false

    onLoaded: {
      if (root.stateDir === "") return
      var state = Model.loadState(text())
      root.items = state.items
      root.initialized = state.initialized
      root.lastRefreshMs = state.lastRefreshMs
      root.finishCacheLoad()
    }

    onLoadFailed: {
      if (root.stateDir === "") return
      root.items = []
      root.initialized = false
      root.lastRefreshMs = 0
      root.finishCacheLoad()
    }
  }

  Process {
    id: articleProc
    running: false
    command: []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseArticle(text)
        var item = Model.itemById(root.items, root.articleId)
        root.articleLoading = false
        if (!parsed || !item) {
          root.article = null
          root.articleError = "Could not fetch this article"
          return
        }

        root.article = {
          id: root.articleId,
          link: item.link,
          title: parsed.title,
          meta: parsed.meta,
          body: parsed.body
        }
        root.articleError = ""
      }
    }
  }

  Process {
    id: refreshProc
    running: false
    command: root.helperPath === "" ? [] : [root.helperPath]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var fetched = Model.parseFeed(text)
        root.refreshing = false
        if (fetched.length === 0) {
          root.lastError = "Could not refresh · showing cached news"
          return
        }

        var merged = Model.mergeFeed(root.items, fetched, root.initialized, root.maxItems)
        root.items = merged.items
        root.initialized = merged.initialized
        root.lastRefreshMs = Date.now()
        root.lastError = ""
        root.saveNow()
      }
    }
  }

  Timer {
    interval: root.refreshMinutes * 60 * 1000
    running: root.ready
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: secureTimer
    interval: 250
    repeat: false
    onTriggered: {
      secureProc.command = ["bash", "-c", "chmod 600 \"$1/cache.json\" 2>/dev/null || true", "_", root.stateDir]
      secureProc.running = true
    }
  }

  Process {
    id: secureProc
    running: false
  }
}
