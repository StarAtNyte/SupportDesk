#!/bin/bash

# Usage:
#   ./setup-server.sh          # auto-detect environment
#   ./setup-server.sh --aws    # force AWS mode (fetch IP from instance metadata)
#   ./setup-server.sh --local  # force local mode (fetch public IP from ifconfig.me)

set -e

DATA_DIR="$HOME/rustdesk-server"
MODE=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

# ── Parse args ───────────────────────────────────────────────────────────────
for arg in "$@"; do
    case $arg in
        --aws)   MODE="aws" ;;
        --local) MODE="local" ;;
        *) err "Unknown argument: $arg. Use --aws or --local." ;;
    esac
done

echo ""
echo "================================================"
echo "       RustDesk Self-Hosted Server Setup"
echo "================================================"
echo ""

# ── 1. Check OS ──────────────────────────────────────────────────────────────
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    err "This script is for Linux only."
fi

# ── 2. Auto-detect environment if no flag given ───────────────────────────────
if [[ -z "$MODE" ]]; then
    log "Auto-detecting environment..."
    # AWS instances expose instance metadata at this address
    AWS_CHECK=$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/ || true)
    if [[ -n "$AWS_CHECK" ]]; then
        MODE="aws"
        log "Detected: AWS EC2 instance."
    else
        MODE="local"
        log "Detected: local/non-AWS machine."
    fi
fi

# ── 3. Resolve public IP ──────────────────────────────────────────────────────
if [[ "$MODE" == "aws" ]]; then
    log "Fetching public IP from AWS instance metadata..."
    # IMDSv2 (recommended by AWS)
    TOKEN=$(curl -s --max-time 5 -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)
    if [[ -n "$TOKEN" ]]; then
        PUBLIC_IP=$(curl -s --max-time 5 -H "X-aws-ec2-metadata-token: $TOKEN" \
            http://169.254.169.254/latest/meta-data/public-ipv4 || true)
    fi
    # Fallback to IMDSv1
    if [[ -z "$PUBLIC_IP" ]]; then
        PUBLIC_IP=$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4 || true)
    fi
    # Final fallback
    if [[ -z "$PUBLIC_IP" ]]; then
        PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me || true)
    fi
else
    log "Fetching public IP..."
    PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me || true)
fi

[[ -z "$PUBLIC_IP" ]] && err "Could not determine public IP. Pass it manually by editing PUBLIC_IP in this script."
log "Public IP: $PUBLIC_IP"

# ── 4. Install Docker ────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    warn "Docker installed. If the next steps fail, run: newgrp docker && ./setup-server.sh --$MODE"
    newgrp docker
else
    log "Docker already installed: $(docker --version)"
fi

# ── 5. Install Docker Compose plugin ─────────────────────────────────────────
if ! docker compose version &>/dev/null; then
    log "Installing Docker Compose plugin..."
    sudo apt-get install -y docker-compose-plugin 2>/dev/null || \
    sudo yum install -y docker-compose-plugin 2>/dev/null || \
    err "Could not install docker-compose-plugin. Install it manually and re-run."
else
    log "Docker Compose already installed: $(docker compose version)"
fi

# ── 6. Create directories ────────────────────────────────────────────────────
log "Creating data directory at $DATA_DIR..."
mkdir -p "$DATA_DIR/data"
cd "$DATA_DIR"

# ── 7. Write docker-compose.yml ──────────────────────────────────────────────
log "Writing docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
networks:
  rustdesk-net:
    external: false

services:
  hbbs:
    container_name: hbbs
    ports:
      - 21115:21115
      - 21116:21116
      - 21116:21116/udp
      - 21118:21118
    image: rustdesk/rustdesk-server:latest
    command: hbbs
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
      - 21117:21117
      - 21119:21119
    image: rustdesk/rustdesk-server:latest
    command: hbbr
    volumes:
      - ./data:/root
    networks:
      - rustdesk-net
    restart: unless-stopped
