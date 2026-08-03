param(
    [switch]$Export,
    [switch]$Summary
)

$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot)
$content = Join-Path $root "content"

function Get-JsonFiles($dir) {
    if (-not (Test-Path $dir)) { return @() }
    Get-ChildItem $dir -Filter "*.json" -Recurse
}

$enemies = @(Get-JsonFiles (Join-Path $content "enemies"))
$bosses = @(Get-JsonFiles (Join-Path $content "bosses"))
$items = @(Get-JsonFiles (Join-Path $content "items"))
$biomes = @(Get-JsonFiles (Join-Path $content "biomes"))

$report = [ordered]@{
    generatedAt = (Get-Date).ToString("o")
    enemies = $enemies.Count
    bosses = $bosses.Count
    itemFiles = $items.Count
    biomes = $biomes.Count
}

if ($Export) {
    $out = Join-Path $root "reports/balance_export.json"
    ($report | ConvertTo-Json -Depth 3) | Set-Content $out -Encoding UTF8
    Write-Host "Exported to $out"
}

if ($Summary) {
    Write-Host "Enemies: $($report.enemies)  Bosses: $($report.bosses)  Items: $($report.itemFiles)  Biomes: $($report.biomes)"
}
