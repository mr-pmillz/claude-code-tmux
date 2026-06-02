#!/usr/bin/env bash
# Notification hook: Claude Code needs attention.
#
#   Layer 1: flash the tmux window holding this pane (visible across windows
#            of this session) and ring its bell.
#   Layer 2: mark this pane as waiting and alert any OTHER session you're
#            currently viewing (visible across sessions).
#
# See hooks/lib.sh for configuration env vars.

# Drain stdin so Claude Code does not get SIGPIPE writing the hook JSON.
cat >/dev/null 2>&1 || true

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cct_have_tmux || exit 0

# Layer 1 — this window.
cct_window_flash_on
cct_bell "$(cct_tmux display-message -t "$TMUX_PANE" -p '#{pane_tty}' 2>/dev/null)"

# Layer 2 — other sessions.
if [ "${CLAUDE_TMUX_CROSS_SESSION:-1}" = "1" ]; then
  cct_mark_waiting
  cct_reconcile
  cct_notify_other_clients
fi

exit 0
