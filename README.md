# claude-code-tmux

Flash the **tmux status bar** when Claude Code is waiting on your input — and clear it as soon as you reply. Works *within* a session (which window?) **and across sessions** (which session you can't even see?).

If you keep multiple long-running Claude Code sessions across several tmux windows — or several tmux **sessions** — this is the easiest way to know which one needs you.

## What it does

When Claude Code fires a `Notification` event (it wants permission, is idle waiting for input, etc.), this plugin alerts you on **two levels**:

**1. The window (same session).** Sets `window-status-style` on the tmux window containing the Claude pane to a bright, attention-grabbing style (default: `bg=red,fg=white,bold`) so the window jumps out in your tmux status bar, and turns on `monitor-bell` + emits a bell so the bell flag (`#`) shows up.

**2. The other session you're actually looking at (cross-session).** If Claude is waiting in a session you *can't* see, the plugin restyles the status bar of every **other** session you're attached to, and sends that session an immediate bell + a `Claude needs input in <session>:<window>` status message. So when you're heads-down in session `A` and Claude in session `B` needs you, session `A`'s bar tells you.

When you submit your next prompt (`UserPromptSubmit`), the plugin reverts everything it changed — but a session you're viewing **stays** alerted as long as *some other* session is still waiting, so a second waiting session is never silently dropped.

> **Note:** the window flash (level 1) is most visible when you are *not* currently looking at that tmux window — tmux's `window-status-current-style` overrides `window-status-style` on the active window. The cross-session alert (level 2) is the opposite: it is designed for exactly the session you *are* looking at, because that's where you'll see it.

## Install

### Option A — Install from Claude Code (recommended)

From inside a Claude Code session, add this repo as a marketplace and install the plugin:

```text
/plugin marketplace add mr-pmillz/claude-code-tmux
/plugin install claude-code-tmux@claude-code-tmux
```

Or do it interactively:

1. Run `/plugin marketplace add mr-pmillz/claude-code-tmux` to register the marketplace.
2. Run `/plugin` and pick **claude-code-tmux** from the browser to install / enable it.

To update later, run `/plugin marketplace update claude-code-tmux`. To remove it, run `/plugin uninstall claude-code-tmux@claude-code-tmux`.

> The hooks attach to new Claude Code sessions, so once the plugin is enabled, your next session inside tmux will flash on `Notification` events automatically.

### Option B — Edit settings.json directly

If you'd rather wire the marketplace up by hand, add this to `~/.claude/settings.json`:

```jsonc
{
  "extraKnownMarketplaces": {
    "claude-code-tmux": {
      "source": {
        "source": "github",
        "repo": "mr-pmillz/claude-code-tmux"
      }
    }
  },
  "enabledPlugins": {
    "claude-code-tmux@claude-code-tmux": true
  }
}
```

Then restart Claude Code (or run `/plugin` and enable the plugin from the menu).

### Option C — Clone and reference locally

```bash
git clone https://github.com/mr-pmillz/claude-code-tmux ~/.claude/plugins/claude-code-tmux
```

Then either:

- Run `/plugin marketplace add ~/.claude/plugins/claude-code-tmux` followed by `/plugin install claude-code-tmux@claude-code-tmux`, or
- Add the marketplace + enable lines from Option B, pointing the marketplace `source` at the local path instead of github.

### Option D — Copy the hooks into your existing settings.json

If you don't want a plugin at all, just splice these into your `~/.claude/settings.json` under `hooks`:

> **Heads-up:** this inline snippet only does the **within-session window flash** (level 1). The **cross-session** alert (level 2) needs the marker-tracking and reconcile logic in `hooks/lib.sh`, so for that, use the plugin (Options A–C) or point the hook commands at the repo's `hooks/flash-on.sh` / `hooks/flash-off.sh`.

```jsonc
"Notification": [
  {
    "matcher": "*",
    "hooks": [
      {
        "type": "command",
        "command": "if [ -n \"$TMUX_PANE\" ]; then tmux set-window-option -t \"$TMUX_PANE\" window-status-style 'bg=red,fg=white,bold' 2>/dev/null; tmux set-window-option -t \"$TMUX_PANE\" monitor-bell on 2>/dev/null; tty=$(tmux display-message -t \"$TMUX_PANE\" -p '#{pane_tty}' 2>/dev/null); [ -n \"$tty\" ] && printf '\\a' > \"$tty\" 2>/dev/null; fi; exit 0"
      }
    ]
  }
],
"UserPromptSubmit": [
  {
    "matcher": "*",
    "hooks": [
      {
        "type": "command",
        "command": "if [ -n \"$TMUX_PANE\" ]; then tmux set-window-option -u -t \"$TMUX_PANE\" window-status-style 2>/dev/null; tmux set-window-option -u -t \"$TMUX_PANE\" monitor-bell 2>/dev/null; fi; exit 0"
      }
    ]
  }
]
```

## Configuration

The hook scripts honor these environment variables, exported in your shell rc:

| Variable | Default | Effect |
|---|---|---|
| `CLAUDE_TMUX_FLASH_STYLE` | `bg=red,fg=white,bold` | Style for the **window** flash (level 1). Any tmux style string — e.g. `bg=yellow,fg=black`, `bg=magenta,fg=white,blink`. |
| `CLAUDE_TMUX_REMOTE_STYLE` | (same as `CLAUDE_TMUX_FLASH_STYLE`) | Style applied to **another session's** status bar (level 2). Set it different from the window flash if you want to tell the two apart. |
| `CLAUDE_TMUX_FLASH_BELL` | `1` | Set to `0` to suppress all bells. |
| `CLAUDE_TMUX_CROSS_SESSION` | `1` | Set to `0` to disable cross-session alerts entirely (keeps the within-session window flash). |
| `CLAUDE_TMUX_STATE_DIR` | `$XDG_RUNTIME_DIR/claude-code-tmux` (falls back to `$TMPDIR`/`/tmp`) | Where the small "which sessions are waiting" markers live. |
| `CLAUDE_TMUX_SOCKET` | (unset) | If set, run tmux against `tmux -L <name>`. Mostly for the test suite / dedicated tmux sockets. |

Examples:

```bash
export CLAUDE_TMUX_FLASH_STYLE='bg=yellow,fg=black,bold'   # window flash
export CLAUDE_TMUX_REMOTE_STYLE='bg=magenta,fg=white,bold' # other-session bar
export CLAUDE_TMUX_FLASH_BELL=0                            # silence bells
```

For the bell flag to actually appear in the status bar, your tmux config needs `window-status-bell-style` defined (most distro defaults already include it). Optionally add:

```tmux
set-window-option -g window-status-bell-style 'bg=red,fg=white,bold'
```

## How it works

Both hooks share `hooks/lib.sh` and are no-ops when `$TMUX_PANE` is unset (i.e. you're running Claude Code outside tmux).

- **Notification hook → `hooks/flash-on.sh`**
  - *Level 1:* `tmux set-window-option` against `$TMUX_PANE` (tmux resolves a pane id to its parent window for window-scoped options), then writes `\a` to the pane's tty so tmux's bell monitor fires.
  - *Level 2:* records this pane in a small marker dir (`CLAUDE_TMUX_STATE_DIR`), then **reconciles**: every session that is *not* itself waiting but has *another* waiting session gets its `status-style` set to the remote style (its prior value is saved for exact restore). It also sends an immediate bell + `display-message` to any attached client viewing a different session.
- **UserPromptSubmit hook → `hooks/flash-off.sh`** unsets the window options, removes this pane's marker, and reconciles again.

**Why a marker dir instead of just toggling on/off?** With two or more sessions waiting at once, answering one must not clear the alert on a session that can still see *another* waiting session. Reconcile recomputes each session's indicator from the full set of waiting panes every time, so the alert persists exactly as long as something is still waiting, and markers whose pane has since disappeared are reaped automatically.

## Troubleshooting

**Nothing flashes.** Make sure `$TMUX_PANE` is set inside your Claude Code session: `tmux display-message -p '#{pane_id}'`. If you launched Claude before attaching tmux, restart it from inside tmux.

**The flash didn't clear after I submitted a prompt.** Run manually:

```bash
tmux set-window-option -u -t "$TMUX_PANE" window-status-style
tmux set-window-option -u -t "$TMUX_PANE" monitor-bell
```

Then check that the plugin is enabled in `/plugin`. Some Claude Code builds only load hooks at session start, so a freshly installed plugin needs a restart.

**Bell doesn't appear.** Your tmux build may suppress bells; confirm `set -g bell-action any` (or `other`) is in your `tmux.conf`, and that `monitor-bell` is on (the plugin sets it, but you can verify with `tmux show-window-options monitor-bell`).

**Another session's bar stays flashed.** It clears when you submit a prompt in the waiting session. If Claude was dismissed another way (e.g. you approved a permission prompt without sending a message, or killed Claude leaving the pane at a shell), its marker can linger. Reset state with:

```bash
rm -rf "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/claude-code-tmux"
tmux set-option -u -t <session> status-style   # for any session still tinted
```

**I don't want cross-session alerts.** Set `export CLAUDE_TMUX_CROSS_SESSION=0`; the within-session window flash keeps working.

## Testing

The hook logic has an integration test that spins up a throwaway tmux server (it never touches your real sessions):

```bash
bash tests/run.sh
```

It covers the window flash, the cross-session status-bar flash, correct restore when multiple sessions wait at once, and stale-marker cleanup.

## License

MIT — see [LICENSE](./LICENSE).
