# Limitless 5-Hour

**Keep your Claude and ChatGPT/Codex 5-hour usage windows on a schedule you control.**

[Türkçe README](README.tr.md)

---

## The problem

Claude Code and Codex both meter usage in **rolling 5-hour windows**. The clock
starts on your *first* message, not at a fixed time of day. So if you send one
quick message at 09:40 and then don't come back until 13:00, you've burned four
hours of a window you never used — and your next window won't open until 14:40.

## What this does

A tiny background job sends a one-word prompt to the CLI every **301 minutes**
(5 h + 1 min). Each ping opens a fresh window the moment the previous one
closes, so:

- windows tile back-to-back around the clock, 24/7
- you always know exactly when the current one ends and the next one starts
- you never accidentally waste a window on a two-second question

It runs either on your own machine (Task Scheduler / cron / launchd) or
entirely in the cloud on GitHub Actions, which keeps going while your computer
is off, asleep, or offline. The cloud route is the one most people want.

The ping runs on the **cheapest model** (Haiku by default) with the system
prompt replaced by six words and every tool disabled, so it costs a rounding
error's worth of quota.

## What it is not

This does **not** raise your limits, bypass anything, or give you extra quota.
It just makes the window boundaries land where you want them. It uses your own
subscription through the official CLIs, exactly as if you had typed `ok`
yourself.

---

## Requirements

