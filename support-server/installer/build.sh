#!/bin/bash
# Builds SupportClient-Setup.exe from the Flutter source + NSIS
#
# Usage:
#   cd installer/
#   ./build.sh
#
# Requirements:
#   - Flutter SDK on PATH (with Windows build support configured)
#   - NSIS (makensis) on PATH  →  sudo apt-get install -y nsis   (Linux/WSL)
#                               or  choco install nsis            (Windows)
#   - Rust + cargo (for the flutter_hbb native library)
#   - .env in support-server/ with SERVER_HOST, SERVER_KEY, SERVER_URL

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FLUTTER_DIR="$REPO_ROOT/flutter"
OUT_DIR="$SCRIPT_DIR/../static"
ENV_FILE="$SCRIPT_DIR/../.env"
APP_STAGING="$SCRIPT_DIR/app"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }

# ── 1. Load .env ───────────────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
    err ".env not found at $ENV_FILE — copy .env.example and fill in your values."
fi
set -a; source "$ENV_FILE"; set +a

[[ -z "$SERVER_HOST" ]] && err "SERVER_HOST is not set in .env"
[[ -z "$SERVER_KEY"  ]] && err "SERVER_KEY is not set in .env"
[[ -z "$SERVER_URL"  ]] && err "SERVER_URL is not set in .env"

log "Building for: SERVER_HOST=$SERVER_HOST  SERVER_URL=$SERVER_URL"

# ── 2. Check tools ─────────────────────────────────────────────────────────────
if ! command -v flutter &>/dev/null; then
    err "flutter not found on PATH. Install Flutter SDK and ensure 'flutter' is accessible."
fi
if ! command -v makensis &>/dev/null; then
    err "makensis not found. Install NSIS:
  Linux/WSL : sudo apt-get install -y nsis
  Windows   : choco install nsis   (or download from https://nsis.sourceforge.io)"
fi

log "Flutter: $(flutter --version --machine 2>/dev/null | grep -o '"frameworkVersion":"[^"]*"' | cut -d'"' -f4 || flutter --version | head -1)"

# ── 3. Build Flutter Windows app ──────────────────────────────────────────────
log "Building Flutter Windows release..."
cd "$FLUTTER_DIR"

flutter pub get

# Pass the support server URL in at compile time so the in-app
# "Request Support" button knows where to send requests even before
# the NSIS installer has written the TOML config.
# The NSIS installer ALSO writes it to RustDesk2.toml as a runtime
# fallback, so both paths work.
flutter build windows --release \
    --dart-define=SUPPORT_SERVER_URL="$SERVER_URL"

FLUTTER_RELEASE_DIR="$FLUTTER_DIR/build/windows/x64/runner/Release"

if [[ ! -f "$FLUTTER_RELEASE_DIR/rustdesk.exe" ]]; then
    # Older Flutter versions put the output one level up
    FLUTTER_RELEASE_DIR="$FLUTTER_DIR/build/windows/runner/Release"
fi

if [[ ! -f "$FLUTTER_RELEASE_DIR/rustdesk.exe" ]]; then
    err "Flutter build succeeded but rustdesk.exe not found. Check build output above."
fi

log "Flutter build complete → $FLUTTER_RELEASE_DIR"

# ── 4. Stage app files for NSIS ───────────────────────────────────────────────
log "Staging app files into installer/app/ ..."
rm -rf "$APP_STAGING"
mkdir -p "$APP_STAGING"

# Copy the entire Release directory contents (exe + DLLs + data/)
cp -r "$FLUTTER_RELEASE_DIR"/. "$APP_STAGING/"

log "Staged files:"
find "$APP_STAGING" -maxdepth 2 | sort | sed 's|^|  |'

# ── 5. Build NSIS installer ───────────────────────────────────────────────────
log "Building SupportClient-Setup.exe with NSIS..."
cd "$SCRIPT_DIR"

makensis \
    -DSERVER_HOST="$SERVER_HOST" \
    -DSERVER_KEY="$SERVER_KEY" \
    -DSERVER_URL="$SERVER_URL" \
    windows.nsi

# ── 6. Move to static/ so the support server can serve it ─────────────────────
mv -f SupportClient-Setup.exe "$OUT_DIR/"

log "Done!"
log "  Installer : $OUT_DIR/SupportClient-Setup.exe"
log "  Served at : $SERVER_URL/download/windows-installer"
warn "  The installer/app/ directory is intermediate build output — do not commit it."
