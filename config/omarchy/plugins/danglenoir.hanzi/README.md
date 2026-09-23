# Omarchy Daily Hanzi

An Omarchy Shell bar widget that teaches one Chinese character a day.

The bar shows **汉字**. Hover for today's character, pinyin, and meaning. Click the widget for components, example words, and a dictionary link. The refresh button (or a middle-click) gives you a different character for today.

## Requirements

- Omarchy 4.0 or newer with the Quickshell-based Omarchy Shell
- Node.js (v18 or newer)
- Internet access to `en.wiktionary.org`

Character data comes from the English Wiktionary Action API (CC BY-SA 4.0). There is no bundled dictionary.

## Install

Install and enable the plugin through Omarchy:

```bash
omarchy plugin add https://github.com/danglenoir/omarchy-hanzi.git --enable
```

The widget is added to the right section of the bar. Move it when needed:

```bash
omarchy bar move danglenoir.hanzi --section right
```

### Local development install

Omarchy rejects plugin folders that contain symlinks, so copy the checkout into the user plugin directory:

```bash
mkdir -p ~/.config/omarchy/plugins
rsync -a --delete --exclude .git "$PWD/" ~/.config/omarchy/plugins/danglenoir.hanzi/
omarchy-shell shell rescanPlugins
omarchy plugin enable danglenoir.hanzi
```

## Use

- **Hover** the bar mark to see today's hanzi, pinyin, and meaning.
- **Click** to open the panel.
- **Refresh** (`󰑐`, middle-click, or `R` in the panel) to study a different character today. Tomorrow returns to the hashed daily pick.
- **Copy** (`󰆏` or `C`) puts the character on the clipboard.
- **Look up on MDBG** opens the CC-CEDICT entry in your browser.

To inspect the adapter directly:

```bash
node ~/.config/omarchy/plugins/danglenoir.hanzi/Hanzi.js --pretty
node ~/.config/omarchy/plugins/danglenoir.hanzi/Hanzi.js --shuffle --pretty
node ~/.config/omarchy/plugins/danglenoir.hanzi/Hanzi.js --character 学 --pretty
```

Useful Omarchy checks:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/danglenoir.hanzi
omarchy plugin list --json
omarchy-shell shell rescanPlugins
```

Today's snapshot is cached in `~/.cache/omarchy-hanzi/`. If Wiktionary is temporarily unreachable, the panel keeps the last successful card and marks it as cached.

## Update

```bash
omarchy plugin update danglenoir.hanzi
```

## Uninstall

```bash
omarchy plugin remove danglenoir.hanzi
```

Optionally remove the cache:

```bash
rm -rf ~/.cache/omarchy-hanzi
```

For a local development symlink, disable the widget first, then remove the link:

```bash
omarchy plugin disable danglenoir.hanzi
rm ~/.config/omarchy/plugins/danglenoir.hanzi
omarchy-shell shell rescanPlugins
```

## License

MIT
