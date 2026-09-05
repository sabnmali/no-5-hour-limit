# Instructions for an AI coding agent

<!-- CLAUDE.md and AGENTS.md are kept identical on purpose: different
     tools look for different filenames. Edit one, mirror the other. -->

This file is for an assistant (Codex, Claude Code, or similar) that has been
pointed at this repository and asked to set it up for its user. Read
[README.md](README.md) for the full picture; this is the short operational
version.

## What this repository is

A keepalive. It sends a one-word prompt to the Claude CLI (and optionally the
Codex CLI) once 301 minutes have elapsed since the last successful ping, which
opens a fresh 5-hour usage window. It does **not** raise or bypass any limit -
it stops windows from being wasted, using the user's own subscription through
the official CLIs.

## Decide which route the user wants

| Route | Runs on | Works while the user's machine is off |
|---|---|---|
| **Cloud** (recommended) | GitHub Actions | yes |
| **Local** | Task Scheduler / launchd / cron | no |

Ask if it is not obvious. Do not set up both: two independent schedules ping
the same account and waste quota without opening extra windows.

## Cloud route

```bash
# Windows
powershell -ExecutionPolicy Bypass -File install\setup-cloud-windows.ps1
# macOS / Linux
./install/setup-cloud.sh
```

That script handles everything except the parts only a human can do. **You
must not run it for the user in a non-interactive shell** - it opens a browser
for sign-in and prompts for a pasted token. Tell the user to run it themselves
in their own terminal, and say why.

Before pointing them at it, you can usefully:

1. Confirm `gh` and `claude` are installed, and install what is missing
   (`npm install -g @anthropic-ai/claude-code`, https://cli.github.com).
2. Fork or create the GitHub repository and push, if they have not:
   `gh repo create no-5-hour-limit --public --source=. --remote=origin --push`
3. Check `cloud.env` matches what they want (interval, providers).
4. After they have run the setup script, verify:
   `gh run list --workflow keepalive.yml -L 3`

**Never handle the token yourself.** `claude setup-token` prints a credential
for the user's subscription. Do not run it, capture it, echo it, write it to a
file, or paste it into anything. The setup script keeps it in memory and pipes
it straight to `gh secret set`.

## Local route

```bash
# Windows
powershell -ExecutionPolicy Bypass -File install\install-windows.ps1
# macOS / Linux
./install/install-unix.sh
```

On Windows the installer registers the scheduler, pins the absolute CLI paths
into `config.env`, installs the Claude Code skill, and then runs the job once
to prove the scheduler can actually reach the CLI. The Unix installer does the
first three; it does not run that verification. On Windows, if it reports that
the scheduled task cannot see `claude`, run
`install\setup-cli-windows.ps1` - the npm global folder is not always visible
to the Task Scheduler service, and that script switches to the native build.

The user still has to run `claude auth login` once themselves.

## Configuration

Two plain `KEY=VALUE` files, same keys in both:

- `config.env` - local scheduler only. Git-ignored, created from
  `config.example.env` by the installer.
- `cloud.env` - GitHub Actions only. Committed, so it can be edited from
  github.com without a computer.

The status view's "window ends" is an estimate: it is the last ping plus five
hours. If the user opened the window themselves before the ping, the real
boundary is earlier.

Keys: `INTERVAL_MINUTES` (do not go below 300), `CLAUDE_ENABLED`,
`CLAUDE_MODEL`, `CLAUDE_PROMPT`, `CLAUDE_BIN`, `CODEX_ENABLED`, `CODEX_MODEL`,
`CODEX_PROMPT`, `CODEX_BIN`, `CODEX_REASONING_EFFORT`, `LOG_RETENTION_DAYS`,
`QUIET_HOURS`.

## Checking on it

```bash
# local state
./bin/keepalive.sh --status
powershell -ExecutionPolicy Bypass -File bin\keepalive.ps1 -Status

# cloud state
L5H_STATE_FILE=state/cloud-state.env ./bin/keepalive.sh --config cloud.env --status
gh run list --workflow keepalive.yml -L 5
```

`--due` reports what is owed and exits 3 when nothing is; `--enabled` lists
the providers a config turns on; `--force` pings immediately.

Be accurate about `--force`: it sends a message now, ignoring the interval and
quiet hours. It does **not** close or reset a window that is already open - a
message inside a live window changes nothing except spending a little quota.
It only opens a new window if the previous one has already expired.

## Security expectations

[SECURITY.md](SECURITY.md) is the reference. The parts you must not undo:

- Keep the workflow's triggers to `schedule` and `workflow_dispatch`. Adding
  `pull_request` would let a fork run it.
- Keep `permissions:` at `contents: write` and nothing more.
- Keep third-party actions pinned to commit SHAs.
- Keep the config-key allowlists in both keepalive scripts. They are what stops
  a config file from reassigning `PATH` or the state file location.
- Keep the log redactor. Cloud logs are public on a public repository.
- Never widen `INTERVAL_MINUTES` below its 60-minute floor.

## Things that will bite you

- **The Claude desktop app does not give the user the `claude` command.** The
  app ships its own private copy that other programs cannot call. The CLI is a
  separate `npm install -g @anthropic-ai/claude-code`. Check with
  `Get-Command claude` / `command -v claude` in the user's own terminal - a
  tool sandbox can see a copy that the machine itself does not have.
- **Schedulers do not inherit your shell's PATH.** That is what `CLAUDE_BIN` /
  `CODEX_BIN` are for; the installers fill them in.
- **The CLI's login is separate from the Claude desktop app.** `claude auth
  status` reporting `loggedIn: false` while the desktop app works is normal.
- **Codex refresh tokens rotate.** A `CODEX_AUTH_JSON` secret can go stale;
  the fix is to copy `~/.codex/auth.json` into the secret again.
- **Do not set `INTERVAL_MINUTES` below 300.** Pinging inside a live window
  consumes quota without opening a new window.
- **`.sh` files must keep LF endings.** `.gitattributes` enforces this; do not
  override it.
