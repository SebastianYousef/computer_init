# =============================================================================
#  vscode_windows.ps1 - Install VSCode on Windows without admin
#  Uses VSCode's official .zip archive + portable mode (no installer, no admin)
#
#  Run with:  powershell -ExecutionPolicy Bypass -File vscode_windows.ps1
#  Or just double-click vscode_windows.bat
# =============================================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # makes Invoke-WebRequest much faster

# -- Output helpers -----------------------------------------------------------
function Step($m) { Write-Host ""; Write-Host "[>] $m" -ForegroundColor Blue }
function Ok($m)   { Write-Host "[OK] $m"  -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m"   -ForegroundColor Yellow }
function Info($m) { Write-Host "     $m"  -ForegroundColor Cyan }
function Err($m)  { Write-Host "[X] $m"   -ForegroundColor Red; exit 1 }

# -- Banner -------------------------------------------------------------------
Write-Host ""
Write-Host "  ==========================================" -ForegroundColor White
Write-Host "  |   VSCode Installer  -  Windows         |" -ForegroundColor White
Write-Host "  |   (portable mode, no admin required)   |" -ForegroundColor White
Write-Host "  ==========================================" -ForegroundColor White
Write-Host ""

# -- 0. Verify Windows --------------------------------------------------------
if ($env:OS -ne 'Windows_NT') { Err "This script is for Windows only." }
$osName = (Get-CimInstance Win32_OperatingSystem).Caption
Ok "Detected: $osName - $env:PROCESSOR_ARCHITECTURE"

# -- Local directories --------------------------------------------------------
$VSCODE_DIR = Join-Path $env:LOCALAPPDATA 'Programs\VSCode'
$VSCODE_BIN = Join-Path $VSCODE_DIR 'bin'          # contains code.cmd
$CODE_EXE   = Join-Path $VSCODE_DIR 'Code.exe'

# -- 1. Check if already installed --------------------------------------------
Step "Checking for existing VSCode installation..."

# Is 'code' already usable from the terminal?
$existing = Get-Command code -ErrorAction SilentlyContinue
if ($existing) {
    Ok "'code' is already available in the terminal: $($existing.Source)"
    Info "Run 'code .' to open a folder, or 'code --version' to confirm."
    Write-Host ""
    exit 0
}

# Portable install present but not on PATH?
$SkipDownload = $false
if (Test-Path $CODE_EXE) {
    Warn "VSCode portable found at: $VSCODE_DIR"
    Warn "But 'code' is not on your PATH yet - fixing that now."
    $SkipDownload = $true
} else {
    Ok "No existing VSCode installation found - downloading."
}

# -- 2. Determine architecture ------------------------------------------------
switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { $OS_TYPE = 'win32-x64-archive'   }
    'ARM64' { $OS_TYPE = 'win32-arm64-archive' }
    'x86'   { $OS_TYPE = 'win32-archive'       }
    default { Err "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
}

# -- 3. Download VSCode archive -----------------------------------------------
if (-not $SkipDownload) {
    Step "Downloading VSCode ($OS_TYPE)..."
    Info "This may take a moment (~130MB)..."

    $DownloadUrl = "https://update.code.visualstudio.com/latest/$OS_TYPE/stable"
    $TmpDir = Join-Path $env:TEMP ("vscode_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null
    $TmpZip = Join-Path $TmpDir 'vscode.zip'

    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TmpZip -UseBasicParsing
    Ok "Download complete."

    # -- 4. Extract into %LOCALAPPDATA%\Programs\VSCode -----------------------
    Step "Extracting VSCode..."
    New-Item -ItemType Directory -Path $VSCODE_DIR -Force | Out-Null
    # The .zip has no top-level folder, so its contents land directly in $VSCODE_DIR
    Expand-Archive -Path $TmpZip -DestinationPath $VSCODE_DIR -Force
    Remove-Item $TmpDir -Recurse -Force
    Ok "VSCode extracted to: $VSCODE_DIR"

    if (-not (Test-Path $CODE_EXE)) { Err "Code.exe was not found after extraction." }

    # -- 5. Create portable mode data directory -------------------------------
    # VSCode looks for a 'data' folder next to Code.exe to activate portable mode.
    # This keeps all extensions and settings inside the install folder instead of
    # scattering them across %APPDATA% and %USERPROFILE%.
    New-Item -ItemType Directory -Path (Join-Path $VSCODE_DIR 'data') -Force | Out-Null
    Ok "Portable mode enabled - settings stored in: $VSCODE_DIR\data"
}

# -- 6. Put 'code' on the user PATH -------------------------------------------
Step "Linking 'code' command to terminal..."

$CodeCmd = Join-Path $VSCODE_BIN 'code.cmd'
if (-not (Test-Path $CodeCmd)) { Err "Could not find the code CLI at: $CodeCmd" }

# User-level PATH only - no admin, and it survives reboots
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ([string]::IsNullOrEmpty($userPath)) { $userPath = '' }
$paths = $userPath -split ';' | Where-Object { $_ -ne '' }

if ($paths -notcontains $VSCODE_BIN) {
    $newPath = (($paths + $VSCODE_BIN) -join ';')
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Ok "Added to your PATH: $VSCODE_BIN"
} else {
    Ok "Already on your PATH: $VSCODE_BIN"
}
# Make it work in this session too
$env:Path = "$env:Path;$VSCODE_BIN"

# -- 7. Start Menu shortcut ---------------------------------------------------
# The .zip archive registers nothing, so create the shortcut ourselves
Step "Creating Start Menu shortcut..."
$StartMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$Shortcut  = Join-Path $StartMenu 'Visual Studio Code.lnk'
try {
    $wsh = New-Object -ComObject WScript.Shell
    $lnk = $wsh.CreateShortcut($Shortcut)
    $lnk.TargetPath       = $CODE_EXE
    $lnk.WorkingDirectory = $VSCODE_DIR
    $lnk.Description      = 'Visual Studio Code'
    $lnk.Save()
    Ok "Shortcut created: $Shortcut"
} catch {
    Warn "Could not create the Start Menu shortcut - not a problem."
    Info "Launch VSCode from: $CODE_EXE"
}

# -- 8. Verify ----------------------------------------------------------------
Step "Verifying installation..."
$version = 'unknown'
try { $version = (& $CodeCmd --version 2>$null | Select-Object -First 1) } catch { }
Ok "VSCode version: $version"

# -- Done ---------------------------------------------------------------------
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Green
Write-Host "  |              OK  Setup complete!             |" -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Green
Write-Host ""
Info "Install location : $VSCODE_DIR"
Info "Settings & exts  : $VSCODE_DIR\data"
Info "CLI command      : $CodeCmd"
Write-Host ""
Write-Host "Note: " -ForegroundColor Yellow -NoNewline
Write-Host "Open a NEW terminal window, then run:"
Write-Host "        code .        -> open current folder"
Write-Host "        code file.txt -> open a specific file"
Write-Host ""
Write-Host "Note: " -ForegroundColor Yellow -NoNewline
Write-Host "No admin was used - VSCode lives entirely in your user profile."
Write-Host ""
