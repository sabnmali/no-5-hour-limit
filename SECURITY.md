# Security

## What this project touches

It runs two official CLIs with a one-word prompt on a timer. It has no server,
no database, no web interface, no user accounts and no network listener of its
own. That removes most of the usual attack surface, but two things do matter:
**a credential for your AI subscription**, and **a scheduled job that can run
commands on your behalf**.

## Where credentials live

| | Stored | Visible to |
|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | GitHub repository secret | GitHub Actions at run time; nobody can read it back, including you |
| `CODEX_AUTH_JSON` | GitHub repository secret | same |
| Local CLI login | Whatever the CLI itself uses (`claude auth login`) | your machine only |

The setup scripts hold the token in memory and pipe it straight into
`gh secret set`. It is never written to a file, never echoed back, and never
passed as a command-line argument (so it does not land in your shell history
or the process list).

Nothing secret is ever committed. `config.env` is git-ignored; `cloud.env` and
`state/cloud-state.env` are committed on purpose and contain only settings and
timestamps.

## Revoking access

Removing the scheduler is not the same as revoking the credential. To fully cut
access:

```bash
# 1. stop the job
gh workflow disable keepalive.yml

# 2. delete the stored credentials
gh secret delete CLAUDE_CODE_OAUTH_TOKEN
gh secret delete CODEX_AUTH_JSON

# 3. revoke the token itself, so it is dead even if a copy leaked
#    Claude: https://claude.ai/settings  ->  revoke the Claude Code token
#    Codex : log out with `codex logout`, which invalidates the stored session
```

Step 3 is the one that actually matters. Steps 1 and 2 only stop *this*
repository from using it.

For a local install, `install/uninstall-*` removes the scheduler; the CLI stays
logged in until you run `claude auth logout`.

## Noticing when something is wrong

GitHub emails you when a scheduled workflow fails, and every run writes a
summary showing when the current window ends. That is the alerting path - if
pings stop, you hear about it.

Two guards limit the damage from a misconfiguration:

- `INTERVAL_MINUTES` is floored at 60 in code, so a typo like `1` cannot turn
  the job into a loop that burns your quota.
- Only keys the scripts actually define are read from a config file. A config
  cannot reassign `PATH`, the state file location, or any other internal.

Actions minutes are free and unlimited on public repositories, so there is no
spending risk to cap.

## Hardening already applied

- Workflow triggers are `schedule` and `workflow_dispatch` only. There is no
  `pull_request` trigger, so a fork or a pull request can never run this
  workflow, and GitHub does not expose secrets to forks in any case.
- `permissions:` grants `contents: write` and nothing else. That is the minimum
  needed to commit the timestamp file.
- Third-party actions are pinned to commit SHAs, not tags, because a tag can be
  repointed at different code. Dependabot proposes updates monthly so the pins
  do not silently rot.
- Log output is passed through a redactor that masks anything token-shaped
  before it can reach a log file or a public Actions log.
- Error messages are truncated and never include raw credential material.
- `.sh` files are `text eol=lf` in `.gitattributes`, so a CRLF checkout cannot
  turn a script into something that fails open.

## Deliberately out of scope

The project has no database, no HTTP endpoints, no HTML rendering, no file
uploads, no cookies and no password storage, so SQL injection, XSS, CORS,
security headers, upload limits, session flags and password hashing have no
surface to apply to here.

## Reporting a problem

Open an issue, or use GitHub's private vulnerability reporting on this
repository. Please do not include a token or any part of one in the report.
