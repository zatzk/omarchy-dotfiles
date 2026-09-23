#!/bin/bash

# Behavioural test for the bounded read. model-test.sh asserts what
# Safe.readCommand() *says*; this one runs it against a hostile state file and
# asserts what it *does* — that no more than the cap can ever reach the shell,
# because QML's FileView would otherwise retain the whole file before any
# JS-side cap could apply.

set -e

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

command -v node >/dev/null || { echo "not ok - node is required" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail() { [[ -n $2 ]] && echo "$2" >&2; echo "not ok - $1" >&2; exit 1; }
pass() { echo "ok - $1"; }
assert() { [[ $1 == 1 ]] || fail "$2" "$3"; pass "$2"; }
assert_equal() {
  [[ $1 == "$2" ]] || fail "$3" "expected: $2
actual:   $1"
  pass "$3"
}

CAP=$(node -e 'process.stdout.write(String(require(process.argv[1] + "/Safe.js").LIMITS.document))' "$ROOT")

# The argv Safe.readCommand() builds, run exactly as the QML Process would.
read_file() { # $1 = path
  node -e '
    const Safe = require(process.argv[1] + "/Safe.js")
    process.stdout.write(JSON.stringify(Safe.readCommand(process.argv[2])))
  ' "$ROOT" "$1" | node -e '
    let raw = ""
    process.stdin.on("data", d => raw += d).on("end", () => {
      const { spawnSync } = require("child_process")
      const argv = JSON.parse(raw)
      const r = spawnSync(argv[0], argv.slice(1), { maxBuffer: 1 << 30 })
      process.stdout.write(r.stdout || Buffer.alloc(0))
    })'
}

# A real state file comes back intact.
printf '{"endAt":123,"durationSec":300,"pausedRemainingSec":0}' > "$WORK/timer.json"
out=$(read_file "$WORK/timer.json")
assert_equal "$out" '{"endAt":123,"durationSec":300,"pausedRemainingSec":0}' "a normal state file is read verbatim"
assert_equal "$(node -e '
  const T = require(process.argv[1] + "/TimerModel.js")
  const S = require(process.argv[1] + "/Safe.js")
  process.stdout.write(String(T.parseState(S.capDocument(process.argv[2]), 0).durationSec))
' "$ROOT" "$out")" "300" "and it parses"

# A 300 MB state file cannot hand the shell more than one byte over the cap,
# and that byte is what makes capDocument() refuse the document.
head -c $((300 * 1024 * 1024)) /dev/zero | tr '\0' 'x' > "$WORK/huge.json"
assert "$([[ $(stat -c %s "$WORK/huge.json") -gt $((300 * 1024 * 1000)) ]] && echo 1)" "the hostile state file really is ~300 MB"
huge=$(read_file "$WORK/huge.json" | wc -c)
assert_equal "$huge" "$((CAP + 1))" "the read stops one byte past the cap ($CAP)"
assert_equal "$(node -e '
  const S = require(process.argv[1] + "/Safe.js")
  process.stdout.write(String(S.capDocument("x".repeat(Number(process.argv[2]))).length))
' "$ROOT" "$huge")" "0" "a document that long is refused whole, so nothing is retained"

# A missing file is the normal idle case: empty output, and empty parses as idle.
out=$(read_file "$WORK/does-not-exist.json" 2>/dev/null || true)
assert_equal "${#out}" 0 "a missing file reads as empty"
assert_equal "$(node -e '
  const T = require(process.argv[1] + "/TimerModel.js")
  process.stdout.write(String(T.parseState("", 0).endAt))
' "$ROOT")" "0" "and empty reads as an idle timer"

# The path travels as an argv element after `--`, so a file named like a flag
# is read rather than interpreted.
printf '{"durationSec":60}' > "$WORK/-n"
assert_equal "$(read_file "$WORK/-n")" '{"durationSec":60}' "a path that looks like a flag is still read as a path"
