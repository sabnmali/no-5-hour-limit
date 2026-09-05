# No 5-Hour Limit

A scheduled, minimal prompt for the official Claude Code and Codex CLIs.
[Türkçe](README.tr.md) · [Security](SECURITY.md)

## What it actually does

Checks periodically and sends `ok` when at least **301 minutes** have passed
since that provider's last successful ping. Each provider has independent state.
A ping may start an idle usage window; it cannot reset a window already in
progress, increase your allowance, or guarantee that quota will be available
when you return. All pings consume usage, including weekly allowances.

The name is not a promise of unlimited use. The script tracks **its own ping
timestamps**, not the provider's actual window boundaries. A successful CLI
response proves a message was processed, not that a new window opened.

## Which apps and models does it cover?

| Surface | Coverage |
|---|---|
| Claude / Claude Code / Cowork | Claude Code usage contributes to the shared allowance on applicable subscription plans. Additional model, feature, weekly and monthly limits still apply. |
| Codex | Sends a message through the official Codex CLI using ChatGPT login. |
| Normal ChatGPT conversations | **Not supported.** Chat usage rules are separate from Work/Codex. A Codex ping does not start all ChatGPT model counters. |
| Other AI tools or models | No generic support. An official integration and that provider's actual metering rules must be checked first. |

