#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
node (Join-Path $PSScriptRoot "validate.mjs") @args
exit $LASTEXITCODE
