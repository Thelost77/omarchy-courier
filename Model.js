var MAX_ITEMS = 20

function list(value) {
  return value && typeof value.length === "number" ? value : []
}

function codePoint(value) {
  var n = Number(value)
  if (!isFinite(n) || n < 0 || n > 0x10ffff) return ""
  if (n <= 0xffff) return String.fromCharCode(n)
  n -= 0x10000
  return String.fromCharCode(0xd800 + (n >> 10), 0xdc00 + (n & 0x3ff))
}

function decodeEntities(value) {
  return String(value || "")
    .replace(/&#x([0-9a-f]+);/gi, function(_, hex) { return codePoint(parseInt(hex, 16)) })
    .replace(/&#([0-9]+);/g, function(_, decimal) { return codePoint(parseInt(decimal, 10)) })
    .replace(/&quot;/gi, '"')
    .replace(/&apos;/gi, "'")
    .replace(/&nbsp;/gi, " ")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&amp;/gi, "&")
}

function plainText(value) {
  var text = String(value || "").replace(/<!\[CDATA\[([\s\S]*?)\]\]>/gi, "$1")
  for (var i = 0; i < 3; i++) {
    var next = decodeEntities(text).replace(/<[^>]*>/g, " ")
    if (next === text) break
    text = next
  }
  return text
    .replace(/\s+/g, " ")
    .replace(/\s+([.,!?;:])/g, "$1")
    .replace(/^\s+|\s+$/g, "")
}

function tagText(block, tag) {
  var match = String(block || "").match(new RegExp("<" + tag + "(?:\\s[^>]*)?>([\\s\\S]*?)</" + tag + ">", "i"))
  return match ? plainText(match[1]) : ""
}

function safeNewsLink(value) {
  var link = plainText(value)
  if (link.length > 2048 || /[\u0000-\u0020\u007f]/.test(link)) return ""

  var match = link.match(/^https:\/\/([^\/?#]+)(\/[^?#]*)?(?:\?[^#]*)?(?:#.*)?$/i)
  if (!match) return ""
  var host = match[1].toLowerCase()
  var path = match[2] || "/"
  if (host !== "omarchy.org" && host !== "www.omarchy.org") return ""
  if (path !== "/news" && path.indexOf("/news/") !== 0) return ""
  return link
}

function normalizeItem(value) {
  if (!value || typeof value !== "object") return null
  var link = safeNewsLink(value.link)
  var title = plainText(value.title)
  var id = plainText(value.id || link).slice(0, 1024)
  if (!link || !title || !id) return null

  var publishedMs = Number(value.publishedMs)
  if (!isFinite(publishedMs) || publishedMs < 0) publishedMs = 0

  return {
    id: id,
    title: title.slice(0, 300),
    link: link,
    summary: plainText(value.summary).slice(0, 600),
    publishedMs: publishedMs,
    read: value.read === true
  }
}

function sortItems(items) {
  return list(items).slice().sort(function(a, b) {
    var timeDiff = Number(b.publishedMs || 0) - Number(a.publishedMs || 0)
    if (timeDiff !== 0) return timeDiff
    return String(a.id || "").localeCompare(String(b.id || ""))
  })
}

function parseFeed(raw) {
  var xml = String(raw || "")
  if (!/<rss\b[^>]*>/i.test(xml) || !/<\/rss\s*>/i.test(xml)
      || !/<channel\b[^>]*>/i.test(xml) || !/<\/channel\s*>/i.test(xml)) return []

  var blocks = xml.match(/<item\b[^>]*>[\s\S]*?<\/item>/gi) || []
  var items = []
  var known = {}

  for (var i = 0; i < blocks.length; i++) {
    var block = blocks[i]
    var link = safeNewsLink(tagText(block, "link"))
    var title = tagText(block, "title")
    if (!link || !title) continue

    var id = tagText(block, "guid") || link
    var published = Date.parse(tagText(block, "pubDate"))
    var item = normalizeItem({
      id: id,
      title: title,
      link: link,
      summary: tagText(block, "description"),
      publishedMs: isFinite(published) ? published : 0,
      read: false
    })
    if (!item || known["$" + item.id]) continue
    known["$" + item.id] = true
    items.push(item)
  }

  return sortItems(items).slice(0, MAX_ITEMS)
}

function normalizeItems(items) {
  var normalized = []
  var known = {}
  var values = list(items)
  for (var i = 0; i < values.length; i++) {
    var item = normalizeItem(values[i])
    if (!item || known["$" + item.id]) continue
    known["$" + item.id] = true
    normalized.push(item)
  }
  return sortItems(normalized).slice(0, MAX_ITEMS)
}

function loadState(raw) {
  try {
    var state = JSON.parse(String(raw || ""))
    if (!state || state.version !== 1) throw new Error("unsupported state")
    return {
      initialized: state.initialized === true,
      lastRefreshMs: Math.max(0, Number(state.lastRefreshMs) || 0),
      items: normalizeItems(state.items)
    }
  } catch (e) {
    return { initialized: false, lastRefreshMs: 0, items: [] }
  }
}

function mergeFeed(cachedItems, fetchedItems, initialized, limit) {
  var cached = normalizeItems(cachedItems)
  var fetched = normalizeItems(fetchedItems)
  var byId = {}
  var combined = []
  var wasInitialized = initialized === true

  for (var i = 0; i < cached.length; i++) byId["$" + cached[i].id] = cached[i]

  for (var j = 0; j < fetched.length; j++) {
    var fresh = fetched[j]
    var previous = byId["$" + fresh.id]
    fresh.read = previous ? previous.read : (wasInitialized ? false : j !== 0)
    combined.push(fresh)
    delete byId["$" + fresh.id]
  }

  for (var k = 0; k < cached.length; k++) {
    if (byId["$" + cached[k].id]) {
      combined.push(cached[k])
      delete byId["$" + cached[k].id]
    }
  }

  var cap = Math.max(1, Number(limit) || MAX_ITEMS)
  return {
    initialized: fetched.length > 0 || wasInitialized,
    items: sortItems(combined).slice(0, cap)
  }
}

function unreadCount(items) {
  var count = 0
  var values = list(items)
  for (var i = 0; i < values.length; i++) if (values[i] && values[i].read !== true) count++
  return count
}

function markRead(items, id) {
  var values = normalizeItems(items)
  var target = String(id || "")
  for (var i = 0; i < values.length; i++) {
    if (values[i].id === target) values[i].read = true
  }
  return values
}

function markAllRead(items) {
  var values = normalizeItems(items)
  for (var i = 0; i < values.length; i++) values[i].read = true
  return values
}

function itemById(items, id) {
  var target = String(id || "")
  var values = list(items)
  for (var i = 0; i < values.length; i++) if (values[i] && values[i].id === target) return values[i]
  return null
}

function articleText(value) {
  return decodeEntities(String(value || "")
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<li\b[^>]*>/gi, "• ")
    .replace(/<\/li\s*>/gi, "\n")
    .replace(/<\/p\s*>/gi, "\n\n")
    .replace(/<\/(?:h[1-6]|blockquote|ul|ol|pre)\s*>/gi, "\n\n")
    .replace(/<[^>]*>/g, ""))
    .replace(/\r/g, "")
    .replace(/[ \t]+/g, " ")
    .replace(/ *\n */g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/^\s+|\s+$/g, "")
    .slice(0, 50000)
}

function contentForClass(html, tag, className) {
  var pattern = new RegExp("<" + tag + "\\b([^>]*)>([\\s\\S]*?)</" + tag + "\\s*>", "gi")
  var match
  while ((match = pattern.exec(String(html || ""))) !== null) {
    var classAttribute = match[1].match(/\bclass\s*=\s*(["'])(.*?)\1/i)
    if (!classAttribute) continue
    var classes = classAttribute[2].split(/\s+/)
    if (classes.indexOf(className) !== -1) return match[2]
  }
  return null
}

function parseArticle(raw) {
  var html = String(raw || "")
  if (!/<html\b[^>]*>/i.test(html) || !/<\/html\s*>/i.test(html)) return null

  var prose = contentForClass(html, "div", "news-prose")
  var title = contentForClass(html, "h1", "news-post__title")
  var meta = contentForClass(html, "p", "news-meta")
  if (prose === null || title === null) return null

  var body = articleText(prose)
  var cleanTitle = plainText(title).slice(0, 300)
  if (!body || !cleanTitle) return null

  return {
    title: cleanTitle,
    meta: meta === null ? "" : plainText(meta).slice(0, 200),
    body: body
  }
}

function relativeTime(timestamp, currentTime) {
  var time = Number(timestamp)
  var now = Number(currentTime)
  if (!isFinite(time) || time <= 0) return ""
  if (!isFinite(now) || now <= 0) now = Date.now()

  var seconds = Math.max(0, Math.floor((now - time) / 1000))
  if (seconds < 60) return "now"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h"
  var days = Math.floor(hours / 24)
  if (days < 7) return days + "d"

  var date = new Date(time)
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return date.getDate() + " " + months[date.getMonth()]
}

if (typeof module !== "undefined") {
  module.exports = {
    parseFeed: parseFeed,
    loadState: loadState,
    mergeFeed: mergeFeed,
    unreadCount: unreadCount,
    markRead: markRead,
    markAllRead: markAllRead,
    itemById: itemById,
    parseArticle: parseArticle,
    relativeTime: relativeTime,
    safeNewsLink: safeNewsLink,
    plainText: plainText
  }
}
