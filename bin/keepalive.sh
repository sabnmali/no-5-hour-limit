#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Limitless 5-Hour - keeps AI CLI usage windows rolling (macOS / Linux).
#
# Sends a minimal "ping" prompt to the Claude CLI and/or the Codex CLI once the
# configured interval has elapsed since the last successful ping. That opens a
# fresh 5-hour usage window, so window boundaries stay predictable.
#
# The script is idempotent: it only pings when the interval has actually
# elapsed, so cron just needs to poke it every few minutes.
#
#   ./bin/keepalive.sh              run a due check (what cron calls)
#   ./bin/keepalive.sh --status     show last ping / window end / next ping
#   ./bin/keepalive.sh --force      ping now, ignoring interval + quiet hours
#   ./bin/keepalive.sh --dry-run    print the commands without running them
#   ./bin/keepalive.sh --due        list providers needing a ping; exit 3 if none
#   ./bin/keepalive.sh --config F   read settings from F instead of config.env
#
# Env overrides: L5H_CONFIG (config file), L5H_STATE_FILE (state file).
# ---------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$REPO_ROOT/logs"
STATE_DIR="$REPO_ROOT/state"
# L5H_STATE_FILE / L5H_CONFIG let a caller (e.g. the GitHub Actions runner)
# point at a different state file and config without touching the local ones.
STATE_FILE="${L5H_STATE_FILE:-$STATE_DIR/state.env}"
WORK_DIR="$STATE_DIR/workdir"
CONFIG_PATH="${L5H_CONFIG:-$REPO_ROOT/config.env}"

DO_STATUS=0
DO_FORCE=0
DO_DRYRUN=0
DO_DUE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --status)   DO_STATUS=1 ;;
        --force)    DO_FORCE=1 ;;
        --dry-run)  DO_DRYRUN=1 ;;
        --due)      DO_DUE=1 ;;
        --config)   shift; CONFIG_PATH="${1:-}" ;;
        -h|--help)  sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

mkdir -p "$LOG_DIR" "$STATE_DIR" "$WORK_DIR" "$(dirname "$STATE_FILE")"

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
INTERVAL_MINUTES=301
CLAUDE_ENABLED=true
CLAUDE_MODEL=haiku
CLAUDE_PROMPT=ok
CLAUDE_BIN=
CODEX_ENABLED=false
CODEX_MODEL=
CODEX_PROMPT=ok
CODEX_BIN=
CODEX_REASONING_EFFORT=minimal
LOG_RETENTION_DAYS=30
QUIET_HOURS=

load_kv_file() {
    # Reads KEY=VALUE lines without executing the file.
    local file="$1" line key val
    [ -f "$file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        case "$line" in ''|'#'*) continue ;; esac
        case "$line" in *=*) ;; *) continue ;; esac
        key="${line%%=*}"
        val="${line#*=}"
        key="$(printf '%s' "$key" | tr -d '[:space:]')"
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        val="${val%\"}"; val="${val#\"}"
        val="${val%\'}"; val="${val#\'}"
        case "$key" in
            [A-Za-z_][A-Za-z0-9_]*) printf -v "$key" '%s' "$val" ;;
        esac
    done < "$file"
}

load_kv_file "$CONFIG_PATH"

case "$INTERVAL_MINUTES" in
    ''|*[!0-9]*) INTERVAL_MINUTES=301 ;;
esac
[ "$INTERVAL_MINUTES" -ge 1 ] 2>/dev/null || INTERVAL_MINUTES=301

is_true() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        true|1|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
LOG_FILE="$LOG_DIR/keepalive-$(date +%Y-%m).log"

log() {
    local level="$1"; shift
    local line
    line="$(printf '[%s] %-5s %s' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$(printf '%s' "$level" | tr '[:lower:]' '[:upper:]')" "$*")"
    printf '%s\n' "$line" >> "$LOG_FILE"
    printf '%s\n' "$line"
}

prune_logs() {
    case "$LOG_RETENTION_DAYS" in ''|*[!0-9]*) return 0 ;; esac
    [ "$LOG_RETENTION_DAYS" -gt 0 ] || return 0
    find "$LOG_DIR" -maxdepth 1 -name 'keepalive-*.log' -type f \
        -mtime "+$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# State  (state.env holds e.g.  CLAUDE_LAST=1757075400 )
# ---------------------------------------------------------------------------
CLAUDE_LAST=0
CODEX_LAST=0
load_kv_file "$STATE_FILE"
case "$CLAUDE_LAST" in ''|*[!0-9]*) CLAUDE_LAST=0 ;; esac
case "$CODEX_LAST"  in ''|*[!0-9]*) CODEX_LAST=0  ;; esac

save_state() {
    {
        echo "# Limitless 5-Hour state - epoch seconds of the last successful ping"
        echo "CLAUDE_LAST=$CLAUDE_LAST"
        echo "CODEX_LAST=$CODEX_LAST"
    } > "$STATE_FILE"
}

