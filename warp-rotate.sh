#!/usr/bin/env bash
#
# warp-rotate.sh - WARP IP Rotation + SOCKS5 Proxy for enowxai
#
# Setup WARP sebagai SOCKS5 proxy lokal yang bisa dipakai enowxai
# atau aplikasi lain. SSH, Tailscale, Nginx TIDAK terganggu.
#
# Usage:
#   ./warp-rotate.sh setup           # First-time setup (install + connect + proxy)
#   ./warp-rotate.sh rotate          # Rotate IP (re-register WARP)
#   ./warp-rotate.sh --check         # Cek IP saat ini (normal + WARP)
#   ./warp-rotate.sh --status        # Cek status lengkap
#   ./warp-rotate.sh --loop 3600     # Auto rotate tiap 3600 detik
#   ./warp-rotate.sh --down          # Stop WARP + proxy
#   ./warp-rotate.sh --up            # Start WARP + proxy
#   ./warp-rotate.sh --enowxai-add   # Add WARP proxy ke enowxai
#   ./warp-rotate.sh --enowxai-clear # Backup + clear proxy enowxai, add WARP
#
# Requires: wgcf, wireguard-tools (wg-quick), microsocks
#

set -euo pipefail

WGCF_DIR="/etc/warp"
WGCF_ACCOUNT="${WGCF_DIR}/wgcf-account.toml"
WGCF_PROFILE="${WGCF_DIR}/wgcf-profile.conf"
WG_CONF="/etc/wireguard/wgcf.conf"
WG_INTERFACE="wgcf"
WARP_IP="172.16.0.2"
SOCKS_PORT="40000"
SOCKS_BIND="127.0.0.1"
LOG_PREFIX="[warp-rotate]"

ENDPOINTS=(
    "162.159.192.1:2408"
    "162.159.193.1:2408"
    "162.159.195.1:2408"
    "162.159.192.7:2408"
    "162.159.193.7:2408"
)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} $*"
}

check_root() {
    if [[ $(id -u) -ne 0 ]]; then
        log "ERROR: Harus dijalankan sebagai root"
        exit 1
    fi
}

check_deps() {
    local missing=()
    command -v wgcf &>/dev/null || missing+=(wgcf)
    command -v wg-quick &>/dev/null || missing+=(wireguard-tools)
    command -v curl &>/dev/null || missing+=(curl)

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "ERROR: Dependencies belum terinstall: ${missing[*]}"
        log "Install dulu:"
        log "  wgcf           → curl -fsSL git.io/wgcf.sh | bash"
        log "  wireguard-tools → apt install wireguard-tools"
        exit 1
    fi
}

check_microsocks() {
    if ! command -v microsocks &>/dev/null; then
        log "microsocks belum terinstall. Installing..."
        install_microsocks
    fi
}

install_microsocks() {
    log "Installing microsocks from source..."
    local tmpdir
    tmpdir=$(mktemp -d)
    cd "$tmpdir"
    git clone https://github.com/rofl0r/microsocks.git 2>/dev/null
    cd microsocks
    make 2>/dev/null
    cp microsocks /usr/local/bin/
    cd /
    rm -rf "$tmpdir"
    log "✅ microsocks installed"
}

