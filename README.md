# WARP Rotate — Cloudflare WARP IP Rotation Tool

Rotate your public IP address using Cloudflare WARP for free. Useful for bypassing IP bans and rate limits.

## What's Included

| File | Description |
|------|-------------|
| `warp.sh` | **Step 1** — Cloudflare WARP installer (install WireGuard + wgcf) |
| `warp-rotate.sh` | **Step 2** — IP rotation script (auto re-register for new IP) |

> ⚠️ You **must** run `warp.sh` first to install the required tools before using `warp-rotate.sh`.

---

## Quick Start

### Step 1: Download

```bash
git clone https://github.com/ochpgit/warp-rotate.git
cd warp-rotate
chmod +x warp.sh warp-rotate.sh
```

Or download individual files:

```bash
curl -fsSL https://raw.githubusercontent.com/ochpgit/warp-rotate/main/warp.sh -o warp.sh
curl -fsSL https://raw.githubusercontent.com/ochpgit/warp-rotate/main/warp-rotate.sh -o warp-rotate.sh
chmod +x warp.sh warp-rotate.sh
```

### Step 2: Install WARP (run `warp.sh` first!)

```bash
sudo bash warp.sh
```

This opens an interactive menu:

```
 ============================================
  Cloudflare WARP Installer
 ============================================
  1. Install WARP Client
  2. Install WireGuard
  3. WARP IPv4
  4. WARP IPv6
  5. WARP Dual Stack
  6. WARP Proxy (SOCKS5)
  7. Disconnect WARP
  8. Uninstall
  0. Exit
 ============================================
```

**Choose option `2` (Install WireGuard)** — this installs:
- `wireguard-tools` (WireGuard tunnel manager)
- `wgcf` (Cloudflare WARP account manager)

Then choose option `3`, `4`, or `5` to connect WARP for the first time.

**Verify installation:**

```bash
wg --version          # Should show wireguard-tools version
wgcf --version        # Should show wgcf version
```

### Step 3: Rotate IP (run `warp-rotate.sh`)

Now you can rotate your IP:

```bash
sudo ./warp-rotate.sh
```

---

## How It Works

```
warp.sh (run once)          warp-rotate.sh (run anytime)
─────────────────           ────────────────────────────
Install WireGuard    →      1. Stop WARP tunnel
Install wgcf         →      2. Delete old WARP account
First WARP connect   →      3. Register NEW free account
                             4. Generate new WireGuard config
                             5. Pick random Cloudflare endpoint
                             6. Start tunnel → NEW IP
```

Uses a **separate routing table (51888)** so your main routing, SSH, Tailscale, and other services are **not affected**.

---

## Usage

```bash
# Rotate IP once
sudo ./warp-rotate.sh

# Check current public IP
sudo ./warp-rotate.sh --check

# Check WARP status (tunnel, IP, config)
sudo ./warp-rotate.sh --status

# Auto-rotate every 1 hour
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

- Linux (Debian/Ubuntu/CentOS/Fedora/Arch)
- Root access
- `curl`

All other dependencies are installed by `warp.sh`.

---

## Troubleshooting

**`warp-rotate.sh` says "wgcf: command not found"**
→ Run `sudo bash warp.sh` first and choose option 2.

**IP didn't change after rotation**
→ Cloudflare may assign the same server. Try running `./warp-rotate.sh` again.

**Lost SSH connection after rotation**
→ This shouldn't happen (separate routing table). If it does, reboot the server — WARP doesn't auto-start.

**Want to completely remove WARP**
→ Run `sudo bash warp.sh` and choose option 8 (Uninstall).

---

## Credits

- **warp.sh** — [P3TERX/warp.sh](https://github.com/P3TERX/warp.sh) (MIT License)
- **wgcf** — [ViRb3/wgcf](https://github.com/ViRb3/wgcf)
- **Cloudflare WARP** — [cloudflare.com/products/warp](https://www.cloudflare.com/products/warp/)

## License

MIT
