# =============================================================================
#  github_windows.ps1 - Automatic GitHub SSH setup for Windows (no admin)
#
#  Run with:  powershell -ExecutionPolicy Bypass -File github_windows.ps1
#  Or just double-click github_windows.bat
# =============================================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# -- Output helpers -----------------------------------------------------------
function Step($m) { Write-Host ""; Write-Host "[>] $m" -ForegroundColor Blue }
function Ok($m)   { Write-Host "[OK] $m"  -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m"   -ForegroundColor Yellow }
function Info($m) { Write-Host "     $m"  -ForegroundColor Cyan }
function Err($m)  { Write-Host "[X] $m"   -ForegroundColor Red; exit 1 }

# -- Banner -------------------------------------------------------------------
Write-Host ""
Write-Host "  ==========================================" -ForegroundColor White
Write-Host "  |   GitHub SSH Auto-Setup  -  Windows    |" -ForegroundColor White
Write-Host "  |   (no admin required)                  |" -ForegroundColor White
Write-Host "  ==========================================" -ForegroundColor White
Write-Host ""

# -- 0. Verify Windows --------------------------------------------------------
if ($env:OS -ne 'Windows_NT') { Err "This script is for Windows only." }
$osName = (Get-CimInstance Win32_OperatingSystem).Caption
Ok "Detected: $osName - $env:PROCESSOR_ARCHITECTURE"

# -- Local bin directory (no admin needed) ------------------------------------
$LOCAL_BIN = Join-Path $env:LOCALAPPDATA 'Programs\bin'
New-Item -ItemType Directory -Path $LOCAL_BIN -Force | Out-Null
$env:Path = "$LOCAL_BIN;$env:Path"

# Persist it on the user PATH (no admin, survives reboots)
function Add-ToUserPath($dir) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ([string]::IsNullOrEmpty($userPath)) { $userPath = '' }
    $paths = $userPath -split ';' | Where-Object { $_ -ne '' }
    if ($paths -notcontains $dir) {
        [Environment]::SetEnvironmentVariable('Path', (($paths + $dir) -join ';'), 'User')
    }
}
Add-ToUserPath $LOCAL_BIN

$SSH_DIR = Join-Path $env:USERPROFILE '.ssh'

# -- 1. Check for existing SSH keys -------------------------------------------
Step "Checking for existing SSH keys..."

$ExistingKeys = @()
if (Test-Path $SSH_DIR) {
    $ExistingKeys = @(Get-ChildItem -Path $SSH_DIR -Filter '*.pub' -File -ErrorAction SilentlyContinue |
        Where-Object { Test-Path ($_.FullName -replace '\.pub$', '') } |
        ForEach-Object { $_.FullName -replace '\.pub$', '' })
}

