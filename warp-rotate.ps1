#Requires -RunAsAdministrator
<#
.SYNOPSIS
    WARP IP Rotation + SOCKS5 Proxy for Windows
.EXAMPLE
    .\warp-rotate.ps1 -Setup
    .\warp-rotate.ps1 -Rotate
    .\warp-rotate.ps1 -Check
    .\warp-rotate.ps1 -Status
    .\warp-rotate.ps1 -Up
    .\warp-rotate.ps1 -Down
#>

param(
    [switch]$Setup,
    [switch]$Rotate,
    [switch]$Check,
    [switch]$Status,
    [switch]$Down,
    [switch]$Up,
    [switch]$EnowxaiAdd,
    [switch]$EnowxaiClear,
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$WARP_CLI = "C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe"
$SOCKS_PORT = 40000
$SOCKS_BIND = "127.0.0.1"
$LOG_PREFIX = "[warp-rotate]"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp $LOG_PREFIX $Message"
}

function Get-CurrentIP {
    try {
        # Pakai curl.exe supaya dapat plain text, bukan HTML
        $ip = (curl.exe -s --max-time 10 -H "Accept: text/plain" https://ifconfig.me 2>$null)
        if ($ip -and $ip -notmatch "<html") {
            return $ip.Trim()
        }
        # Fallback ke api.ipify.org
        $ip = (curl.exe -s --max-time 10 https://api.ipify.org 2>$null)
        if ($ip) { return $ip.Trim() }
        return "unknown"
    }
    catch {
        return "unknown"
    }
}

function Get-WarpIP {
    try {
        $proxyAddr = "socks5://127.0.0.1:" + $SOCKS_PORT
        $ip = (curl.exe -s --max-time 10 -x $proxyAddr -H "Accept: text/plain" https://ifconfig.me 2>$null)
        if ($ip -and $ip -notmatch "<html") {
            return $ip.Trim()
        }
        $ip = (curl.exe -s --max-time 10 -x $proxyAddr https://api.ipify.org 2>$null)
        if ($ip) { return $ip.Trim() }
        return "not active"
    }
    catch {
        return "not active"
    }
}

function Test-WarpInstalled {
    return (Test-Path $WARP_CLI)
}

function Get-WarpStatus {
    if (-not (Test-WarpInstalled)) { return "NOT INSTALLED" }
    try {
        $result = & $WARP_CLI status 2>&1 | Out-String
        return $result.Trim()
    }
    catch {
        return "ERROR"
    }
}

function Install-Warp {
    Write-Log "Downloading Cloudflare WARP installer..."
    $installerUrl = "https://1111-releases.cloudflareclient.com/windows/Cloudflare_WARP_Release-x64.msi"
    $installerPath = "$env:TEMP\Cloudflare_WARP.msi"

    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
        Write-Log "Installing Cloudflare WARP..."
        Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /quiet /norestart" -Wait
        Remove-Item $installerPath -Force
        Write-Log "[OK] WARP installed"
        Start-Sleep -Seconds 5
    }
    catch {
        Write-Log ("ERROR: Failed to install WARP - " + $_.Exception.Message)
        exit 1
    }
}

function Start-WarpService {
    $service = Get-Service -Name "CloudflareWARP" -ErrorAction SilentlyContinue
    if (-not $service) {
        $service = Get-Service -Name "Cloudflare WARP" -ErrorAction SilentlyContinue
    }
    if ($service) {
        if ($service.Status -ne "Running") {
            Write-Log "Starting WARP service..."
            Start-Service $service.Name
            Start-Sleep -Seconds 3
        }
        Write-Log ("[OK] WARP service: " + $service.Status)
    }
    else {
        Write-Log "ERROR: WARP service not found. Install WARP first with -Setup"
        exit 1
    }
}

function Register-Warp {
    Write-Log "Checking WARP registration..."
    $warpStatus = Get-WarpStatus
    if ($warpStatus -match "Registration Missing") {
        Write-Log "Registering WARP..."
        & $WARP_CLI registration new 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        Write-Log "[OK] WARP registered"
    }
    else {
        Write-Log "WARP already registered"
    }
}

function Set-WarpMode {
    Write-Log "Setting WARP mode to proxy..."
    try {
        & $WARP_CLI mode proxy 2>&1 | Out-Null
        Start-Sleep -Seconds 1
        Write-Log "[OK] WARP mode set to proxy"
    }
    catch {
        Write-Log "[WARN] Could not set proxy mode. Trying warp mode..."
        & $WARP_CLI mode warp 2>&1 | Out-Null
    }
}

function Set-ProxyPort {
    Write-Log ("Setting WARP proxy port to " + $SOCKS_PORT + "...")
    try {
        & $WARP_CLI proxy port $SOCKS_PORT 2>&1 | Out-Null
        Start-Sleep -Seconds 1
        Write-Log ("[OK] Proxy port set to " + $SOCKS_PORT)
    }
    catch {
        Write-Log ("[WARN] Could not set proxy port: " + $_.Exception.Message)
    }
}

function Connect-Warp {
    Write-Log "Connecting to WARP..."
    & $WARP_CLI connect 2>&1 | Out-Null
    Start-Sleep -Seconds 5

    $warpStatus = Get-WarpStatus
    Write-Log ("WARP status: " + $warpStatus)

    if ($warpStatus -match "Connected") {
        Write-Log "[OK] WARP connected"
        return $true
    }
    else {
        Write-Log "[WARN] WARP may not be connected"
        Write-Log "Try: Open Cloudflare WARP GUI and connect manually"
        return $false
    }
}

function Disconnect-Warp {
    Write-Log "Disconnecting WARP..."
    & $WARP_CLI disconnect 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    Write-Log "[OK] WARP disconnected"
}

function Test-Proxy {
    Write-Log "Testing SOCKS5 proxy..."
    try {
        $tcpTest = New-Object System.Net.Sockets.TcpClient
        $tcpTest.Connect("127.0.0.1", $SOCKS_PORT)
        $tcpTest.Close()
        Write-Log ("[OK] SOCKS5 proxy active on 127.0.0.1:" + $SOCKS_PORT)
        return $true
    }
    catch {
        Write-Log ("[WARN] SOCKS5 proxy not responding on port " + $SOCKS_PORT)
        return $false
    }
}

# === Commands ===

function Invoke-Setup {
    Write-Log "=== WARP + SOCKS5 Proxy Setup ==="

    if (-not (Test-WarpInstalled)) {
        Install-Warp
    }
    else {
        Write-Log "WARP already installed"
    }

    # Start service
    Start-WarpService

    # Register
    Register-Warp

    # Set mode to proxy (SOCKS5)
    Set-WarpMode

    # Set proxy port
    Set-ProxyPort

    # Connect
    Connect-Warp

    # Wait and test
    Start-Sleep -Seconds 3
    $proxyOk = Test-Proxy

    $normalIP = Get-CurrentIP
    Write-Host ""
    Write-Log "=== Setup Complete ==="
    Write-Log ("Normal IP:  " + $normalIP)

    if ($proxyOk) {
        $warpIP = Get-WarpIP
        Write-Log ("WARP IP:    " + $warpIP)
        Write-Log ("SOCKS5:     socks5://127.0.0.1:" + $SOCKS_PORT)
    }
    else {
        Write-Log "WARP IP:    proxy not active"
        Write-Log ""
        Write-Log "=== TROUBLESHOOT ==="
        Write-Log "1. Buka Cloudflare WARP GUI"
        Write-Log "2. Klik Settings > Advanced > Configure Proxy"
        Write-Log "3. Enable proxy, set port 40000"
        Write-Log "4. Connect WARP dari GUI"
        Write-Log ("5. Lalu jalankan: .\warp-rotate.ps1 -Check")
    }
    Write-Host ""
}

function Invoke-Rotate {
    $oldWarpIP = Get-WarpIP
    Write-Log ("Current WARP IP: " + $oldWarpIP)

    Disconnect-Warp

    Write-Log "Waiting 3 seconds before reconnect..."
    Start-Sleep -Seconds 3

    Connect-Warp

    Start-Sleep -Seconds 3
    $newWarpIP = Get-WarpIP
    Write-Log ("New WARP IP: " + $newWarpIP)

    if ($oldWarpIP -ne "not active" -and $newWarpIP -ne "not active" -and $oldWarpIP -ne $newWarpIP) {
        Write-Log ("[OK] IP rotated: " + $oldWarpIP + " -> " + $newWarpIP)
    }
    elseif ($newWarpIP -ne "not active") {
        Write-Log ("[OK] WARP active - IP: " + $newWarpIP)
    }
    else {
        Write-Log "[FAIL] Failed to get new IP"
    }
}

function Invoke-Check {
    $normalIP = Get-CurrentIP
    $warpIP = Get-WarpIP

    Write-Host ("Normal IP: " + $normalIP)
    Write-Host ("WARP IP:   " + $warpIP)
}

function Invoke-Status {
    Write-Host "=== WARP Status ==="

    # Service
    $service = Get-Service -Name "CloudflareWARP" -ErrorAction SilentlyContinue
    if (-not $service) {
        $service = Get-Service -Name "Cloudflare WARP" -ErrorAction SilentlyContinue
    }
    if ($service) {
        Write-Host ("Service:   " + $service.Status)
    }
    else {
        Write-Host "Service:   NOT INSTALLED"
    }

    # WARP status
    $warpStatus = Get-WarpStatus
    Write-Host ("WARP:      " + $warpStatus)

    # Proxy
    $proxyOk = $false
    try {
        $tcpTest = New-Object System.Net.Sockets.TcpClient
        $tcpTest.Connect("127.0.0.1", $SOCKS_PORT)
        $tcpTest.Close()
        $proxyOk = $true
    }
    catch { }

    if ($proxyOk) {
        Write-Host ("SOCKS5:    ACTIVE (127.0.0.1:" + $SOCKS_PORT + ")")
    }
    else {
        Write-Host "SOCKS5:    INACTIVE"
    }

    Write-Host ""
    Write-Host ("Normal IP: " + (Get-CurrentIP))
    if ($proxyOk) {
        Write-Host ("WARP IP:   " + (Get-WarpIP))
    }
    else {
        Write-Host "WARP IP:   proxy not active"
    }
}

function Invoke-Down {
    Disconnect-Warp
    Write-Log "[OK] WARP stopped"
}

function Invoke-Up {
    Start-WarpService
    Set-WarpMode
    Set-ProxyPort
    Connect-Warp

    Start-Sleep -Seconds 2
    Write-Log ("Normal IP: " + (Get-CurrentIP))
    Write-Log ("WARP IP:   " + (Get-WarpIP))
    Write-Log "[OK] WARP started"
}

# === enowxai Integration ===

function Get-EnowxaiExe {
    $enowx = Get-Command "enowxai" -ErrorAction SilentlyContinue
    if ($enowx) { return $enowx.Source }
    $local1 = "$env:USERPROFILE\.local\bin\enowxai.exe"
    if (Test-Path $local1) { return $local1 }
    $local2 = "C:\Users\$env:USERNAME\AppData\Local\Programs\enowxai\enowxai.exe"
    if (Test-Path $local2) { return $local2 }
    # Search in PATH and common locations
    $found = Get-ChildItem -Path "C:\Program Files","C:\Program Files (x86)",$env:LOCALAPPDATA,$env:APPDATA -Filter "enowxai.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Invoke-EnowxaiAdd {
    $enowx = Get-EnowxaiExe
    if (-not $enowx) {
        Write-Log "ERROR: enowxai not found"
        Write-Log "Searched: PATH, .local/bin, AppData, Program Files"
        return
    }
    Write-Log ("Found enowxai: " + $enowx)

    $proxyUrl = "socks5://" + $SOCKS_BIND + ":" + $SOCKS_PORT
    Write-Log ("Adding WARP proxy to enowxai: " + $proxyUrl)
    & $enowx proxy add $proxyUrl 2>&1
    Write-Host ""
    Write-Log "Current proxy list:"
    & $enowx proxy list 2>&1
}

function Invoke-EnowxaiClear {
    $enowx = Get-EnowxaiExe
    if (-not $enowx) {
        Write-Log "ERROR: enowxai not found"
        return
    }
    Write-Log ("Found enowxai: " + $enowx)

    # Backup existing proxies
    $enowxDir = "$env:USERPROFILE\.enowxai"
    $proxiesFile = "$enowxDir\proxies.json"
    if (Test-Path $proxiesFile) {
        $ts = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupFile = "$enowxDir\proxies.json.bak.$ts"
        Copy-Item $proxiesFile $backupFile
        Write-Log ("Proxy backup saved: " + $backupFile)
    }

    Write-Log "Clearing all enowxai proxies..."
    & $enowx proxy clear 2>&1

    $proxyUrl = "socks5://" + $SOCKS_BIND + ":" + $SOCKS_PORT
    Write-Log ("Adding WARP proxy: " + $proxyUrl)
    & $enowx proxy add $proxyUrl 2>&1

    Write-Host ""
    & $enowx proxy test 2>&1
    Write-Host ""
    & $enowx proxy list 2>&1
    Write-Log "[OK] enowxai now uses WARP proxy only"
}

function Invoke-Help {
    Write-Host @"
warp-rotate.ps1 -- Cloudflare WARP IP Rotation + SOCKS5 Proxy (Windows)

Usage:
  .\warp-rotate.ps1 <command>

Commands:
  -Setup              First-time setup (install WARP + connect + proxy)
  -Rotate             Rotate IP (disconnect + reconnect WARP)
  -Check              Check current IPs (normal + WARP)
  -Status             Full status (service, tunnel, proxy, IPs)
  -Up                 Start WARP + proxy
  -Down               Stop WARP + proxy
  -EnowxaiAdd         Add WARP proxy to enowxai
  -EnowxaiClear       Backup + clear all enowxai proxies, add WARP only
  -Help               Show this help message

Config:
  SOCKS5 Proxy:       127.0.0.1:40000
  WARP Client:        Cloudflare WARP (warp-cli.exe)
  Mode:               Proxy (SOCKS5)

Examples:
  .\warp-rotate.ps1 -Setup
  .\warp-rotate.ps1 -Rotate
  .\warp-rotate.ps1 -Check
  .\warp-rotate.ps1 -EnowxaiAdd
  curl -x socks5://127.0.0.1:40000 https://ifconfig.me

Note:
  Run as Administrator. If blocked by Execution Policy:
  powershell -ExecutionPolicy Bypass -File .\warp-rotate.ps1 -Setup

Requirements:
  - Cloudflare WARP for Windows (auto-installed on -Setup)
  - Administrator privileges
  - curl.exe (included in Windows 10/11)

Repo: https://github.com/ocdewe/warp-rotate
"@
}

# === Main ===
if ($Setup) {
    Invoke-Setup
}
elseif ($Rotate) {
    Invoke-Rotate
}
elseif ($Check) {
    Invoke-Check
}
elseif ($Status) {
    Invoke-Status
}
elseif ($Down) {
    Invoke-Down
}
elseif ($Up) {
    Invoke-Up
}
elseif ($EnowxaiAdd) {
    Invoke-EnowxaiAdd
}
elseif ($EnowxaiClear) {
    Invoke-EnowxaiClear
}
elseif ($Help) {
    Invoke-Help
}
else {
    Invoke-Help
}
