# OmaCourier

**News from the Omagods.**

OmaCourier is a quiet, keyboard-first inbox and reader for the official [Omarchy News](https://omarchy.org/news) feed.

The bar shows an outline envelope and the unread count. The compact panel lists the newest stories first, marks unread titles in bold, and opens each story in a plain-text reader.

## Install

```bash
omarchy plugin add https://github.com/Thelost77/omarchy-courier.git --enable
```

The widget defaults to the center section. If the built-in weather widget is enabled, place OmaCourier after it with:

```bash
omarchy bar move io.github.thelost77.omacourier --after omarchy.weather
```

## Remove

```bash
omarchy plugin remove io.github.thelost77.omacourier
```

## Controls

- Left or right click: open the news panel
- Middle click: refresh
- `j`/`k` or arrow keys: move through stories or scroll an article
- `Enter`: read the selected story; from the reader, open it in the browser
- `h`, `b`, or `Esc`: return from the reader to the story list
- `o`: open the current article in the browser
- `A`: mark every story read
- `r`: refresh the story list
- `Esc`: close from the story list

## Data and dependencies

The first refresh leaves only the newest current story unread. Later stories arrive unread. OmaCourier checks `https://omarchy.org/news/rss.xml` every 30 minutes and keeps the latest 20 stories in `~/.local/state/omacourier/cache.json`. It fetches article pages only from validated `https://omarchy.org/news/…` links when you select them.

OmaCourier requires Omarchy, Omarchy Shell, Bash, curl, and GNU coreutils. These tools are part of a standard Omarchy installation. Node.js is required only to run the tests.

The panel uses Omarchy color, font, spacing, state, and corner-radius tokens. It has no separate theme or settings.

## Test

```bash
./test/news-test.sh
omarchy plugin validate .
```

## License

[MIT](LICENSE)
