@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Content -Raw -LiteralPath '%~f0'; $m = '# NORMAHUB POWERSHELL PAYLOAD'; Invoke-Expression ($s.Substring($s.LastIndexOf($m) + $m.Length))"
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" echo Installation failed. 1>&2
exit /b %CODE%
# NORMAHUB POWERSHELL PAYLOAD
$ErrorActionPreference = "Stop"
$apiUrl = "https://api.normahub.cc/api/v1/public/models"
$baseUrl = "https://api.normahub.cc"
$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$settingsFile = Join-Path $claudeDir "settings.json"
$cacheDir = Join-Path $claudeDir "cache"
$catalogFile = Join-Path $cacheDir "gateway-models.json"

$secureKey = Read-Host "NormaHub API key" -AsSecureString
$keyPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try { $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPtr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPtr) }
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw "API key cannot be empty." }

New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
$payload = $null
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try { $payload = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 30; break }
    catch {
        if ($attempt -eq 3) { throw "Failed to download ${apiUrl}: $($_.Exception.Message)" }
        Start-Sleep -Seconds $attempt
    }
}
if (-not $payload.models -or $payload.models.Count -eq 0) { throw "NormaHub returned an empty or invalid model catalog." }

$models = @($payload.models | ForEach-Object {
    if (-not $_.id) { return }
    $slug = ([string]$_.id).Trim().ToLowerInvariant()
    if (-not ($slug.StartsWith("claude") -or ($slug -split "-") -contains "claude")) { return }
    if ($slug.Contains("image")) { return }
    foreach ($ep in @($_.endpoints)) {
        if ($ep -and ([string]$ep).ToLowerInvariant().Contains("images")) { return }
    }
    [string]$_.id
})
if ($models.Count -eq 0) { throw "NormaHub catalog contains no valid Claude model IDs." }
$modelIds = @($models | ForEach-Object { [string]$_ })
$defaultModel = if ($modelIds -contains "claude-opus-4-6") { "claude-opus-4-6" }
    elseif ($modelIds -contains "claude-sonnet-4-6") { "claude-sonnet-4-6" }
    else { $modelIds[0] }

function ConvertTo-Hashtable($value) {
    if ($value -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $value.Keys) { $result[$key] = ConvertTo-Hashtable $value[$key] }
        return $result
    }
    if ($value -is [System.Management.Automation.PSCustomObject]) {
        $result = @{}
        foreach ($property in $value.PSObject.Properties) { $result[$property.Name] = ConvertTo-Hashtable $property.Value }
        return $result
    }
    if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
        return @($value | ForEach-Object { ConvertTo-Hashtable $_ })
    }
    return $value
}

$settings = if (Test-Path $settingsFile) {
    try { ConvertTo-Hashtable (Get-Content -Raw -LiteralPath $settingsFile | ConvertFrom-Json) }
    catch { throw "Refusing to overwrite invalid settings.json: $($_.Exception.Message)" }
} else { @{} }
if ($settings -isnot [hashtable]) { throw "settings.json must contain a JSON object." }
if (-not $settings.ContainsKey("env") -or $settings.env -isnot [hashtable]) { $settings.env = @{} }
$settings.env["ANTHROPIC_BASE_URL"] = $baseUrl
$settings.env["ANTHROPIC_AUTH_TOKEN"] = $apiKey
$settings.env["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"] = "1"
$settings.env["CLAUDE_CODE_DISABLE_1M_CONTEXT"] = "1"
if ($modelIds -contains "claude-opus-4-6") { $settings.env["ANTHROPIC_DEFAULT_OPUS_MODEL"] = "claude-opus-4-6" }
if ($modelIds -contains "claude-sonnet-4-6") { $settings.env["ANTHROPIC_DEFAULT_SONNET_MODEL"] = "claude-sonnet-4-6" }
if ($modelIds -contains "claude-fable-5-1") { $settings.env["ANTHROPIC_DEFAULT_FABLE_MODEL"] = "claude-fable-5-1" }
$settings["model"] = $defaultModel

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($settingsFile, ($settings | ConvertTo-Json -Depth 20) + "`n", $utf8NoBom)
$catalog = @{ data = @($models | ForEach-Object { @{ id = $_ } }) }
[IO.File]::WriteAllText($catalogFile, ($catalog | ConvertTo-Json -Depth 10) + "`n", $utf8NoBom)
$apiKey = $null
Write-Host "Configured $($models.Count) NormaHub Claude model(s) in $settingsFile"
Write-Host "Default model: $defaultModel"
Write-Host "Restart Claude Code to apply the new configuration."
