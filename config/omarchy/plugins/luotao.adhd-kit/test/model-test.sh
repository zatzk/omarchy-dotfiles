#!/bin/bash

# Node tests for the plugin's pure JS: Safe.js (bounds and sanitising for
# everything that arrives from outside the plugin), TimerModel.js, and
# GuardModel.js. Mirrors the shape of Omarchy's test/shell.d tests so the
# files could move upstream unchanged.

set -e

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export ROOT

command -v node >/dev/null || { echo "not ok - node is required" >&2; exit 1; }

node <<'JS'
const path = require('path')
const root = process.env.ROOT
const Safe = require(path.join(root, 'Safe.js'))
const Timer = require(path.join(root, 'TimerModel.js'))
const Guard = require(path.join(root, 'GuardModel.js'))

function fail(description, detail) {
  if (detail) console.error(detail)
  console.error(`not ok - ${description}`)
  process.exit(1)
}
function pass(description) { console.log(`ok - ${description}`) }
function assert(condition, description, detail) {
  if (!condition) fail(description, detail)
  pass(description)
}
function assertEqual(actual, expected, description) {
  assert(actual === expected, description, `expected: ${expected}\nactual:   ${actual}`)
}
function assertDeepEqual(actual, expected, description) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  assert(a === e, description, `expected: ${e}\nactual:   ${a}`)
}

const NUL = '\u0000'
const DEL = '\u007F'

// ---- Safe.js: data that stays data

assertEqual(Safe.bounded('dev.zed.Zed'), 'dev.zed.Zed', 'bounded keeps an ordinary app id verbatim')
assertEqual(Safe.bounded(`dev${NUL}.zed${DEL}`), 'dev.zed', 'bounded drops control characters')
assertEqual(Safe.bounded('a'.repeat(500), 10), 'a'.repeat(10), 'bounded caps the length')
assertEqual(Safe.bounded(null), '', 'bounded turns null into an empty string')
assertEqual(Safe.bounded('x'.repeat(400)).length, Safe.LIMITS.label, 'bounded defaults to the label limit')

// ---- Safe.js: data that reaches a sink we do not own

assertEqual(Safe.plainLabel('<img src=x onerror=y>Zed'), 'img src=x onerror=yZed', 'plainLabel strips markup delimiters')
assertEqual(Safe.plainLabel('a &amp; b'), 'a amp; b', 'plainLabel strips entity ampersands')
assertEqual(Safe.plainLabel(`Ze${NUL}d   the\t editor `), 'Ze d the editor', 'plainLabel neutralises control chars and collapses whitespace')
assertEqual(Safe.plainLabel('a'.repeat(200), 10), 'a'.repeat(9) + '…', 'plainLabel ellipsises past the cap')
assertEqual(Safe.plainLabel(''), '', 'plainLabel of nothing is nothing')

// ---- Safe.js: a capture path out of a summon payload

assertEqual(Safe.payloadPath('~/notes/inbox.md'), '~/notes/inbox.md', 'payloadPath passes an ordinary path through')
assertEqual(Safe.payloadPath(`~/a${NUL}b`), '', 'payloadPath refuses a path with control characters')
assertEqual(Safe.payloadPath('~/' + 'a'.repeat(Safe.LIMITS.path)), '', 'payloadPath refuses a path over the cap')
assertEqual(Safe.payloadPath(''), '', 'payloadPath refuses an empty path')
assert(Safe.payloadPath("~/it's a file.md") === "~/it's a file.md", 'payloadPath does not rewrite quoting')

// ---- Safe.js: documents the plugin parses

assertEqual(Safe.capDocument('{"a":1}'), '{"a":1}', 'capDocument passes a small document through')
assertEqual(Safe.capDocument('x'.repeat(Safe.LIMITS.document + 1)), '', 'capDocument refuses an oversized document whole')
assertEqual(Safe.capDocument('x'.repeat(20), 10), '', 'capDocument honours an explicit cap')

// ---- Safe.js: the bounded read that keeps oversized files out of the shell

const readCmd = Safe.readCommand('/home/u/.local/state/omarchy/adhd-kit/timer.json')
assertEqual(readCmd[0], 'head', 'readCommand reads through head, not the QML file view')
assertEqual(readCmd[1], '-c', 'readCommand bounds by bytes')
assertEqual(readCmd[2], String(Safe.LIMITS.document + 1), 'readCommand asks for one byte past the cap, so an oversized file is detectable')
assertEqual(readCmd[3], '--', 'readCommand ends option parsing before the path')
assertEqual(readCmd[4], '/home/u/.local/state/omarchy/adhd-kit/timer.json', 'the path travels as its own argv element')
assertEqual(readCmd.length, 5, 'nothing else is passed to the helper')
assertEqual(Safe.readCommand('/p', 100)[2], '101', 'an explicit cap is honoured')
assertEqual(Safe.readCommand(null)[4], '', 'a missing path does not become the string "null"')
// One byte over is exactly what capDocument refuses, so the two halves agree.
assertEqual(Safe.capDocument('x'.repeat(Number(readCmd[2]))), '', 'what the helper can return at most is what capDocument refuses')

// ---- TimerModel: presets

