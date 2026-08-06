# Resolves the Godot console binary for headless validation and export.
# Usage:
#   $GODOT = & "$PSScriptRoot/godot-bin.ps1"
#   & $GODOT --headless --path apps/game/client --quit
#   & "$PSScriptRoot/godot-bin.ps1" --headless --path apps/game/client --quit

param(
    [switch]$Quiet
)

$GodotArgs = $args

$Candidates = @(
    $env:GODOT_BIN,
    "C:\Users\halag\Downloads\Godot\Godot_x64_console.exe",
    "C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe"
)

if (-not $Quiet) {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) {
        $Candidates += $cmd.Source
    }
} else {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
}

foreach ($path in $Candidates) {
    if ($path -and (Test-Path -LiteralPath $path)) {
        if ($GodotArgs -and $GodotArgs.Count -gt 0) {
            & $path @GodotArgs
            exit $LASTEXITCODE
        }
        if (-not $Quiet) { Write-Output $path }
        return $path
    }
}

if (-not $Quiet) {
    Write-Error "Godot binary not found. Set GODOT_BIN or install Godot 4.7 console build."
}
exit 1
