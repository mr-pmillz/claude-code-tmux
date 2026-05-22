#!/usr/bin/env bash
# Restore default tmux window styling when the user submits a prompt.

# Drain stdin so Claude Code does not get SIGPIPE writing the hook JSON.
cat >/dev/null 2>&1 || true

# No-op outside tmux.
[ -z "$TMUX_PANE" ] && exit 0
command -v tmux >/dev/null 2>&1 || exit 0

tmux set-window-option -u -t "$TMUX_PANE" window-status-style 2>/dev/null || true
tmux set-window-option -u -t "$TMUX_PANE" monitor-bell 2>/dev/null || true

exit 0
