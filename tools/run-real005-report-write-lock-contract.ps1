param(
    [string] $WorkRoot = 'tmp/real005-write-lock-contract',
    [int] $LockHoldMilliseconds = 1200
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-InRepoPath([string] $RelativePath) {
    return Join-Path $repoRoot $RelativePath
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$workRootFullPath = Resolve-InRepoPath $WorkRoot
$jsonReportRelativePath = Join-Path $WorkRoot 'real005-report.json'
$markdownReportRelativePath = Join-Path $WorkRoot 'real005-report.md'
$readyFlagFullPath = Join-Path $workRootFullPath 'lock.ready'

New-Item -ItemType Directory -Path $workRootFullPath -Force | Out-Null
Remove-Item -LiteralPath $readyFlagFullPath -Force -ErrorAction SilentlyContinue
Set-Content -LiteralPath (Resolve-InRepoPath $jsonReportRelativePath) -Value '{}' -Encoding UTF8

$locker = Start-Job -ScriptBlock {
    param(
        [string] $Path,
        [string] $ReadyPath,
        [int] $HoldMilliseconds
    )

    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        [System.IO.File]::WriteAllText($ReadyPath, 'locked')
        Start-Sleep -Milliseconds $HoldMilliseconds
    }
    finally {
        $fs.Dispose()
    }
} -ArgumentList (Resolve-InRepoPath $jsonReportRelativePath), $readyFlagFullPath, $LockHoldMilliseconds

try {
    $deadline = (Get-Date).AddSeconds(5)
    while ((-not (Test-Path -LiteralPath $readyFlagFullPath)) -and ((Get-Date) -lt $deadline)) {
        Start-Sleep -Milliseconds 50
    }

    Assert-True (Test-Path -LiteralPath $readyFlagFullPath) 'lock helper did not acquire the report file in time'

    & (Join-Path $repoRoot 'tools\run-real005-guangzhou-2015-2025-closure-standard.ps1') `
        -JsonReportPath $jsonReportRelativePath `
        -MarkdownReportPath $markdownReportRelativePath | Out-Null

    $reportJson = Get-Content -LiteralPath (Resolve-InRepoPath $jsonReportRelativePath) -Raw | ConvertFrom-Json
    Assert-True ([string] $reportJson.status -eq 'pass') 'REAL005 report write-lock contract expected status=pass'

    [ordered]@{
        status = 'pass'
        taskId = 'REAL005_REPORT_WRITE_LOCK_CONTRACT'
        checkedAt = (Get-Date).ToString('s')
        jsonReportPath = $jsonReportRelativePath.Replace('\', '/')
        markdownReportPath = $markdownReportRelativePath.Replace('\', '/')
        lockHoldMilliseconds = $LockHoldMilliseconds
        boundary = 'REAL005 report writer tolerates a transient read lock on the JSON report path'
    } | ConvertTo-Json -Depth 5
}
finally {
    if ($null -ne $locker) {
        Wait-Job -Id $locker.Id -ErrorAction SilentlyContinue | Out-Null
        Receive-Job -Id $locker.Id -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Id $locker.Id -Force -ErrorAction SilentlyContinue
    }
}
