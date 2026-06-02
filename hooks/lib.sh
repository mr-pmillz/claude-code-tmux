#!/usr/bin/env bash
# Shared helpers for claude-code-tmux hooks.
#
# Two layers of "Claude needs you" signalling:
#   1. Window flash  — restyle the tmux *window* holding the Claude pane.
#                      Visible from other windows of the SAME session.
#   2. Cross-session — prepend a small, non-destructive *badge* to the
#                      status-right of every OTHER session, so a session you
#                      can see tells you another session (that you can't) is
#                      waiting. It never touches status-style, so your themed
#                      bar stays intact, and the original status-right is saved
#                      for an exact restore.
#
# Layer 2 is reconciled from a small state dir of "waiting pane" markers, so it
# stays correct when several sessions wait at once: answering one session only
# clears the alert when no other session is still waiting. Markers are cleared
# on UserPromptSubmit *and* Stop (the end of every Claude turn), so a pane you
# are actively working in can never stay flagged across turns and deadlock the
# bars. Markers for vanished panes are reaped automatically.
#
# Configuration (env vars):
#   CLAUDE_TMUX_FLASH_STYLE    Window flash style.        Default: bg=red,fg=white,bold
#   CLAUDE_TMUX_REMOTE_STYLE   Other-session badge style. Default: $CLAUDE_TMUX_FLASH_STYLE
#   CLAUDE_TMUX_FLASH_BELL     Set 0 to suppress bells.   Default: 1
#   CLAUDE_TMUX_CROSS_SESSION  Set 0 to disable layer 2.  Default: 1
#   CLAUDE_TMUX_STATE_DIR      Override state dir location (mainly for tests).
#   CLAUDE_TMUX_SOCKET         Run tmux against `-L <name>` (mainly for tests).

# --- tmux plumbing ----------------------------------------------------------

# Run tmux, honouring an optional dedicated socket. In normal use this is just
# `tmux` (which finds the ambient server via $TMUX); tests point it at -L.
cct_tmux() {
  if [ -n "${CLAUDE_TMUX_SOCKET:-}" ]; then
    command tmux -L "$CLAUDE_TMUX_SOCKET" "$@"
  else
    command tmux "$@"
  fi
}

cct_have_tmux() {
  [ -n "${TMUX_PANE:-}" ] && command -v tmux >/dev/null 2>&1
}

cct_session_of_pane() {
  cct_tmux display-message -t "$1" -p '#{session_id}' 2>/dev/null
}

cct_session_name() {
  cct_tmux display-message -t "$1" -p '#{session_name}' 2>/dev/null
}

# Turn a tmux id ($3, %5, @1) into a filename-safe token. Pane and session ids
# live in separate dirs, so the collapse of the leading sigil is harmless.
cct_token() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'
}

# Strip characters tmux would interpret as format expansions (#[...], #(...),
# #{...}) plus newlines/tabs, so an odd or hostile session name can't corrupt
# the status line or our tab-delimited state files.
cct_sanitize() {
  printf '%s' "$1" | tr -d '#' | tr -d '\n\r\t'
}

# --- state dir --------------------------------------------------------------

cct_state_dir() {
  if [ -n "${CLAUDE_TMUX_STATE_DIR:-}" ]; then
    printf '%s' "$CLAUDE_TMUX_STATE_DIR"
    return
  fi
  printf '%s/claude-code-tmux' "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
}

# --- layer 1: window flash --------------------------------------------------

cct_window_flash_on() {
  local style="${CLAUDE_TMUX_FLASH_STYLE:-bg=red,fg=white,bold}"
  cct_tmux set-window-option -t "$TMUX_PANE" window-status-style "$style" 2>/dev/null || true
  cct_tmux set-window-option -t "$TMUX_PANE" monitor-bell on 2>/dev/null || true
}

cct_window_flash_off() {
  cct_tmux set-window-option -u -t "$TMUX_PANE" window-status-style 2>/dev/null || true
  cct_tmux set-window-option -u -t "$TMUX_PANE" monitor-bell 2>/dev/null || true
}

# Ring the terminal bell on a tty (honours CLAUDE_TMUX_FLASH_BELL).
cct_bell() {
  [ "${CLAUDE_TMUX_FLASH_BELL:-1}" = "1" ] || return 0
  [ -n "$1" ] || return 0
  printf '\a' >"$1" 2>/dev/null || true
}

# --- layer 2: cross-session marker set --------------------------------------

cct_mark_waiting() {
  local dir; dir="$(cct_state_dir)/panes"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\n' "$TMUX_PANE" >"$dir/$(cct_token "$TMUX_PANE")" 2>/dev/null || true
}

cct_unmark_waiting() {
  rm -f "$(cct_state_dir)/panes/$(cct_token "$TMUX_PANE")" 2>/dev/null || true
}

# Echo "<had_override>\t<value>": whether this session has its OWN status-right
# (a session-scoped override, as opposed to inheriting the global), and that
# override's value. `show-options -t <session>` prints nothing when the option
# is only inherited, so an empty result means "no override -> restore by unset".
cct_capture_status_right() {
  if [ -n "$(cct_tmux show-options -t "$1" status-right 2>/dev/null)" ]; then
    printf '1\t%s' "$(cct_tmux show-options -t "$1" -v status-right 2>/dev/null)"
  else
    printf '0\t'
  fi
}

# The status-right a session would show WITHOUT our badge: its own saved
# override ($1=1), else the live global default. We always rebuild the badged
# value from this baseline, never off the already-badged current value, so the
# badge never stacks and its label can refresh as the waiting set changes.
cct_base_status_right() {
  if [ "$1" = 1 ]; then
    printf '%s' "$2"
  else
    cct_tmux show-options -gv status-right 2>/dev/null
  fi
}

