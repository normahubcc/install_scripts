@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Content -Raw -LiteralPath '%~f0'; $m = '# NORMAHUB POWERSHELL PAYLOAD'; Invoke-Expression ($s.Substring($s.LastIndexOf($m) + $m.Length))" -args "%~1"
set "CODE=%ERRORLEVEL%"
exit /b %CODE%
# NORMAHUB POWERSHELL PAYLOAD
param([string]$KeyArg)

$ErrorActionPreference = "Continue"
$hostName = "api.normahub.cc"
$baseUrl = "https://api.normahub.cc/v1"
$apiKey = if ($KeyArg) { $KeyArg } elseif ($env:NORMAHUB_API_KEY) { $env:NORMAHUB_API_KEY } else { "" }

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "NormaHub Windows Network & Gateway Diagnostics" -ForegroundColor White
Write-Host "Host: $hostName | Gateway: $baseUrl"
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host ""

$errors = 0

# Step 1: DNS Resolution
Write-Host -NoNewline "[1/4] DNS Resolution ($hostName)... "
try {
    $dns = [System.Net.Dns]::GetHostAddresses($hostName)
    $ip = $dns[0].IPAddressToString
    Write-Host "[OK] Resolved to $ip" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] DNS Resolution failed: $($_.Exception.Message)" -ForegroundColor Red
    $errors++
}

# Step 2: TCP Latency
Write-Host -NoNewline "[2/4] TCP Handshake & Port 443 Connectivity... "
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $client = New-Object System.Net.Sockets.TcpClient
    $iar = $client.BeginConnect($hostName, 443, $null, $null)
    $success = $iar.AsyncWaitHandle.WaitOne(5000, $false)
    $sw.Stop()
    if ($success) {
        $client.EndConnect($iar)
        $client.Close()
        Write-Host "[OK] Connected in $($sw.ElapsedMilliseconds)ms" -ForegroundColor Green
    } else {
        $client.Close()
        Write-Host "[FAIL] TCP Connection timed out" -ForegroundColor Red
        $errors++
    }
} catch {
    Write-Host "[FAIL] Connection error: $($_.Exception.Message)" -ForegroundColor Red
    $errors++
}

# Step 3: HTTPS API Gateway
Write-Host -NoNewline "[3/4] HTTPS Gateway Reachability... "
try {
    $req = [System.Net.WebRequest]::Create("$baseUrl/models")
    $req.Timeout = 10000
    try {
        $resp = $req.GetResponse()
        Write-Host "[OK] Gateway responsive (HTTP 200)" -ForegroundColor Green
        $resp.Close()
    } catch [System.Net.WebException] {
        $httpResp = $_.Exception.Response
        if ($httpResp -and [int]$httpResp.StatusCode -eq 401) {
            Write-Host "[OK] Gateway responsive (HTTP 401 Authorized API Gate)" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Gateway HTTP: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "[FAIL] HTTPS Gateway check failed: $($_.Exception.Message)" -ForegroundColor Red
    $errors++
}

# Step 4: Key Authentication
Write-Host -NoNewline "[4/4] API Key Authentication... "
if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
    try {
        $headers = @{ "Authorization" = "Bearer $apiKey" }
        $authResp = Invoke-RestMethod -Uri "$baseUrl/models" -Headers $headers -TimeoutSec 10 -Method Get
        Write-Host "[OK] API Key is valid and authorized!" -ForegroundColor Green
    } catch {
        Write-Host "[FAIL] API Key check failed: $($_.Exception.Message)" -ForegroundColor Red
        $errors++
    }
} else {
    Write-Host "[SKIP] No API key provided (set NORMAHUB_API_KEY to verify)" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "--------------------------------------------------------------------" -ForegroundColor Cyan
if ($errors -eq 0) {
    Write-Host "✔ All network diagnostics PASSED! Connection to NormaHub is optimal." -ForegroundColor Green
    exit 0
} else {
    Write-Host "✘ Diagnostics finished with $errors error(s)." -ForegroundColor Red
    exit 1
}