| | |
|---|---|
| **Claude** | [Claude Code CLI](https://claude.com/claude-code) + a Claude subscription |
| **Codex** *(optional)* | [Codex CLI](https://github.com/openai/codex) + a ChatGPT plan that includes Codex |
| **OS** | Windows 10/11, macOS, or Linux |

A machine that stays on. On a laptop that sleeps, missed pings fire as soon as
it wakes.

---

## Install

```bash
git clone https://github.com/<you>/limitless-5-hour.git
cd limitless-5-hour
```

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File install\install-windows.ps1
```

Creates a Task Scheduler entry named `Limitless5Hour` that runs as you, needs
no administrator rights, and survives reboots and sleep.

### macOS / Linux

```bash
./install/install-unix.sh
```

Registers a LaunchAgent on macOS, or a crontab entry on Linux.

### Then, once

```bash
claude auth login       # the CLI needs its own login, separate from the desktop app
codex login             # only if you enable Codex
```

On Windows there is a helper that does the login *and* makes sure the CLI sits
somewhere the Task Scheduler can actually reach - run it in a normal PowerShell
window:

```powershell
powershell -ExecutionPolicy Bypass -File install\setup-cli-windows.ps1
```

### Start the first window

```bash
# Windows
powershell -ExecutionPolicy Bypass -File bin\keepalive.ps1 -Force
# macOS / Linux
./bin/keepalive.sh --force
```

---

## Run it in the cloud (recommended)

Everything above needs your own computer to be awake. If you would rather it
kept going while your machine is off, asleep, or offline, push this repository
to GitHub and let GitHub Actions send the pings. The workflow in
[`.github/workflows/keepalive.yml`](.github/workflows/keepalive.yml) is ready
to go.

**1. Create the credentials**

On any machine, once:

```bash
claude setup-token     # prints a long-lived token - copy it
```

For Codex, copy the whole contents of `~/.codex/auth.json` (optional).

**2. Push the repo and add the secrets**

```bash
gh repo create limitless-5-hour --public --source=. --remote=origin --push
gh secret set CLAUDE_CODE_OAUTH_TOKEN
gh secret set CODEX_AUTH_JSON < ~/.codex/auth.json
```

Or on the website: **Settings -> Secrets and variables -> Actions -> New
repository secret**.

**3. Turn it on**

Open the **Actions** tab, enable the `keepalive` workflow, then
**Run workflow** with *Force* ticked to open the first window immediately.

From then on it runs on GitHub's machines, forever, with your computer out of
the picture entirely.

### Managing it without a computer

`cloud.env` is committed to the repo, so you can open it on github.com from
your phone, change the interval or switch Codex on, and the next run picks it
up. Every ping writes a summary showing when the current window ends, and
`state/cloud-state.env` records the last ping time.

### What to know before you rely on it

- **Timing is approximate.** GitHub's scheduler is best-effort: runs are often
  a few minutes late and occasionally half an hour. Windows still tile, the
  boundaries just are not to the minute.
- **Keep the repo public** for unlimited Actions minutes. On a private repo the
  15-minute schedule would consume most of the 2000 free minutes - change the
  cron to `0,30 * * * *` there.
- **Scheduled workflows are disabled after 60 days without repository
  activity.** Each ping commits the state file, which counts as activity.
- **The token grants access to your subscription.** Only put it in a repository
  you control. Secrets are not exposed to forks or pull requests.
- **Codex refresh tokens rotate.** If Codex pings start failing, copy
  `~/.codex/auth.json` into the secret again.

### Cloud or local?

Pick one. Running both means two independent schedules pinging the same
account, which wastes a little quota without opening any extra windows. If you
move to the cloud, remove the local task:

```powershell
powershell -ExecutionPolicy Bypass -File install\uninstall-windows.ps1
```

---

## Daily use

You don't have to do anything. To look in on it:

```bash
# Windows
powershell -ExecutionPolicy Bypass -File bin\keepalive.ps1 -Status
# macOS / Linux
./bin/keepalive.sh --status
```

```
  Limitless 5-Hour - status
  ---------------------------------------------------------
  config       : /home/you/limitless-5-hour/config.env
  interval     : 301 minutes
  quiet hours  : disabled (24/7)

  claude       : enabled
     last ping   2026-09-05 09:12:04
     window ends 2026-09-05 14:12:04  (3h 41m left)
     next ping   2026-09-05 14:13:04
  codex        : disabled

  scheduler    : installed, state = Ready
  log file     : /home/you/limitless-5-hour/logs/keepalive-2026-09.log
```

If you installed the bundled Claude Code skill (the installer does it for you),
you can also just ask Claude in plain language — *"when does my window reset?"*
— and it will run the status check for you.

---

## Configuration

Edit `config.env` (created from `config.example.env` on first install). Changes
take effect on the next tick; nothing to restart.

| Key | Default | Meaning |
|---|---|---|
| `INTERVAL_MINUTES` | `301` | Minutes between pings. Don't go below 300 — pinging inside a live window wastes it. |
| `CLAUDE_ENABLED` | `true` | Keep the Claude window rolling. |
| `CLAUDE_MODEL` | `haiku` | Model used for the ping. Cheapest is best. |
| `CLAUDE_PROMPT` | `ok` | The ping text. Keep it short. |
| `CLAUDE_BIN` | *(filled in by the installer)* | Absolute path to `claude`. Needed because schedulers run with a stripped-down `PATH`. |
| `CODEX_ENABLED` | `false` | Set to `true` to keep the Codex window rolling too. |
| `CODEX_MODEL` | *(empty)* | Empty = whatever your Codex config defaults to. |
| `CODEX_BIN` | *(filled in by the installer)* | Absolute path to `codex`. |
| `CODEX_REASONING_EFFORT` | `minimal` | Keeps the Codex ping cheap. |
| `LOG_RETENTION_DAYS` | `30` | Delete logs older than this. `0` = keep forever. |
| `QUIET_HOURS` | *(empty)* | e.g. `02:00-08:00` to skip pings overnight. Empty = true 24/7. |

### Adding ChatGPT / Codex

Codex meters the same way. Two steps:

```bash
codex login
```

then in `config.env`:

```
CODEX_ENABLED=true
```

Both providers are tracked independently, so if one is rate-limited the other
keeps going.

---

## How it works

```
scheduler (every 5 min)  ->  keepalive script
                                  |
                                  +-- has INTERVAL_MINUTES passed
                                  |   since the last successful ping?
                                  |
                                 no --> exit, cost nothing
                                  |
                                 yes -> claude -p "ok" --model haiku ...
                                        record the timestamp
                                        append one line to logs/
```

The script — not the scheduler — decides when a ping is due. That is what makes
it survive sleep, reboots, missed runs, and clock changes: whatever happens, the
next time it wakes up it just asks *"has it been 301 minutes?"*

The ping is deliberately stripped down:

```
claude -p "ok" --model haiku
       --system-prompt "Reply with exactly: ok"   # replaces the full system prompt
       --restricted                               # no Bash, no code execution
       --strict-mcp-config                        # no MCP servers loaded
       --no-session-persistence                   # nothing written to disk
       --permission-mode dontAsk                  # never blocks on a prompt
       --output-format json
```

---

## Files

```
.github/workflows/        GitHub Actions: the device-independent scheduler
cloud.env                  Cloud settings - committed, editable from the web
state/cloud-state.env      Cloud last-ping timestamps (committed by the runner)
bin/keepalive.ps1          Windows: the whole thing (ping, state, status)
bin/keepalive.sh           macOS/Linux: same
install/install-*.{ps1,sh} Register the scheduler + install the skill
install/setup-cli-windows.ps1  Windows: native CLI install + login + re-register
install/uninstall-*        Remove the scheduler (keeps config and logs)
skill/limitless-5-hour/    Claude Code skill: ask about your window in chat
config.example.env         Template for config.env
logs/                      One log file per month
state/                     Last-ping timestamps
```

---

## Troubleshooting

**`not logged in - run: claude auth login`**
The CLI keeps its own credentials, separate from the Claude desktop app. Run
`claude auth login` once in a terminal.

**The background task does nothing, but running it by hand works**

The Task Scheduler service launches processes with a different environment -
and on some Windows machines a different view of `%APPDATA%` - than your
interactive shell. A `claude` installed through npm lives in `%APPDATA%\npm`,
which the scheduler may not be able to see, so the log fills with
`claude CLI not found`.

The installer detects this and tells you. The fix is to switch to the native
build, which installs under your user folder where the scheduler can reach it:

```powershell
powershell -ExecutionPolicy Bypass -File install\setup-cli-windows.ps1
```

That installs the native build, logs the CLI in, and re-registers the task.
On any platform you can also point at the binary yourself in `config.env`:

```
CLAUDE_BIN=C:\Users\you\.local\bin\claude.exe
```

**Nothing in the logs**
Check the scheduler row in `-Status` / `--status`. On Windows, look for
`Limitless5Hour` in Task Scheduler; on Linux, `crontab -l`.

**`usage limit reached`**
Expected when you've already exhausted a window. The script backs off and
retries on the next tick.

**Cron can't find `claude`**
Cron runs with a minimal `PATH`. Put the absolute path in the crontab line, or
add a `PATH=` line at the top of your crontab.

---

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File install\uninstall-windows.ps1
```

```bash
./install/uninstall-unix.sh
```

Removes the scheduler entry only. `config.env`, `logs/` and `state/` stay put;
delete the folder to remove everything.

---

## License

MIT — see [LICENSE](LICENSE).

Not affiliated with Anthropic or OpenAI. Use it within the terms of your own
subscription.
