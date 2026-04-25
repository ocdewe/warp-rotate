#!/usr/bin/env bash
#
# warp-rotate.sh - WARP IP Rotation via Re-register
# Otomatis delete akun WARP lama, register baru, reconnect → IP baru
#
# Usage:
#   ./warp-rotate.sh              # Rotate sekali
#   ./warp-rotate.sh --check      # Cek IP saat ini
#   ./warp-rotate.sh --status     # Cek status WARP
#   ./warp-rotate.sh --loop 3600  # Auto rotate tiap 3600 detik (1 jam)
#
# Requires: wgcf, wireguard-tools (wg-quick)
#

set -euo pipefail

WGCF_DIR="/etc/warp"
WGCF_ACCOUNT="${WGCF_DIR}/wgcf-account.toml"
WGCF_PROFILE="${WGCF_DIR}/wgcf-profile.conf"
WG_CONF="/etc/wireguard/wgcf.conf"
WG_INTERFACE="wgcf"
ENDPOINT="162.159.192.1:2408"
LOG_PREFIX="[warp-rotate]"

# Daftar endpoint Cloudflare (rotate untuk variasi IP)
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
        log "  wgcf        → curl -fsSL git.io/wgcf.sh | bash"
        log "  wireguard   → apt install wireguard-tools"
        exit 1
    fi
}

get_current_ip() {
    # Cek IP publik via Cloudflare trace
    local ip
    ip=$(curl -s --max-time 10 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep "ip=" | cut -d= -f2)
    if [[ -z "$ip" ]]; then
        ip=$(curl -s --max-time 10 https://ifconfig.me 2>/dev/null)
    fi
    echo "$ip"
}

get_warp_ip() {
    # Cek IP via WARP interface
    local ip
    if ip link show "$WG_INTERFACE" &>/dev/null; then
        ip=$(curl -s --max-time 10 --interface "$WG_INTERFACE" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep "ip=" | cut -d= -f2)
    fi
    echo "$ip"
}

random_endpoint() {
    local idx=$((RANDOM % ${#ENDPOINTS[@]}))
    echo "${ENDPOINTS[$idx]}"
}

warp_down() {
    if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}" 2>/dev/null; then
        log "Stopping WARP tunnel..."
        wg-quick down "$WG_INTERFACE" 2>/dev/null || true
    fi
}

warp_up() {
    log "Starting WARP tunnel..."
    wg-quick up "$WG_INTERFACE"
}

register_new_account() {
    log "Deleting old WARP account..."
    rm -f "$WGCF_ACCOUNT" "$WGCF_PROFILE"

    mkdir -p "$WGCF_DIR"
    cd "$WGCF_DIR"

    log "Registering new WARP account..."
    local retries=3
    for ((i=1; i<=retries; i++)); do
        if yes | wgcf register 2>/dev/null; then
            log "Account registered successfully"
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
    wgcf generate

    if [[ ! -f "$WGCF_PROFILE" ]]; then
        log "ERROR: Profile generation failed"
        exit 1
    fi
}

patch_profile() {
    # Pilih random endpoint untuk variasi IP
    local ep
    ep=$(random_endpoint)
    log "Using endpoint: $ep"

    # Baca profile dan buat WireGuard config
    local private_key address dns
    private_key=$(grep "^PrivateKey" "$WGCF_PROFILE" | cut -d= -f2- | xargs)
    address=$(grep "^Address" "$WGCF_PROFILE" | cut -d= -f2- | xargs)
    dns="8.8.8.8,8.8.4.4"

    cat > "$WG_CONF" << EOF
[Interface]
PrivateKey = ${private_key}
Address = ${address}
DNS = ${dns}
MTU = 1280
Table = 51888
PostUp = ip -4 rule add from \$(echo ${address} | cut -d, -f1 | cut -d/ -f1) lookup 51888
PostUp = ip -4 route add default dev ${WG_INTERFACE} table 51888
PostDown = ip -4 rule delete from \$(echo ${address} | cut -d, -f1 | cut -d/ -f1) lookup 51888
PostDown = ip -4 route delete default dev ${WG_INTERFACE} table 51888

[Peer]
PublicKey = $(grep "^PublicKey" "$WGCF_PROFILE" | cut -d= -f2- | xargs)
AllowedIPs = 0.0.0.0/0
Endpoint = ${ep}
EOF

    log "WireGuard config written to $WG_CONF"
}

rotate() {
    local old_ip
    old_ip=$(get_current_ip)
    log "Current IP: ${old_ip:-unknown}"

    warp_down
    register_new_account
    patch_profile
    warp_up

    sleep 3

    local new_ip
    new_ip=$(get_current_ip)
    log "New IP: ${new_ip:-unknown}"

    if [[ "$old_ip" != "$new_ip" && -n "$new_ip" ]]; then
        log "✅ IP berhasil dirotasi: $old_ip → $new_ip"
    elif [[ -n "$new_ip" ]]; then
        log "⚠️ IP sama: $new_ip (Cloudflare mungkin assign server yang sama)"
    else
        log "❌ Gagal mendapatkan IP baru"
    fi
}

status() {
    echo "=== WARP Status ==="
    if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}" 2>/dev/null; then
        echo "Tunnel: ACTIVE"
        wg show "$WG_INTERFACE" 2>/dev/null || true
    else
        echo "Tunnel: INACTIVE"
    fi
    echo ""
    echo "Current IP: $(get_current_ip)"
    echo "WARP IP:    $(get_warp_ip)"
    echo ""
    if [[ -f "$WGCF_ACCOUNT" ]]; then
        echo "Account: $WGCF_ACCOUNT (exists)"
    else
        echo "Account: not registered"
    fi
    if [[ -f "$WG_CONF" ]]; then
        echo "Config: $WG_CONF (exists)"
        grep "Endpoint" "$WG_CONF" 2>/dev/null || true
    else
        echo "Config: not found"
    fi
}

loop_rotate() {
    local interval="${1:-3600}"
    log "Auto-rotate mode: setiap ${interval} detik"
    while true; do
        rotate
        log "Next rotation in ${interval} seconds..."
        sleep "$interval"
    done
}

# === Main ===
check_root

case "${1:-}" in
    --check)
        echo "Current IP: $(get_current_ip)"
        ;;
    --status)
        status
        ;;
    --loop)
        check_deps
        loop_rotate "${2:-3600}"
        ;;
    --down)
        warp_down
        log "WARP tunnel stopped"
        ;;
    --up)
        check_deps
        warp_up
        log "WARP tunnel started"
        ;;
    *)
        check_deps
        rotate
        ;;
esac
