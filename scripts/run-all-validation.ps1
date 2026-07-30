#!/usr/bin/env pwsh
# Run all validation layers and merge into reports/validation-summary.json.
# Usage: ./scripts/run-all-validation.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$ReportsDir = Join-Path $Root "reports"
$SummaryPath = Join-Path $ReportsDir "validation-summary.json"

if (-not (Test-Path $ReportsDir)) {
    New-Item -ItemType Directory -Path $ReportsDir | Out-Null
}

$layers = @()
$totalPassed = 0
$totalFailed = 0
$anyFailed = $false

function Add-LayerResult {
    param(
        [string]$Name,
        [bool]$Ok,
        [int]$Passed = 0,
        [int]$Failed = 0,
        [string]$Detail = "",
        [object]$Report = $null
    )
    $script:layers += @{
        name = $Name
        ok = $Ok
        passed = $Passed
        failed = $Failed
        detail = $Detail
        report = $Report
    }
    $script:totalPassed += $Passed
    $script:totalFailed += $Failed
    if (-not $Ok) { $script:anyFailed = $true }
}

Write-Host "== Layer 1: C# + content validation =="
try {
    & "$Root/scripts/run-automated-tests.ps1"
    Add-LayerResult -Name "csharp_content" -Ok $true -Detail "dotnet test + content validate passed"
}
catch {
    Add-LayerResult -Name "csharp_content" -Ok $false -Detail $_.Exception.Message
}

Write-Host "`n== Layer 2: Godot in-engine validation =="
$mcpReport = $null
try {
    & "$Root/scripts/run-mcp-validation.ps1"
    $reportPath = Join-Path $env:APPDATA "Godot/app_userdata/Aumbrye/mcp_validation.json"
    if (Test-Path $reportPath) {
        $mcpReport = Get-Content $reportPath -Raw | ConvertFrom-Json
        Add-LayerResult -Name "godot_mcp" -Ok ($mcpReport.failed -eq 0) `
            -Passed $mcpReport.passed -Failed $mcpReport.failed -Report $mcpReport
    }
    else {
        Add-LayerResult -Name "godot_mcp" -Ok $false -Detail "Report not found at $reportPath"
    }
}
catch {
    Add-LayerResult -Name "godot_mcp" -Ok $false -Detail $_.Exception.Message
}

$summary = @{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    passed = $totalPassed
    failed = $totalFailed
    layers = $layers
    summaryPath = $SummaryPath
}

$summary | ConvertTo-Json -Depth 10 | Set-Content -Path $SummaryPath -Encoding UTF8

Write-Host ""
Write-Host "== Validation summary =="
Write-Host "Report: $SummaryPath"
foreach ($layer in $layers) {
    $mark = if ($layer.ok) { "[OK]" } else { "[FAIL]" }
    if ($layer.passed -gt 0 -or $layer.failed -gt 0) {
        Write-Host "$mark $($layer.name): passed=$($layer.passed) failed=$($layer.failed)"
    }
    else {
        Write-Host "$mark $($layer.name): $($layer.detail)"
    }
}

if ($anyFailed) {
    exit 1
}