fmt_time() {
    # $1 = epoch seconds -> local human time (GNU and BSD date)
    local e="$1"
    date -d "@$e" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
        || date -r "$e" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
        || echo "$e"
}

# ---------------------------------------------------------------------------
# Quiet hours
# ---------------------------------------------------------------------------
in_quiet_hours() {
    [ -n "$QUIET_HOURS" ] || return 1
    local re='^([0-9]{1,2}):([0-9]{2})-([0-9]{1,2}):([0-9]{2})$'
    local spec; spec="$(printf '%s' "$QUIET_HOURS" | tr -d '[:space:]')"
    [[ "$spec" =~ $re ]] || return 1
    local start=$((10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]}))
    local end=$((10#${BASH_REMATCH[3]} * 60 + 10#${BASH_REMATCH[4]}))
    local now=$((10#$(date +%H) * 60 + 10#$(date +%M)))
    if [ "$start" -le "$end" ]; then
        [ "$now" -ge "$start" ] && [ "$now" -lt "$end" ]
    else
        [ "$now" -ge "$start" ] || [ "$now" -lt "$end" ]
    fi
}

# ---------------------------------------------------------------------------
# Providers
# ---------------------------------------------------------------------------
PING_MESSAGE=''

# resolve_cli <name> -> echoes an absolute path, or nothing.
# Schedulers (cron, launchd) run with a stripped-down PATH, so an explicit path
# from config.env wins; the installer fills it in.
resolve_cli() {
    local name="$1" configured="" var candidate
    var="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')_BIN"
    configured="${!var:-}"

    if [ -n "$configured" ] && [ -x "$configured" ]; then
        printf '%s' "$configured"; return 0
    fi
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"; return 0
    fi
    for candidate in "$HOME/.local/bin/$name" \
                     "$HOME/bin/$name" \
                     "$HOME/.npm-global/bin/$name" \
                     "/usr/local/bin/$name" \
                     "/opt/homebrew/bin/$name" \
                     "/usr/bin/$name"
    do
        [ -x "$candidate" ] && { printf '%s' "$candidate"; return 0; }
    done
    return 1
}

ping_claude() {
    PING_MESSAGE=''
    local exe
    if ! exe="$(resolve_cli claude)"; then
        PING_MESSAGE='claude CLI not found (set CLAUDE_BIN in config.env, or npm i -g @anthropic-ai/claude-code)'
        return 1
    fi

    local args=(
        -p "$CLAUDE_PROMPT"
        --model "$CLAUDE_MODEL"
        --system-prompt 'Reply with exactly: ok'
        --restricted
        --strict-mcp-config
        --no-session-persistence
        --permission-mode dontAsk
        --output-format json
    )

    if [ "$DO_DRYRUN" -eq 1 ]; then
        PING_MESSAGE="DRY RUN: claude ${args[*]}"
        return 0
    fi

    local out
    out="$(cd "$WORK_DIR" && "$exe" "${args[@]}" 2>&1)"

    if printf '%s' "$out" | grep -qi 'not logged in'; then
        PING_MESSAGE='not logged in - run: claude auth login'
        return 1
    fi
    if printf '%s' "$out" | grep -q '"is_error"[[:space:]]*:[[:space:]]*true'; then
        PING_MESSAGE="claude error: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-300)"
        return 1
    fi
    if ! printf '%s' "$out" | grep -q '"type"[[:space:]]*:[[:space:]]*"result"'; then
        PING_MESSAGE="unreadable claude output: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-300)"
        return 1
    fi

    PING_MESSAGE="claude ok (model=$CLAUDE_MODEL)"
    return 0
}

ping_codex() {
    PING_MESSAGE=''
    local exe
    if ! exe="$(resolve_cli codex)"; then
        PING_MESSAGE='codex CLI not found (set CODEX_BIN in config.env, or npm i -g @openai/codex)'
        return 1
    fi

    local args=(exec --skip-git-repo-check --ephemeral -s read-only -C "$WORK_DIR")
    [ -n "$CODEX_MODEL" ] && args+=(-m "$CODEX_MODEL")
    [ -n "$CODEX_REASONING_EFFORT" ] && args+=(-c "model_reasoning_effort=\"$CODEX_REASONING_EFFORT\"")
    args+=("$CODEX_PROMPT")

    if [ "$DO_DRYRUN" -eq 1 ]; then
        PING_MESSAGE="DRY RUN: codex ${args[*]}"
        return 0
    fi

    local out
    out="$("$exe" "${args[@]}" 2>&1)"

    if printf '%s' "$out" | grep -qi 'usage limit'; then
        PING_MESSAGE='usage limit reached - will retry next cycle'
        return 1
    fi
    if printf '%s' "$out" | grep -qi 'not logged in'; then
        PING_MESSAGE='not logged in - run: codex login'
        return 1
    fi
    if printf '%s' "$out" | grep -qi '^ERROR:'; then
        PING_MESSAGE="error: $(printf '%s' "$out" | grep -i '^ERROR:' | head -1 | cut -c1-200)"
        return 1
    fi

    PING_MESSAGE='codex ok'
    return 0
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
show_status() {
    local now; now="$(date +%s)"
    echo
    echo "  Limitless 5-Hour - status"
    echo "  ---------------------------------------------------------"
    echo "  config       : $CONFIG_PATH"
    echo "  interval     : $INTERVAL_MINUTES minutes"
    if [ -n "$QUIET_HOURS" ]; then
        if in_quiet_hours; then
            echo "  quiet hours  : $QUIET_HOURS (ACTIVE right now)"
        else
            echo "  quiet hours  : $QUIET_HOURS (inactive)"
        fi
    else
        echo "  quiet hours  : disabled (24/7)"
    fi
    echo

    local name enabled last ends nextp remain
    for name in claude codex; do
        if [ "$name" = claude ]; then enabled="$CLAUDE_ENABLED"; last="$CLAUDE_LAST"
        else enabled="$CODEX_ENABLED"; last="$CODEX_LAST"; fi

        if ! is_true "$enabled"; then
            printf '  %-6s       : disabled\n' "$name"
            continue
        fi
        if [ "$last" -eq 0 ]; then
            printf '  %-6s       : enabled - no successful ping yet\n' "$name"
            continue
        fi

        ends=$((last + 300 * 60))
        nextp=$((last + INTERVAL_MINUTES * 60))
        remain=$((ends - now))

        printf '  %-6s       : enabled\n' "$name"
        printf '     last ping   %s\n' "$(fmt_time "$last")"
        if [ "$remain" -gt 0 ]; then
            printf '     window ends %s  (%dh %dm left)\n' "$(fmt_time "$ends")" "$((remain / 3600))" "$(((remain % 3600) / 60))"
        else
            printf '     window ends %s  (expired)\n' "$(fmt_time "$ends")"
        fi
        printf '     next ping   %s\n' "$(fmt_time "$nextp")"
    done

    echo
    if crontab -l 2>/dev/null | grep -q 'keepalive.sh'; then
        echo "  scheduler    : cron entry found"
        crontab -l 2>/dev/null | grep 'keepalive.sh' | sed 's/^/     /'
    else
        echo "  scheduler    : NOT INSTALLED - run install/install-unix.sh"
    fi
    echo "  log file     : $LOG_FILE"
    echo
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [ "$DO_STATUS" -eq 1 ]; then
    show_status
    exit 0
fi

# --due: report which providers need a ping and say so through the exit code,
# without contacting anything. Lets a caller skip expensive setup on a no-op
# run (exit 0 = at least one is due, exit 3 = nothing to do).
if [ "$DO_DUE" -eq 1 ]; then
    DUE_LIST=""
    NOW="$(date +%s)"
    for provider in claude codex; do
        if [ "$provider" = claude ]; then enabled="$CLAUDE_ENABLED"; last="$CLAUDE_LAST"
        else enabled="$CODEX_ENABLED"; last="$CODEX_LAST"; fi
        is_true "$enabled" || continue
        if [ "$last" -gt 0 ] && [ $(( (NOW - last) / 60 )) -lt "$INTERVAL_MINUTES" ]; then
            continue
        fi
        DUE_LIST="$DUE_LIST $provider"
    done
    if in_quiet_hours; then
        printf 'quiet hours active (%s) - nothing due
' "$QUIET_HOURS"
        exit 3
    fi
    if [ -n "$DUE_LIST" ]; then
        printf '%s
' "${DUE_LIST# }"
        exit 0
    fi
    echo 'nothing due'
    exit 3
fi

prune_logs

if in_quiet_hours && [ "$DO_FORCE" -eq 0 ]; then
    log info "quiet hours active ($QUIET_HOURS) - skipping"
    exit 0
fi

NOW="$(date +%s)"
ANY_FAIL=0
DID_WORK=0

for provider in claude codex; do
    if [ "$provider" = claude ]; then enabled="$CLAUDE_ENABLED"; last="$CLAUDE_LAST"
    else enabled="$CODEX_ENABLED"; last="$CODEX_LAST"; fi

    is_true "$enabled" || continue

    if [ "$DO_FORCE" -eq 0 ] && [ "$last" -gt 0 ]; then
        [ $(( (NOW - last) / 60 )) -lt "$INTERVAL_MINUTES" ] && continue
    fi

    DID_WORK=1
    if [ "$provider" = claude ]; then ping_claude; rc=$?; else ping_codex; rc=$?; fi

    if [ "$rc" -eq 0 ]; then
        log info "$PING_MESSAGE"
        if [ "$DO_DRYRUN" -eq 0 ]; then
            if [ "$provider" = claude ]; then CLAUDE_LAST="$NOW"; else CODEX_LAST="$NOW"; fi
        fi
    else
        ANY_FAIL=1
        log error "$provider: $PING_MESSAGE"
    fi
done

if [ "$DID_WORK" -eq 1 ] && [ "$DO_DRYRUN" -eq 0 ]; then
    save_state
fi

exit "$ANY_FAIL"
