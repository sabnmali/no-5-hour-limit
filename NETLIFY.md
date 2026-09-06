# Independent cloud scheduling

Netlify wakes GitHub Actions every fifteen minutes. Actions still enforces the
301-minute interval and serializes runs. Netlify never receives AI credentials.
This removes dependence on GitHub's cron delivery, not GitHub runner availability
or the providers' quota rules. No component guarantees an always-open window.

1. Import this repository into Netlify, using the default branch and netlify.toml.
   Only the published production deployment runs scheduled functions.
2. Create a fine-grained GitHub token restricted to this repository with
   **Actions: read and write**. Do not use your account-wide CLI token.
3. In Netlify, store it as **L5H_GITHUB_DISPATCH_TOKEN**, restricted to Functions
   and production. Set **L5H_GITHUB_REPOSITORY** to your `owner/repo` and
   **L5H_GITHUB_BRANCH** to the default branch. Redeploy after changing variables.
4. Use Functions > dispatch > Run now. Confirm a new workflow_dispatch run in
   GitHub Actions, then confirm a later scheduled invocation without your PC.
   HTTP 204 means GitHub accepted dispatch, not that a provider was pinged.
5. Check Netlify function failures and GitHub Actions failures. Renew the token
   before its expiry. Stay within your Netlify plan; there are about 2,880
   invocations per 30 days. State-only commits are skipped by the build ignore rule.

No new npm dependencies or public trigger endpoint are used. GitHub cron can
remain as fallback because all dispatches use the same lock and state.

Each scheduler makes 96 checks per day instead of 288 at five-minute intervals.
Checks do not send AI prompts unless due. Polling can add up to fifteen minutes
after the 301-minute threshold, plus any platform scheduling or runner delay.
These checks are internal operations, not user notifications.

## Cloud Codex credentials

Cloud Codex needs its own subscription login, not a copy of a desktop session.
Use a separate CODEX_HOME outside this repository and perform `codex login` there
interactively. Store its auth.json as CODEX_AUTH_JSON using gh secret set via
stdin. Never print or commit it; remove the disposable local copy after upload.

A second fine-grained token, restricted to this repository with **Secrets: read
and write**, must be stored as **CODEX_SECRET_UPDATE_TOKEN in GitHub only**.
The workflow saves auth.json back to CODEX_AUTH_JSON after each invocation,
including failures, so normal refresh rotation survives the ephemeral runner.
GitHub cannot scope this permission to a single secret: the token can replace
other repository secrets. It cannot read secret values back. Review that access
before creating it. Do not give this second token to Netlify.

Set CODEX_ENABLED=true in cloud.env only after both secrets exist. Verify a cloud
Codex turn before disabling its local scheduler. Revocation, login expiry,
provider policy changes or a failed secret write can still require signing in
again. A copied desktop login is not made safe merely by persisting it here.

## Provider-native scheduling

[Claude Routines](https://code.claude.com/docs/en/routines) run in Claude's cloud
but create full agent sessions and have routine limits. They are an alternative
scheduler, not proof that every Claude model counter starts.
[ChatGPT scheduled tasks](https://help.openai.com/en/articles/10291617-scheduled-tasks-in-chatgpt)
and Codex automations are separate. Scheduling a ChatGPT task is not a supported
way to start every ChatGPT and Codex allowance together.

## Disable and revoke

Pause/delete the Netlify production deployment's scheduled function or remove
the project, then revoke its dedicated GitHub token. Disable keepalive.yml to
stop the fallback too. For Codex, revoke its dedicated login and secret-update
token and remove CODEX_AUTH_JSON and CODEX_SECRET_UPDATE_TOKEN. Deleting secret
storage alone is not revocation.
