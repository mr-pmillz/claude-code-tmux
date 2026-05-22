# claude-code-tmux

Flash the **tmux window status bar** when Claude Code is waiting on your input — and clear it as soon as you reply.

If you keep multiple long-running Claude Code sessions across several tmux windows, this is the easiest way to know which one needs you.

## What it does

When Claude Code fires a `Notification` event (it wants permission, is idle waiting for input, etc.), this plugin:

- Sets `window-status-style` on the tmux window containing the Claude pane to a bright, attention-grabbing style (default: `bg=red,fg=white,bold`) so the window jumps out in your tmux status bar from any other tmux window.
- Turns on tmux `monitor-bell` for that window and emits a literal bell so the bell flag (`#`) shows in the status bar.

When you submit your next prompt (`UserPromptSubmit`), it unsets both options and the window goes back to normal.

> **Note:** the flash is most visible when you are *not* currently looking at that tmux window. tmux's `window-status-current-style` overrides `window-status-style` on the active window, so a flashed pane that is already the active window in the current tmux session may not visibly change. That's actually a feature — you don't need a flash for the window you're already on.

## Install

### Option A — Marketplace (recommended)

Add to `~/.claude/settings.json`:

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

### Option B — Clone and reference locally

```bash
git clone https://github.com/mr-pmillz/claude-code-tmux ~/.claude/plugins/claude-code-tmux
```

Then add the marketplace + enable lines from Option A, pointing your marketplace source at the local path instead of github.

### Option C — Copy the hooks into your existing settings.json

If you don't want a plugin at all, just splice these into your `~/.claude/settings.json` under `hooks`:

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

The hook scripts honor two environment variables, exported in your shell rc:

| Variable | Default | Effect |
|---|---|---|
| `CLAUDE_TMUX_FLASH_STYLE` | `bg=red,fg=white,bold` | Any tmux style string — e.g. `bg=yellow,fg=black`, `bg=magenta,fg=white,blink`. |
| `CLAUDE_TMUX_FLASH_BELL` | `1` | Set to `0` to suppress the bell. |

Examples:

```bash
export CLAUDE_TMUX_FLASH_STYLE='bg=yellow,fg=black,bold'
export CLAUDE_TMUX_FLASH_BELL=0
```

For the bell flag to actually appear in the status bar, your tmux config needs `window-status-bell-style` defined (most distro defaults already include it). Optionally add:

```tmux
set-window-option -g window-status-bell-style 'bg=red,fg=white,bold'
```

## How it works

- **Notification hook → `hooks/flash-on.sh`** runs `tmux set-window-option` against `$TMUX_PANE` (tmux resolves a pane id to its parent window for window-scoped options), then writes `\a` to the pane's tty so tmux's bell monitor fires.
- **UserPromptSubmit hook → `hooks/flash-off.sh`** unsets the same options with `tmux set-window-option -u`, reverting to whatever your config sets globally.

Both scripts are no-ops when `$TMUX_PANE` is unset (i.e. you're running Claude Code outside tmux).

## Troubleshooting

**Nothing flashes.** Make sure `$TMUX_PANE` is set inside your Claude Code session: `tmux display-message -p '#{pane_id}'`. If you launched Claude before attaching tmux, restart it from inside tmux.

**The flash didn't clear after I submitted a prompt.** Run manually:

```bash
tmux set-window-option -u -t "$TMUX_PANE" window-status-style
tmux set-window-option -u -t "$TMUX_PANE" monitor-bell
```

Then check that the plugin is enabled in `/plugin`. Some Claude Code builds only load hooks at session start, so a freshly installed plugin needs a restart.

**Bell doesn't appear.** Your tmux build may suppress bells; confirm `set -g bell-action any` (or `other`) is in your `tmux.conf`, and that `monitor-bell` is on (the plugin sets it, but you can verify with `tmux show-window-options monitor-bell`).

## License

MIT — see [LICENSE](./LICENSE).
