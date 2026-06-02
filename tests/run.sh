#!/usr/bin/env bash
# Integration tests for claude-code-tmux hooks, run against a private tmux
# server so they never touch your real sessions.
#
#   bash tests/run.sh
#
# Requires tmux. Exits non-zero if any assertion fails.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOCK="cct_test_$$"
FLASH="bg=red,fg=white,bold"   # default CLAUDE_TMUX_REMOTE_STYLE
GLOBAL="bg=green"              # known baseline so restore is observable

command -v tmux >/dev/null 2>&1 || { echo "SKIP: tmux not installed"; exit 0; }

WORK="$(mktemp -d)"
export TMUX_TMPDIR="$WORK/sock"; mkdir -p "$TMUX_TMPDIR"
export CLAUDE_TMUX_SOCKET="$SOCK"
export CLAUDE_TMUX_STATE_DIR="$WORK/state"
# Hooks must not inherit a real $TMUX; they target the test server via -L.
unset TMUX 2>/dev/null || true

t() { tmux -L "$SOCK" "$@"; }
cleanup() { t kill-server >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want [$3] got [$2])"; fi; }

style()  { t show-options -t "$1" -v status-style 2>/dev/null; }   # override value, "" if inherited
oride()  { t show-options -t "$1" status-style 2>/dev/null; }      # non-empty IFF a session override exists
wstyle() { t show-window-options -t "$1" -v window-status-style 2>/dev/null; }

# Fire a hook as though Claude in <session> triggered it.
hook() { # $1=script  $2=session
  local pane; pane="$(t display-message -t "$2" -p '#{pane_id}')"
  TMUX_PANE="$pane" bash "$REPO/hooks/$1" </dev/null >/dev/null 2>&1
}

marker_count() { ls -1 "$CLAUDE_TMUX_STATE_DIR/panes" 2>/dev/null | wc -l | tr -d ' '; }
flag_count()   { ls -1 "$CLAUDE_TMUX_STATE_DIR/flagged" 2>/dev/null | wc -l | tr -d ' '; }

# --- setup ------------------------------------------------------------------
t new-session -d -s A
t set-option -g status-style "$GLOBAL"   # global baseline all sessions inherit
t new-session -d -s B
t new-session -d -s C

echo "test: baseline (sessions inherit the global bar, no per-session override)"
eq "A has no override"        "$(oride A)" ""

echo "test: B waits -> other sessions (A,C) flag, B itself does not"
hook flash-on.sh B
eq "A bar flashed"            "$(style A)" "$FLASH"
eq "C bar flashed"            "$(style C)" "$FLASH"
eq "B bar not flashed"        "$(style B)" ""
eq "B has no override"        "$(oride B)" ""
eq "B window flashed"         "$(wstyle B)" "$FLASH"
eq "one waiting marker"       "$(marker_count)" "1"

echo "test: answering B restores cleanly (unset, NOT blanked to empty override)"
hook flash-off.sh B
eq "A override removed"       "$(oride A)" ""
eq "C override removed"       "$(oride C)" ""
eq "B window restored"        "$(wstyle B)" ""
eq "no markers left"          "$(marker_count)" "0"
eq "no flags left"            "$(flag_count)" "0"

echo "test: B and C both wait, then answer B -> A stays flagged (C still waiting)"
hook flash-on.sh B
hook flash-on.sh C
eq "A flagged (B,C wait)"     "$(style A)" "$FLASH"
eq "B flagged (C waits)"      "$(style B)" "$FLASH"
eq "C flagged (B waits)"      "$(style C)" "$FLASH"
hook flash-off.sh B
eq "A still flagged"          "$(style A)" "$FLASH"
eq "B still flagged (C waits)" "$(style B)" "$FLASH"
eq "C cleared (no other waits)" "$(style C)" ""
eq "C override removed"       "$(oride C)" ""
hook flash-off.sh C
eq "A cleared + unset"        "$(oride A)" ""
eq "B cleared + unset"        "$(oride B)" ""

echo "test: stale marker for a dead pane is reaped on reconcile"
printf '%%99999\n' >"$CLAUDE_TMUX_STATE_DIR/panes/_99999"
eq "stale marker present"     "$(marker_count)" "1"
hook flash-off.sh A
eq "stale marker reaped"      "$(marker_count)" "0"
eq "nothing flagged from stale" "$(oride A)" ""

echo "test: CROSS_SESSION=0 leaves other sessions untouched"
( export CLAUDE_TMUX_CROSS_SESSION=0; hook flash-on.sh B )
eq "A untouched when disabled" "$(oride A)" ""
eq "B window still flashes"   "$(wstyle B)" "$FLASH"
( export CLAUDE_TMUX_CROSS_SESSION=0; hook flash-off.sh B )

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
