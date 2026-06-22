# patch-gitlab.ps1
# Run this from %USERPROFILE%\pd-ai-tools to fix GitLab connectivity and MCP auth.
# Usage: .\patch-gitlab.ps1

$ErrorActionPreference = "Stop"

Write-Host "`nGitLab patch - sets up git clone and Claude MCP`n" -ForegroundColor Cyan

# -- Read credentials from .env --
if (-not (Test-Path ".env")) {
    Write-Host "[ERROR] No .env found - run this script from $env:USERPROFILE\pd-ai-tools" -ForegroundColor Red
    exit 1
}

$envLines = Get-Content ".env"
$email = ($envLines | Where-Object { $_ -match "^GITLAB_EMAIL=" }) -replace "^GITLAB_EMAIL=", ""
$pat   = ($envLines | Where-Object { $_ -match "^GITLAB_PAT=" })   -replace "^GITLAB_PAT=", ""

if (-not $email -or $email -eq "your-gitlab-email") {
    Write-Host "[ERROR] GITLAB_EMAIL not set in .env - fill it in first" -ForegroundColor Red
    exit 1
}
if (-not $pat -or $pat -eq "your-personal-access-token") {
    Write-Host "[ERROR] GITLAB_PAT not set in .env - fill it in first" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Read credentials from .env" -ForegroundColor Green

# Store credentials in Windows Credential Manager so git can auth
cmdkey /generic:"LegacyGeneric:target=git:https://gitlab.com" /user:"$email" /pass:"$pat" | Out-Null
Write-Host "[OK] Credentials stored in Windows Credential Manager" -ForegroundColor Green

$remoteUrl = "https://gitlab.com/sae_devops/saepri-pd-tools.git"

# -- 1. Set up git --
if (Test-Path ".git") {
    # Already a git repo - just make sure the remote is clean (no embedded credentials)
    git remote set-url origin $remoteUrl
    Write-Host "[OK] git remote updated to clean URL" -ForegroundColor Green
} else {
    # Folder was downloaded as a zip - initialize it as a proper git clone
    Write-Host "   No git repo found - initializing from GitLab..." -ForegroundColor Yellow
    git init
    git remote add origin $remoteUrl
    git fetch origin
    # Reset to match remote, keeping untracked files like .env
    git reset --hard origin/main
    Write-Host "[OK] Initialized as git clone from $remoteUrl" -ForegroundColor Green
}

git pull
Write-Host "[OK] git pull succeeded" -ForegroundColor Green

# -- 2. Add GITLAB_TOKEN to Claude Code settings --
$claudeDir    = "$env:USERPROFILE\.claude"
$settingsPath = "$claudeDir\settings.json"

if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir | Out-Null
}

if (Test-Path $settingsPath) {
    $s = Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
    $s = [PSCustomObject]@{}
}

if (-not $s.PSObject.Properties["env"]) {
    $s | Add-Member -MemberType NoteProperty -Name "env" -Value ([PSCustomObject]@{})
}
$s.env | Add-Member -MemberType NoteProperty -Name "GITLAB_TOKEN" -Value $pat -Force

if (-not $s.PSObject.Properties["enabledPlugins"]) {
    $s | Add-Member -MemberType NoteProperty -Name "enabledPlugins" -Value ([PSCustomObject]@{})
}
$s.enabledPlugins | Add-Member -MemberType NoteProperty -Name "gitlab@claude-plugins-official" -Value $true -Force

$s | ConvertTo-Json -Depth 10 | Set-Content $settingsPath
Write-Host "[OK] GitLab MCP configured in Claude settings" -ForegroundColor Green

Write-Host "`nDone! Restart Claude Code for the MCP change to take effect." -ForegroundColor Cyan
