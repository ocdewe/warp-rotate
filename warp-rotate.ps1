#Requires -RunAsAdministrator
<#
.SYNOPSIS
    WARP Rotate for Windows — Cloudflare WARP IP Rotation + SOCKS5 Proxy

.DESCRIPTION
    Rotate your public IP using Cloudflare WARP for free.
    Creates a WireGuard tunnel + local SOCKS5 proxy.
    Works with enowxai or any app that supports SOCKS5.

.EXAMPLE
    .\warp-rotate.ps1 -Setup          # First-time setup
    .\warp-rotate.ps1 -Rotate         # Rotate IP
    .\warp-rotate.ps1 -Check          # Check IPs
    .\warp-rotate.ps1 -Status         # Full status
    .\warp-rotate.ps1 -Up             # Start WARP + proxy
    .\warp-rotate.ps1 -Down           # Stop WARP + proxy
    .\warp-rotate.ps1 -Loop 3600      # Auto-rotate every hour
    .\warp-rotate.ps1 -EnowxaiAdd     # Add WARP proxy to enowxai
    .\warp-rotate.ps1 -EnowxaiClear   # Backup + clear + add WARP to enowxai
#>

param(
    [switch]$Setup,
    [switch]$Rotate,
    [switch]$Check,
    [switch]$Status,
    [switch]$Up,
    [switch]$Down,
    [switch]$EnowxaiAdd,
    [switch]$EnowxaiClear,
    [int]$Loop = 0
)

# === Config ===
$WARP_DIR = "$env:USERPROFILE\.warp-rotate"
$WGCF_EXE = "$WARP_DIR\wgcf.exe"
$WGCF_ACCOUNT = "$WARP_DIR\wgcf-account.toml"
$WGCF_PROFILE = "$WARP_DIR\wgcf-profile.conf"
$WG_CONF = "$WARP_DIR\wgcf-tunnel.conf"
$MICROSOCKS_EXE = "$WARP_DIR\microsocks.exe"
$TUNNEL_NAME = "wgcf"
$SOCKS_PORT = 40000
$SOCKS_BIND = "127.0.0.1"
$WARP_IP = "172.16.0.2"

$ENDPOINTS = @(
    "162.159.192.1:2408"
    "162.159.193.1:2408"
    "162.159.195.1:2408"
    "162.159.192.7:2408"
    "162.159.193.7:2408"
)

$WGCF_VERSION = "2.2.30"
$WGCF_URL = "https://github.com/ViRb3/wgcf/releases/download/v$WGCF_VERSION/wgcf_${WGCF_VERSION}_windows_amd64.exe"
$MICROSOCKS_URL = "https://github.com/nicjansma/microsocks-windows/releases/latest/download/microsocks-x64.exe"

# === Helpers ===

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$ts [warp-rotate] $msg"
}

function Get-CurrentIP {
    try {
        $ip = (Invoke-WebRequest -Uri "https://ifconfig.me" -UseBasicParsing -TimeoutSec 10).Content.Trim()
        return $ip
    } catch {
        return "unknown"
    }
}

function Get-WarpIP {
    try {
        $ip = (Invoke-WebRequest -Uri "https://ifconfig.me" -UseBasicParsing -TimeoutSec 10 -Proxy "socks5://${SOCKS_BIND}:${SOCKS_PORT}").Content.Trim()
        return $ip
    } catch {
        # Fallback: try via interface
        try {
            $ip = (Invoke-WebRequest -Uri "https://ifconfig.me" -UseBasicParsing -TimeoutSec 10).Content.Trim()
            return $ip
        } catch {
            return "not active"
        }
    }
}

function Get-RandomEndpoint {
    return $ENDPOINTS | Get-Random
}

function Test-WireGuardInstalled {
    $wgPath = Get-Command "wireguard" -ErrorAction SilentlyContinue
    if (-not $wgPath) {
        $wgPath = Get-Command "C:\Program Files\WireGuard\wireguard.exe" -ErrorAction SilentlyContinue
    }
    return $null -ne $wgPath
}

function Get-WireGuardExe {
    $wg = Get-Command "wireguard" -ErrorAction SilentlyContinue
    if ($wg) { return $wg.Source }
    $default = "C:\Program Files\WireGuard\wireguard.exe"
    if (Test-Path $default) { return $default }
    return $null
}

function Get-WgExe {
    $wg = Get-Command "wg" -ErrorAction SilentlyContinue
    if ($wg) { return $wg.Source }
    $default = "C:\Program Files\WireGuard\wg.exe"
    if (Test-Path $default) { return $default }
    return $null
}

# === Install Dependencies ===

