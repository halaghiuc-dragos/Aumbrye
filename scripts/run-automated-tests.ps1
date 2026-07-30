#!/usr/bin/env pwsh
# Run automated checks for offline procgen, catalogs, and content schemas.
# Usage: ./scripts/run-automated-tests.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

Write-Host "== Build procgen-cli =="
dotnet build "$Root/tools/procgen-cli/ProcgenCli.csproj" -c Debug

Write-Host "`n== Unit tests (Aumbrye.UnitTests) =="
dotnet test "$Root/services/backend/tests/Aumbrye.UnitTests/Aumbrye.UnitTests.csproj" --no-restore

Write-Host "`n== Content validation =="
Push-Location "$Root/scripts/validate-content"
if (-not (Test-Path "node_modules")) { npm install --silent }
npm run validate
Pop-Location

Write-Host "`nAll automated checks passed."
