#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v node >/dev/null
bash -n "$root/bin/omarchy-news-feed"
bash -n "$root/bin/omarchy-news-article"
if "$root/bin/omarchy-news-article" "https://example.com/news/2026/09/story" >/dev/null 2>&1; then
  echo "not ok - article helper rejects non-Omarchy URLs" >&2
  exit 1
fi

ROOT="$root" node <<'JS'
const fs = require('fs')
const path = require('path')
const root = process.env.ROOT
const news = require(path.join(root, 'Model.js'))

function assert(condition, description) {
  if (!condition) {
    console.error(`not ok - ${description}`)
    process.exit(1)
  }
  console.log(`ok - ${description}`)
}

const feed = `<?xml version="1.0"?>
<rss version="2.0"><channel>
  <item>
    <title><![CDATA[Older &amp; stable]]></title>
    <link>https://omarchy.org/news/2026/08/older</link>
    <guid>older</guid>
    <pubDate>Mon, 31 Aug 2026 10:00:00 GMT</pubDate>
    <description><![CDATA[<p>An older summary.</p>]]></description>
  </item>
  <item>
    <title>Newest &lt;strong&gt;story&lt;/strong&gt;</title>
    <link>https://omarchy.org/news/2026/09/newest</link>
    <guid>newest</guid>
    <pubDate>Thu, 03 Sep 2026 19:45:00 GMT</pubDate>
    <description><![CDATA[The newest <em>summary</em>.]]></description>
  </item>
  <item>
    <title>Unsafe story</title>
    <link>https://example.com/not-omarchy</link>
    <guid>unsafe</guid>
    <pubDate>Fri, 04 Sep 2026 10:00:00 GMT</pubDate>
  </item>
</channel></rss>`

const parsed = news.parseFeed(feed)
assert(parsed.length === 2, 'parser keeps only valid Omarchy News entries')
assert(parsed[0].id === 'newest' && parsed[1].id === 'older', 'parser sorts stories newest first')
assert(parsed[0].title === 'Newest story', 'parser emits plain title text')
assert(parsed[0].summary === 'The newest summary.', 'parser emits a plain summary')
assert(parsed[1].title === 'Older & stable', 'parser decodes XML entities')
assert(news.parseFeed(feed.replace('</rss>', '')).length === 0, 'parser rejects a truncated RSS document')
assert(
  !news.safeNewsLink('file:///tmp/story')
    && !news.safeNewsLink('https://example.com/story')
    && !news.safeNewsLink('https://omarchy.org/news/story\nhttps://example.com'),
  'links stay on the official HTTPS news origin'
)

const first = news.mergeFeed([], parsed, false, 20)
assert(first.initialized, 'first successful refresh initializes the inbox')
assert(news.unreadCount(first.items) === 1 && !first.items[0].read && first.items[1].read, 'first refresh leaves only the newest story unread')

const read = news.markRead(first.items, 'newest')
assert(news.unreadCount(read) === 0, 'opening a story can mark it read')

const nextFeed = news.parseFeed(feed.replace(
  '<channel>',
  `<channel><item><title>Brand new</title><link>https://omarchy.org/news/2026/09/brand-new</link><guid>brand-new</guid><pubDate>Fri, 04 Sep 2026 10:00:00 GMT</pubDate><description>Fresh.</description></item>`
))
const second = news.mergeFeed(read, nextFeed, true, 20)
assert(second.items[0].id === 'brand-new' && !second.items[0].read, 'later refreshes put unseen stories at the top as unread')
assert(second.items.find(item => item.id === 'newest').read, 'later refreshes preserve existing read state')
assert(news.unreadCount(news.markAllRead(second.items)) === 0, 'mark all read clears the unread count')

const partial = news.mergeFeed(second.items, [nextFeed[0]], true, 20)
assert(partial.items.some(item => item.id === 'older'), 'a partial feed response does not discard cached stories')

const saved = news.loadState(JSON.stringify({ version: 1, initialized: true, lastRefreshMs: 42, items: second.items }))
assert(saved.initialized && saved.lastRefreshMs === 42 && saved.items.length === 3, 'cache state survives a shell restart')
assert(news.loadState('not json').items.length === 0, 'invalid cache state fails closed')
assert(news.relativeTime(1000, 61000) === '1m', 'relative timestamps use compact labels')

const articleHtml = `<!doctype html><html><body><article class="news-post">
<p data-kind="byline" class="news-meta muted">By <a href="https://dhh.dk">DHH</a> on September 3, 2026</p>
<h1 id="story-title" class="featured news-post__title">A readable &amp; useful story</h1>
<div data-kind="article" class="flow news-prose">
<p>First paragraph with <code>&lt;code&gt;</code>.</p>
<ul><li>One item</li><li>Another item</li></ul>
</div></article></body></html>`
const article = news.parseArticle(articleHtml)
assert(article && article.title === 'A readable & useful story', 'article parser extracts a plain title')
assert(article.meta === 'By DHH on September 3, 2026', 'article parser tolerates attribute order and extra classes')
assert(article.body.includes('First paragraph with <code>.') && article.body.includes('• One item'), 'article parser preserves readable paragraphs and lists')
assert(news.parseArticle(articleHtml.replace('</html>', '')) === null, 'article parser rejects truncated HTML')