function Install-Dependencies {
    # Create working directory
    if (-not (Test-Path $WARP_DIR)) {
        New-Item -ItemType Directory -Path $WARP_DIR -Force | Out-Null
        Log "Created directory: $WARP_DIR"
    }

    # Check WireGuard
    if (-not (Test-WireGuardInstalled)) {
        Log "WireGuard not found. Please install from: https://www.wireguard.com/install/"
        Log "Download: https://download.wireguard.com/windows-client/wireguard-installer.exe"
        Write-Host ""
        $install = Read-Host "Open download page? (y/n)"
        if ($install -eq 'y') {
            Start-Process "https://download.wireguard.com/windows-client/wireguard-installer.exe"
            Log "Install WireGuard, then run this script again."
        }
        exit 1
    }
    Log "WireGuard: OK"

    # Download wgcf
    if (-not (Test-Path $WGCF_EXE)) {
        Log "Downloading wgcf v$WGCF_VERSION..."
        Invoke-WebRequest -Uri $WGCF_URL -OutFile $WGCF_EXE -UseBasicParsing
        Log "wgcf downloaded"
    }
    Log "wgcf: OK"

    # Download microsocks
    if (-not (Test-Path $MICROSOCKS_EXE)) {
        Log "Downloading microsocks..."
        try {
            Invoke-WebRequest -Uri $MICROSOCKS_URL -OutFile $MICROSOCKS_EXE -UseBasicParsing
            Log "microsocks downloaded"
        } catch {
            Log "WARN: Could not download microsocks. SOCKS5 proxy will not be available."
            Log "You can manually download from: https://github.com/nicjansma/microsocks-windows/releases"
        }
    }
    if (Test-Path $MICROSOCKS_EXE) { Log "microsocks: OK" }
}

# === WARP Tunnel ===

function Stop-WarpTunnel {
    $wgExe = Get-WireGuardExe
    if (-not $wgExe) { return }

    # Check if tunnel exists
    $tunnels = & "$wgExe" /listtunnels 2>$null
    if ($tunnels -match $TUNNEL_NAME) {
        Log "Stopping WARP tunnel..."
        & "$wgExe" /uninstalltunnelservice $TUNNEL_NAME 2>$null
        Start-Sleep -Seconds 2
        Log "Tunnel stopped"
    }
}

function Start-WarpTunnel {
    $wgExe = Get-WireGuardExe
    if (-not $wgExe) {
        Log "ERROR: WireGuard not found"
        exit 1
    }

    if (-not (Test-Path $WG_CONF)) {
        Log "ERROR: WireGuard config not found: $WG_CONF"
        exit 1
    }

    # Copy config to WireGuard directory
    $wgConfDir = "C:\Program Files\WireGuard\Data\Configurations"
    if (-not (Test-Path $wgConfDir)) {
        New-Item -ItemType Directory -Path $wgConfDir -Force | Out-Null
    }
    Copy-Item $WG_CONF "$wgConfDir\$TUNNEL_NAME.conf.dpapi" -Force 2>$null

    Log "Starting WARP tunnel..."
    & "$wgExe" /installtunnelservice $WG_CONF 2>$null
    Start-Sleep -Seconds 3

    # Verify
    $wg = Get-WgExe
    if ($wg) {
        $show = & "$wg" show $TUNNEL_NAME 2>$null
        if ($show) {
            Log "WARP tunnel active"
        } else {
            Log "WARN: Tunnel may not be active. Check WireGuard GUI."
        }
    }
}

function Register-NewAccount {
    Log "Deleting old WARP account..."
    Remove-Item $WGCF_ACCOUNT -Force -ErrorAction SilentlyContinue
    Remove-Item $WGCF_PROFILE -Force -ErrorAction SilentlyContinue

    Set-Location $WARP_DIR

    Log "Registering new WARP account..."
    $retries = 3
    for ($i = 1; $i -le $retries; $i++) {
        # Auto-accept ToS
        "y" | & $WGCF_EXE register 2>$null

        if (Test-Path $WGCF_ACCOUNT) {
            Log "Account registered"
            break
        }
        if ($i -eq $retries) {
            Log "ERROR: Failed to register after $retries attempts"
            exit 1
        }
        Log "Retry $i/$retries..."
        Start-Sleep -Seconds 2
    }

    Log "Generating WireGuard profile..."
    & $WGCF_EXE generate 2>$null

    if (-not (Test-Path $WGCF_PROFILE)) {
        Log "ERROR: Profile generation failed"
        exit 1
    }
}

