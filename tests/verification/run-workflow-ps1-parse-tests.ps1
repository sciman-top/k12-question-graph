$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$workflowPath = if ($env:KQG_WORKFLOW_PARSE_TARGET) {
    [System.IO.Path]::GetFullPath($env:KQG_WORKFLOW_PARSE_TARGET)
}
else {
    Join-Path $repoRoot '.github/workflows/repo-preflight.yml'
}
$lines = Get-Content -LiteralPath $workflowPath

# GitHub runs `run: |` blocks with a YAML-indented PowerShell body. Parse each
# inline block locally so a workflow-only syntax error fails before a push.
$blockStartIndexes = @()
for ($index = 0; $index -lt $lines.Count; $index++) {
    if ($lines[$index] -match '^\s*run: \|\s*$') {
        $blockStartIndexes += $index
    }
}
if ($blockStartIndexes.Count -eq 0) { throw 'workflow has no inline run blocks' }

$caseCount = 0
foreach ($startIndex in $blockStartIndexes) {
    $indent = ([regex]::Match($lines[$startIndex], '^(\s*)')).Groups[1].Value.Length
    $bodyLines = New-Object System.Collections.Generic.List[string]
    for ($lineIndex = $startIndex + 1; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = $lines[$lineIndex]
        if ($line.Trim().Length -eq 0) {
            if ($bodyLines.Count -gt 0) { $bodyLines.Add('') }
            continue
        }
        $lineIndent = ([regex]::Match($line, '^(\s*)')).Groups[1].Value.Length
        if ($lineIndent -le $indent) { break }
        $bodyLines.Add($line.Substring([Math]::Min($indent + 2, $line.Length)))
    }

    if ($bodyLines.Count -eq 0) { throw "workflow run block starting at line $($startIndex + 1) is empty" }
    $source = $bodyLines -join "`n"
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $detail = ($errors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join '; '
        throw "workflow run block starting at line $($startIndex + 1) has PowerShell syntax errors: $detail"
    }
    $caseCount += 1
}

[ordered]@{
    status = 'pass'
    workflow = '.github/workflows/repo-preflight.yml'
    inlinePowerShellBlockCount = $caseCount
} | ConvertTo-Json -Depth 4
