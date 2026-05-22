# build.ps1 - Builds SupportClient-Setup.exe from the Flutter source + NSIS
#
# Usage:
#   cd installer\
#   .\build.ps1
#
# Requirements:
#   - Flutter SDK on PATH  (flutter config --enable-windows-desktop)
#   - NSIS (makensis) on PATH  ->  choco install nsis
#                               or https://nsis.sourceforge.io
#   - Rust + cargo  (rustup target add x86_64-pc-windows-msvc)
#   - .env in support-server\ with SERVER_HOST, SERVER_KEY, SERVER_URL

$ErrorActionPreference = 'Stop'

# -- Paths --------------------------------------------------------------------
# installer\ -> support-server\ -> rustdesk\  (2 levels up = repo root)
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot   = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
$FlutterDir = Join-Path $RepoRoot 'flutter'
$OutDir     = Join-Path $ScriptDir '..\static'
$EnvFile    = Join-Path $ScriptDir '..\.env'
$AppStaging = Join-Path $ScriptDir 'app'

# -- Logging helpers ----------------------------------------------------------
function Log  { param([string]$msg) Write-Host "[+] $msg" -ForegroundColor Green  }
function Warn { param([string]$msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Err  {
    param([string]$msg)
    Write-Host "[x] $msg" -ForegroundColor Red
    exit 1
}

# -- 1. Load .env -------------------------------------------------------------
if (!(Test-Path $EnvFile)) {
    Err ".env not found at $EnvFile - copy .env.example and fill in your values."
}

Get-Content $EnvFile | ForEach-Object {
    $line = $_.Trim()
    # Skip blank lines and comments
    if ($line -eq '' -or $line.StartsWith('#')) { return }
    # Strip optional leading 'export '
    $line = $line -replace '^export\s+', ''
    if ($line -match '^([^=]+)=(.*)$') {
        $key = $Matches[1].Trim()
        # Strip surrounding quotes from value (single or double)
        $val = $Matches[2].Trim().Trim('"').Trim("'")
        [System.Environment]::SetEnvironmentVariable($key, $val, 'Process')
    }
}

$SERVER_HOST = $env:SERVER_HOST
$SERVER_KEY  = $env:SERVER_KEY
$SERVER_URL  = $env:SERVER_URL

if (!$SERVER_HOST) { Err "SERVER_HOST is not set in .env" }
if (!$SERVER_KEY)  { Err "SERVER_KEY is not set in .env"  }
if (!$SERVER_URL)  { Err "SERVER_URL is not set in .env"  }

Log "Building for: SERVER_HOST=$SERVER_HOST  SERVER_URL=$SERVER_URL"

# -- 2. Check required tools --------------------------------------------------
if (!(Get-Command flutter  -ErrorAction SilentlyContinue)) {
    Err "flutter not found on PATH.`nInstall Flutter SDK and run: flutter config --enable-windows-desktop"
}
if (!(Get-Command makensis -ErrorAction SilentlyContinue)) {
    Err "makensis not found on PATH.`nInstall NSIS:`n  choco install nsis`n  or https://nsis.sourceforge.io"
}
if (!(Get-Command cargo    -ErrorAction SilentlyContinue)) {
    Err "cargo not found on PATH.`nInstall Rust from https://rustup.rs"
}

$flutterVersion = (flutter --version 2>&1 | Select-Object -First 1).ToString().Trim()
Log "Flutter : $flutterVersion"

# -- 3. Build Rust library (generates generated_bridge.dart + librustdesk.dll) -
Log "Building Rust library (cargo build --lib --release)..."
Push-Location $RepoRoot
try {
    cargo build --lib --release --features flutter
    if ($LASTEXITCODE -ne 0) { Err "cargo build failed." }
    if (!(Test-Path (Join-Path $RepoRoot 'target\release\librustdesk.dll'))) {
        Err "cargo build succeeded but librustdesk.dll was not found. Check Rust source."
    }
    # Also build the virtual display dylib required on Windows
    Push-Location (Join-Path $RepoRoot 'libs\virtual_display\dylib')
    try {
        cargo build --release
        if ($LASTEXITCODE -ne 0) { Err "virtual_display dylib build failed." }
    } finally {
        Pop-Location
    }
} finally {
    Pop-Location
}
Log "Rust build complete."

# -- 4. Build Flutter Windows app ---------------------------------------------
Log "Running flutter pub get..."
Push-Location $FlutterDir
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { Err "flutter pub get failed." }

    Log "Building Flutter Windows release..."
    flutter build windows --release "--dart-define=SUPPORT_SERVER_URL=$SERVER_URL"
    if ($LASTEXITCODE -ne 0) { Err "flutter build windows failed." }
} finally {
    Pop-Location
}

# Resolve output directory - newer Flutter uses x64\, older omits it
$FlutterReleaseDir = Join-Path $FlutterDir 'build\windows\x64\runner\Release'
if (!(Test-Path (Join-Path $FlutterReleaseDir 'rustdesk.exe'))) {
    $FlutterReleaseDir = Join-Path $FlutterDir 'build\windows\runner\Release'
}
if (!(Test-Path (Join-Path $FlutterReleaseDir 'rustdesk.exe'))) {
    Err "Flutter build succeeded but rustdesk.exe was not found.`nExpected: $FlutterReleaseDir"
}

Log "Flutter build complete -> $FlutterReleaseDir"

# Copy virtual display DLL into the Flutter release dir (required at runtime)
$vdDll = Join-Path $RepoRoot 'target\release\deps\dylib_virtual_display.dll'
if (Test-Path $vdDll) {
    Copy-Item $vdDll -Destination $FlutterReleaseDir -Force
    Log "Copied dylib_virtual_display.dll -> $FlutterReleaseDir"
} else {
    Log "Warning: dylib_virtual_display.dll not found at $vdDll - skipping copy."
}

# -- 5. Stage app files for NSIS ----------------------------------------------
Log "Staging app files into installer\app\ ..."
if (Test-Path $AppStaging) {
    Remove-Item $AppStaging -Recurse -Force
}
New-Item -ItemType Directory -Path $AppStaging -Force | Out-Null

# Copy entire Release folder (rustdesk.exe + all DLLs + data\)
Copy-Item "$FlutterReleaseDir\*" -Destination $AppStaging -Recurse -Force

Log "Staged files (top 2 levels):"
Get-ChildItem -Path $AppStaging -Depth 1 | ForEach-Object {
    Write-Host "  $($_.FullName.Replace($AppStaging, '').TrimStart('\'))"
}

# -- 6. Build NSIS installer --------------------------------------------------
Log "Building SupportClient-Setup.exe with NSIS..."
Push-Location $ScriptDir
try {
    & makensis `
        "-DSERVER_HOST=$SERVER_HOST" `
        "-DSERVER_KEY=$SERVER_KEY"  `
        "-DSERVER_URL=$SERVER_URL"  `
        'windows.nsi'
    if ($LASTEXITCODE -ne 0) { Err "makensis failed. Check output above." }
} finally {
    Pop-Location
}

# -- 7. Move installer to static\ for the support server to serve -------------
$installerSrc = Join-Path $ScriptDir 'SupportClient-Setup.exe'
$installerDst = Join-Path $OutDir   'SupportClient-Setup.exe'

if (!(Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

Move-Item -Path $installerSrc -Destination $installerDst -Force

$OutDirFull = (Resolve-Path $OutDir).Path

Log "Done!"
Log "  Installer : $OutDirFull\SupportClient-Setup.exe"
Log "  Served at : $SERVER_URL/download/windows-installer"
Warn "  The installer\app\ directory is intermediate build output - do not commit it."