function New-WireGuardConfig {
    $ep = Get-RandomEndpoint
    Log "Using endpoint: $ep"

    $profileContent = Get-Content $WGCF_PROFILE -Raw
    $privateKey = ($profileContent | Select-String "PrivateKey\s*=\s*(.+)").Matches[0].Groups[1].Value.Trim()
    $publicKey = ($profileContent | Select-String "PublicKey\s*=\s*(.+)").Matches[0].Groups[1].Value.Trim()

    # Windows WireGuard config (no Table/PostUp/PostDown — handled differently)
    $config = @"
[Interface]
PrivateKey = $privateKey
Address = $WARP_IP/32
DNS = 8.8.8.8, 8.8.4.4
MTU = 1280

[Peer]
PublicKey = $publicKey
AllowedIPs = 0.0.0.0/0
Endpoint = $ep
"@

    $config | Out-File -FilePath $WG_CONF -Encoding UTF8 -Force
    Log "WireGuard config written"
}

# === SOCKS5 Proxy ===

function Start-SocksProxy {
    if (-not (Test-Path $MICROSOCKS_EXE)) {
        Log "WARN: microsocks not found. SOCKS5 proxy not available."
        Log "Download from: https://github.com/nicjansma/microsocks-windows/releases"
        return
    }

    # Check if already running
    $existing = Get-Process -Name "microsocks*" -ErrorAction SilentlyContinue
    if ($existing) {
        Log "SOCKS5 proxy already running (PID: $($existing.Id))"
        return
    }

    Log "Starting SOCKS5 proxy (${SOCKS_BIND}:${SOCKS_PORT})..."
    Start-Process -FilePath $MICROSOCKS_EXE `
        -ArgumentList "-i", $SOCKS_BIND, "-p", $SOCKS_PORT, "-b", $WARP_IP `
        -WindowStyle Hidden -PassThru | Out-Null

    Start-Sleep -Seconds 1

    $proc = Get-Process -Name "microsocks*" -ErrorAction SilentlyContinue
    if ($proc) {
        Log "SOCKS5 proxy active on ${SOCKS_BIND}:${SOCKS_PORT}"
    } else {
        Log "WARN: SOCKS5 proxy may not have started"
    }
}

function Stop-SocksProxy {
    $proc = Get-Process -Name "microsocks*" -ErrorAction SilentlyContinue
    if ($proc) {
        Stop-Process -Name "microsocks" -Force -ErrorAction SilentlyContinue
        Log "SOCKS5 proxy stopped"
    }
}

# === enowxai Integration ===

function Get-EnowxaiExe {
    $enowx = Get-Command "enowxai" -ErrorAction SilentlyContinue
    if ($enowx) { return $enowx.Source }
    $local = "$env:USERPROFILE\.local\bin\enowxai.exe"
    if (Test-Path $local) { return $local }
    return $null
}

function Add-EnowxaiProxy {
    $enowx = Get-EnowxaiExe
    if (-not $enowx) {
        Log "ERROR: enowxai not found"
        return
    }

    Log "Adding WARP proxy to enowxai..."
    & $enowx proxy add "socks5://${SOCKS_BIND}:${SOCKS_PORT}"
    Write-Host ""
    & $enowx proxy list
}

function Clear-EnowxaiProxy {
    $enowx = Get-EnowxaiExe
    if (-not $enowx) {
        Log "ERROR: enowxai not found"
        return
    }

    # Backup
    $enowxDir = "$env:USERPROFILE\.enowxai"
    $proxiesFile = "$enowxDir\proxies.json"
    if (Test-Path $proxiesFile) {
        $ts = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupFile = "$enowxDir\proxies.json.bak.$ts"
        Copy-Item $proxiesFile $backupFile
        Log "Proxy backup saved: $backupFile"
    }

    Log "Clearing all enowxai proxies..."
    & $enowx proxy clear

    Log "Adding WARP proxy..."
    & $enowx proxy add "socks5://${SOCKS_BIND}:${SOCKS_PORT}"

    & $enowx proxy test
    Write-Host ""
    & $enowx proxy list
    Write-Host ""
    Log "Done! Check dashboard: http://localhost:1431/proxy"
    if ($backupFile) {
        Log "Rollback: Copy-Item '$backupFile' '$proxiesFile'; enowxai restart"
    }
}

# === Commands ===

