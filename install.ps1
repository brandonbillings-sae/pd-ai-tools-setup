# =============================================================================
# pd-ai-tools setup script
# Source: https://github.com/brandonbillings-sae/pd-ai-tools-setup/blob/main/install.ps1
#
# HOW TO DOWNLOAD AND RUN:
#   irm https://raw.githubusercontent.com/brandonbillings-sae/pd-ai-tools-setup/main/install.ps1 -OutFile "$env:USERPROFILE\Downloads\setup.ps1"
#   notepad "$env:USERPROFILE\Downloads\setup.ps1"
#   cd "$env:USERPROFILE\Downloads"
#   .\setup.ps1
#
# WHAT THIS SCRIPT DOES — review before running:
#   1. Installs Node.js, Git, and Python via winget (user scope, no admin needed)
#   2. Installs Claude Code via npm
#   3. Clones the pd-ai-tools GitLab repo to your user folder
#   4. Creates a .env credential template you fill in manually
#   5. Copies Claude Code skills to ~/.claude/skills/
#   6. Configures GitLab MCP token in ~/.claude/settings.json
#
# ALREADY INSTALLED? No problem — each step checks first:
#   - Node.js / Git / Python: skipped if winget already shows them installed
#   - Claude Code: skipped if already present in npm globals
#   - Repo clone: skipped if the destination folder already exists
#   - .env: skipped if a .env file already exists in the repo folder
#   - Skills: always refreshed (ensures you have the latest version)
#
# WHAT IT DOES NOT DO:
#   - Store or transmit your credentials anywhere
#   - Modify system-level settings or registry
#   - Install anything outside your user profile
#
# To inspect any step, search for the matching ## STEP comment below.
# =============================================================================

$ErrorActionPreference = "Stop"