Provider references (reviewed September 2026):
[OpenAI: Chat versus Work/Codex allowances](https://help.openai.com/en/articles/20001354),
[Claude Code on Pro/Max](https://support.claude.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan),
[Claude usage limits](https://support.claude.com/en/articles/9797557-usage-limit-best-practices).
Shared usage does not prove that one ping initializes every model-specific counter.

## Choose where it runs

Choose **one scheduler per provider/account**, including across devices.
Claude in the cloud and Codex locally is fine; running the same provider on
both independent schedules wastes quota.

- **Local:** Windows Task Scheduler, macOS launchd, Linux cron. Uses your existing
  CLI login and persistent credential storage. The computer must be awake and
  online. Windows uses an interactive user task; it requires you to be logged in.
- **Cloud:** GitHub Actions. Works while your computer is off. Polls every 30
  minutes; GitHub can delay or drop scheduled runs, so timing is not guaranteed.
  Requires a subscription credential stored in your repository's Actions secrets.

**Prefer local Codex.** Its refresh credentials rotate. Copying the same login
into an ephemeral cloud runner can make the repository secret stale and conflict
with your desktop login. Cloud Codex is an optional setup requiring credential
maintenance, not an unattended permanent login. This project does not refresh
GitHub secrets automatically.

## Local installation

Install the official CLIs separately and log in with your subscription:

```sh
claude auth login
codex login  # optional; use ChatGPT sign-in, not an API key
```

Tested CLI versions: Claude Code **2.1.261**, Codex **0.153.1**. Older versions
may lack the isolation flags used here. No runtime Python dependency is needed.

```sh
git clone https://github.com/sabnmali/no-5-hour-limit.git
cd no-5-hour-limit
```

Copy `config.example.env` to `config.env` and choose enabled providers before
installing, especially if Claude already runs in the cloud. For Codex only:

```ini
CLAUDE_ENABLED=false
CODEX_ENABLED=true
```

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install\install-windows.ps1
```

macOS / Linux:

```sh
./install/install-unix.sh
```

Installers register the scheduler, record CLI paths, and install the bundled
Claude skill. Windows also starts the task and checks its completion. A no-op
run is not proof of CLI connectivity. On macOS/Linux, run the script once to
check a due ping. If the CLI cannot be found, set its absolute `*_BIN` path.
`install/setup-cli-windows.ps1` can help install/login to the native Claude CLI.

## Cloud installation

Fork this repository into your own GitHub account. In your clone, run the setup
script **in your own interactive terminal**; Claude sign-in and token entry
require a person. The assistant should never capture the printed Claude token.

```powershell
powershell -ExecutionPolicy Bypass -File install\setup-cloud-windows.ps1
```

```sh
./install/setup-cloud.sh
```

The setup stores `CLAUDE_CODE_OAUTH_TOKEN` as a repository secret and dispatches
the workflow. Configure providers in **cloud.env**, not config.env. For optional
cloud Codex, `-Codex` (Windows) / `--codex` uploads auth.json and edits cloud.env;
you must **commit and push that edit** before Codex is enabled on GitHub.
Use a dedicated login and expect to reauthenticate when its secret expires.
Never commit credentials. A GitHub secret is still accessible to code run by
trusted repository writers; a public repository does not make it safe to run
unreviewed changes. Forks do not inherit the upstream secrets.

The workflow runs on the default branch only and needs `contents: write` to
save timestamps. Third-party action SHAs and CLI versions are pinned. Review
updates before changing them. Scheduled workflows can be disabled by GitHub
for inactivity or other account/repository conditions; check Actions regularly.
Standard hosted runners are free on public repositories under GitHub's applicable
terms. Private-repository allowances and overage charges vary; no fixed monthly
cost guarantee is made.

## Configuration

`config.env` is local and ignored by Git. `cloud.env` is public configuration.
Both are data-only KEY=VALUE files; unknown keys are ignored.

| Key | Default | Meaning |
|---|---|---|
| INTERVAL_MINUTES | 301 | Minimum minutes since last successful ping; clamped to 300–525600. |
| CLAUDE_ENABLED | true | Enable Claude. |
| CLAUDE_MODEL | haiku | Claude model alias or ID. |
| CLAUDE_PROMPT | ok | Keep it short. |
| CLAUDE_BIN | empty | Explicit executable path; otherwise search common locations. |
| CODEX_ENABLED | false | Enable Codex. |
| CODEX_MODEL | empty | Codex CLI built-in default; user config is intentionally ignored. Set a lightweight model available on your plan. |
| CODEX_PROMPT | ok | Keep it short. |
| CODEX_BIN | empty | Explicit executable path. |
| CODEX_REASONING_EFFORT | low | Must be supported by the selected model. |
| LOG_RETENTION_DAYS | 30 | Prune old monthly keepalive log files; 0 disables pruning. |
| QUIET_HOURS | empty | Local time HH:MM-HH:MM; GitHub runners use UTC. |

Claude runs with safe mode, restricted mode, no built-in tools and no MCP.
Codex uses read-only sandboxing, ignores user config/rules and disables project
document loading. Codex still has its built-in tools; do not use untrusted prompts.
Managed CLI policies may still apply. Each CLI invocation is bounded to about
120 seconds; a failed provider does not discard another provider's success.

## Status and manual checks

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File bin\keepalive.ps1 -Status
powershell -NoProfile -ExecutionPolicy Bypass -File bin\keepalive.ps1 -DryRun
# Only when an immediate real message is wanted:
powershell -NoProfile -ExecutionPolicy Bypass -File bin\keepalive.ps1 -Force
```

```sh
./bin/keepalive.sh --status
./bin/keepalive.sh --dry-run
./bin/keepalive.sh --force
# Cloud timestamps from this checkout (fetch current state first if needed):
L5H_STATE_FILE=state/cloud-state.env ./bin/keepalive.sh --config cloud.env --status
gh run list --workflow keepalive.yml -L 5
```

Estimated window end = last ping + five hours, **not a provider-reported reset**.
Use the provider's Usage page for actual limits. `--force` ignores both interval
and quiet hours; it does not reset a live window. Bash `--due` exits 0 if due,
3 if nothing is due, and 2 for invalid CLI arguments/config paths. `--enabled`
prints the enabled providers. Normal execution exits 1 on provider/state failure.

## Troubleshooting and removal

A green GitHub run can mean only “nothing due.” Inspect the **Ping** step and
saved timestamps to verify an actual message. CLI errors intentionally withhold
raw output to keep credentials out of public logs. Check `claude auth status` /
`codex login status` locally, installed CLI versions, and model availability.
A failed ping is retried at the next scheduler check; no tight retry loop is used.

```powershell
powershell -ExecutionPolicy Bypass -File install\uninstall-windows.ps1
```

```sh
./install/uninstall-unix.sh
# Cloud:
gh workflow disable keepalive.yml
```

Local uninstall keeps configuration, state and CLI logins. Disabling a workflow
does not revoke its credentials. See [SECURITY.md](SECURITY.md) for revocation.

## Development

```sh
python -m unittest discover -s tests -v
```

Tests use fake CLIs and temporary directories, never real AI accounts. The test
workflow covers Windows, Linux and macOS. Runtime scripts live in `bin/`,
installers in `install/`, and agent instructions in identical `AGENTS.md` and
`CLAUDE.md`. Local logs, credentials and instruction backups are git-ignored.

MIT — [LICENSE](LICENSE). Not affiliated with Anthropic or OpenAI.
