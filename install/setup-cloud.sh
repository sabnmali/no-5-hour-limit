#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# No 5-Hour Limit - one command that finishes the cloud setup (macOS / Linux).
#
# It will:
#   1. check that gh and claude are available and signed in
#   2. run `claude setup-token`, which opens your browser so you can approve
#   3. ask you to paste the token it printed
#   4. store it as the CLAUDE_CODE_OAUTH_TOKEN repository secret
#   5. trigger the workflow and wait for the result
#
# The token is never written to a file and never printed back.
#
#   ./install/setup-cloud.sh                    detect the repo from git
#   ./install/setup-cloud.sh --repo owner/name  say it explicitly
#   ./install/setup-cloud.sh --codex            also upload ~/.codex/auth.json
# ---------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

REPO=""
WITH_CODEX=0

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)   shift; REPO="${1:-}" ;;
        --codex)  WITH_CODEX=1 ;;
        -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

say()  { printf '  %s\n' "$*"; }
ok()   { printf '  OK  %s\n' "$*"; }
warn() { printf '  !   %s\n' "$*"; }
die()  { printf '  X   %s\n' "$*" >&2; exit 1; }
head_() { printf '\n  %s\n' "$*"; }

echo
echo "  No 5-Hour Limit - cloud setup"
echo "  ============================================================"

# --- 1. tools --------------------------------------------------------------
head_ "Step 1 of 5 - checking the tools"

command -v gh >/dev/null 2>&1 || \
    die "The GitHub CLI (gh) is not installed. See https://cli.github.com then run this again."

if ! gh auth status >/dev/null 2>&1; then
    warn "You are not signed in to GitHub. Starting the sign-in now..."
    gh auth login
    gh auth status >/dev/null 2>&1 || die "Still not signed in to GitHub - stopping."
fi
ok "GitHub CLI ready"

if ! command -v claude >/dev/null 2>&1; then
    # Having the Claude desktop app does not put `claude` on your PATH - the app
    # carries its own private copy. The command-line tool is a separate install.
    warn "The claude command-line tool is not installed on this computer yet."
    say  "(The Claude desktop app has its own private copy that other programs cannot use.)"
    echo
    command -v npm >/dev/null 2>&1 || \
        die "Installing it needs Node.js. Get it from https://nodejs.org then run this script again."

    printf '  Install it now? (press Enter for yes, or type n): '
    IFS= read -r answer
    case "$answer" in
        [nNhH]*) die "Nothing installed. Run this again when you are ready." ;;
    esac

    say "Installing - this takes a minute..."
    npm install -g @anthropic-ai/claude-code \
        || die "The install failed. Try running this by hand:  npm install -g @anthropic-ai/claude-code"

    hash -r 2>/dev/null || true
    command -v claude >/dev/null 2>&1 || \
        die "Installed, but the claude command still is not visible. Open a new terminal and run this script again."
    ok "claude installed: $(command -v claude)"
else
    ok "claude command found: $(command -v claude)"
fi

# --- 2. which repository ---------------------------------------------------
if [ -z "$REPO" ]; then
    remote="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
    if [[ "$remote" =~ github\.com[:/]+([^/]+)/([^/.]+) ]]; then
        REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    fi
fi
[ -n "$REPO" ] || die "Could not work out which GitHub repository to use. Re-run with:  --repo owner/name"
ok "repository: $REPO"

# --- 3. the token ----------------------------------------------------------
head_ "Step 2 of 5 - creating your login token"
say "A browser window will open. Sign in and approve, then come back here."
echo

claude setup-token

echo
say "Copy the long token printed above,"
printf '  paste it here and press Enter: '
IFS= read -r TOKEN
TOKEN="$(printf '%s' "$TOKEN" | tr -d '[:space:]')"

[ "${#TOKEN}" -ge 20 ] || die "That does not look like a token. Run the script again and paste the whole line."
ok "token received"

# --- 4. store it -----------------------------------------------------------
head_ "Step 3 of 5 - storing it on GitHub"

printf '%s' "$TOKEN" | gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo "$REPO" \
    || die "Could not store the secret. Check that you have access to the repository."
TOKEN=""
ok "CLAUDE_CODE_OAUTH_TOKEN stored (it is not saved anywhere on this computer)"

if [ "$WITH_CODEX" -eq 1 ]; then
    if [ -f "$HOME/.codex/auth.json" ]; then
        if gh secret set CODEX_AUTH_JSON --repo "$REPO" < "$HOME/.codex/auth.json"; then
            ok "CODEX_AUTH_JSON stored"
            if [ -f "$REPO_ROOT/cloud.env" ]; then
                tmp="$(mktemp)"
                sed 's/^[[:space:]]*CODEX_ENABLED[[:space:]]*=.*$/CODEX_ENABLED=true/' \
                    "$REPO_ROOT/cloud.env" > "$tmp" && mv "$tmp" "$REPO_ROOT/cloud.env"
                warn "cloud.env now has CODEX_ENABLED=true - commit and push it to switch Codex on."
            fi
        else
            warn "Could not store CODEX_AUTH_JSON - continuing without Codex."
        fi
    else
        warn "No ~/.codex/auth.json found. Run 'codex login' first if you want Codex too."
    fi
fi

# --- 5. first window -------------------------------------------------------
head_ "Step 4 of 5 - opening your first window"

gh workflow run keepalive.yml -f force=true --repo "$REPO" \
    || die "Could not start the workflow. Is Actions enabled on the repository?"
ok "workflow started"

# --- 6. wait and report ----------------------------------------------------
head_ "Step 5 of 5 - waiting for the result"

deadline=$(( $(date +%s) + 180 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
    sleep 5
    json="$(gh run list --workflow keepalive.yml --limit 1 \
            --json databaseId,status,conclusion --repo "$REPO" 2>/dev/null || true)"
    [ -n "$json" ] || continue

    status="$(printf '%s' "$json"     | tr -d ' \n' | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"
    conclusion="$(printf '%s' "$json" | tr -d ' \n' | sed -n 's/.*"conclusion":"\([^"]*\)".*/\1/p')"
    run_id="$(printf '%s' "$json"     | tr -d ' \n' | sed -n 's/.*"databaseId":\([0-9]*\).*/\1/p')"

    if [ "$status" = "completed" ]; then
        echo
        if [ "$conclusion" = "success" ]; then
            ok "It works. A fresh 5-hour window is open and it will keep renewing itself."
            echo
            say "Details: https://github.com/$REPO/actions/runs/$run_id"
            echo
            say "Nothing else to do. You can close this window."
            echo
            exit 0
        fi
        warn "The run finished with: $conclusion"
        say  "Look at what went wrong: https://github.com/$REPO/actions/runs/$run_id"
        say  "The most common cause is a token pasted incomplete - just run this script again."
        exit 1
    fi
    printf '.'
done

echo
warn "Still running after 3 minutes. It is probably fine - check here in a moment:"
say  "https://github.com/$REPO/actions"
