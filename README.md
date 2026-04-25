# WARP Rotate — Cloudflare WARP IP Rotation Tool

Rotate your public IP address using Cloudflare WARP for free. Useful for bypassing IP bans and rate limits.

## What's Included

| File | Description |
|------|-------------|
| `warp-rotate.sh` | IP rotation script — auto re-register WARP account for new IP |
| `warp.sh` | Cloudflare WARP installer by [P3TERX](https://github.com/P3TERX/warp.sh) (MIT License) |

## How It Works

1. Stops the current WARP tunnel
2. Deletes the old WARP account
3. Registers a new free WARP account
4. Generates a new WireGuard profile
5. Picks a random Cloudflare endpoint (for IP variation)
6. Starts the tunnel with the new account → **new public IP**

Uses a **separate routing table (51888)** so your main routing, SSH, Tailscale, and other services are **not affected**.

---

## Quick Start

### 1. Download

```bash
git clone https://github.com/ochpgit/warp-rotate.git
cd warp-rotate
chmod +x warp.sh warp-rotate.sh
```

Or download individual files:

```bash
# warp-rotate.sh only
curl -fsSL https://raw.githubusercontent.com/ochpgit/warp-rotate/main/warp-rotate.sh -o warp-rotate.sh
chmod +x warp-rotate.sh

# warp.sh only
curl -fsSL https://raw.githubusercontent.com/ochpgit/warp-rotate/main/warp.sh -o warp.sh
chmod +x warp.sh
```

### 2. Install Dependencies

```bash
# Install WireGuard tools
apt install wireguard-tools -y

# Install wgcf (WARP account manager)
curl -fsSL git.io/wgcf.sh | bash
```

Or use the included `warp.sh` installer:

```bash
# Interactive menu — install WireGuard + WARP
bash warp.sh
```

### 3. First Run

```bash
# Rotate IP (register new account + connect)
sudo ./warp-rotate.sh
```

---

## Usage

```bash
# Rotate IP once (delete old account → register new → reconnect)
sudo ./warp-rotate.sh

# Check current public IP
sudo ./warp-rotate.sh --check

# Check WARP status (tunnel, IP, config)
sudo ./warp-rotate.sh --status

# Auto-rotate every 1 hour (3600 seconds)
sudo ./warp-rotate.sh --loop 3600

# Auto-rotate every 30 minutes
sudo ./warp-rotate.sh --loop 1800

# Stop WARP tunnel
sudo ./warp-rotate.sh --down

# Start WARP tunnel
sudo ./warp-rotate.sh --up
```

---

## How IP Rotation Works

Each rotation:
- Deletes the old WARP account (`wgcf-account.toml`)
- Registers a **brand new** free Cloudflare WARP account
- Picks a **random endpoint** from 5 Cloudflare servers
- New account + different endpoint = **higher chance of getting a different IP**

> ⚠️ IP is assigned by Cloudflare. You may occasionally get the same IP. The script logs old vs new IP for verification.

---

## Safety

| Aspect | Detail |
|--------|--------|
| Routing | Uses separate table `51888` — does NOT touch default route |
| SSH | ✅ Not affected |
| Tailscale | ✅ Not affected |
| DNS | Changed to `8.8.8.8` for WARP interface only |
| Reversible | `./warp-rotate.sh --down` removes everything |
| Auto-start | No — does not persist after reboot |

---

## Requirements

- Linux (Debian/Ubuntu/CentOS/Fedora)
- Root access
- `curl`
- `wireguard-tools` (`apt install wireguard-tools`)
- `wgcf` (`curl -fsSL git.io/wgcf.sh | bash`)

---

## Credits

- **warp.sh** — [P3TERX/warp.sh](https://github.com/P3TERX/warp.sh) (MIT License)
- **wgcf** — [ViRb3/wgcf](https://github.com/ViRb3/wgcf)
- **Cloudflare WARP** — [cloudflare.com/products/warp](https://www.cloudflare.com/products/warp/)

## License

MIT