EOF

# ── 8. Firewall ───────────────────────────────────────────────────────────────
if [[ "$MODE" == "aws" ]]; then
    warn "AWS mode: firewall rules are managed via Security Groups in the AWS console."
    warn "Make sure these inbound rules are open for 0.0.0.0/0 (or your IP range):"
    echo ""
    echo "   Port 21115  TCP"
    echo "   Port 21116  TCP + UDP"
    echo "   Port 21117  TCP"
    echo "   Port 21118  TCP"
    echo "   Port 21119  TCP"
    echo ""
else
    log "Configuring local firewall..."
    if command -v ufw &>/dev/null; then
        sudo ufw allow 21115:21119/tcp
        sudo ufw allow 21116/udp
        sudo ufw reload
        log "UFW rules added."
    elif command -v firewall-cmd &>/dev/null; then
        sudo firewall-cmd --permanent --add-port=21115-21119/tcp
        sudo firewall-cmd --permanent --add-port=21116/udp
        sudo firewall-cmd --reload
        log "firewalld rules added."
    else
        warn "No supported firewall found. Manually open ports 21115-21119 TCP and 21116 UDP."
    fi
fi

# ── 9. Start containers ───────────────────────────────────────────────────────
log "Pulling latest RustDesk server images..."
docker compose pull

log "Starting RustDesk server..."
# If containers are already running (possibly from a different compose project), skip entirely
HBBS_RUNNING=$(docker ps --filter "name=^hbbs$" --filter "status=running" -q)
HBBR_RUNNING=$(docker ps --filter "name=^hbbr$" --filter "status=running" -q)

if [[ -n "$HBBS_RUNNING" && -n "$HBBR_RUNNING" ]]; then
    warn "hbbs and hbbr are already running — skipping container creation."
elif docker ps -a --format '{{.Names}}' | grep -qE '^(hbbs|hbbr)$'; then
    warn "Containers hbbs/hbbr exist but are not running — they may belong to another compose project."
    warn "Start them manually with: docker start hbbs hbbr"
    warn "Or check their compose file and use that instead."
else
    docker compose up -d
fi

# ── 10. Wait for key ──────────────────────────────────────────────────────────
log "Waiting for key generation..."
for i in $(seq 1 15); do
    [[ -f "$DATA_DIR/data/id_ed25519.pub" ]] && break
    sleep 1
done

[[ ! -f "$DATA_DIR/data/id_ed25519.pub" ]] && err "Key not generated after 15s. Run: docker compose logs"

PUBLIC_KEY=$(cat "$DATA_DIR/data/id_ed25519.pub")

# ── 11. Summary ───────────────────────────────────────────────────────────────
echo ""
echo "================================================"
echo -e "       ${GREEN}RustDesk Server is Running!${NC}  [$MODE mode]"
echo "================================================"
echo ""
info "Server status:"
docker compose ps
echo ""
echo -e "${CYAN}┌─ Client Configuration ──────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ID Server    : ${GREEN}$PUBLIC_IP${NC}"
echo -e "${CYAN}│${NC}  Relay Server : ${GREEN}$PUBLIC_IP${NC}"
echo -e "${CYAN}│${NC}  Key          : ${YELLOW}$PUBLIC_KEY${NC}"
echo -e "${CYAN}│${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────┘${NC}"
echo ""
info "In RustDesk client: Settings → Network → ID/Relay Server"
info "Paste the above values into the corresponding fields."
echo ""
info "Useful commands:"
echo "   docker compose -f $DATA_DIR/docker-compose.yml logs -f    # live logs"
echo "   docker compose -f $DATA_DIR/docker-compose.yml ps         # status"
echo "   docker compose -f $DATA_DIR/docker-compose.yml restart    # restart"
echo "   docker compose -f $DATA_DIR/docker-compose.yml down       # stop"
echo ""
