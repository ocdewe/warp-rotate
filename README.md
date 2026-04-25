# WARP Rotate — Cloudflare WARP IP Rotation + SOCKS5 Proxy

Rotate your public IP address using Cloudflare WARP for free. Works as a **SOCKS5 proxy** that can be used by [enowxai](https://enowxlabs.com) or any application that supports SOCKS5 proxy.

**SSH, Tailscale, Nginx, and all other services are NOT affected** — WARP uses a separate routing table.

## What's Included

| File | Platform | Description |
|------|----------|-------------|
| `warp-rotate.sh` | Linux | All-in-one: setup, rotate, SOCKS5 proxy, enowxai integration |
| `warp-rotate.ps1` | Windows | PowerShell version with same features |

---

## Quick Start

### Step 1: Install Dependencies

```bash
# Install WireGuard tools
apt install -y wireguard-tools

# Install wgcf (Cloudflare WARP account manager)
curl -fsSL git.io/wgcf.sh | bash
```

Verify:
```bash
wg --version     # wireguard-tools v1.x
wgcf version     # wgcf v2.x
```

### Step 2: Download Script

```bash
curl -fsSL https://raw.githubusercontent.com/ocdewe/warp-rotate/main/warp-rotate.sh -o warp-rotate.sh
chmod +x warp-rotate.sh
```

### Step 3: Setup (First Time)

```bash
sudo ./warp-rotate.sh setup
```

This will:
1. Register a free Cloudflare WARP account
2. Generate WireGuard config (separate routing table 51888)
3. Start WARP tunnel
4. Install `microsocks` (lightweight SOCKS5 proxy, built from source)
5. Start SOCKS5 proxy on `127.0.0.1:40000` → routed through WARP

Output:
```
Normal IP:  203.0.113.10         ← Your real VPS IP (unchanged)
WARP IP:    104.28.xxx.xxx       ← Cloudflare WARP IP (different!)
SOCKS5:     socks5://127.0.0.1:40000
```

### Step 4: Verify

```bash
# Check normal IP (should be your VPS IP)
curl https://ifconfig.me

# Check WARP IP via SOCKS5 proxy (should be different)
curl -x socks5://127.0.0.1:40000 https://ifconfig.me
```

---

## enowxai Integration

### Option A: Add WARP as Additional Proxy

```bash
sudo ./warp-rotate.sh --enowxai-add
```

This adds `socks5://127.0.0.1:40000` to your existing enowxai proxy list.

### Option B: Replace All Proxies with WARP (Recommended)

```bash
sudo ./warp-rotate.sh --enowxai-clear
```

This will:
1. **Backup** your current proxy list to `/root/.enowxai/proxies.json.bak.<timestamp>`
2. **Clear** all existing proxies
3. **Add** WARP SOCKS5 proxy as the only proxy
4. **Test** the proxy

After running, verify in the enowxai dashboard:
```
http://localhost:1431/proxy
```
Confirm WARP proxy is listed and status is `ok`.

### Rollback (Restore Old Proxies)

```bash
# Find your backup
ls /root/.enowxai/proxies.json.bak.*

# Restore
cp /root/.enowxai/proxies.json.bak.<timestamp> /root/.enowxai/proxies.json
enowxai restart
```

---

## Usage

```bash
# First-time setup (install + connect + proxy)
sudo ./warp-rotate.sh setup

# Rotate IP (re-register WARP → new IP)
sudo ./warp-rotate.sh rotate

# Check IPs
sudo ./warp-rotate.sh --check

# Full status (tunnel, proxy, services)
sudo ./warp-rotate.sh --status

# Auto-rotate every 1 hour
sudo ./warp-rotate.sh --loop 3600

# Auto-rotate every 30 minutes
sudo ./warp-rotate.sh --loop 1800

# Stop everything (WARP + proxy)
sudo ./warp-rotate.sh --down

# Start everything (WARP + proxy)
sudo ./warp-rotate.sh --up

# Add WARP proxy to enowxai
sudo ./warp-rotate.sh --enowxai-add

# Replace enowxai proxies with WARP (backup + clear + add)
sudo ./warp-rotate.sh --enowxai-clear
```

---

## How It Works

```
┌─────────────────────────────────────────────────────┐
│  Your VPS                                           │
│                                                     │
│  ┌──────────┐    ┌──────────┐    ┌───────────────┐  │
│  │ enowxai  │───▶│microsocks│───▶│  WARP tunnel  │──┼──▶ Cloudflare ──▶ Internet
│  │ :1430    │    │ :40000   │    │  (wgcf)       │  │    (new IP)
│  └──────────┘    └──────────┘    └───────────────┘  │
│                                                     │
│  ┌──────────┐                                       │
│  │ SSH      │────────────────────────────────────────┼──▶ Direct (original IP)
│  │Tailscale │────────────────────────────────────────┼──▶ Direct (original IP)
│  │ Nginx    │────────────────────────────────────────┼──▶ Direct (original IP)
│  └──────────┘                                       │
│                                                     │
│  Routing table 51888 (WARP only)                    │
│  Default route (SSH/Tailscale/Nginx untouched)      │
└─────────────────────────────────────────────────────┘
```

### IP Rotation Flow

```
rotate command
  ├── Stop SOCKS5 proxy (microsocks)
  ├── Stop WARP tunnel (wg-quick down)
  ├── Delete old WARP account
  ├── Register NEW free Cloudflare account
  ├── Generate new WireGuard config
  ├── Pick random Cloudflare endpoint
  ├── Start WARP tunnel (wg-quick up)
  ├── Restore DNS (so SSH/Tailscale work)
  └── Start SOCKS5 proxy → NEW IP!
```

---

## Safety

| Aspect | Detail |
|--------|--------|
| **Routing** | Separate table `51888` — default route NOT touched |
| **SSH** | ✅ Not affected (uses original IP) |
| **Tailscale** | ✅ Not affected (uses own interface) |
| **Nginx** | ✅ Not affected (listens on original IP) |
| **DNS** | Restored after WARP start (no DNS leak) |
| **Reversible** | `./warp-rotate.sh --down` stops everything cleanly |
| **Auto-start** | No — does NOT persist after reboot |
| **enowxai backup** | `--enowxai-clear` always backs up before clearing |

---

## Step-by-Step: Full Setup for enowxai

Complete walkthrough from zero to WARP proxy on enowxai:

```bash
# 1. Install dependencies
apt install -y wireguard-tools
curl -fsSL git.io/wgcf.sh | bash

# 2. Download script
curl -fsSL https://raw.githubusercontent.com/ocdewe/warp-rotate/main/warp-rotate.sh -o warp-rotate.sh
chmod +x warp-rotate.sh

# 3. Setup WARP + SOCKS5 proxy
sudo ./warp-rotate.sh setup

# 4. Verify WARP is working
curl -x socks5://127.0.0.1:40000 https://ifconfig.me

# 5. Replace enowxai proxies with WARP
sudo ./warp-rotate.sh --enowxai-clear

# 6. Check enowxai dashboard
#    Open http://localhost:1431/proxy
#    Should show: socks5://127.0.0.1:40000 → status: ok

# 7. (Optional) Auto-rotate every hour
sudo ./warp-rotate.sh --loop 3600
```

---

## Requirements

### Linux
- Debian/Ubuntu/CentOS/Fedora/Arch
- Root access
- `curl`, `git`, `make`, `gcc` (for building microsocks)

### Windows
- Windows 10/11
- [WireGuard for Windows](https://www.wireguard.com/install/)
- Run PowerShell as Administrator

---

## Windows Quick Start

### Step 1: Install WireGuard

Download and install from: https://www.wireguard.com/install/

### Step 2: Download Script

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ocdewe/warp-rotate/main/warp-rotate.ps1" -OutFile "warp-rotate.ps1"
```

### Step 3: Setup (Run as Administrator)

```powershell
.\warp-rotate.ps1 -Setup
```

This will:
1. Download `wgcf.exe` and `microsocks.exe` automatically
2. Register a free Cloudflare WARP account
3. Create WireGuard tunnel config
4. Start WARP tunnel via WireGuard
5. Start SOCKS5 proxy on `127.0.0.1:40000`

### Step 4: Usage

```powershell
# Rotate IP
.\warp-rotate.ps1 -Rotate

# Check IPs
.\warp-rotate.ps1 -Check

# Full status
.\warp-rotate.ps1 -Status

# Auto-rotate every hour
.\warp-rotate.ps1 -Loop 3600

# Stop everything
.\warp-rotate.ps1 -Down

# Start everything
.\warp-rotate.ps1 -Up

# enowxai: replace proxies with WARP
.\warp-rotate.ps1 -EnowxaiClear
```

### Step 5: Verify

```powershell
# Normal IP
curl https://ifconfig.me

# WARP IP (should be different)
curl -x socks5://127.0.0.1:40000 https://ifconfig.me
```

---

## Troubleshooting

**"wgcf: command not found"** (Linux)
→ Run `curl -fsSL git.io/wgcf.sh | bash`

**"wireguard-tools not found"**
→ Run `apt install -y wireguard-tools`

**IP didn't change after rotation**
→ Cloudflare may assign the same server. Run `./warp-rotate.sh rotate` again.

**SOCKS5 proxy not responding**
→ Check if WARP tunnel is up: `./warp-rotate.sh --status`
→ Restart: `./warp-rotate.sh --down && ./warp-rotate.sh --up`

**Lost SSH connection**
→ This shouldn't happen (separate routing table). Reboot the server — WARP doesn't auto-start.

**Want to restore old enowxai proxies**
→ `ls /root/.enowxai/proxies.json.bak.*` → `cp <backup> /root/.enowxai/proxies.json && enowxai restart`

**Want to completely remove WARP**
```bash
./warp-rotate.sh --down
rm -f /etc/wireguard/wgcf.conf
rm -rf /etc/warp
```

---

## Credits

- **wgcf** — [ViRb3/wgcf](https://github.com/ViRb3/wgcf)
- **microsocks** — [rofl0r/microsocks](https://github.com/rofl0r/microsocks)
- **Cloudflare WARP** — [cloudflare.com/products/warp](https://www.cloudflare.com/products/warp/)

## License

MIT