# A compact, themed badge to prepend to a session's status-right. The trailing
# "#[default] " resets styling so the original status-right renders normally.
cct_badge() {
  local style="${CLAUDE_TMUX_REMOTE_STYLE:-${CLAUDE_TMUX_FLASH_STYLE:-bg=red,fg=white,bold}}"
  printf '#[%s] ⚠ %s #[default] ' "$style" "$1"
}

# Human label for the OTHER waiting sessions (their ids on $1, newline-separated):
# the session name when one waits, "<n> waiting" when several do.
cct_alert_label() {
  local ids n first
  ids="$(printf '%s\n' "$1" | grep -v '^[[:space:]]*$')"
  n="$(printf '%s\n' "$ids" | grep -c .)"
  if [ "${n:-0}" -le 1 ]; then
    first="$(printf '%s\n' "$ids" | head -n1)"
    printf '%s' "$(cct_sanitize "$(cct_session_name "$first")")"
  else
    printf '%s waiting' "$n"
  fi
}

# Recompute every session's cross-session badge from the marker set.
# Idempotent: safe to call on every hook event.
cct_reconcile() {
  cct_have_tmux || return 0
  [ "${CLAUDE_TMUX_CROSS_SESSION:-1}" = "1" ] || return 0

  local root panes flags
  root="$(cct_state_dir)"; panes="$root/panes"; flags="$root/flagged"
  mkdir -p "$panes" "$flags" 2>/dev/null || return 0

  # Serialize concurrent hooks so two sessions can't race on capture/restore.
  if command -v flock >/dev/null 2>&1 && exec 9>"$root/.lock"; then
    flock -w 2 9 2>/dev/null || true
  fi

  # Sessions that have a live waiting pane (drop markers for vanished panes).
  local f pane sid waiting_sids=""
  for f in "$panes"/*; do
    [ -e "$f" ] || continue
    pane="$(cat "$f" 2>/dev/null)"
    if [ -z "$pane" ]; then rm -f "$f" 2>/dev/null; continue; fi
    sid="$(cct_session_of_pane "$pane")"
    if [ -z "$sid" ]; then rm -f "$f" 2>/dev/null; continue; fi
    waiting_sids="${waiting_sids}${sid}
"
  done

  local present targets
  present="$(cct_tmux list-sessions -F '#{session_id}' 2>/dev/null)"
  # Evaluate every session that exists now plus any we previously flagged
  # (so a flag still clears even if its session was meanwhile destroyed).
  targets="$( { printf '%s\n' "$present"
                for f in "$flags"/*; do [ -e "$f" ] || continue; cut -f1 "$f" 2>/dev/null; done
              } | grep -v '^[[:space:]]*$' | sort -u )"

  local others desired flagfile had saved base label
  while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    others="$(printf '%s\n' "$waiting_sids" | grep -vxF -e "$sid" | grep -v '^[[:space:]]*$')"
    desired=0; [ -n "$others" ] && desired=1
    flagfile="$flags/$(cct_token "$sid")"

    if [ "$desired" = 1 ] && printf '%s\n' "$present" | grep -qxF -e "$sid"; then
      # Save the pre-badge baseline once, on the 0->1 transition.
      if [ ! -e "$flagfile" ]; then
        printf '%s\t%s\n' "$sid" "$(cct_capture_status_right "$sid")" >"$flagfile" 2>/dev/null || true
      fi
      # Never badge a session whose baseline we couldn't persist — otherwise we
      # could apply a badge we have no saved value to restore from later.
      [ -e "$flagfile" ] || continue
      # Rebuild the badged value from the SAVED baseline every reconcile, so the
      # label stays current and the badge never stacks onto itself.
      IFS=$'\t' read -r _sid had saved <"$flagfile"
      base="$(cct_base_status_right "$had" "$saved")"
      label="$(cct_alert_label "$others")"
      cct_tmux set-option -t "$sid" status-right "$(cct_badge "$label")$base" 2>/dev/null || true
    elif [ "$desired" = 0 ] && [ -e "$flagfile" ]; then
      # No longer needs it: restore whatever was there before.
      IFS=$'\t' read -r _sid had saved <"$flagfile"
      if [ "$had" = 1 ]; then
        cct_tmux set-option -t "$sid" status-right "$saved" 2>/dev/null || true
      else
        cct_tmux set-option -u -t "$sid" status-right 2>/dev/null || true
      fi
      rm -f "$flagfile" 2>/dev/null || true
    fi
  done <<EOF
$targets
EOF
}

# Immediate nudge to clients viewing a DIFFERENT session: bell + status message.
cct_notify_other_clients() {
  cct_have_tmux || return 0
  [ "${CLAUDE_TMUX_CROSS_SESSION:-1}" = "1" ] || return 0

  local me label
  me="$(cct_session_of_pane "$TMUX_PANE")"
  label="$(cct_tmux display-message -t "$TMUX_PANE" -p '#{session_name}:#{window_index}' 2>/dev/null)"

  cct_tmux list-clients -F '#{client_tty}	#{session_id}' 2>/dev/null | while IFS=$'\t' read -r tty csid; do
    [ -n "$csid" ] || continue
    [ "$csid" = "$me" ] && continue
    cct_tmux display-message -c "$tty" "Claude needs input in ${label:-another session}" 2>/dev/null || true
    cct_bell "$tty"
  done
}