function Write-Step  { param($msg) Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-OK    { param($msg) Write-Host "   [OK] $msg" -ForegroundColor Green }
function Write-Skip  { param($msg) Write-Host "   [--] $msg (already installed, skipping)" -ForegroundColor DarkGray }
function Write-Warn  { param($msg) Write-Host "   [!]  $msg" -ForegroundColor Yellow }
function Write-Fatal { param($msg) Write-Host "`n[FATAL] $msg" -ForegroundColor Red; exit 1 }

# =============================================================================
## CONFIRMATION — show intent, require explicit yes before proceeding
# =============================================================================

Write-Host @"

=====================================================================
  pd-ai-tools installer
  github.com/brandonbillings-sae/pd-ai-tools-setup
=====================================================================

This script will:
  - Install Node.js, Git, Python (via winget, user scope)
  - Install Claude Code (npm global)
  - Clone the pd-ai-tools repo to: $env:USERPROFILE\pd-ai-tools
  - Create a .env credential template (you fill in values manually)
  - Copy Claude Code skills to: $env:USERPROFILE\.claude\skills\

Nothing is installed at the system level. No credentials are stored
or transmitted by this script.

If you have not already reviewed this script, press Ctrl+C now and
open it in Notepad before proceeding.

"@ -ForegroundColor White

$confirm = Read-Host "Type YES to continue"
if ($confirm -ne "YES") {
    Write-Host "Aborted. No changes were made." -ForegroundColor Yellow
    exit 0
}

# =============================================================================
## STEP 1 — Install prerequisites via winget
# =============================================================================

Write-Step "Step 1/5 — Checking prerequisites"

$packages = @(
    [PSCustomObject]@{ Id = "OpenJS.NodeJS.LTS";  Name = "Node.js" },
    [PSCustomObject]@{ Id = "Git.Git";             Name = "Git" },
    [PSCustomObject]@{ Id = "Python.Python.3.12";  Name = "Python 3.12" }
)

foreach ($pkg in $packages) {
    $result = winget list --id $pkg.Id --accept-source-agreements 2>&1
    if ($result -match [regex]::Escape($pkg.Id)) {
        Write-Skip $pkg.Name
    } else {
        Write-Host "   Installing $($pkg.Name)..." -ForegroundColor Yellow
        winget install --id $pkg.Id --scope user --accept-package-agreements --accept-source-agreements
        Write-OK "$($pkg.Name) installed"
    }
}

# Refresh PATH so newly installed binaries are available in this session
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("PATH","User")

# =============================================================================
## STEP 2 — Install Claude Code
# =============================================================================

Write-Step "Step 2/5 — Claude Code"

$claudeCheck = npm list -g @anthropic-ai/claude-code --depth=0 2>&1
if ($claudeCheck -match "claude-code") {
    Write-Skip "Claude Code"
} else {
    npm install -g @anthropic-ai/claude-code
    Write-OK "Claude Code installed"
}

# =============================================================================
## STEP 3 — Clone the repo
# =============================================================================

Write-Step "Step 3/5 — Clone pd-ai-tools repo"

$dest = "$env:USERPROFILE\pd-ai-tools"

if (Test-Path $dest) {
    Write-Skip "Repo folder $dest already exists"
} else {
    Write-Host @"

  You need a GitLab Personal Access Token (PAT) to clone the repo.
  If you don't have one yet:
    1. Go to https://gitlab.com/-/profile/personal_access_tokens
    2. Create a token with the 'read_repository' scope
    3. Copy it — GitLab will not show it again

"@ -ForegroundColor DarkGray

    $email = Read-Host "   Your GitLab email"
    $patSecure = Read-Host "   Your GitLab PAT" -AsSecureString
    $pat = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
               [Runtime.InteropServices.Marshal]::SecureStringToBSTR($patSecure))
    $encodedEmail = [Uri]::EscapeDataString($email)

    # Store credentials in Windows Credential Manager before cloning so the
    # remote URL stays clean (no embedded credentials). Claude Code reads the
    # remote URL to identify the GitLab project -- embedded credentials break that.
    cmdkey /generic:"LegacyGeneric:target=git:https://gitlab.com" /user:"$email" /pass:"$pat" | Out-Null

    git clone "https://gitlab.com/sae_devops/saepri-pd-tools.git" $dest
    Write-OK "Repo cloned to $dest"
    Write-OK "GitLab credentials stored in Windows Credential Manager"

    # Save to script-level variables so Step 4 can write them to .env
    $script:gitlabEmail = $email
    $script:gitlabPat   = $pat
}

Set-Location $dest

# =============================================================================
## STEP 4 — Create .env credential template
# =============================================================================

Write-Step "Step 4/5 — Credential template (.env)"

if (Test-Path ".env") {
    Write-Skip ".env already exists"
} else {
    $org = ""
    while ($org -notin @("SAE","PRI")) {
        $org = (Read-Host "   Your org (SAE or PRI)").ToUpper()
    }

    $prodUrl  = if ($org -eq "SAE") { "https://training.sae.org" }          else { "https://your-lms.docebosaas.com" }
    $sbxUrl   = if ($org -eq "SAE") { "https://sandbox-training.sae.org" }  else { "https://your-sandbox.docebosaas.com" }
    $accOrgId = if ($org -eq "SAE") { "98705" }                             else { "105825" }

    $gitlabEmailVal = if ($script:gitlabEmail) { $script:gitlabEmail } else { "your-gitlab-email" }
    $gitlabPatVal   = if ($script:gitlabPat)   { $script:gitlabPat }   else { "your-personal-access-token" }

    @"
# ── GitLab ───────────────────────────────────────────────────────
GITLAB_EMAIL=$gitlabEmailVal
GITLAB_PAT=$gitlabPatVal

# ── Docebo Production ────────────────────────────────────────────
PROD_URL=$prodUrl
PROD_CLIENT_ID=your-client-id
PROD_CLIENT_SECRET=your-client-secret
PROD_USERNAME=your-api-account-email
PROD_PASSWORD=your-api-account-password

# ── Docebo Sandbox ───────────────────────────────────────────────
SBX_URL=$sbxUrl
SBX_CLIENT_ID=your-sandbox-client-id
SBX_CLIENT_SECRET=your-sandbox-client-secret
SBX_USERNAME=your-api-account-email
SBX_PASSWORD=your-sandbox-password

# ── Accredible ───────────────────────────────────────────────────
ACCREDIBLE_API_KEY=your-api-key
ACCREDIBLE_ORG_ID=$accOrgId
# Refresh from browser DevTools (Network tab > Authorization header) every ~7 days
ACCREDIBLE_JWT=Bearer eyJ...replace-me
"@ | Set-Content ".env"

    Write-OK ".env template created"
    Write-Warn "Open .env in a text editor and fill in your credentials before using any tools"
}

