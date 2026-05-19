# RustDesk Agent Installer - Windows
# Usage:
#   .\install.ps1                         # agent mode (default)
#   .\install.ps1 -AgentPassword "s3cr3t" # skip password prompt
#
# Run as Administrator. Right-click -> Run with PowerShell.

param (
    [switch]$Agent = $true,
    [string]$AgentPassword = ""
)

$SERVER        = "your.domain.com"
$KEY           = "Jf5elrunPtjOAXfEVt5hsx6kTTjlrwGjQEMiJ1qJHuQ="
$VERSION       = "1.3.8"
$INSTALLER_URL = "https://github.com/rustdesk/rustdesk/releases/download/$VERSION/rustdesk-$VERSION-x86_64.exe"
$INSTALLER_PATH= "$env:TEMP\rustdesk-setup.exe"
$RUSTDESK_EXE  = "C:\Program Files\RustDesk\rustdesk.exe"
$CONFIG_DIR    = "$env:APPDATA\RustDesk\config"

function Write-Step { param($msg) Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "[x] $msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "   RustDesk Agent Setup" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# 1. Download and install if not present
if (Test-Path $RUSTDESK_EXE) {
    Write-Step "RustDesk already installed - skipping download."
} else {
    Write-Step "Downloading RustDesk $VERSION..."
    try {
        Invoke-WebRequest -Uri $INSTALLER_URL -OutFile $INSTALLER_PATH -UseBasicParsing
    } catch {
        Write-Err "Download failed: $_"
    }
    Write-Step "Installing RustDesk silently..."
    Start-Process -Wait -FilePath $INSTALLER_PATH -ArgumentList "--silent-install"
    if (-not (Test-Path $RUSTDESK_EXE)) {
        Write-Err "Installation failed. Try running as Administrator."
    }
    Write-Step "RustDesk installed."
}

# 2. Stop RustDesk if running
Write-Step "Stopping RustDesk if running..."
Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

# 3. Write config (server settings go in RustDesk2.toml)
Write-Step "Configuring server..."
New-Item -ItemType Directory -Force -Path $CONFIG_DIR | Out-Null

$config2 = "[options]`r`ncustom-rendezvous-server = `"$SERVER`"`r`nkey = `"$KEY`"`r`nrelay-server = `"$SERVER`""

if ($Agent) {
    if ($AgentPassword -eq "") {
        $AgentPassword = Read-Host "Set a permanent password for this agent (leave blank to skip)"
    }
    if ($AgentPassword -ne "") {
        $config2 += "`r`npermanent-password = `"$AgentPassword`""
        Write-Warn "Permanent password set."
    }
}

Set-Content -Path "$CONFIG_DIR\RustDesk2.toml" -Value $config2 -Encoding UTF8
Write-Step "Config written."

# 4. Start RustDesk
Write-Step "Starting RustDesk..."
Start-Process -FilePath $RUSTDESK_EXE
Start-Sleep -Seconds 3

# 5. Get ID
$id = & $RUSTDESK_EXE --get-id 2>$null
if (-not $id) { $id = "(open RustDesk to see your ID)" }

# 6. Summary
Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "   Setup Complete!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "   Server : $SERVER" -ForegroundColor White
Write-Host "   Your ID: $id" -ForegroundColor Yellow
Write-Host ""
Write-Host "   Open the dashboard to monitor support requests." -ForegroundColor Cyan
Write-Host ""
