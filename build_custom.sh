#!/usr/bin/env bash
# ── build_custom.sh ─────────────────────────────────────────────────────────
# Reads deploy.env and builds the RustDesk app with those values baked in.
# Usage: ./build_custom.sh [--skip-cargo]

set -euo pipefail
cd "$(dirname "$0")"

ENV_FILE="deploy.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found. Create it from deploy.env.example"
    exit 1
fi

# Load config
source "$ENV_FILE"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building RustDesk with custom server"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Rendezvous : $RENDEZVOUS_SERVER"
echo "  Relay      : $RELAY_SERVER"
echo "  Key        : ${SERVER_KEY:0:20}..."
echo "  Support    : $SUPPORT_SERVER_URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Patch Rust source: RENDEZVOUS_SERVERS + RS_PUB_KEY ──────────────────
CONFIG_FILE="libs/hbb_common/src/config.rs"

sed -i "s|pub const RENDEZVOUS_SERVERS: &\[&str\] = &\[.*\];|pub const RENDEZVOUS_SERVERS: \&[\&str] = \&[\"$RENDEZVOUS_SERVER\"];|" "$CONFIG_FILE"
sed -i "s|pub const RS_PUB_KEY: &str = \".*\";|pub const RS_PUB_KEY: \&str = \"$SERVER_KEY\";|" "$CONFIG_FILE"
echo "[1/5] Patched config.rs (rendezvous + key)"

# ── 2. Patch Dart source: support-server-url fallback ──────────────────────
DESKTOP_DART="flutter/lib/desktop/pages/desktop_home_page.dart"
MOBILE_DART="flutter/lib/mobile/pages/connection_page.dart"

sed -i "s|return v.isNotEmpty ? v : '.*';|return v.isNotEmpty ? v : '$SUPPORT_SERVER_URL';|" "$DESKTOP_DART"
sed -i "s|return v.isNotEmpty ? v : '.*';|return v.isNotEmpty ? v : '$SUPPORT_SERVER_URL';|" "$MOBILE_DART"
echo "[2/5] Patched Dart files (support-server-url)"

# ── 3. Cargo build (Rust library) ─────────────────────────────────────────
SKIP_CARGO=false
if [[ "${1:-}" == "--skip-cargo" ]]; then
    SKIP_CARGO=true
fi

export PATH="$HOME/.cargo/bin:$HOME/flutter/bin:$PATH"
export VCPKG_ROOT="${VCPKG_ROOT:-$HOME/vcpkg}"

if [[ "$SKIP_CARGO" == "false" ]]; then
    echo "[3/5] Building Rust library (this takes ~5 min)..."
    cargo build --features flutter --lib --release
else
    echo "[3/5] Skipping cargo build"
fi

# ── 4. Flutter build ──────────────────────────────────────────────────────
echo "[4/5] Building Flutter app..."
cd flutter
flutter build linux --release
cd ..

# ── 5. Install ────────────────────────────────────────────────────────────
echo "[5/5] Installing..."
BUNDLE="flutter/build/linux/x64/release/bundle"

# Write a default config so the app picks up relay + key on first launch
mkdir -p ~/.config/rustdesk
cat > ~/.config/rustdesk/RustDesk2.toml << EOF2
rendezvous_server = '$RENDEZVOUS_SERVER'

[options]
custom-rendezvous-server = '$RENDEZVOUS_SERVER'
relay-server = '$RELAY_SERVER'
key = '$SERVER_KEY'
support-server-url = '$SUPPORT_SERVER_URL'
EOF2

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  BUILD COMPLETE ✓"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Bundle: $(pwd)/$BUNDLE/"
echo "  Config: ~/.config/rustdesk/RustDesk2.toml"
echo ""
echo "  To install system-wide:"
echo "    sudo cp -r $BUNDLE/* /usr/share/rustdesk/"
echo "    sudo ln -sf /usr/share/rustdesk/rustdesk /usr/bin/rustdesk"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
