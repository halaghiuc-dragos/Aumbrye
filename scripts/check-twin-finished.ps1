$ai = "D:\Proiecte\Aumbrye\docs\actual_improvements"
$ec = "D:\Proiecte\Aumbrye\docs\existing_codebase"
$missing = @()
Get-ChildItem -Path $ai -Recurse -Filter "*.md" | ForEach-Object {
    if ($_.Name -match "^(README|_INDEX)" -or $_.Name -like "00-*") { return }
    $c = Get-Content $_.FullName -Raw
    if ($c -notmatch "Status:\s*FINISHED") { return }
    $rel = $_.FullName.Substring($ai.Length + 1)
    $twin = Join-Path $ec $rel
    if (-not (Test-Path $twin)) {
        $missing += "$rel [no twin]"
        return
    }
    $tc = Get-Content $twin -Raw
    if ($tc -notmatch "FINISHED") { $missing += $rel }
}
$missing | Sort-Object
Write-Host "Count: $($missing.Count)"
