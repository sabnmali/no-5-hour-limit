<#
.SYNOPSIS
    Limitless 5-Hour - keeps AI CLI usage windows rolling.

.DESCRIPTION
    Sends a minimal "ping" prompt to the Claude CLI and/or the Codex CLI once
    the configured interval has elapsed since the last successful ping. That
    opens a fresh 5-hour usage window, so window boundaries stay predictable
    instead of starting whenever you happen to send your first real message.

    The script is idempotent. It only pings when the interval has actually
    elapsed, so the scheduler just needs to poke it every few minutes.

.PARAMETER Status
    Print current state (last ping, window end, next ping due) and exit.

.PARAMETER Force
    Ping now, ignoring the interval and quiet hours.

.PARAMETER DryRun
    Show what would be run without calling any CLI.

.PARAMETER ConfigPath
    Path to a config file. Defaults to <repo>/config.env.

.EXAMPLE
    powershell -File bin\keepalive.ps1 -Status
#>
[CmdletBinding()]
param(
    [switch] $Status,
    [switch] $Force,
    [switch] $DryRun,
    [string] $ConfigPath
)

# Native CLIs write progress to stderr; 'Stop' would turn that into a crash.
$ErrorActionPreference = 'Continue'

# --------------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------------
$RepoRoot  = Split-Path -Parent $PSScriptRoot
$LogDir    = Join-Path $RepoRoot 'logs'
$StateDir  = Join-Path $RepoRoot 'state'
$StateFile = Join-Path $StateDir 'state.json'
$WorkDir   = Join-Path $StateDir 'workdir'

foreach ($d in @($LogDir, $StateDir, $WorkDir)) {
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

if (-not $ConfigPath) { $ConfigPath = Join-Path $RepoRoot 'config.env' }

# --------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------
$Config = @{
    INTERVAL_MINUTES       = '301'
    CLAUDE_ENABLED         = 'true'
    CLAUDE_MODEL           = 'haiku'
    CLAUDE_PROMPT          = 'ok'
    CLAUDE_BIN             = ''
    CODEX_ENABLED          = 'false'
    CODEX_MODEL            = ''
    CODEX_PROMPT           = 'ok'
    CODEX_BIN              = ''
    CODEX_REASONING_EFFORT = 'minimal'
    LOG_RETENTION_DAYS     = '30'
    QUIET_HOURS            = ''
}

if (Test-Path -LiteralPath $ConfigPath) {
    foreach ($line in (Get-Content -LiteralPath $ConfigPath)) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        $idx = $trimmed.IndexOf('=')
        if ($idx -lt 1) { continue }
        $key = $trimmed.Substring(0, $idx).Trim()
        $val = $trimmed.Substring($idx + 1).Trim().Trim('"').Trim("'")
        $Config[$key] = $val
    }
}

function Get-Cfg([string] $Key) {
    if ($Config.ContainsKey($Key)) { return [string] $Config[$Key] }
    return ''
}

function Get-CfgBool([string] $Key) {
    return ((Get-Cfg $Key) -match '^(?i:true|1|yes|on)$')
}

$IntervalMinutes = 301
$parsed = 0
if ([int]::TryParse((Get-Cfg 'INTERVAL_MINUTES'), [ref] $parsed) -and $parsed -ge 1) {
    $IntervalMinutes = $parsed
}

# --------------------------------------------------------------------------
# Logging
# --------------------------------------------------------------------------
$LogFile = Join-Path $LogDir ("keepalive-{0}.log" -f (Get-Date -Format 'yyyy-MM'))

function Write-Log {
    param([string] $Level, [string] $Message)
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')
    $line = "[{0}] {1,-5} {2}" -f $stamp, $Level.ToUpperInvariant(), $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch { }
    if ($Level -eq 'error') { Write-Host $line -ForegroundColor Red }
    elseif ($Level -eq 'warn') { Write-Host $line -ForegroundColor Yellow }
    else { Write-Host $line }
}

