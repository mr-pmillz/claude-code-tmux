#!/usr/bin/env bash
# UserPromptSubmit + Stop hook: this session is no longer waiting on you.
#
# Wired to BOTH events: UserPromptSubmit (you replied) and Stop (the turn
# ended). The Stop wiring is what keeps it self-healing — a pane you're
# actively working in clears its waiting marker at the end of every turn, so a
# Notification that wasn't followed by a prompt (e.g. a permission you approved)
# can't leave a stale marker that deadlocks the cross-session bars. A genuine
# idle wait re-marks itself, because its Notification fires *after* Stop.
#
#   Layer 1: restore this window's styling.
#   Layer 2: drop this pane's waiting marker and reconcile cross-session
#            indicators (a session you're viewing stays alerted only while
#            some OTHER session is still waiting).
#
# See hooks/lib.sh for configuration env vars.

# Drain stdin so Claude Code does not get SIGPIPE writing the hook JSON.
cat >/dev/null 2>&1 || true

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cct_have_tmux || exit 0

# Layer 1 — this window.
cct_window_flash_off

# Layer 2 — other sessions.
if [ "${CLAUDE_TMUX_CROSS_SESSION:-1}" = "1" ]; then
  cct_unmark_waiting
  cct_reconcile
fi

exit 0
