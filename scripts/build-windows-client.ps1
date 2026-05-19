# build-windows-client.ps1
# Run this on a Windows machine to build the custom RustDesk client.
# Requirements: Git, internet connection. Everything else is installed automatically.
#
# Usage:
#   .\build-windows-client.ps1
#
# Output: rustdesk.exe in the current directory

$ErrorActionPreference = "Stop"

$REPO_URL     = "https://github.com/StarAtNyte/rustdesk"   # <-- your fork
$FLUTTER_VER  = "3.24.5"
$LLVM_VER     = "15.0.6"
$VCPKG_COMMIT = "120deac3062162151622ca4860575a33844ba10b"
$WORKDIR      = "$env:USERPROFILE\rustdesk-build"

function Step { param($msg) Write-Host "`n[+] $msg" -ForegroundColor Green }
function Warn  { param($msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Err   { param($msg) Write-Host "[x] $msg" -ForegroundColor Red; exit 1 }

Step "RustDesk Custom Client Builder"
New-Item -ItemType Directory -Force -Path $WORKDIR | Out-Null
Set-Location $WORKDIR

# ── 1. Install Chocolatey ──────────────────────────────────────────────────
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Step "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    $env:PATH += ";$env:ALLUSERSPROFILE\chocolatey\bin"
}

# ── 2. Install build tools ──────────────────────────────────────────────────
Step "Installing build tools (Git, Rust, NASM, LLVM, Python, NSIS)..."
$tools = @("git", "rust", "nasm", "nsis")
foreach ($t in $tools) {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
        choco install $t -y --no-progress
    } else {
        Warn "$t already installed"
    }
}
# Refresh PATH
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

# ── 3. Install LLVM ─────────────────────────────────────────────────────────
Step "Installing LLVM $LLVM_VER..."
$llvmUrl = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VER/LLVM-$LLVM_VER-win64.exe"
if (-not (Test-Path "C:\Program Files\LLVM\bin\clang.exe")) {
    Invoke-WebRequest $llvmUrl -OutFile "$WORKDIR\llvm-setup.exe"
    Start-Process -Wait "$WORKDIR\llvm-setup.exe" -ArgumentList "/S"
}
$env:LIBCLANG_PATH = "C:\Program Files\LLVM\bin"
$env:PATH += ";C:\Program Files\LLVM\bin"

# ── 4. Install Flutter ──────────────────────────────────────────────────────
Step "Installing Flutter $FLUTTER_VER..."
if (-not (Test-Path "C:\flutter\bin\flutter.bat")) {
    $flutterUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_${FLUTTER_VER}-stable.zip"
    Invoke-WebRequest $flutterUrl -OutFile "$WORKDIR\flutter.zip"
    Expand-Archive "$WORKDIR\flutter.zip" -DestinationPath "C:\" -Force
}
$env:PATH += ";C:\flutter\bin"
flutter config --enable-windows-desktop | Out-Null

# ── 5. Setup vcpkg ──────────────────────────────────────────────────────────
Step "Setting up vcpkg..."
if (-not (Test-Path "C:\vcpkg\vcpkg.exe")) {
    git clone https://github.com/microsoft/vcpkg.git C:\vcpkg
    Push-Location C:\vcpkg
    git checkout $VCPKG_COMMIT
    .\bootstrap-vcpkg.bat -disableMetrics
    Pop-Location
}
$env:VCPKG_ROOT = "C:\vcpkg"
$env:PATH += ";C:\vcpkg"

Step "Installing vcpkg packages (this takes ~20 minutes first time)..."
& C:\vcpkg\vcpkg install --triplet x64-windows-static

# ── 6. Clone repo ────────────────────────────────────────────────────────────
Step "Cloning modified RustDesk repo..."
if (-not (Test-Path "$WORKDIR\repo")) {
    git clone --recursive $REPO_URL "$WORKDIR\repo"
} else {
    Push-Location "$WORKDIR\repo"
    git pull
    git submodule update --init --recursive
    Pop-Location
}
Set-Location "$WORKDIR\repo"

# ── 7. Install Rust Windows target ──────────────────────────────────────────
Step "Setting up Rust toolchain..."
rustup target add x86_64-pc-windows-msvc
rustup component add rustfmt

# ── 8. Get Flutter dependencies ──────────────────────────────────────────────
Step "Getting Flutter dependencies..."
Push-Location flutter
flutter pub get
Pop-Location

# ── 9. Build ─────────────────────────────────────────────────────────────────
Step "Building RustDesk (this takes 10-20 minutes)..."
$env:VCPKG_ROOT = "C:\vcpkg"
cargo build --release --features flutter

# ── 10. Copy output ───────────────────────────────────────────────────────────
Step "Done!"
$outExe = "target\release\rustdesk.exe"
if (Test-Path $outExe) {
    Copy-Item $outExe "$PSScriptRoot\..\support-server\installer\rustdesk-custom.exe"
    Write-Host ""
    Write-Host "  Built: $outExe" -ForegroundColor Yellow
    Write-Host "  Copied to: support-server\installer\rustdesk-custom.exe" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Now run installer/build.sh on Linux to package it." -ForegroundColor Cyan
} else {
    Err "Build failed - rustdesk.exe not found in target\release\"
}
