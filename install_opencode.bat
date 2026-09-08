@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Content -Raw -LiteralPath '%~f0'; $m = '# NORMAHUB POWERSHELL PAYLOAD'; Invoke-Expression ($s.Substring($s.LastIndexOf($m) + $m.Length))"
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" echo Installation failed. 1>&2
exit /b %CODE%
# NORMAHUB POWERSHELL PAYLOAD
$ErrorActionPreference = "Stop"
$apiUrl = "https://api.normahub.cc/api/v1/public/models"
$baseUrl = "https://api.normahub.cc/v1"
$opencodeDir = if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME ".config\opencode" }
$configFile = Join-Path $opencodeDir "opencode.json"

$secureKey = Read-Host "NormaHub API key" -AsSecureString
$keyPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try { $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPtr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPtr) }
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw "API key cannot be empty." }

New-Item -ItemType Directory -Force -Path $opencodeDir | Out-Null
$payload = $null
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try { $payload = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 30; break }
    catch {
        if ($attempt -eq 3) { throw "Failed to download ${apiUrl}: $($_.Exception.Message)" }
        Start-Sleep -Seconds $attempt
    }
}
if (-not $payload.models -and -not $payload.data) { throw "NormaHub returned an empty or invalid model catalog." }
$items = if ($payload.models) { @($payload.models) } else { @($payload.data) }

function Test-SkipModel($item) {
    $slug = ([string]$item.id).Trim().ToLowerInvariant()
    if ($slug.Contains("image")) { return $true }
    $endpoints = @($item.endpoints)
    foreach ($ep in $endpoints) {
        if ($ep -and ([string]$ep).ToLowerInvariant().Contains("images")) { return $true }
    }
    $imagePrice = $item.pricing.image_price
    if ($null -ne $imagePrice) {
        $parsed = 0.0
        if ([double]::TryParse([string]$imagePrice, [ref]$parsed) -and $parsed -gt 0) { return $true }
    }
    return $false
}

$openaiModels = [ordered]@{}
$anthropicModels = [ordered]@{}
$items | ForEach-Object {
    if (-not $_.id) { return }
    if (Test-SkipModel $_) { return }
    $id = [string]$_.id
    $model = [ordered]@{
        name = $id
        modalities = [ordered]@{
            input = if ($_.capabilities.vision) { @("text", "image") } else { @("text") }
            output = @("text")
        }
    }
    $context = if ($_.context_window -is [ValueType] -and $_.context_window -gt 0) { [long]$_.context_window } else { 128000 }
    $output = if ($_.max_output_tokens -is [ValueType] -and $_.max_output_tokens -gt 0) { [long]$_.max_output_tokens }
        elseif ($_.output_tokens -is [ValueType] -and $_.output_tokens -gt 0) { [long]$_.output_tokens }
        elseif ($_.limits.output -is [ValueType] -and $_.limits.output -gt 0) { [long]$_.limits.output }
        else { 65536 }
    $model.limit = [ordered]@{
        context = $context
        output = $output
    }
    $slug = $id.Trim().ToLowerInvariant()
    if ($slug.StartsWith("claude") -or ($slug -split "-") -contains "claude") {
        $anthropicModels[$id] = $model
    } else {
        $openaiModels[$id] = $model
    }
}

if ($openaiModels.Count -eq 0 -and $anthropicModels.Count -eq 0) { throw "NormaHub catalog contains no valid model IDs." }

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

$config = if (Test-Path $configFile) {
    try {
        $rawConfig = Get-Content -Raw -LiteralPath $configFile
        if ([string]::IsNullOrWhiteSpace($rawConfig)) { @{} }
        else { ConvertTo-Hashtable ($rawConfig | ConvertFrom-Json) }
    }
    catch { throw "Refusing to overwrite invalid opencode.json: $($_.Exception.Message)" }
} else { @{} }
if ($config -isnot [hashtable]) { throw "opencode.json must contain a JSON object." }

if (-not $config.ContainsKey("provider") -or $config.provider -isnot [hashtable]) {
    $config.provider = @{}
}

if ($openaiModels.Count -gt 0) {
    $config.provider["normahub"] = @{
        npm = "@ai-sdk/openai-compatible"
        name = "NormaHub (OpenAI)"
        options = @{
            apiKey = $apiKey
            baseURL = $baseUrl
        }
        models = $openaiModels
    }
}
if ($anthropicModels.Count -gt 0) {
    $config.provider["normahub-anthropic"] = @{
        npm = "@ai-sdk/anthropic"
        name = "NormaHub (Claude)"
        options = @{
            apiKey = $apiKey
            baseURL = $baseUrl
            headers = @{
                Authorization = "Bearer " + $apiKey
            }
        }
        models = $anthropicModels
    }
}

if (-not $config.ContainsKey('$schema')) {
    $config['$schema'] = "https://opencode.ai/config.json"
}
if (-not $config.ContainsKey("model") -or [string]::IsNullOrWhiteSpace([string]$config.model)) {
    if ($openaiModels.Count -gt 0) {
        $config["model"] = "normahub/" + ([string](@($openaiModels.Keys)[0]))
    } else {
        $config["model"] = "normahub-anthropic/" + ([string](@($anthropicModels.Keys)[0]))
    }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($configFile, ($config | ConvertTo-Json -Depth 20) + "`n", $utf8NoBom)
$apiKey = $null
Write-Host "Configured $($openaiModels.Count + $anthropicModels.Count) NormaHub model(s) in $configFile"
Write-Host "Default model: $($config.model)"
Write-Host "Restart OpenCode to apply the new configuration."
