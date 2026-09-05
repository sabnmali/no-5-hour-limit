---
name: no-5-hour-limit
description: Inspect or control the No 5-Hour Limit keepalive - the local or GitHub Actions job that pings the Claude and Codex CLIs every ~5 hours so a fresh usage window is always open. Use when the user asks about their 5-hour limit/window, "kotam ne zaman yenilenir", "limitim ne durumda", "keepalive", "pencere ne zaman bitiyor", or wants to start/stop/check the keepalive, fire a ping now, or read its logs.
---

# No 5-Hour Limit

A scheduled job that sends a tiny prompt to the Claude CLI (and optionally the
Codex CLI) once every `INTERVAL_MINUTES` (default 301 = 5 h + 1 min). Each ping
opens a fresh 5-hour usage window, so the window boundary is predictable
instead of starting whenever the user happens to send their first real message.

## Locating the install

The repository root is wherever the user cloned it. Find it in this order:

1. `NO_5H_LIMIT_HOME` environment variable, if set.
2. The path recorded in `~/.no-5-hour-limit-path` (written by the installer).
3. Ask the user.

Set `REPO` to that path before running the commands below.

## Commands

All of these are read-only or user-initiated; none of them need approval
beyond the normal Bash permission prompt.

**Windows**

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<REPO>\bin\keepalive.ps1" -Status
powershell -NoProfile -ExecutionPolicy Bypass -File "<REPO>\bin\keepalive.ps1" -Force
powershell -NoProfile -ExecutionPolicy Bypass -File "<REPO>\install\install-windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "<REPO>\install\uninstall-windows.ps1"
```

**macOS / Linux**

```
"<REPO>/bin/keepalive.sh" --status
"<REPO>/bin/keepalive.sh" --force
"<REPO>/install/install-unix.sh"
"<REPO>/install/uninstall-unix.sh"
```

## When it runs in the cloud

If `<REPO>/.github/workflows/keepalive.yml` exists and the repo has a remote,
the keepalive may be running on GitHub Actions instead of (or as well as) this
machine. In that case the authoritative state is `state/cloud-state.env` in the
repo, not `state/state.env`:

```
git -C "<REPO>" pull --quiet
L5H_STATE_FILE=state/cloud-state.env bash "<REPO>/bin/keepalive.sh" --config "<REPO>/cloud.env" --status
```

To ping now from the cloud, or to check recent runs:

```
gh workflow run keepalive.yml -f force=true -R <owner>/<repo>
gh run list --workflow keepalive.yml -L 5 -R <owner>/<repo>
```

Settings live in `cloud.env` (committed); editing and pushing it is what
changes cloud behaviour. `config.env` only affects the local scheduler.

## Answering common questions

| User asks | Do this |
|---|---|
| "When does my window reset?" / "Kotam ne zaman yenilenir?" | Run `--status` / `-Status` and report **window ends** and **next ping**. |
| "Is it running?" | `--status` shows the scheduler row: installed / NOT INSTALLED. |
| "Start a window now" | Run with `--force` / `-Force`. Warn that this consumes the current window and starts a new 5-hour one immediately. |
| "It isn't working" | Read the newest file in `<REPO>/logs/`. The most common cause is `not logged in` - the fix is `claude auth login` (or `codex login`). |
| "Turn it off" | Run the uninstall script. It only removes the scheduler entry; config and logs stay. |
| "Also keep ChatGPT/Codex alive" | Set `CODEX_ENABLED=true` in `<REPO>/config.env` (local) or `<REPO>/cloud.env` (cloud, then commit and push). |
| "Does it work when my PC is off?" | Only if the GitHub Actions workflow is set up. Check `gh run list --workflow keepalive.yml`. |

## Editing settings

`<REPO>/config.env` is a plain `KEY=VALUE` file. Keys:
`INTERVAL_MINUTES`, `CLAUDE_ENABLED`, `CLAUDE_MODEL`, `CLAUDE_PROMPT`,
`CODEX_ENABLED`, `CODEX_MODEL`, `CODEX_PROMPT`, `CODEX_REASONING_EFFORT`,
`LOG_RETENTION_DAYS`, `QUIET_HOURS`.

Changes take effect on the next scheduler tick - no restart needed.

## Cautions

- `--force` burns the currently open window. Only run it when the user asks.
- Do not lower `INTERVAL_MINUTES` below 300: pinging inside a live window
  wastes it without opening a new one.
