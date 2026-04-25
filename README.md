# WARP Rotate — Cloudflare WARP IP Rotation + SOCKS5 Proxy

Rotate your public IP address using Cloudflare WARP for free. Works as a **SOCKS5 proxy** that can be used by [enowxai](https://enowxlabs.com) or any application that supports SOCKS5 proxy.

**SSH, Tailscale, Nginx, and all other services are NOT affected** — WARP uses a separate routing table.

## What's Included

| File | Platform | Description |
|------|----------|-------------|
| `warp-rotate.sh` | Linux | All-in-one: setup, rotate, SOCKS5 proxy, enowxai integration |
| `warp-rotate.ps1` | Windows | PowerShell version with same features |

---

## 🐧 Linux Quick Start

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

### Step 3: Setup

```bash
sudo ./warp-rotate.sh setup
```

This will:
1. Register a free Cloudflare WARP account
2. Generate WireGuard config (separate routing table 51888)
3. Start WARP tunnel
4. Install `microsocks` (lightweight SOCKS5 proxy, built from source)
5. Start SOCKS5 proxy on `127.0.0.1:40000`

### Step 4: Verify

```bash
# Normal IP (your real VPS IP)
curl https://ifconfig.me

# WARP IP via SOCKS5 proxy (should be different!)
curl -x socks5://127.0.0.1:40000 https://ifconfig.me
```

Output example:
```
Normal IP:  203.0.113.10         ← Your real VPS IP (unchanged)
WARP IP:    104.28.xxx.xxx       ← Cloudflare WARP IP (different!)
SOCKS5:     socks5://127.0.0.1:40000
```

### Linux Commands

```bash
sudo ./warp-rotate.sh setup           # First-time setup
sudo ./warp-rotate.sh rotate          # Rotate IP
sudo ./warp-rotate.sh --check         # Check IPs
sudo ./warp-rotate.sh --status        # Full status
sudo ./warp-rotate.sh --loop 3600     # Auto-rotate every hour
sudo ./warp-rotate.sh --down          # Stop WARP + proxy
sudo ./warp-rotate.sh --up            # Start WARP + proxy
sudo ./warp-rotate.sh --enowxai-add   # Add WARP proxy to enowxai
sudo ./warp-rotate.sh --enowxai-clear # Backup + clear + add WARP to enowxai
```

---

## 🪟 Windows Quick Start

### Step 1: Install WireGuard

Download and install from: https://www.wireguard.com/install/

### Step 2: Download Script

Open PowerShell **as Administrator**, then:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ocdewe/warp-rotate/main/warp-rotate.ps1" -OutFile "warp-rotate.ps1"
```

### Step 3: Setup

```powershell
.\warp-rotate.ps1 -Setup
```

This will:
1. Download `wgcf.exe` and `microsocks.exe` automatically
2. Register a free Cloudflare WARP account
3. Create WireGuard tunnel config
4. Start WARP tunnel via WireGuard service
5. Start SOCKS5 proxy on `127.0.0.1:40000`

### Step 4: Verify

```powershell
# Normal IP (your real IP)
curl https://ifconfig.me

# WARP IP via SOCKS5 proxy (should be different!)
curl -x socks5://127.0.0.1:40000 https://ifconfig.me
```

### Windows Commands

```powershell
.\warp-rotate.ps1 -Setup          # First-time setup
.\warp-rotate.ps1 -Rotate         # Rotate IP
.\warp-rotate.ps1 -Check          # Check IPs
.\warp-rotate.ps1 -Status         # Full status
.\warp-rotate.ps1 -Loop 3600      # Auto-rotate every hour
.\warp-rotate.ps1 -Down           # Stop WARP + proxy
.\warp-rotate.ps1 -Up             # Start WARP + proxy
.\warp-rotate.ps1 -EnowxaiAdd     # Add WARP proxy to enowxai
.\warp-rotate.ps1 -EnowxaiClear   # Backup + clear + add WARP to enowxai
```

> ⚠️ Always run PowerShell **as Administrator** — WireGuard tunnel requires admin privileges.

---

## enowxai Integration

Works on both Linux and Windows.

### 🐧 Linux

**Option A: Add WARP as additional proxy**
```bash
sudo ./warp-rotate.sh --enowxai-add
```

**Option B: Replace all proxies with WARP**
```bash
sudo ./warp-rotate.sh --enowxai-clear
```

**Rollback (restore old proxies):**
```bash
ls /root/.enowxai/proxies.json.bak.*
cp /root/.enowxai/proxies.json.bak.<timestamp> /root/.enowxai/proxies.json
enowxai restart
```

### 🪟 Windows (PowerShell as Admin)

**Option A: Add WARP as additional proxy**
```powershell
.\warp-rotate.ps1 -EnowxaiAdd
```

**Option B: Replace all proxies with WARP**
```powershell
.\warp-rotate.ps1 -EnowxaiClear
```

**Rollback (restore old proxies):**
```powershell
dir $env:USERPROFILE\.enowxai\proxies.json.bak.*
Copy-Item "$env:USERPROFILE\.enowxai\proxies.json.bak.<timestamp>" "$env:USERPROFILE\.enowxai\proxies.json"
enowxai restart
```

### What it does

- **Option A** — adds `socks5://127.0.0.1:40000` to your existing proxy list
- **Option B** — backs up current proxies, clears all, adds WARP as the only proxy

After running, verify in the enowxai dashboard:
```
http://localhost:1431/proxy
```
Confirm WARP proxy is listed and status is `ok`.

---

## How It Works

```
┌─────────────────────────────────────────────────────┐
│  Your Server / PC                                   │
│                                                     │
│  ┌──────────┐    ┌──────────┐    ┌───────────────┐  │
│  │ enowxai  │── ▶│microsocks│──▶│  WARP tunnel  │──┼──▶ Cloudflare ──▶ Internet
│  │ :1430    │    │ :40000   │    │  (WireGuard)  │  │    (new IP)
│  └──────────┘    └──────────┘    └───────────────┘  │
│                                                     │
│  ┌──────────┐                                       │
│  │ SSH      │───────────────────────────────────────┼──▶ Direct (original IP)
│  │Tailscale │───────────────────────────────────────┼──▶ Direct (original IP)
│  │ Nginx    │───────────────────────────────────────┼──▶ Direct (original IP)
│  └──────────┘                                       │
│                                                     │
│  WARP traffic only goes through tunnel              │
│  Everything else uses your original IP              │
└─────────────────────────────────────────────────────┘
```

### IP Rotation Flow

```
rotate command
  ├── Stop SOCKS5 proxy (microsocks)
  ├── Stop WARP tunnel
  ├── Delete old WARP account
  ├── Register NEW free Cloudflare account
  ├── Generate new WireGuard config
  ├── Pick random Cloudflare endpoint
  ├── Start WARP tunnel
  ├── Restore DNS (Linux only)
  └── Start SOCKS5 proxy → NEW IP!
```

---

## Safety

| Aspect | Detail |
|--------|--------|
| **Routing** | Separate table — default route NOT touched |
| **SSH** | ✅ Not affected |
| **Tailscale** | ✅ Not affected |
| **Nginx** | ✅ Not affected |
| **DNS** | Restored after WARP start (no DNS leak) |
| **Reversible** | `--down` / `-Down` stops everything cleanly |
| **Auto-start** | No — does NOT persist after reboot |
| **enowxai backup** | `--enowxai-clear` always backs up before clearing |

---

## Full Setup for enowxai (Linux)

Complete walkthrough from zero:

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

## Full Setup for enowxai (Windows)

```powershell
# 1. Install WireGuard from https://www.wireguard.com/install/

# 2. Download script (PowerShell as Admin)
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ocdewe/warp-rotate/main/warp-rotate.ps1" -OutFile "warp-rotate.ps1"

# 3. Setup WARP + SOCKS5 proxy
.\warp-rotate.ps1 -Setup

# 4. Verify WARP is working
curl -x socks5://127.0.0.1:40000 https://ifconfig.me

# 5. Replace enowxai proxies with WARP
.\warp-rotate.ps1 -EnowxaiClear

# 6. Check enowxai dashboard
#    Open http://localhost:1431/proxy
#    Should show: socks5://127.0.0.1:40000 → status: ok

# 7. (Optional) Auto-rotate every hour
.\warp-rotate.ps1 -Loop 3600
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
- PowerShell (run as Administrator)

---

## Troubleshooting

### Linux

**"wgcf: command not found"**
→ `curl -fsSL git.io/wgcf.sh | bash`

**"wireguard-tools not found"**
→ `apt install -y wireguard-tools`

**Want to completely remove WARP**
```bash
./warp-rotate.sh --down
rm -f /etc/wireguard/wgcf.conf
rm -rf /etc/warp
```

### Windows

**"WireGuard not found"**
→ Install from https://www.wireguard.com/install/

**"Running scripts is disabled"**
→ `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

**"Access denied"**
→ Right-click PowerShell → "Run as Administrator"

### WSL (Windows Subsystem for Linux)

> ⚠️ **WSL is NOT recommended.** Use the PowerShell version (`warp-rotate.ps1`) instead.

WSL has several limitations that make WARP tunneling unreliable:

1. **No WireGuard kernel module** — WSL doesn't include the WireGuard kernel module, so `wg-quick up` will fail
2. **File path issues** — `wgcf` may write config files to unexpected locations
3. **No persistent `/etc/wireguard/`** — WSL filesystem may reset on restart

**If you must use WSL:**
- Install `wireguard-go` (userspace WireGuard implementation)
- Or use `boringtun` as a userspace alternative
- Make sure to run as root (`sudo bash warp-rotate.sh`)

**Recommended for Windows users:**
```powershell
# Use the PowerShell version instead
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ocdewe/warp-rotate/main/warp-rotate.ps1" -OutFile "warp-rotate.ps1"
.\warp-rotate.ps1 -Setup
```

### Both

**IP didn't change after rotation**
→ Cloudflare may assign the same server. Run rotate again.

**SOCKS5 proxy not responding**
→ Check status, then restart: `--down` then `--up`

**Lost SSH/RDP connection**
→ This shouldn't happen (separate routing table). Reboot — WARP doesn't auto-start.

**Want to restore old enowxai proxies**
→ Check backup files and copy back (see Rollback section above)

---

## Credits

- **wgcf** — [ViRb3/wgcf](https://github.com/ViRb3/wgcf)
- **microsocks** — [rofl0r/microsocks](https://github.com/rofl0r/microsocks)
- **microsocks-windows** — [nicjansma/microsocks-windows](https://github.com/nicjansma/microsocks-windows)
- **Cloudflare WARP** — [cloudflare.com/products/warp](https://www.cloudflare.com/products/warp/)

## License

MIT
