$ai = "D:\Proiecte\Aumbrye\docs\actual_improvements"
$ec = "D:\Proiecte\Aumbrye\docs\existing_codebase"
$updated = 0
Get-ChildItem -Path $ai -Recurse -Filter "*.md" | ForEach-Object {
    if ($_.Name -match "^(README|_INDEX)" -or $_.Name -like "00-*") { return }
    $c = Get-Content $_.FullName -Raw
    if ($c -notmatch "Status:\s*FINISHED") { return }
    $rel = $_.FullName.Substring($ai.Length + 1)
    $twin = Join-Path $ec $rel
    if (-not (Test-Path $twin)) { return }
    $lines = Get-Content $twin
    $newLines = @()
    $changed = $false
    foreach ($line in $lines) {
        if ($line -match "Improvement plan:" -and $line -notmatch "FINISHED") {
            if ($line -match "\)\s*$") {
                $line = $line -replace "\)\s*$", ") - **FINISHED**"
                $changed = $true
            }
        }
        $newLines += $line
    }
    if ($changed) {
        Set-Content -Path $twin -Value $newLines -Encoding utf8
        $updated++
        Write-Host "Updated: $rel"
    }
}
Write-Host "Updated count: $updated"