function Invoke-Setup {
    Log "=== WARP + SOCKS5 Proxy Setup (Windows) ==="
    Install-Dependencies
    Register-NewAccount
    New-WireGuardConfig
    Start-WarpTunnel
    Start-SocksProxy

    Start-Sleep -Seconds 3
    $normalIP = Get-CurrentIP
    $warpIP = Get-WarpIP

    Write-Host ""
    Log "=== Setup Complete ==="
    Log "Normal IP:  $normalIP"
    Log "WARP IP:    $warpIP"
    Log "SOCKS5:     socks5://${SOCKS_BIND}:${SOCKS_PORT}"
    Write-Host ""
    Log "Test: curl -x socks5://${SOCKS_BIND}:${SOCKS_PORT} https://ifconfig.me"
    Log "enowxai: .\warp-rotate.ps1 -EnowxaiAdd"
}

function Invoke-Rotate {
    $oldIP = Get-WarpIP
    Log "Current WARP IP: $oldIP"

    Stop-SocksProxy
    Stop-WarpTunnel
    Register-NewAccount
    New-WireGuardConfig
    Start-WarpTunnel
    Start-SocksProxy

    Start-Sleep -Seconds 3
    $newIP = Get-WarpIP
    Log "New WARP IP: $newIP"

    if ($oldIP -ne $newIP -and $newIP -ne "not active") {
        Log "IP rotated: $oldIP -> $newIP"
    } elseif ($newIP -ne "not active") {
        Log "IP: $newIP (may be same — Cloudflare assigns server)"
    } else {
        Log "Failed to get new IP"
    }
}

function Invoke-Status {
    Write-Host "=== WARP Status (Windows) ==="
    $wg = Get-WgExe
    if ($wg) {
        $show = & "$wg" show $TUNNEL_NAME 2>$null
        if ($show) {
            Write-Host "Tunnel:  ACTIVE"
        } else {
            Write-Host "Tunnel:  INACTIVE"
        }
    } else {
        Write-Host "Tunnel:  WireGuard not found"
    }

    $proc = Get-Process -Name "microsocks*" -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "SOCKS5:  ACTIVE (${SOCKS_BIND}:${SOCKS_PORT})"
    } else {
        Write-Host "SOCKS5:  INACTIVE"
    }

    Write-Host ""
    Write-Host "Normal IP: $(Get-CurrentIP)"
    Write-Host "WARP IP:   $(Get-WarpIP)"
    Write-Host ""

    if (Test-Path $WGCF_ACCOUNT) {
        Write-Host "Account: $WGCF_ACCOUNT (exists)"
    } else {
        Write-Host "Account: not registered"
    }
    if (Test-Path $WG_CONF) {
        Write-Host "Config:  $WG_CONF (exists)"
    }
}

function Invoke-Loop($interval) {
    Log "Auto-rotate mode: every $interval seconds"
    while ($true) {
        Invoke-Rotate
        Log "Next rotation in $interval seconds..."
        Start-Sleep -Seconds $interval
    }
}

# === Main ===

if ($Setup) {
    Invoke-Setup
} elseif ($Rotate) {
    Invoke-Rotate
} elseif ($Check) {
    Write-Host "Normal IP: $(Get-CurrentIP)"
    Write-Host "WARP IP:   $(Get-WarpIP)"
} elseif ($Status) {
    Invoke-Status
} elseif ($Up) {
    Start-WarpTunnel
    Start-SocksProxy
    Start-Sleep -Seconds 2
    Log "Normal IP: $(Get-CurrentIP)"
    Log "WARP IP:   $(Get-WarpIP)"
} elseif ($Down) {
    Stop-SocksProxy
    Stop-WarpTunnel
    Log "WARP + proxy stopped"
} elseif ($EnowxaiAdd) {
    Add-EnowxaiProxy
} elseif ($EnowxaiClear) {
    Clear-EnowxaiProxy
} elseif ($Loop -gt 0) {
    Invoke-Loop $Loop
} else {
    # Default: show help
    Write-Host @"
WARP Rotate for Windows — Cloudflare WARP IP Rotation + SOCKS5 Proxy

Usage:
  .\warp-rotate.ps1 -Setup          First-time setup (install + connect + proxy)
  .\warp-rotate.ps1 -Rotate         Rotate IP (re-register WARP)
  .\warp-rotate.ps1 -Check          Check current IPs (normal + WARP)
  .\warp-rotate.ps1 -Status         Full status
  .\warp-rotate.ps1 -Up             Start WARP + proxy
  .\warp-rotate.ps1 -Down           Stop WARP + proxy
  .\warp-rotate.ps1 -Loop 3600      Auto-rotate every N seconds
  .\warp-rotate.ps1 -EnowxaiAdd     Add WARP proxy to enowxai
  .\warp-rotate.ps1 -EnowxaiClear   Backup + clear + add WARP to enowxai

Requirements:
  - WireGuard for Windows (https://www.wireguard.com/install/)
  - Run as Administrator
"@
}