function Remove-OldLogs {
    $days = 0
    if (-not [int]::TryParse((Get-Cfg 'LOG_RETENTION_DAYS'), [ref] $days)) { return }
    if ($days -le 0) { return }
    $cutoff = (Get-Date).AddDays(-$days)
    Get-ChildItem -LiteralPath $LogDir -Filter 'keepalive-*.log' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------
function Read-State {
    $result = @{}
    if (-not (Test-Path -LiteralPath $StateFile)) { return $result }
    try {
        $raw = Get-Content -LiteralPath $StateFile -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return $result }
        $obj = $raw | ConvertFrom-Json
        foreach ($p in $obj.PSObject.Properties) { $result[$p.Name] = $p.Value }
    } catch { }
    return $result
}

function Write-State($State) {
    try {
        ($State | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $StateFile -Encoding UTF8
    } catch {
        Write-Log 'warn' "could not write state file: $($_.Exception.Message)"
    }
}

function Get-LastPingUtc($State, [string] $Provider) {
    if (-not $State.ContainsKey($Provider)) { return $null }
    $entry = $State[$Provider]
    if ($null -eq $entry) { return $null }

    $value = $null
    if ($entry -is [System.Collections.IDictionary]) {
        $value = $entry['lastSuccessUtc']
    } elseif ($entry.PSObject.Properties.Name -contains 'lastSuccessUtc') {
        $value = $entry.lastSuccessUtc
    }
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }

    try {
        return [datetime]::Parse(
            $value, [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind)
    } catch { return $null }
}

# --------------------------------------------------------------------------
# Quiet hours
# --------------------------------------------------------------------------
function Test-QuietHours {
    $spec = Get-Cfg 'QUIET_HOURS'
    if ([string]::IsNullOrWhiteSpace($spec)) { return $false }
    if ($spec -notmatch '^\s*(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})\s*$') { return $false }
    $start = [int] $Matches[1] * 60 + [int] $Matches[2]
    $end   = [int] $Matches[3] * 60 + [int] $Matches[4]
    $nowM  = (Get-Date).Hour * 60 + (Get-Date).Minute
    if ($start -le $end) { return ($nowM -ge $start -and $nowM -lt $end) }
    return ($nowM -ge $start -or $nowM -lt $end)   # range crosses midnight
}

# --------------------------------------------------------------------------
# Providers
# --------------------------------------------------------------------------
function Resolve-Cli([string] $Name) {
    # 1. An explicit path from config.env always wins. Task Scheduler runs with
    #    a different PATH than an interactive shell, so this is the reliable
    #    route and the installer fills it in.
    $configured = Get-Cfg ('{0}_BIN' -f $Name.ToUpperInvariant())
    if ((-not [string]::IsNullOrWhiteSpace($configured)) -and (Test-Path -LiteralPath $configured)) {
        return $configured
    }

    # 2. PATH.
    $cmd = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($cmd) { return $cmd.Source }

    # 3. The usual install locations.
    $candidates = @(
        (Join-Path $env:APPDATA          ('npm\{0}.cmd'  -f $Name)),
        (Join-Path $env:APPDATA          ('npm\{0}.ps1'  -f $Name)),
        (Join-Path $env:LOCALAPPDATA     ('{0}\bin\{0}.exe' -f $Name)),
        (Join-Path $env:USERPROFILE      ('bin\{0}.cmd'  -f $Name)),
        (Join-Path $env:USERPROFILE      ('bin\{0}.exe'  -f $Name)),
        (Join-Path $env:USERPROFILE      ('.local\bin\{0}.exe' -f $Name)),
        (Join-Path $env:ProgramFiles     ('nodejs\{0}.cmd' -f $Name))
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }

    return $null
}

function Invoke-ClaudePing {
    $exe = Resolve-Cli 'claude'
    if (-not $exe) {
        return @{ ok = $false; message = 'claude CLI not found - set CLAUDE_BIN in config.env, or run install\setup-cli-windows.ps1' }
    }

    $cliArgs = @(
        '-p', (Get-Cfg 'CLAUDE_PROMPT'),
        '--model', (Get-Cfg 'CLAUDE_MODEL'),
        '--system-prompt', 'Reply with exactly: ok',
        '--restricted',
        '--strict-mcp-config',
        '--no-session-persistence',
        '--permission-mode', 'dontAsk',
        '--output-format', 'json'
    )

    if ($DryRun) { return @{ ok = $true; message = "DRY RUN: claude $($cliArgs -join ' ')" } }

    $raw = ''
    Push-Location $WorkDir
    try {
        $raw = (& $exe @cliArgs 2>&1 | Out-String)
    } catch {
        Pop-Location
        return @{ ok = $false; message = "claude invocation failed: $($_.Exception.Message)" }
    }
    Pop-Location

    $json = $null
    try { $json = $raw | ConvertFrom-Json } catch { }

    if ($null -eq $json) {
        $flat = ($raw -replace '\s+', ' ').Trim()
        if ($flat.Length -gt 300) { $flat = $flat.Substring(0, 300) + '...' }
        return @{ ok = $false; message = "unreadable claude output: $flat" }
    }

    $isError = $false
    if ($json.PSObject.Properties.Name -contains 'is_error') { $isError = [bool] $json.is_error }
    if ($isError) {
        $msg = 'unknown error'
        if ($json.PSObject.Properties.Name -contains 'result') { $msg = [string] $json.result }
        if ($msg -match '(?i)not logged in') {
            $msg = 'not logged in - run: claude auth login'
        }
        return @{ ok = $false; message = "claude: $msg" }
    }

    $inTok = 0; $outTok = 0; $ms = 0
    try { $inTok  = [int] $json.usage.input_tokens }  catch { }
    try { $outTok = [int] $json.usage.output_tokens } catch { }
    try { $ms     = [int] $json.duration_ms }         catch { }

    return @{
        ok = $true
        message = "claude ok (model=$(Get-Cfg 'CLAUDE_MODEL') in=$inTok out=$outTok ${ms}ms)"
    }
}

function Invoke-CodexPing {
    $exe = Resolve-Cli 'codex'
    if (-not $exe) {
        return @{ ok = $false; message = 'codex CLI not found - set CODEX_BIN in config.env, or npm i -g @openai/codex' }
    }

    $cliArgs = @('exec', '--skip-git-repo-check', '--ephemeral', '-s', 'read-only', '-C', $WorkDir)

    $model = Get-Cfg 'CODEX_MODEL'
    if (-not [string]::IsNullOrWhiteSpace($model)) { $cliArgs += @('-m', $model) }

    $effort = Get-Cfg 'CODEX_REASONING_EFFORT'
    if (-not [string]::IsNullOrWhiteSpace($effort)) {
        $cliArgs += @('-c', ('model_reasoning_effort="{0}"' -f $effort))
    }

    $cliArgs += (Get-Cfg 'CODEX_PROMPT')

    if ($DryRun) { return @{ ok = $true; message = "DRY RUN: codex $($cliArgs -join ' ')" } }

    $raw = ''
    try {
        $raw = (& $exe @cliArgs 2>&1 | Out-String)
    } catch {
        return @{ ok = $false; message = "codex invocation failed: $($_.Exception.Message)" }
    }

    if ($raw -match '(?i)usage limit') {
        return @{ ok = $false; message = 'usage limit reached - will retry next cycle' }
    }
    if ($raw -match '(?i)not logged in|run .{0,3}codex login') {
        return @{ ok = $false; message = 'not logged in - run: codex login' }
    }
    if ($raw -match '(?im)^\s*ERROR:\s*(.+)$') {
        return @{ ok = $false; message = "error: $($Matches[1].Trim())" }
    }

    return @{ ok = $true; message = 'codex ok' }
}

# --------------------------------------------------------------------------
# Status report
# --------------------------------------------------------------------------
function Show-Status {
    $state = Read-State

    Write-Host ''
    Write-Host '  Limitless 5-Hour - status' -ForegroundColor Cyan
    Write-Host '  ---------------------------------------------------------'
    Write-Host ("  config       : {0}" -f $ConfigPath)
    Write-Host ("  interval     : {0} minutes" -f $IntervalMinutes)

    $q = Get-Cfg 'QUIET_HOURS'
    if ($q) {
        $qState = 'inactive'
        if (Test-QuietHours) { $qState = 'ACTIVE right now' }
        Write-Host ("  quiet hours  : {0} ({1})" -f $q, $qState)
    } else {
        Write-Host '  quiet hours  : disabled (24/7)'
    }
    Write-Host ''

    foreach ($name in @('claude', 'codex')) {
        $enabled = Get-CfgBool ('{0}_ENABLED' -f $name.ToUpperInvariant())
        $label = $name.PadRight(6)

        if (-not $enabled) {
            Write-Host ("  {0}       : disabled" -f $label) -ForegroundColor DarkGray
            continue
        }

        $last = Get-LastPingUtc $state $name
        if ($null -eq $last) {
            Write-Host ("  {0}       : enabled - no successful ping yet" -f $label) -ForegroundColor Yellow
            continue
        }

        $lastLocal  = $last.ToLocalTime()
        $windowEnds = $lastLocal.AddMinutes(300)
        $nextDue    = $lastLocal.AddMinutes($IntervalMinutes)
        $remaining  = $windowEnds - (Get-Date)

        $remainText = 'expired'
        if ($remaining.TotalSeconds -gt 0) {
            $remainText = '{0}h {1}m left' -f [int] $remaining.TotalHours, $remaining.Minutes
        }

        Write-Host ("  {0}       : enabled" -f $label) -ForegroundColor Green
        Write-Host ("     last ping   {0}" -f $lastLocal.ToString('yyyy-MM-dd HH:mm:ss'))
        Write-Host ("     window ends {0}  ({1})" -f $windowEnds.ToString('yyyy-MM-dd HH:mm:ss'), $remainText)
        Write-Host ("     next ping   {0}" -f $nextDue.ToString('yyyy-MM-dd HH:mm:ss'))
    }

    Write-Host ''
    $task = Get-ScheduledTask -TaskName 'Limitless5Hour' -ErrorAction SilentlyContinue
    if ($task) {
        Write-Host ("  scheduler    : installed, state = {0}" -f $task.State) -ForegroundColor Green
        $info = Get-ScheduledTaskInfo -TaskName 'Limitless5Hour' -ErrorAction SilentlyContinue
        if ($info) { Write-Host ("     next check  {0}" -f $info.NextRunTime) }
    } else {
        Write-Host '  scheduler    : NOT INSTALLED - run install\install-windows.ps1' -ForegroundColor Yellow
    }
    Write-Host ("  log file     : {0}" -f $LogFile)
    Write-Host ''
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
if ($Status) {
    Show-Status
    exit 0
}

Remove-OldLogs

if ((Test-QuietHours) -and (-not $Force)) {
    Write-Log 'info' ("quiet hours active ({0}) - skipping" -f (Get-Cfg 'QUIET_HOURS'))
    exit 0
}

$state   = Read-State
$nowUtc  = [datetime]::UtcNow
$anyFail = $false
$didWork = $false

foreach ($name in @('claude', 'codex')) {
    if (-not (Get-CfgBool ('{0}_ENABLED' -f $name.ToUpperInvariant()))) { continue }

    $last = Get-LastPingUtc $state $name
    if ((-not $Force) -and ($null -ne $last)) {
        $elapsed = ($nowUtc - $last).TotalMinutes
        if ($elapsed -lt $IntervalMinutes) { continue }
    }

    $didWork = $true
    if ($name -eq 'claude') { $result = Invoke-ClaudePing } else { $result = Invoke-CodexPing }

    if ($result.ok) {
        Write-Log 'info' $result.message
        if (-not $DryRun) {
            $state[$name] = @{
                lastSuccessUtc = $nowUtc.ToString('o')
                lastMessage    = $result.message
            }
        }
    } else {
        $anyFail = $true
        Write-Log 'error' ("{0}: {1}" -f $name, $result.message)
    }
}

if ($didWork -and (-not $DryRun)) { Write-State $state }
if ($anyFail) { exit 1 }
exit 0
