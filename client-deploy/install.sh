#!/bin/bash
# RustDesk Silent Installer — Linux
# Usage:
#   ./install.sh           # user mode (default)
#   ./install.sh --agent   # support agent mode

set -e

SERVER="113.199.192.32"
KEY="Jf5elrunPtjOAXfEVt5hsx6kTTjlrwGjQEMiJ1qJHuQ="
VERSION="1.3.8"   # update when new release is out
CONFIG_DIR="$HOME/.config/rustdesk"
CONFIG_FILE="$CONFIG_DIR/RustDesk.toml"
MODE="user"
AGENT_PASSWORD=""

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }

for arg in "$@"; do
    case $arg in
        --agent) MODE="agent" ;;
        --password=*) AGENT_PASSWORD="${arg#*=}" ;;
    esac
done

echo ""
echo "======================================"
echo "   RustDesk Client Setup"
[[ "$MODE" == "agent" ]] && echo "   Mode: Support Agent" || echo "   Mode: User"
echo "======================================"
echo ""

# ── 1. Detect package manager & install ──────────────────────────────────────
if command -v rustdesk &>/dev/null; then
    log "RustDesk already installed — skipping download."
else
    log "Downloading RustDesk $VERSION..."
    TMP=$(mktemp -d)

    if command -v apt-get &>/dev/null; then
        DEB_URL="https://github.com/rustdesk/rustdesk/releases/download/$VERSION/rustdesk-$VERSION-x86_64.deb"
        curl -L "$DEB_URL" -o "$TMP/rustdesk.deb"
        log "Installing..."
        sudo apt-get install -y "$TMP/rustdesk.deb"

    elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        RPM_URL="https://github.com/rustdesk/rustdesk/releases/download/$VERSION/rustdesk-$VERSION-0.x86_64.rpm"
        curl -L "$RPM_URL" -o "$TMP/rustdesk.rpm"
        log "Installing..."
        sudo rpm -i "$TMP/rustdesk.rpm" 2>/dev/null || sudo dnf install -y "$TMP/rustdesk.rpm"

    else
        err "Unsupported package manager. Install RustDesk manually from: https://rustdesk.com"
    fi

    rm -rf "$TMP"
    log "RustDesk installed."
fi

# ── 2. Write config ───────────────────────────────────────────────────────────
log "Configuring server..."
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" << EOF
[options]
custom-rendezvous-server = "$SERVER"
key = "$KEY"
relay-server = "$SERVER"
EOF

# Agent mode: set a permanent password
if [[ "$MODE" == "agent" ]]; then
    if [[ -z "$AGENT_PASSWORD" ]]; then
        read -rsp "Set a permanent password for this agent (used to receive connections): " AGENT_PASSWORD
        echo ""
    fi
    echo "permanent-password = \"$AGENT_PASSWORD\"" >> "$CONFIG_FILE"
    warn "Permanent password set. Keep it secret — anyone with it can connect to this machine."
fi

log "Config written to $CONFIG_FILE"

# ── 3. Enable autostart ────────────────────────────────────────────────────────
log "Enabling RustDesk autostart..."
sudo systemctl enable rustdesk 2>/dev/null && \
sudo systemctl start rustdesk 2>/dev/null || \
warn "Could not enable systemd service. RustDesk will need to be started manually."

# ── 4. Get the machine ID ────────────────────────────────────────────────────
sleep 2
RDID=$(rustdesk --get-id 2>/dev/null || echo "(open RustDesk to see your ID)")

# ── 5. Summary ────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e "${GREEN}   Setup Complete!${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""
echo -e "   Server : ${GREEN}$SERVER${NC}"
echo -e "   Your ID: ${YELLOW}$RDID${NC}"
echo ""
if [[ "$MODE" == "agent" ]]; then
    echo -e "   ${CYAN}[Agent]${NC} Share your ID with users so they can request support."
else
    echo -e "   ${CYAN}[User]${NC} Share your ID with your support agent to get help."
fi
echo ""
