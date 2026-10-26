Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CurrentTruth {
    param(
        [Parameter(Mandatory = $true)][string] $RepoRoot,
        [string] $IndexPath = 'docs/evidence/index.json',
        [string] $ReleaseCardPath = 'docs/109_ReleaseGoNoGoCard.md',
        [string] $ClosureSummaryPath = 'docs/CurrentClosureStatus.md'
    )

    $indexFullPath = Join-Path $RepoRoot $IndexPath
    $index = Get-Content -LiteralPath $indexFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $real005Entry = @($index.entries | Where-Object id -eq 'real005-closure-standard')
    if ($real005Entry.Count -ne 1) {
        throw 'evidence index must contain exactly one REAL005 current entry'
    }
    $real005Path = [string]$real005Entry[0].currentPath
    if ([string]::IsNullOrWhiteSpace($real005Path)) {
        throw 'REAL005 current evidence path is missing'
    }
    $real005FullPath = Join-Path $RepoRoot $real005Path
    if (-not (Test-Path -LiteralPath $real005FullPath -PathType Leaf)) {
        throw "REAL005 current evidence file is missing: $real005Path"
    }

    $real005 = Get-Content -LiteralPath $real005FullPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $releaseCardFullPath = Join-Path $RepoRoot $ReleaseCardPath
    $closureSummaryFullPath = Join-Path $RepoRoot $ClosureSummaryPath
    if (-not (Test-Path -LiteralPath $releaseCardFullPath -PathType Leaf)) {
        throw "release card is missing: $ReleaseCardPath"
    }
    if (-not (Test-Path -LiteralPath $closureSummaryFullPath -PathType Leaf)) {
        throw "closure summary is missing: $ClosureSummaryPath"
    }
    $releaseCardText = Get-Content -LiteralPath $releaseCardFullPath -Raw -Encoding UTF8
    $closureSummaryText = Get-Content -LiteralPath $closureSummaryFullPath -Raw -Encoding UTF8

    if ([string]$real005.closureStatus -ne 'not_closed' -or $real005.fullClosureAllowed -ne $false) {
        throw 'REAL005 must remain not_closed with fullClosureAllowed=false'
    }
    if ($releaseCardText -notmatch 'No-Go') {
        throw 'release card must remain No-Go'
    }
    if ($closureSummaryText -notmatch 'REAL005\s*=\s*not_closed') {
        throw 'current closure status must preserve REAL005 not_closed'
    }

    $releaseCardHash = (Get-FileHash -LiteralPath $releaseCardFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $closureHash = (Get-FileHash -LiteralPath $closureSummaryFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $real005EntryObject = [pscustomobject][ordered]@{
        id = [string]$real005Entry[0].id
        currentPath = $real005Path
        claimBoundary = [string]$real005Entry[0].claimBoundary
        closureStatus = [string]$real005.closureStatus
        fullClosureAllowed = [bool]$real005.fullClosureAllowed
    }
    [pscustomobject][ordered]@{
        kind = 'kqg-current-truth.v1'
        real005 = $real005EntryObject
        releaseDecision = 'No-Go'
        p001ThroughP006 = '待办'
        sourceHashes = [pscustomobject][ordered]@{
            real005Sha256 = (Get-FileHash -LiteralPath $real005FullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            releaseCardSha256 = $releaseCardHash
            closureSummarySha256 = $closureHash
        }
        truth = [pscustomobject][ordered]@{
            real005ClosureStatus = 'not_closed'
            fullClosureAllowed = $false
            releaseDecision = 'No-Go'
            p001ThroughP006 = '待办'
            real005RepoSide = '已完成'
            liveAccepted = $false
        }
        boundary = 'Canonical current truth only; it does not prove onsite, live, or signed release acceptance.'
    }
}

function Assert-CurrentTruthReceipt {
    param(
        [Parameter(Mandatory = $true)][string] $RepoRoot,
        [Parameter(Mandatory = $true)][string] $ReceiptPath,
        [string] $IndexPath = 'docs/evidence/index.json',
        [string] $ReleaseCardPath = 'docs/109_ReleaseGoNoGoCard.md',
        [string] $ClosureSummaryPath = 'docs/CurrentClosureStatus.md'
    )

    $fullReceiptPath = Join-Path $RepoRoot $ReceiptPath
    if (-not (Test-Path -LiteralPath $fullReceiptPath -PathType Leaf)) {
        throw "current truth receipt is missing: $ReceiptPath"
    }
    $receipt = Get-Content -LiteralPath $fullReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $expected = Get-CurrentTruth -RepoRoot $RepoRoot -IndexPath $IndexPath `
        -ReleaseCardPath $ReleaseCardPath -ClosureSummaryPath $ClosureSummaryPath
    if ([string]$receipt.kind -ne 'kqg-current-truth.v1' -or
        [string]$receipt.real005.currentPath -ne [string]$expected.real005.currentPath -or
        [string]$receipt.real005.closureStatus -ne 'not_closed' -or
        [bool]$receipt.real005.fullClosureAllowed -ne $false -or
        [string]$receipt.releaseDecision -ne 'No-Go' -or
        [string]$receipt.p001ThroughP006 -ne '待办') {
        throw 'current truth receipt contradicts repository truth'
    }
    if ([string]$receipt.sourceHashes.real005Sha256 -ne [string]$expected.sourceHashes.real005Sha256 -or
        [string]$receipt.sourceHashes.releaseCardSha256 -ne [string]$expected.sourceHashes.releaseCardSha256 -or
        [string]$receipt.sourceHashes.closureSummarySha256 -ne [string]$expected.sourceHashes.closureSummarySha256) {
        throw 'current truth receipt is stale against current evidence sources'
    }
    return $receipt
}

Export-ModuleMember -Function Get-CurrentTruth, Assert-CurrentTruthReceipt