if ($ExistingKeys.Count -gt 0) {
    $sshConfigText = ''
    $cfg = Join-Path $SSH_DIR 'config'
    if (Test-Path $cfg) { $sshConfigText = (Get-Content $cfg -Raw) }

    Write-Host ""
    Write-Host "  /!\  Existing SSH keys found on this machine:" -ForegroundColor Yellow
    Write-Host ""
    foreach ($key in $ExistingKeys) {
        $name = Split-Path $key -Leaf
        if ($sshConfigText -match [regex]::Escape($name)) {
            Write-Host "    - $name" -NoNewline -ForegroundColor Yellow
            Write-Host " <- referenced in ~/.ssh/config" -ForegroundColor Cyan
        } else {
            Write-Host "    - $name" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    Write-Host "  If you continue, a new key will be created and added to GitHub."  -ForegroundColor Yellow
    Write-Host "  Existing keys will not be touched, but make sure you actually"    -ForegroundColor Yellow
    Write-Host "  need a new one - old keys should be removed from GitHub when"     -ForegroundColor Yellow
    Write-Host "  they are no longer in use."                                       -ForegroundColor Yellow
    Write-Host ""
    $continue = Read-Host "  Are you sure you want to continue? (y/N)"
    Write-Host ""
    if ($continue -notmatch '^[yY]$') {
        Write-Host "  Aborted. No changes were made." -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Your existing public keys:"
        foreach ($key in $ExistingKeys) {
            $pub = (Get-Content "$key.pub" -Raw).Trim()
            Write-Host "    $pub"
        }
        Write-Host ""
        exit 0
    }
} else {
    Ok "No existing SSH keys found - continuing."
}

# -- 2. Install git (PortableGit - no admin) ----------------------------------
Step "Checking for git..."

$GIT_DIR = Join-Path $env:LOCALAPPDATA 'Programs\PortableGit'
$GIT_OK  = $false

# Pick up a PortableGit from a previous run, if present
if (Test-Path (Join-Path $GIT_DIR 'cmd\git.exe')) {
    $env:Path = "$env:Path;$GIT_DIR\cmd;$GIT_DIR\usr\bin"
}

$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    $GIT_OK = $true
    Ok "Git already installed: $(git --version)"
} else {
    Info "Git not found - installing PortableGit (no admin needed)..."
    try {
        $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' -UseBasicParsing
        $pattern = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'PortableGit-*-arm64.7z.exe' }
                   elseif ($env:PROCESSOR_ARCHITECTURE -eq 'x86') { 'PortableGit-*-32-bit.7z.exe' }
                   else { 'PortableGit-*-64-bit.7z.exe' }
        $asset = $rel.assets | Where-Object { $_.name -like $pattern } | Select-Object -First 1
        if (-not $asset) { throw "No PortableGit asset matching $pattern in the latest release." }

        Info "Downloading: $($asset.name) (~70MB)"
        $TmpExe = Join-Path $env:TEMP $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $TmpExe -UseBasicParsing

        New-Item -ItemType Directory -Path $GIT_DIR -Force | Out-Null
        # PortableGit is a 7-Zip self-extractor: -o<dir> sets the target, -y auto-confirms.
        # Start-Process -Wait so we do not race the extraction if the SFX is windowed.
        Start-Process -FilePath $TmpExe -ArgumentList "-o`"$GIT_DIR`" -y" -Wait -NoNewWindow
        Remove-Item $TmpExe -Force -ErrorAction SilentlyContinue

        if (Test-Path (Join-Path $GIT_DIR 'cmd\git.exe')) {
            $env:Path = "$env:Path;$GIT_DIR\cmd;$GIT_DIR\usr\bin"
            Add-ToUserPath "$GIT_DIR\cmd"
            $GIT_OK = $true
            Ok "Git installed: $(git --version)"
            Info "Location: $GIT_DIR"
        } else {
            Warn "PortableGit extraction did not produce cmd\git.exe."
        }
    } catch {
        Warn "Could not install git automatically: $($_.Exception.Message)"
        Info "The SSH key and GitHub connection will still work without git."
        Info "You can install it later from https://git-scm.com/download/win"
    }
}

# -- 3. Locate ssh-keygen / ssh-add / ssh -------------------------------------
Step "Checking for OpenSSH tools..."

function Find-SshTool($name) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($p in @(
        (Join-Path $env:SystemRoot "System32\OpenSSH\$name.exe"),
        (Join-Path $GIT_DIR "usr\bin\$name.exe")
    )) { if (Test-Path $p) { return $p } }
    return $null
}

$SSH_KEYGEN = Find-SshTool 'ssh-keygen'
$SSH_ADD    = Find-SshTool 'ssh-add'
$SSH        = Find-SshTool 'ssh'

if (-not $SSH_KEYGEN) {
    Err "ssh-keygen not found. Enable the built-in OpenSSH Client (Settings -> Apps -> Optional features) or install git."
}
Ok "ssh-keygen: $SSH_KEYGEN"

# -- 4. Install GitHub CLI (gh) - no admin ------------------------------------
Step "Checking for GitHub CLI (gh)..."

function Install-Gh {
    Info "Fetching latest gh release from GitHub..."
    $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/cli/cli/releases/latest' -UseBasicParsing
    $ver = $rel.tag_name -replace '^v', ''
    if (-not $ver) { Err "Could not fetch gh version from the GitHub API." }
    Info "Latest gh: v$ver"

    switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { $ghArch = 'windows_amd64' }
        'ARM64' { $ghArch = 'windows_arm64' }
        'x86'   { $ghArch = 'windows_386'   }
        default { Err "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
    }

    $ghZip = "gh_${ver}_${ghArch}.zip"
    $ghUrl = "https://github.com/cli/cli/releases/download/v$ver/$ghZip"
    $tmp   = Join-Path $env:TEMP ("gh_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    Info "Downloading: $ghZip"
    Invoke-WebRequest -Uri $ghUrl -OutFile (Join-Path $tmp $ghZip) -UseBasicParsing
    Expand-Archive -Path (Join-Path $tmp $ghZip) -DestinationPath (Join-Path $tmp 'extracted') -Force

    $ghBin = Get-ChildItem -Path (Join-Path $tmp 'extracted') -Filter 'gh.exe' -Recurse -File |
             Select-Object -First 1
    if (-not $ghBin) { Err "Could not find gh.exe inside the zip." }
    Copy-Item $ghBin.FullName (Join-Path $LOCAL_BIN 'gh.exe') -Force
    Remove-Item $tmp -Recurse -Force

    Ok "gh v$ver installed -> $LOCAL_BIN\gh.exe"
}

if (Get-Command gh -ErrorAction SilentlyContinue) {
    Ok "gh already available: $((gh --version) | Select-Object -First 1)"
} else {
    Install-Gh
}

# -- 5. Collect user details --------------------------------------------------
Write-Host ""
Step "Collecting details..."

$GH_USER = Read-Host "  GitHub username      "
if ([string]::IsNullOrWhiteSpace($GH_USER)) { Err "Username is required." }

$GH_EMAIL = Read-Host "  GitHub email         "
if ([string]::IsNullOrWhiteSpace($GH_EMAIL)) { Err "Email is required." }

$sec1 = Read-Host "  SSH key passphrase (leave empty for none)" -AsSecureString
$sec2 = Read-Host "  Confirm passphrase                       " -AsSecureString
function ConvertFrom-Secure($s) {
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}
$SSH_PASS  = ConvertFrom-Secure $sec1
$SSH_PASS2 = ConvertFrom-Secure $sec2
if ($SSH_PASS -ne $SSH_PASS2) { Err "Passphrases do not match." }

$hostShort = ($env:COMPUTERNAME).ToLower()
$KEY_LABEL = "$GH_USER-$hostShort-$(Get-Date -Format 'yyyyMMdd')"
$KEY_PATH  = Join-Path $SSH_DIR $KEY_LABEL

# -- 6. Ensure SSH directory exists -------------------------------------------
New-Item -ItemType Directory -Path $SSH_DIR -Force | Out-Null

# -- 7. Generate SSH key ------------------------------------------------------
Step "Generating SSH key (ed25519)..."

# Windows PowerShell 5.1 drops empty string arguments to native commands,
# so an empty passphrase has to be passed as a literal pair of quotes.
$passArg = if ([string]::IsNullOrEmpty($SSH_PASS)) { '""' } else { $SSH_PASS }

$generate = $true
if (Test-Path $KEY_PATH) {
    Warn "Key already exists at: $KEY_PATH"
    $ow = Read-Host "  Overwrite? (y/N)"
    if ($ow -match '^[yY]$') {
        Remove-Item $KEY_PATH, "$KEY_PATH.pub" -Force -ErrorAction SilentlyContinue
    } else {
        $generate = $false
        Ok "Keeping existing key."
    }
}

if ($generate) {
    & $SSH_KEYGEN -t ed25519 -C $GH_EMAIL -f $KEY_PATH -N $passArg
    if ($LASTEXITCODE -ne 0) { Err "ssh-keygen failed." }
    Ok "Key generated: $KEY_PATH"
}

# Lock the private key down to just you - OpenSSH refuses keys that are too open
& icacls $KEY_PATH /inheritance:r /grant:r "${env:USERNAME}:F" | Out-Null

# -- 8. Add key to ssh-agent --------------------------------------------------
Step "Adding key to ssh-agent..."
$agentOk = $false
try {
    $svc = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') { Start-Service ssh-agent -ErrorAction Stop }
    if ($SSH_ADD) {
        & $SSH_ADD $KEY_PATH
        if ($LASTEXITCODE -eq 0) { $agentOk = $true }
    }
} catch { }

if ($agentOk) {
    Ok "Key added to ssh-agent."
} else {
    Warn "Could not add the key to ssh-agent (the service may need an admin to enable it)."
    Info "Not a problem - ~/.ssh/config points git straight at the key file."
    Info "To enable it later, an admin can run: Set-Service ssh-agent -StartupType Automatic"
}

# -- 9. Update ~/.ssh/config --------------------------------------------------
Step "Updating ~/.ssh/config..."
$SSH_CONFIG = Join-Path $SSH_DIR 'config'
$MARKER     = "# github-$KEY_LABEL"

$configText = ''
if (Test-Path $SSH_CONFIG) { $configText = Get-Content $SSH_CONFIG -Raw }

if ($configText -notmatch [regex]::Escape($MARKER)) {
    # OpenSSH config is happiest with forward slashes, and the path is quoted
    # because a Windows user profile can contain spaces.
    $KEY_PATH_CFG = $KEY_PATH -replace '\\', '/'
    $block = @"

$MARKER
Host github.com
    HostName github.com
    User git
    IdentityFile "$KEY_PATH_CFG"
    AddKeysToAgent yes
    IdentitiesOnly yes
"@
    Add-Content -Path $SSH_CONFIG -Value $block
    Ok "SSH config updated."
} else {
    Ok "SSH config already contains this key."
}

# -- 10. Authenticate and add key to GitHub -----------------------------------
Step "Connecting to GitHub via gh..."

$authOk = $false
try { & gh auth status *> $null; if ($LASTEXITCODE -eq 0) { $authOk = $true } } catch { }

if (-not $authOk) {
    Info "Your browser will open - log in and approve access."
    & gh auth login --hostname github.com --git-protocol ssh --web
} else {
    Ok "Already logged in to gh."
}

$keyList = ''
try { $keyList = (& gh ssh-key list 2>$null) -join "`n" } catch { }
if ($keyList -match [regex]::Escape($KEY_LABEL)) {
    Ok "SSH key '$KEY_LABEL' already exists on GitHub."
} else {
    & gh ssh-key add "$KEY_PATH.pub" --title $KEY_LABEL
    Ok "SSH key added to GitHub!"
}

# -- 11. Configure git identity -----------------------------------------------
Step "Configuring git..."
if ($GIT_OK) {
    & git config --global user.name  $GH_USER
    & git config --global user.email $GH_EMAIL
    Ok "Git identity set: $GH_USER <$GH_EMAIL>"
} else {
    Warn "Git not available - skipping git config."
    Info "Run these manually once git is installed:"
    Info "  git config --global user.name  ""$GH_USER"""
    Info "  git config --global user.email ""$GH_EMAIL"""
}

# -- 12. Test connection ------------------------------------------------------
Step "Testing SSH connection to GitHub..."
Start-Sleep -Seconds 1
$sshTest = ''
if ($SSH) {
    try {
        $sshTest = (& $SSH -T git@github.com -i $KEY_PATH `
            -o StrictHostKeyChecking=no -o BatchMode=yes 2>&1) -join "`n"
    } catch { $sshTest = $_.Exception.Message }
}

if ($sshTest -match 'successfully authenticated') {
    Ok "GitHub connection is working!"
} else {
    Warn "Could not confirm connection automatically."
    Info "Test manually with: ssh -T git@github.com"
    if ($sshTest) { Info "Response received: $sshTest" }
}

# -- Done ---------------------------------------------------------------------
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Green
Write-Host "  |              OK  Setup complete!             |" -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Green
Write-Host ""
Info "Private key  : $KEY_PATH"
Info "Public key   : $KEY_PATH.pub"
$ghPath = Get-Command gh -ErrorAction SilentlyContinue
$ghWhere = if ($ghPath) { $ghPath.Source } else { Join-Path $LOCAL_BIN 'gh.exe' }
Info "gh binary    : $ghWhere"
Write-Host ""
Write-Host "Note: " -ForegroundColor Yellow -NoNewline
Write-Host "No admin password was used during setup."
Write-Host "      Everything is stored in your user profile."
Write-Host "      Open a NEW terminal window so the updated PATH takes effect."
Write-Host "      Run this script on the next machine to set that up too."
Write-Host ""
