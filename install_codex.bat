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
$codexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
$configFile = Join-Path $codexDir "config.toml"
$catalogFile = Join-Path $codexDir "normahub-models.json"

$secureKey = Read-Host "NormaHub API key" -AsSecureString
$keyPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try { $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPtr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPtr) }
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw "API key cannot be empty." }

New-Item -ItemType Directory -Force -Path $codexDir | Out-Null
$payload = $null
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try { $payload = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 30; break }
    catch {
        if ($attempt -eq 3) { throw "Failed to download ${apiUrl}: $($_.Exception.Message)" }
        Start-Sleep -Seconds $attempt
    }
}
if (-not $payload.models -or $payload.models.Count -eq 0) { throw "NormaHub returned an empty or invalid model catalog." }

function Test-SkipModel($item) {
    $slug = ([string]$item.id).Trim().ToLowerInvariant()
    if ($slug.StartsWith("claude") -or ($slug -split "-") -contains "claude") { return $true }
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

$priority = 0
$models = @($payload.models | ForEach-Object {
    if (-not $_.id) { return }
    if (Test-SkipModel $_) { return }
    $priority++
    $context = if ($_.context_window -is [ValueType] -and $_.context_window -gt 0) { [long]$_.context_window } else { $null }
    $modalities = if ($_.capabilities.vision) { @("text", "image") } else { @("text") }
    [ordered]@{
        slug = [string]$_.id
        display_name = [string]$_.id
        description = "Available through NormaHub"
        default_reasoning_level = "medium"
        supported_reasoning_levels = @(
            [ordered]@{ effort = "low"; description = "Faster responses" },
            [ordered]@{ effort = "medium"; description = "Balanced reasoning" },
            [ordered]@{ effort = "high"; description = "Deeper reasoning" }
        )
        shell_type = "unified_exec"
        visibility = "list"
        supported_in_api = $true
        priority = $priority
        availability_nux = $null
        upgrade = $null
        base_instructions = "You are Codex, a coding agent. Work with the user in the current workspace to complete software engineering tasks."
        support_verbosity = $true
        default_verbosity = $null
        apply_patch_tool_type = "freeform"
        truncation_policy = [ordered]@{ mode = "tokens"; limit = 10000 }
        supports_parallel_tool_calls = $true
        context_window = $context
        max_context_window = $context
        experimental_supported_tools = @()
        input_modalities = $modalities
    }
})
if ($models.Count -eq 0) { throw "NormaHub catalog contains no valid model IDs." }

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$catalogJson = [ordered]@{ models = $models } | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($catalogFile, $catalogJson + "`n", $utf8NoBom)
$text = if (Test-Path $configFile) { Get-Content -Raw -LiteralPath $configFile } else { "" }
$text = [regex]::Replace($text, '(?ms)^# BEGIN NORMAHUB CODEX ROOT\r?\n.*?^# END NORMAHUB CODEX ROOT\r?\n?', '')
$text = [regex]::Replace($text, '(?ms)^# BEGIN NORMAHUB CODEX PROVIDER\r?\n.*?^# END NORMAHUB CODEX PROVIDER\r?\n?', '')
$text = [regex]::Replace($text, '(?ms)^\[model_providers\.normahub\]\s*\r?\n.*?(?=^\[|\z)', '')
$firstTable = [regex]::Match($text, '(?m)^\s*\[')
$split = if ($firstTable.Success) { $firstTable.Index } else { $text.Length }
$rootText = $text.Substring(0, $split)
$tableText = $text.Substring($split)
$rootText = [regex]::Replace($rootText, '(?m)^(model|model_provider|model_catalog_json)\s*=.*\r?\n?', '')
$text = $rootText + $tableText

function ConvertTo-TomlString([string]$value) {
    return '"' + $value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n') + '"'
}
$root = "# BEGIN NORMAHUB CODEX ROOT`r`n" +
    "model = $(ConvertTo-TomlString $models[0].slug)`r`n" +
    "model_provider = `"normahub`"`r`n" +
    "model_catalog_json = $(ConvertTo-TomlString $catalogFile)`r`n" +
    "# END NORMAHUB CODEX ROOT`r`n`r`n"
$provider = "`r`n# BEGIN NORMAHUB CODEX PROVIDER`r`n" +
    "[model_providers.normahub]`r`n" +
    "name = `"NormaHub`"`r`n" +
    "base_url = $(ConvertTo-TomlString $baseUrl)`r`n" +
    "wire_api = `"responses`"`r`n" +
    "experimental_bearer_token = $(ConvertTo-TomlString $apiKey)`r`n" +
    "# END NORMAHUB CODEX PROVIDER`r`n"
[IO.File]::WriteAllText($configFile, $root + $text.Trim() + $provider, $utf8NoBom)
$apiKey = $null
Write-Host "Configured $($models.Count) NormaHub model(s) in $configFile"
Write-Host "Default model: $($models[0].slug)"
Write-Host "Restart Codex to apply the new configuration."