// Reduced from https://omarchy.org/news/2026/09/omarchy-org-redesign-launches-with-29-languages/
const redesignedHtml = `<!DOCTYPE html><html lang="en"><body><div class="flex min-h-dvh flex-col">
<header><h1>Omarchy</h1><p>Site navigation</p></header><div class="prose">Not the article</div>
<div id="main"><main><header><p>News</p></header><article><header>
<p class="font-mono text-xs text-text-muted">By<!-- --> <a href="https://dhh.dk" rel="author" class="text-text-secondary">DHH</a> <!-- -->on<!-- --> <time dateTime="2026-09-07T20:15:00+02:00">September 7, 2026</time></p>
<h1 class="mt-2 text-3xl font-semibold tracking-tight text-text">Omarchy.org redesign launches with 29 languages</h1>
</header><div class="prose mt-8"><p>The website for a beautiful, fun Linux distribution ought to be beautiful and fun too.</p>
<p>So pick a theme. Poke the pixels. Computers should be fun!</p></div></article>
<footer><p>More news</p></footer></main></div></div></body></html>`
const redesigned = news.parseArticle(redesignedHtml)
assert(redesigned && redesigned.title === 'Omarchy.org redesign launches with 29 languages', 'article parser reads the redesigned news page title')
assert(redesigned.meta === 'By DHH on September 7, 2026', 'article parser reads the redesigned byline and date')
assert(redesigned.body === 'The website for a beautiful, fun Linux distribution ought to be beautiful and fun too.\n\nSo pick a theme. Poke the pixels. Computers should be fun!', 'article parser reads the complete prose without site navigation or footer text')
assert(news.parseArticle(redesignedHtml.replace(/<article>[\s\S]*?<\/article>/, '')) === null, 'article parser rejects non-article pages')
assert(news.parseArticle(redesignedHtml.replace('</article>', '')) === null, 'article parser rejects an unclosed article')
assert(news.parseArticle(redesignedHtml.replace(/<h1 class="mt-2[^>]*>[\s\S]*?<\/h1>/, '')) === null, 'article parser rejects a missing article title')
assert(news.parseArticle(redesignedHtml.replace('class="prose mt-8"', 'class="not-prose"')) === null, 'article parser rejects a missing article body')
assert(news.parseArticle(redesignedHtml.replace(/<div class="prose mt-8">[\s\S]*?<\/div>/, '<div class="prose mt-8"></div>')) === null, 'article parser rejects an empty article body')

const bar = fs.readFileSync(path.join(root, 'BarWidget.qml'), 'utf8')
const panel = fs.readFileSync(path.join(root, 'Panel.qml'), 'utf8')
const articleView = fs.readFileSync(path.join(root, 'ArticleView.qml'), 'utf8')
const service = fs.readFileSync(path.join(root, 'Service.qml'), 'utf8')
const helper = fs.readFileSync(path.join(root, 'bin/omarchy-news-feed'), 'utf8')
const articleHelper = fs.readFileSync(path.join(root, 'bin/omarchy-news-article'), 'utf8')
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json'), 'utf8'))
const offsetUses = bar.match(/anchors\.verticalCenterOffset: root\.iconVerticalOffset/g) || []
assert(manifest.id === 'io.github.thelost77.omacourier' && manifest.name === 'OmaCourier' && manifest.barWidget.defaultSection === 'center', 'manifest has the final identity and default placement')
assert(bar.includes('text: ""') && bar.includes('Color.accent') && bar.includes('readonly property real iconVerticalOffset:') && offsetUses.length === 2, 'bar applies one tunable optical offset to both envelope layouts')
assert(panel.includes('Color.popups.text') && panel.includes('Style.font.') && panel.includes('Style.spacing.'), 'panel follows Omarchy color, type, and spacing tokens')
assert(panel.includes('text: "Mark all read"') && panel.includes('font.bold: !storyDelegate.modelData.read'), 'panel exposes mark all read and bold unread stories')
assert(panel.includes('j/k move  ·  Enter read  ·  A mark all  ·  r refresh'), 'story list includes a subtle keyboard hint')
assert(articleView.includes('text: "ARTICLE"') && articleView.includes('textFormat: Text.PlainText'), 'panel has a plain-text article reader')
assert(articleView.includes('j/k scroll  ·  h back  ·  o browser'), 'article reader includes a subtle keyboard hint')
assert(service.includes('readonly property int refreshMinutes: 30') && service.includes('function loadArticle(id)'), 'service refreshes the feed and loads selected articles')
assert(helper.includes('https://omarchy.org/news/rss.xml') && helper.includes('--max-filesize'), 'feed helper has one fixed bounded HTTPS source')
assert(articleHelper.includes('omarchy\\.org/news/') && articleHelper.includes('--max-filesize'), 'article helper accepts only bounded official news pages')
JS
