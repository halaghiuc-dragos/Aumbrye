#!/usr/bin/env pwsh
# Run in-engine validation and print the JSON report.
# Requires Godot 4.x on PATH (or set GODOT_BIN).
# Usage: ./scripts/run-mcp-validation.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $Root "apps/game/client"

function Find-GodotExecutable {
    if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) {
        return $env:GODOT_BIN
    }

    $onPath = Get-Command godot -ErrorAction SilentlyContinue
    if ($onPath) {
        return $onPath.Source
    }

    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Godot\Godot*.exe",
        "$env:ProgramFiles\Godot\Godot*.exe",
        "$env:USERPROFILE\Downloads\Godot_v*-stable_win64.exe\Godot_v*-stable_win64_console.exe",
        "$env:USERPROFILE\Downloads\Godot_v*-stable_win64.exe\Godot_v*-stable_win64.exe"
    )
    foreach ($pattern in $candidates) {
        $match = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }

    return $null
}

$Godot = Find-GodotExecutable
if (-not $Godot) {
    Write-Error @"
Godot 4.x not found. Install Godot or set GODOT_BIN to the console executable, e.g.:
  `$env:GODOT_BIN = 'C:\path\to\Godot_v4.7.1-stable_win64_console.exe'
  ./scripts/run-mcp-validation.ps1
"@
}

Write-Host "== MCP validation (Godot in-engine) =="
Write-Host "Using: $Godot"
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $Godot --path $Project --headless res://scenes/debug/mcp_validation.tscn *> $null
$godotExit = $LASTEXITCODE
$ErrorActionPreference = $prevEap
if ($godotExit -ne 0) {
    throw "Godot validation scene failed (exit $godotExit)"
}

$reportPath = Join-Path $env:APPDATA "Godot/app_userdata/Aumbrye/mcp_validation.json"
if (-not (Test-Path $reportPath)) {
    throw "Report not found at $reportPath"
}

$report = Get-Content $reportPath -Raw | ConvertFrom-Json
Write-Host ""
Write-Host ("Passed: {0}  Failed: {1}  (schema v{2})" -f $report.passed, $report.failed, $report.schemaVersion)
if ($report.suites) {
    Write-Host "`nPer suite:"
    foreach ($suite in $report.suites) {
        $mark = if ($suite.failed -eq 0) { "[OK]" } else { "[FAIL]" }
        Write-Host "$mark $($suite.name): passed=$($suite.passed) failed=$($suite.failed)"
    }
}
Write-Host ""
foreach ($test in $report.tests) {
    $mark = if ($test.pass) { "[OK]" } else { "[FAIL]" }
    Write-Host "$mark $($test.id): $($test.message)"
}
if ($report.failed -gt 0) {
    exit 1
}
