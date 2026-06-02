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
FLASH="bg=red,fg=white,bold"   # default CLAUDE_TMUX_FLASH_STYLE (window flash)
GLYPH="⚠"                      # badge marker the cross-session alert prepends
GLOBAL_STYLE="bg=green"        # global status-style — MUST stay untouched (theme intact)
GLOBAL_RIGHT="GLOBAL_RIGHT"    # known global status-right so restore is observable

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

sr()       { t show-options -t "$1" -v status-right 2>/dev/null; }  # override value, "" if inherited
sr_or()    { t show-options -t "$1" status-right 2>/dev/null; }     # non-empty IFF a session override exists
sstyle_or(){ t show-options -t "$1" status-style 2>/dev/null; }     # non-empty IFF status-style overridden (must stay "")
wstyle()   { t show-window-options -t "$1" -v window-status-style 2>/dev/null; }
badge_n()  { printf '%s' "$(sr "$1")" | grep -o "$GLYPH" | wc -l | tr -d ' '; }     # how many badges (catch stacking)
has_badge(){ [ "$(badge_n "$1")" -ge 1 ] && echo 1 || echo 0; }
keeps_tail() { case "$(sr "$1")" in *"$2") echo 1;; *) echo 0;; esac; }              # status-right still ends with $2

# Fire a hook as though Claude in <session> triggered it.
hook() { # $1=script  $2=session
  local pane; pane="$(t display-message -t "$2" -p '#{pane_id}')"
  TMUX_PANE="$pane" bash "$REPO/hooks/$1" </dev/null >/dev/null 2>&1
}

marker_count() { ls -1 "$CLAUDE_TMUX_STATE_DIR/panes" 2>/dev/null | wc -l | tr -d ' '; }
flag_count()   { ls -1 "$CLAUDE_TMUX_STATE_DIR/flagged" 2>/dev/null | wc -l | tr -d ' '; }

# --- setup ------------------------------------------------------------------
t new-session -d -s A
t set-option -g status-style "$GLOBAL_STYLE"   # themed bar all sessions inherit
t set-option -g status-right "$GLOBAL_RIGHT"   # observable baseline for restore
t new-session -d -s B
t new-session -d -s C

echo "test: baseline (sessions inherit the global bar, no per-session override)"
eq "A no status-right override" "$(sr_or A)" ""
eq "A status-style untouched"   "$(sstyle_or A)" ""

echo "test: B waits -> A,C get a status-right badge; status-style untouched; B does not"
hook flash-on.sh B
eq "A badged"                 "$(has_badge A)" "1"
eq "A exactly one badge"      "$(badge_n A)" "1"
eq "A keeps its global tail"  "$(keeps_tail A "$GLOBAL_RIGHT")" "1"
eq "A status-style untouched" "$(sstyle_or A)" ""
eq "C badged"                 "$(has_badge C)" "1"
eq "B not badged"             "$(sr_or B)" ""
eq "B window flashed"         "$(wstyle B)" "$FLASH"
eq "one waiting marker"       "$(marker_count)" "1"

echo "test: answering B restores cleanly (back to inherited, NOT a blank override)"
hook flash-off.sh B
eq "A override removed"       "$(sr_or A)" ""
eq "C override removed"       "$(sr_or C)" ""
eq "B window restored"        "$(wstyle B)" ""
eq "no markers left"          "$(marker_count)" "0"
eq "no flags left"            "$(flag_count)" "0"

echo "test: a second waiter does not stack a second badge"
hook flash-on.sh B
hook flash-on.sh C            # A is reconciled twice; must rebuild, not prepend onto itself
eq "A still exactly one badge" "$(badge_n A)" "1"
eq "A still keeps global tail" "$(keeps_tail A "$GLOBAL_RIGHT")" "1"
hook flash-off.sh B
hook flash-off.sh C

echo "test: B and C both wait, then answer B -> A,B stay badged (C still waiting), C clears"
hook flash-on.sh B
hook flash-on.sh C
eq "A badged (B,C wait)"      "$(has_badge A)" "1"
eq "B badged (C waits)"       "$(has_badge B)" "1"
eq "C badged (B waits)"       "$(has_badge C)" "1"
hook flash-off.sh B
eq "A still badged"           "$(has_badge A)" "1"
eq "B still badged (C waits)" "$(has_badge B)" "1"
eq "C cleared (no other waits)" "$(sr_or C)" ""
hook flash-off.sh C
eq "A cleared + back to inherited" "$(sr_or A)" ""
eq "B cleared + back to inherited" "$(sr_or B)" ""

echo "test: non-destructive — a session's OWN status-right override is restored exactly"
t set-option -t A status-right "MY_OWN_RIGHT"
eq "A has its own override"   "$(sr A)" "MY_OWN_RIGHT"
hook flash-on.sh B
eq "A badged over its own"    "$(has_badge A)" "1"
eq "A keeps its own tail"     "$(keeps_tail A "MY_OWN_RIGHT")" "1"
hook flash-off.sh B
eq "A own override restored"  "$(sr A)" "MY_OWN_RIGHT"
t set-option -u -t A status-right   # back to inheriting the global

echo "test: self-healing — a Stop in an active (leaked) session breaks the deadlock"
# A got a Notification (e.g. a permission prompt) while you were working in it,
# and B is genuinely idle-waiting. Both are marked -> both badged (the deadlock).
hook flash-on.sh A
hook flash-on.sh B
eq "deadlock: A badged"       "$(has_badge A)" "1"
eq "deadlock: B badged"       "$(has_badge B)" "1"
hook flash-off.sh A           # Stop fires at the end of A's turn -> clears A's marker
eq "A still badged (B waits)" "$(has_badge A)" "1"
eq "B cleared (A done)"       "$(sr_or B)" ""
hook flash-off.sh B
eq "all clear after B answered" "$(sr_or A)" ""
eq "no markers left"          "$(marker_count)" "0"

echo "test: stale marker for a dead pane is reaped on reconcile"
printf '%%99999\n' >"$CLAUDE_TMUX_STATE_DIR/panes/_99999"
eq "stale marker present"     "$(marker_count)" "1"
hook flash-off.sh A
eq "stale marker reaped"      "$(marker_count)" "0"
eq "nothing badged from stale" "$(sr_or A)" ""

echo "test: a styled global status-right (format codes) round-trips through a badge"
STYLED='#[fg=cyan,bg=black] #{=21:pane_title} %H:%M '
t set-option -g status-right "$STYLED"
hook flash-on.sh B
eq "A badged over styled global" "$(has_badge A)" "1"
eq "A keeps the styled tail"     "$(keeps_tail A "$STYLED")" "1"
hook flash-off.sh B
eq "A back to inheriting styled global" "$(sr_or A)" ""
eq "global status-right intact"  "$(t show-options -gv status-right 2>/dev/null)" "$STYLED"
t set-option -g status-right "$GLOBAL_RIGHT"   # restore the suite baseline

echo "test: CROSS_SESSION=0 leaves other sessions untouched"
( export CLAUDE_TMUX_CROSS_SESSION=0; hook flash-on.sh B )
eq "A untouched when disabled" "$(sr_or A)" ""
eq "B window still flashes"   "$(wstyle B)" "$FLASH"
( export CLAUDE_TMUX_CROSS_SESSION=0; hook flash-off.sh B )

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
