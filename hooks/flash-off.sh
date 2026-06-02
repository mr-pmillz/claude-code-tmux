#!/usr/bin/env bash
# UserPromptSubmit hook: you responded, so this session is no longer waiting.
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
