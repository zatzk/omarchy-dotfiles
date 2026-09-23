# ADHD Kit for Omarchy

Two small tools for ADHD brains, built as a native [Omarchy](https://omarchy.org) shell plugin (Omarchy 4 "Quattro" or later):

- **Visual Timer** — a Time Timer-style bar widget: the time you have left is a shrinking disc sector plus an `mm:ss` countdown, always in your peripheral vision. Built against time blindness: remaining time is a *shape*, not a number you have to go look up.
- **Big Timer** — the same timer as a fullscreen overlay, readable from across the room: a clock-face disc with minute graduations over a near-opaque scrim.
- **Quick Capture** — a summonable overlay: hit a key, type the thought, press Enter, it's appended to your inbox file with a timestamp. The thought is written down before the context switch can eat it.
- **Hyperfocus Guard** — a background service that notices when one app has held focus for hours and asks, gently, whether that's still on purpose. Not a blocker — a hand on the shoulder.

## Install

```bash
omarchy plugin add https://github.com/ya-luotao/omarchy-adhd-kit.git --enable
```

When prompted, pick a bar section for the timer (it defaults to `right`).

## Uninstall

```bash
omarchy plugin remove luotao.adhd-kit
```

This disables the timer widget and the hyperfocus guard and deletes the plugin files. If you added the keybindings below, remove them from `~/.config/hypr/bindings.lua`. Two optional leftovers you can delete by hand:

- `~/.local/state/omarchy/adhd-kit/` — timer state
- `~/.config/omarchy/adhd-kit.json` — hyperfocus guard config, if you created one

Your inbox file (`~/Documents/inbox.md` by default) is your data and is never touched.

## Keybindings

Add to `~/.config/hypr/bindings.lua`:

```lua
-- Quick capture: dump a thought into ~/Documents/inbox.md
o.bind("SUPER + SHIFT + I", "Quick capture", "omarchy-shell shell summon luotao.adhd-kit '{}'")

-- Fullscreen big timer
o.bind("SUPER + SHIFT + T", "Big timer",
  [[omarchy-shell shell summon luotao.adhd-kit '{"view": "timer"}']])
```

Custom inbox file:

```lua
o.bind("SUPER + SHIFT + I", "Quick capture",
  [[omarchy-shell shell summon luotao.adhd-kit '{"file": "~/notes/inbox.md"}']])
```

## Visual Timer

| Interaction | Effect |
|---|---|
| Left click | Open the control panel (presets, pause, ±5m, cancel) |
| Right click | Pause / resume |
| Middle click | Cancel |
| Scroll | Nudge a running timer ±1 minute |

In the panel: click a preset, or type minutes and press Enter. While a timer runs: `Space` pauses, `+`/`−` adjust by 5 minutes, `C` cancels.

The **big timer** (`summon` with `{"view": "timer"}`) is the same shared timer fullscreen — same presets, same keys, `Esc` or a click dismisses it. Start it from the couch, glance at it from the kitchen.

The last minute pulses in the theme's urgent color. When time is up you get a notification. Timers are shared across monitors and survive shell restarts (state lives in `~/.local/state/omarchy/adhd-kit/timer.json`); a timer that expires while the shell is down comes back as idle rather than firing a stale alarm.

From scripts:

```bash
omarchy-shell luotao.adhd-kit start 25
omarchy-shell luotao.adhd-kit pause
omarchy-shell luotao.adhd-kit resume
omarchy-shell luotao.adhd-kit cancel
omarchy-shell luotao.adhd-kit status   # {"state":"running","remainingSec":1493,...}
```

### Settings

Via `omarchy bar set`, or the widget entry in `~/.config/omarchy/shell.json`:

```bash
omarchy bar set luotao.adhd-kit presets "10,25,50"
omarchy bar set luotao.adhd-kit showLabel false   # disc only, no mm:ss text
```

## Quick Capture

Summon, type, Enter. Each capture appends one line to the inbox file:

```markdown
- [ ] 2026-08-22 14:31 email the landlord about the heater
```

- `Enter` — save and dismiss
- `Shift+Enter` — save and keep capturing
- `Esc` — clear the text, or dismiss if already empty

## Hyperfocus Guard

Runs automatically once the plugin is enabled. A *streak* is wall-clock time since an app took focus; quick detours to other windows (up to `graceMinutes`) neither reset nor pause it, staying away longer adopts the new app, and going idle (AFK) resets it. At `thresholdMinutes` you get a notification, repeated every `repeatMinutes` while the streak continues.

Configure in `~/.config/omarchy/adhd-kit.json` (hot-reloads on save; every key optional):

```json
{
  "hyperfocus": {
    "enabled": true,
    "thresholdMinutes": 90,
    "repeatMinutes": 30,
    "graceMinutes": 5,
    "idleResetMinutes": 10,
    "ignore": ["mpv", "vlc"]
  }
}
```

`ignore` matches app ids case-insensitively — movies aren't hyperfocus.

```bash
omarchy-shell luotao.adhd-kit.guard status     # what it's tracking right now
omarchy-shell luotao.adhd-kit.guard snooze 45  # quiet for 45 minutes
omarchy-shell luotao.adhd-kit.guard reset      # start the streak over
```

## How it works

The bar widget, the big timer and any other surface share one state file
(`~/.local/state/omarchy/adhd-kit/timer.json`), so an action anywhere shows up
everywhere; the hyperfocus guard is a background service that watches the
active window and the idle monitor. Both are pure-JS models (`TimerModel.js`,
`GuardModel.js`) with QML on top, so the logic is testable without a shell.

Three things reach the plugin from outside it, and `Safe.js` is where each is
bounded before it is stored or shown: **window app ids** (every Wayland client
picks its own, so one is bounded on intake and stripped of anything a
notification daemon would read as Pango markup before it goes in a
notification body), **summon payloads** (`omarchy-shell shell summon` carries
JSON from any local process, so a capture path with control characters or an
absurd length is refused in favour of the default inbox rather than quietly
rewritten), and **the state and config files** (read through a
bounded `head -c` helper rather than QML's `FileView`, so an oversized file
cannot be retained by the long-lived shell in the first place, and refused
whole rather than parsed on top of that). Every `Text` in the plugin is
`Text.PlainText`, so nothing rendered — including the thought you are typing —
is ever interpreted as markup.

## Development

```sh
./test/model-test.sh        # Node tests for Safe.js, TimerModel.js, GuardModel.js
./test/read-test.sh         # runs the bounded read against a 300 MB state file
omarchy plugin validate .   # manifest and entry-point checks
```

`test/fileview-probe.qml` documents why the state and config files are read
through a bounded helper process rather than QML's `FileView` — which hands the
shell the whole file before any cap in `Safe.js` could apply — and why the
`FileView` that remains as a change notifier needs both `preload: false` and
`blockAllReads: true`. Run it with `PROBE_FILE=<huge file> qs -p
test/fileview-probe.qml`.

Symlinking a checkout into `~/.config/omarchy/plugins/` is the quickest way to
iterate. If a change does not seem to take, clear Quickshell's stale compile
cache: `rm -rf ~/.cache/quickshell/qmlcache && omarchy restart shell`.

## Roadmap

- Transition warnings off the calendar (15/5/1 minutes, escalating)

## License

MIT