assertDeepEqual(Timer.parsePresets('5,15,25,45'), [5, 15, 25, 45], 'presets parse in order')
assertDeepEqual(Timer.parsePresets(' 10 , 25 ,10, junk, 0, 1000 '), [10, 25], 'presets drop junk, dupes and out-of-range values')
assertDeepEqual(Timer.parsePresets(''), [5, 15, 25, 45], 'an empty preset string falls back to the defaults')
assertDeepEqual(Timer.parsePresets(null), [5, 15, 25, 45], 'a missing preset string falls back to the defaults')
assertEqual(Timer.parsePresets('1,2,3,4,5,6,7,8').length, 6, 'presets are capped at six')

// ---- TimerModel: rendering

assertEqual(Timer.formatRemaining(1500), '25:00', 'mm:ss under an hour')
assertEqual(Timer.formatRemaining(3725), '1:02:05', 'h:mm:ss past an hour')
assertEqual(Timer.formatRemaining(-5), '0:00', 'a negative remainder reads as zero')

// ---- TimerModel: state, which any local process can write

const now = 1_700_000_000_000
const live = Timer.parseState(JSON.stringify({ endAt: now + 60000, durationSec: 300 }), now)
assertEqual(live.endAt, now + 60000, 'a live timer survives a reload')
assertEqual(live.durationSec, 300, 'its duration comes back with it')

const expired = Timer.parseState(JSON.stringify({ endAt: now - 1, durationSec: 300 }), now)
assertEqual(expired.endAt, 0, 'a timer that expired while the shell was down comes back idle')

const garbage = Timer.parseState('not json at all', now)
assertDeepEqual(garbage, { endAt: 0, durationSec: 0, pausedRemainingSec: 0 }, 'unparseable state reads as idle')

const hostile = Timer.parseState(JSON.stringify({ endAt: 'NaN', durationSec: -9, pausedRemainingSec: 1e400 }), now)
assertEqual(hostile.endAt, 0, 'a non-numeric endAt reads as idle')
assertEqual(hostile.durationSec, 0, 'a negative duration clamps to zero')
assertEqual(hostile.pausedRemainingSec, 0, 'a non-finite paused remainder clamps to zero')

// The state file is a plugin file, but nothing stops another local process
// from growing it; the read is refused before it is parsed or retained.
assertEqual(Timer.parseState(Safe.capDocument('x'.repeat(Safe.LIMITS.document + 1)), now).endAt, 0, 'an oversized state file reads as idle')

// ---- TimerModel: persistence argv

const cmd = Timer.persistCommand('/tmp/s tate.json', 1, 2, 3)
assertEqual(cmd[0], 'sh', 'persist runs through sh')
assertEqual(cmd[3], 'sh', 'persist passes $0 before the positional args')
assertEqual(cmd[4], '/tmp/s tate.json', 'the state path travels as a positional arg, never as syntax')
assert(cmd[2].indexOf('"$1"') !== -1 && cmd[2].indexOf('"$2"') !== -1, 'the script only ever expands quoted positionals')
assert(JSON.parse(cmd[5]).durationSec === 2, 'the payload is JSON data in $2')

// ---- GuardModel: config, which is a user file that may be broken

const defaults = Guard.parseConfig('')
assertEqual(defaults.enabled, true, 'a missing config leaves the guard enabled')
assertEqual(defaults.thresholdMinutes, 90, 'a missing config keeps the default threshold')
assertDeepEqual(Guard.parseConfig('{{{ broken').ignore, [], 'a broken config falls back to defaults instead of crashing')

const cfg = Guard.parseConfig(JSON.stringify({
  hyperfocus: { enabled: false, thresholdMinutes: 100000, repeatMinutes: 0, ignore: ['MPV', 'vlc'] }
}))
assertEqual(cfg.enabled, false, 'enabled: false is honoured')
assertEqual(cfg.thresholdMinutes, 1440, 'an absurd threshold clamps to the maximum')
assertEqual(cfg.repeatMinutes, 1, 'a zero repeat clamps to the minimum')
assertDeepEqual(cfg.ignore, ['mpv', 'vlc'], 'ignore entries are lowercased for case-insensitive matching')

const flood = Guard.parseConfig(JSON.stringify({
  hyperfocus: { ignore: new Array(5000).fill('a'.repeat(4000)) }
}))
assertEqual(flood.ignore.length, Guard.LIMITS.ignoreEntries, 'the ignore list is capped')
assertEqual(flood.ignore[0].length, Guard.LIMITS.ignoreEntry, 'each ignore entry is bounded')

// ---- GuardModel: rendering an app id, which the app itself chooses

assertEqual(Guard.friendlyName('dev.zed.Zed'), 'Zed', 'a reverse-DNS app id reads as its last segment')
assertEqual(Guard.friendlyName('Alacritty'), 'Alacritty', 'a plain app id is left alone')
assertEqual(Guard.friendlyName(''), 'this app', 'an app with no id still reads as something')
assertEqual(Guard.friendlyName('a'.repeat(500)).length, Guard.LIMITS.appName, 'a hostile app id is bounded before it is rendered')
assertEqual(Safe.plainLabel(Guard.friendlyName('org.x.<img src=x>')), 'img src=x', 'an app id cannot smuggle markup into the notification body')

assertEqual(Guard.formatMinutes(1), '1 minute', 'one minute is singular')
assertEqual(Guard.formatMinutes(45), '45 minutes', 'under an hour reads in minutes')
assertEqual(Guard.formatMinutes(135), '2h 15m', 'past an hour reads as hours and minutes')
assertEqual(Guard.formatMinutes(120), '2 hours', 'a whole number of hours drops the minutes')
JS