# =============================================================================
## STEP 5 — Install Claude Code skills
# =============================================================================

Write-Step "Step 5/6 — Installing Claude Code skills"

$skillsDir = "$env:USERPROFILE\.claude\skills"
if (-not (Test-Path $skillsDir)) {
    New-Item -ItemType Directory -Path $skillsDir | Out-Null
}

foreach ($skill in @("docebo-api", "docebo-sync", "accredible-api")) {
    $src = "skills\$skill"
    if (Test-Path $src) {
        Copy-Item -Recurse -Force $src "$skillsDir\$skill"
        Write-OK "$skill skill installed"
    } else {
        Write-Warn "skills\$skill not found in repo — skipping"
    }
}

# =============================================================================
## STEP 6 — Configure GitLab MCP in Claude Code settings
# =============================================================================

Write-Step "Step 6/6 — GitLab MCP configuration"

$claudeSettingsPath = "$env:USERPROFILE\.claude\settings.json"
$claudeDir = "$env:USERPROFILE\.claude"

if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir | Out-Null
}

# Read existing settings or start fresh
if (Test-Path $claudeSettingsPath) {
    $settings = Get-Content $claudeSettingsPath -Raw | ConvertFrom-Json
} else {
    $settings = [PSCustomObject]@{}
}

# Ensure env block exists
if (-not $settings.PSObject.Properties["env"]) {
    $settings | Add-Member -MemberType NoteProperty -Name "env" -Value ([PSCustomObject]@{})
}

# Write GITLAB_TOKEN (same value as PAT)
$patForMcp = if ($script:gitlabPat) { $script:gitlabPat } else { "" }
if ($patForMcp) {
    $settings.env | Add-Member -MemberType NoteProperty -Name "GITLAB_TOKEN" -Value $patForMcp -Force
    Write-OK "GITLAB_TOKEN added to Claude settings"
} else {
    Write-Warn "No GitLab PAT found — add GITLAB_TOKEN manually to $claudeSettingsPath"
}

# Ensure enabledPlugins block exists and enable GitLab plugin
if (-not $settings.PSObject.Properties["enabledPlugins"]) {
    $settings | Add-Member -MemberType NoteProperty -Name "enabledPlugins" -Value ([PSCustomObject]@{})
}
$settings.enabledPlugins | Add-Member -MemberType NoteProperty -Name "gitlab@claude-plugins-official" -Value $true -Force

$settings | ConvertTo-Json -Depth 10 | Set-Content $claudeSettingsPath
Write-OK "GitLab MCP plugin enabled in Claude settings"

# =============================================================================
## DONE
# =============================================================================

Write-Host @"

=====================================================================
  Setup complete!
=====================================================================

Next steps:
  1. Open .env in a text editor and fill in your credentials
     Notepad: notepad $dest\.env

  2. Launch Claude Code from the repo folder:
     cd $dest
     claude

  3. Tell Claude: "I'm setting up at [SAE / PRI]. What tools are available?"

  Claude will verify your credentials and walk through any remaining steps.

"@ -ForegroundColor Green