get_current_ip() {
    local ip
    ip=$(curl -s --max-time 10 https://ifconfig.me 2>/dev/null)
    echo "$ip"
}

get_warp_ip() {
    local ip
    if ss -tlnp | grep -q ":${SOCKS_PORT}" 2>/dev/null; then
        ip=$(curl -s --max-time 10 -x socks5://${SOCKS_BIND}:${SOCKS_PORT} https://ifconfig.me 2>/dev/null)
    elif ip link show "$WG_INTERFACE" &>/dev/null; then
        ip=$(curl -s --max-time 10 --interface "$WG_INTERFACE" https://ifconfig.me 2>/dev/null)
    fi
    echo "$ip"
}

random_endpoint() {
    local idx=$((RANDOM % ${#ENDPOINTS[@]}))
    echo "${ENDPOINTS[$idx]}"
}

# === WARP Tunnel ===

warp_down() {
    if ip link show "$WG_INTERFACE" &>/dev/null; then
        log "Stopping WARP tunnel..."
        wg-quick down "$WG_INTERFACE" 2>/dev/null || true
    fi
}

warp_up() {
    if ip link show "$WG_INTERFACE" &>/dev/null; then
        log "WARP tunnel already running"
        return 0
    fi

    log "Starting WARP tunnel..."
    # Backup DNS
    cp /etc/resolv.conf /etc/resolv.conf.bak.warp 2>/dev/null || true
    wg-quick up "$WG_INTERFACE"
    # Restore DNS agar SSH/Tailscale tidak terganggu
    cp /etc/resolv.conf.bak.warp /etc/resolv.conf 2>/dev/null || true
    log "✅ WARP tunnel active"
}

register_new_account() {
    log "Deleting old WARP account..."
    rm -f "$WGCF_ACCOUNT" "$WGCF_PROFILE"

    mkdir -p "$WGCF_DIR"
    cd "$WGCF_DIR"

    log "Registering new WARP account..."
    local retries=3
    for ((i=1; i<=retries; i++)); do
        echo 'y' | wgcf register --accept-tos 2>/dev/null \
            || echo 'y' | wgcf register 2>/dev/null \
            || yes | wgcf register 2>/dev/null

        if [[ -f "$WGCF_ACCOUNT" ]]; then
            log "✅ Account registered"
            break
        fi
        if [[ $i -eq $retries ]]; then
            log "ERROR: Failed to register after $retries attempts"
            exit 1
        fi
        log "Retry $i/$retries..."
        sleep 2
    done

    log "Generating WireGuard profile..."
    wgcf generate 2>/dev/null

    if [[ ! -f "$WGCF_PROFILE" ]]; then
        log "ERROR: Profile generation failed"
        exit 1
    fi
}

patch_profile() {
    local ep
    ep=$(random_endpoint)
    log "Using endpoint: $ep"

    local private_key public_key
    private_key=$(grep "^PrivateKey" "$WGCF_PROFILE" | cut -d= -f2- | xargs)
    public_key=$(grep "^PublicKey" "$WGCF_PROFILE" | cut -d= -f2- | xargs)

    cat > "$WG_CONF" << EOF
[Interface]
PrivateKey = ${private_key}
Address = ${WARP_IP}/32
DNS = 8.8.8.8,8.8.4.4
MTU = 1280
Table = 51888
PostUp = ip -4 rule add from ${WARP_IP} lookup 51888 2>/dev/null || true
PostDown = ip -4 rule delete from ${WARP_IP} lookup 51888 2>/dev/null || true

[Peer]
PublicKey = ${public_key}
AllowedIPs = 0.0.0.0/0
Endpoint = ${ep}
EOF

    log "✅ WireGuard config written"
}

# === SOCKS5 Proxy ===

proxy_start() {
    if ss -tlnp | grep -q ":${SOCKS_PORT}" 2>/dev/null; then
        log "SOCKS5 proxy already running on ${SOCKS_BIND}:${SOCKS_PORT}"
        return 0
    fi

    check_microsocks

    log "Starting SOCKS5 proxy (${SOCKS_BIND}:${SOCKS_PORT} → WARP)..."
    nohup microsocks -i "$SOCKS_BIND" -p "$SOCKS_PORT" -b "$WARP_IP" > /var/log/microsocks.log 2>&1 &
    sleep 1

    if ss -tlnp | grep -q ":${SOCKS_PORT}" 2>/dev/null; then
        log "✅ SOCKS5 proxy active on ${SOCKS_BIND}:${SOCKS_PORT}"
    else
        log "ERROR: SOCKS5 proxy failed to start"
        exit 1
    fi
}

proxy_stop() {
    if pkill -f "microsocks.*${SOCKS_PORT}" 2>/dev/null; then
        log "✅ SOCKS5 proxy stopped"
    else
        log "SOCKS5 proxy was not running"
    fi
}

# === enowxai Integration ===

enowxai_add() {
    if ! command -v enowxai &>/dev/null && [[ ! -f /root/.local/bin/enowxai ]]; then
        log "ERROR: enowxai not found"
        exit 1
    fi
    local enowx
    enowx=$(command -v enowxai 2>/dev/null || echo "/root/.local/bin/enowxai")

    log "Adding WARP proxy to enowxai..."
    "$enowx" proxy add "socks5://${SOCKS_BIND}:${SOCKS_PORT}" 2>&1
    log "✅ WARP proxy added to enowxai"
    echo ""
    "$enowx" proxy list 2>&1
}

enowxai_clear_and_add() {
    if ! command -v enowxai &>/dev/null && [[ ! -f /root/.local/bin/enowxai ]]; then
        log "ERROR: enowxai not found"
        exit 1
    fi
    local enowx
    enowx=$(command -v enowxai 2>/dev/null || echo "/root/.local/bin/enowxai")

    # Backup existing proxies
    local backup_file="/root/.enowxai/proxies.json.bak.$(date +%Y%m%d-%H%M%S)"
    if [[ -f /root/.enowxai/proxies.json ]]; then
        cp /root/.enowxai/proxies.json "$backup_file"
        log "✅ Proxy backup saved: $backup_file"
    fi

    # Clear all proxies
    log "Clearing all enowxai proxies..."
    "$enowx" proxy clear 2>&1

    # Add WARP proxy
    log "Adding WARP proxy..."
    "$enowx" proxy add "socks5://${SOCKS_BIND}:${SOCKS_PORT}" 2>&1

    # Test
    "$enowx" proxy test 2>&1

    echo ""
    log "✅ Done! enowxai now uses WARP proxy only"
    echo ""
    "$enowx" proxy list 2>&1
    echo ""
    log "📋 Rollback command:"
    log "   cp $backup_file /root/.enowxai/proxies.json && enowxai restart"
}

# === Commands ===

do_setup() {
    log "=== WARP + SOCKS5 Proxy Setup ==="
    check_deps
    check_microsocks

    # Register + config
    register_new_account
    patch_profile

    # Start tunnel
    warp_up

    # Start SOCKS5 proxy
    proxy_start

    # Verify
    sleep 2
    local normal_ip warp_ip
    normal_ip=$(get_current_ip)
    warp_ip=$(get_warp_ip)

    echo ""
    log "=== Setup Complete ==="
    log "Normal IP:  ${normal_ip:-unknown}"
    log "WARP IP:    ${warp_ip:-unknown}"
    log "SOCKS5:     socks5://${SOCKS_BIND}:${SOCKS_PORT}"
    echo ""
    log "Test: curl -x socks5://${SOCKS_BIND}:${SOCKS_PORT} https://ifconfig.me"
    log "enowxai: ./warp-rotate.sh --enowxai-add"
}

do_rotate() {
    local old_warp_ip
    old_warp_ip=$(get_warp_ip)
    log "Current WARP IP: ${old_warp_ip:-not active}"

    # Stop proxy + tunnel
    proxy_stop
    warp_down

    # Re-register
    register_new_account
    patch_profile

    # Start tunnel + proxy
    warp_up
    proxy_start

    sleep 2
    local new_warp_ip
    new_warp_ip=$(get_warp_ip)
    log "New WARP IP: ${new_warp_ip:-unknown}"

    if [[ -n "$old_warp_ip" && "$old_warp_ip" != "$new_warp_ip" && -n "$new_warp_ip" ]]; then
        log "✅ IP rotated: $old_warp_ip → $new_warp_ip"
    elif [[ -n "$new_warp_ip" ]]; then
        log "⚠️ IP: $new_warp_ip (mungkin sama, Cloudflare assign server yang sama)"
    else
        log "❌ Gagal mendapatkan IP baru"
    fi
}

do_status() {
    echo "=== WARP Status ==="
    if ip link show "$WG_INTERFACE" &>/dev/null; then
        echo "Tunnel:  ACTIVE"
    else
        echo "Tunnel:  INACTIVE"
    fi

    if ss -tlnp | grep -q ":${SOCKS_PORT}" 2>/dev/null; then
        echo "SOCKS5:  ACTIVE (${SOCKS_BIND}:${SOCKS_PORT})"
    else
        echo "SOCKS5:  INACTIVE"
    fi

    echo ""
    echo "Normal IP: $(get_current_ip)"
    echo "WARP IP:   $(get_warp_ip)"
    echo ""

    if [[ -f "$WGCF_ACCOUNT" ]]; then
        echo "Account: $WGCF_ACCOUNT (exists)"
    else
        echo "Account: not registered"
    fi
    if [[ -f "$WG_CONF" ]]; then
        echo "Config:  $WG_CONF (exists)"
        grep "Endpoint" "$WG_CONF" 2>/dev/null || true
    fi

    echo ""
    echo "=== Services ==="
    echo "SSH:       OK (you're reading this)"
    echo "Tailscale: $(tailscale status 2>/dev/null | head -1 || echo 'not installed')"
    echo "Nginx:     $(systemctl is-active nginx 2>/dev/null || echo 'not installed')"
}

do_loop() {
    local interval="${1:-3600}"
    log "Auto-rotate mode: setiap ${interval} detik"
    while true; do
        do_rotate
        log "Next rotation in ${interval} seconds..."
        sleep "$interval"
    done
}

do_down() {
    proxy_stop
    warp_down
    log "✅ WARP + proxy stopped"
}

do_up() {
    check_deps
    warp_up
    proxy_start
    sleep 1
    log "Normal IP: $(get_current_ip)"
    log "WARP IP:   $(get_warp_ip)"
    log "✅ WARP + proxy started"
}

# === Main ===
check_root

case "${1:-}" in
    setup)
        check_deps
        do_setup
        ;;
    rotate)
        check_deps
        do_rotate
        ;;
    --check)
        echo "Normal IP: $(get_current_ip)"
        echo "WARP IP:   $(get_warp_ip)"
        ;;
    --status)
        do_status
        ;;
    --loop)
        check_deps
        do_loop "${2:-3600}"
        ;;
    --down)
        do_down
        ;;
    --up)
        do_up
        ;;
    --enowxai-add)
        enowxai_add
        ;;
    --enowxai-clear)
        enowxai_clear_and_add
        ;;
    *)
        # Default: rotate
        check_deps
        do_rotate
        ;;
esac
