#!/usr/bin/env bash
# ── deploy_server.sh ───────────────────────────────────────────────────────
# Deploys RustDesk server (hbbs + hbbr) on any Linux server via SSH.
# Also generates the key and prints the deploy.env values to use.
#
# Usage: ./deploy_server.sh <host> [user] [password-or-key]
#
# Examples:
#   ./deploy_server.sh 192.168.50.28 at-office atpass
#   ./deploy_server.sh ec2-xx-xx.compute.amazonaws.com ubuntu ~/.ssh/my.pem

set -euo pipefail

HOST="${1:?Usage: $0 <host> [user] [password-or-key]}"
USER="${2:-root}"
AUTH="${3:-}"

# Build SSH/SCP commands
if [[ -f "${AUTH:-}" ]]; then
    SSH="ssh -o StrictHostKeyChecking=no -i $AUTH $USER@$HOST"
    SCP="scp -o StrictHostKeyChecking=no -i $AUTH"
else
    SSH="sshpass -p '${AUTH:-}' ssh -o StrictHostKeyChecking=no $USER@$HOST"
    SCP="sshpass -p '${AUTH:-}' scp -o StrictHostKeyChecking=no"
fi

run() { eval "$SSH" "'$*'"; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Deploying RustDesk Server"
echo "  Host: $USER@$HOST"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Install Docker ────────────────────────────────────────────────────
echo "[1/4] Checking Docker..."
run "command -v docker >/dev/null 2>&1 || { curl -fsSL https://get.docker.com | sh; }"
run "docker --version"

# ── 2. Create directory + compose file ───────────────────────────────────
echo "[2/4] Setting up..."
run "mkdir -p ~/rustdesk-server/data"

run "cat > ~/rustdesk-server/docker-compose.yml" << 'EOF'
networks:
  rustdesk-net:

services:
  hbbs:
    container_name: hbbs
    ports:
      - "21115:21115"
      - "21116:21116"
      - "21116:21116/udp"
      - "21118:21118"
    image: rustdesk/rustdesk-server:latest
    command: hbbs -r hbbr:21117
    volumes:
      - ./data:/root
    networks:
      - rustdesk-net
    depends_on:
      - hbbr
    restart: unless-stopped

  hbbr:
    container_name: hbbr
    ports:
      - "21117:21117"
      - "21119:21119"
    image: rustdesk/rustdesk-server:latest
    command: hbbr
    volumes:
      - ./data:/root
    networks:
      - rustdesk-net
    restart: unless-stopped
EOF

# ── 3. Start ─────────────────────────────────────────────────────────────
echo "[3/4] Starting servers..."
run "cd ~/rustdesk-server && docker compose up -d"
sleep 5

# ── 4. Get key ───────────────────────────────────────────────────────────
echo "[4/4] Getting public key..."
SERVER_KEY=$(eval "$SSH" "cat ~/rustdesk-server/data/id_ed25519.pub 2>/dev/null || echo FAILED")

if [[ "$SERVER_KEY" == "FAILED" ]]; then
    echo "ERROR: Key not generated yet. Wait a moment and run:"
    echo "  ssh $USER@$HOST 'cat ~/rustdesk-server/data/id_ed25519.pub'"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SERVER DEPLOYED ✓"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Copy this into deploy.env:"
echo ""
echo "  RENDEZVOUS_SERVER=$HOST"
echo "  RELAY_SERVER=$HOST"
echo "  SERVER_KEY=$SERVER_KEY"
echo "  SUPPORT_SERVER_URL=http://$HOST:3030"
echo ""
echo "  Then run: ./build_custom.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
