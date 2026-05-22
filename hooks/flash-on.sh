#!/usr/bin/env bash
# Flash the tmux window status when Claude Code needs attention.
#
# Configuration (env vars):
#   CLAUDE_TMUX_FLASH_STYLE  tmux style string. Default: bg=red,fg=white,bold
#   CLAUDE_TMUX_FLASH_BELL   Set to 0 to suppress the bell. Default: 1

# Drain stdin so Claude Code does not get SIGPIPE writing the hook JSON.
cat >/dev/null 2>&1 || true

# No-op outside tmux.
[ -z "$TMUX_PANE" ] && exit 0
command -v tmux >/dev/null 2>&1 || exit 0

style="${CLAUDE_TMUX_FLASH_STYLE:-bg=red,fg=white,bold}"
bell="${CLAUDE_TMUX_FLASH_BELL:-1}"

tmux set-window-option -t "$TMUX_PANE" window-status-style "$style" 2>/dev/null || true
tmux set-window-option -t "$TMUX_PANE" monitor-bell on 2>/dev/null || true

if [ "$bell" = "1" ]; then
  tty=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_tty}' 2>/dev/null)
  [ -n "$tty" ] && printf '\a' >"$tty" 2>/dev/null || true
fi

exit 0
