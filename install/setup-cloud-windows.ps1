<#
.SYNOPSIS
    One command that finishes the cloud setup: creates the login token, stores
    it as a GitHub secret, starts the first window and checks that it worked.

.DESCRIPTION
    Run this in a normal PowerShell window (Start menu -> type "powershell").
    It will:

      1. check that the gh and claude commands are available and signed in
      2. run `claude setup-token`, which opens your browser so you can approve
      3. ask you to paste the token it printed
      4. store that token as the CLAUDE_CODE_OAUTH_TOKEN repository secret
      5. trigger the workflow and wait for the result

    The token is never written to a file and never printed back.

.PARAMETER Repo
    owner/name of the GitHub repository. Detected from the git remote if the
    script is run from inside a clone.

.PARAMETER Codex
    Also upload ~/.codex/auth.json as the CODEX_AUTH_JSON secret, and switch
    CODEX_ENABLED on in cloud.env.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install\setup-cloud-windows.ps1
#>
[CmdletBinding()]
param(
    [string] $Repo,
    [switch] $Codex
)

$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Say  ($m) { Write-Host "  $m" }
function Ok   ($m) { Write-Host "  OK  $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "  !   $m" -ForegroundColor Yellow }
function Die  ($m) { Write-Host "  X   $m" -ForegroundColor Red; exit 1 }
function Head ($m) { Write-Host ''; Write-Host "  $m" -ForegroundColor Cyan }

Write-Host ''
Write-Host '  No 5-Hour Limit - cloud setup' -ForegroundColor Cyan
Write-Host '  ============================================================'

# --------------------------------------------------------------------------
# 0. Tools
# --------------------------------------------------------------------------
Head 'Step 1 of 5 - checking the tools'

$gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $gh) {
    Die 'The GitHub CLI (gh) is not installed. Get it from https://cli.github.com then run this again.'
}
& $gh.Source auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Warn 'You are not signed in to GitHub. Starting the sign-in now...'
    & $gh.Source auth login
    & $gh.Source auth status *> $null
    if ($LASTEXITCODE -ne 0) { Die 'Still not signed in to GitHub - stopping.' }
}
Ok 'GitHub CLI ready'

$claude = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $claude) {
    Die 'The claude command was not found. Install it with:  npm install -g @anthropic-ai/claude-code'
}
Ok "claude command found"

# --------------------------------------------------------------------------
# 1. Which repository
# --------------------------------------------------------------------------
if (-not $Repo) {
    Push-Location $RepoRoot
    $remote = (& git remote get-url origin 2>$null)
    Pop-Location
    if ($remote -match 'github\.com[:/]+([^/]+)/([^/.]+)') {
        $Repo = "$($Matches[1])/$($Matches[2])"
    }
}
if (-not $Repo) {
    Die 'Could not work out which GitHub repository to use. Re-run with:  -Repo owner/name'
}
Ok "repository: $Repo"

# --------------------------------------------------------------------------
# 2. The token
# --------------------------------------------------------------------------
Head 'Step 2 of 5 - creating your login token'
Say 'A browser window will open. Sign in and approve, then come back here.'
Say ''

& $claude.Source setup-token

Say ''
Say 'Copy the long token printed above (select it with the mouse, then Ctrl+C)'
$token = Read-Host '  and paste it here, then press Enter'
$token = ($token + '').Trim()

if ($token.Length -lt 20) {
    Die 'That does not look like a token. Run the script again and paste the whole line.'
}
Ok 'token received'

# --------------------------------------------------------------------------
# 3. Store it as a repository secret
# --------------------------------------------------------------------------
Head 'Step 3 of 5 - storing it on GitHub'

$token | & $gh.Source secret set CLAUDE_CODE_OAUTH_TOKEN --repo $Repo
if ($LASTEXITCODE -ne 0) { Die 'Could not store the secret. Check that you have access to the repository.' }
$token = $null
Ok 'CLAUDE_CODE_OAUTH_TOKEN stored (it is not saved anywhere on this computer)'

if ($Codex) {
    $authFile = Join-Path $env:USERPROFILE '.codex\auth.json'
    if (Test-Path -LiteralPath $authFile) {
        Get-Content -LiteralPath $authFile -Raw | & $gh.Source secret set CODEX_AUTH_JSON --repo $Repo
        if ($LASTEXITCODE -eq 0) {
            Ok 'CODEX_AUTH_JSON stored'
            $cloudEnv = Join-Path $RepoRoot 'cloud.env'
            if (Test-Path -LiteralPath $cloudEnv) {
                (Get-Content -LiteralPath $cloudEnv) `
                    -replace '^\s*CODEX_ENABLED\s*=.*$', 'CODEX_ENABLED=true' |
                    Set-Content -LiteralPath $cloudEnv -Encoding UTF8
                Warn 'cloud.env now has CODEX_ENABLED=true - commit and push it to switch Codex on.'
            }
        } else {
            Warn 'Could not store CODEX_AUTH_JSON - continuing without Codex.'
        }
    } else {
        Warn "No $authFile found. Run 'codex login' first if you want Codex too."
    }
}

# --------------------------------------------------------------------------
# 4. Open the first window
# --------------------------------------------------------------------------
Head 'Step 4 of 5 - opening your first window'

& $gh.Source workflow run keepalive.yml -f force=true --repo $Repo
if ($LASTEXITCODE -ne 0) { Die 'Could not start the workflow. Is Actions enabled on the repository?' }
Ok 'workflow started'

# --------------------------------------------------------------------------
# 5. Wait and report
# --------------------------------------------------------------------------
Head 'Step 5 of 5 - waiting for the result'

$runId = $null
$deadline = (Get-Date).AddMinutes(3)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $json = & $gh.Source run list --workflow keepalive.yml --limit 1 --json databaseId,status,conclusion --repo $Repo 2>$null
    if (-not $json) { continue }
    try { $run = ($json | ConvertFrom-Json)[0] } catch { continue }
    if (-not $run) { continue }
    $runId = $run.databaseId
    if ($run.status -eq 'completed') {
        Write-Host ''
        if ($run.conclusion -eq 'success') {
            Ok 'It works. A fresh 5-hour window is open and it will keep renewing itself.'
            Write-Host ''
            Say "Details: https://github.com/$Repo/actions/runs/$runId"
            Write-Host ''
            Write-Host '  Nothing else to do. You can close this window.' -ForegroundColor Green
            Write-Host ''
            exit 0
        }
        Warn "The run finished with: $($run.conclusion)"
        Say  "Look at what went wrong: https://github.com/$Repo/actions/runs/$runId"
        Say  'The most common cause is a token that was pasted incomplete - just run this script again.'
        exit 1
    }
    Write-Host '.' -NoNewline
}

Write-Host ''
Warn 'Still running after 3 minutes. It is probably fine - check here in a moment:'
Say  "https://github.com/$Repo/actions"
