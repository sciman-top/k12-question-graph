param(
    [string] $ReportPath = 'tmp/verification/no-active-write.json',
    [string] $EvidenceIndexPath = 'docs/evidence/index.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Read-RepoJson([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "required no-active-write input is missing: $Path"
    }
    return Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$readiness = Read-RepoJson 'configs/ai-evals/c002q0-outer-ai-readiness.sample.json'
$dryRun = Read-RepoJson 'configs/ai-evals/c002q-ai-extract-dry-run.sample.json'
$appSettings = Read-RepoJson 'apps/api/appsettings.json'
$index = Read-RepoJson $EvidenceIndexPath
$real005Entry = @($index.entries | Where-Object id -eq 'real005-closure-standard')
if ($real005Entry.Count -ne 1) {
    throw 'evidence index must contain exactly one REAL005 current entry'
}
$real005 = Read-RepoJson ([string]$real005Entry[0].currentPath)

if ($readiness.allowProjectRuntimeRealModelCalls -ne $false -or
    $readiness.noActiveWrite -ne $true -or
    $readiness.productionEligible -ne $false -or
    [string]$readiness.reviewStatus -ne 'pending_review') {
    throw 'AI readiness defaults must remain pending_review, no-active-write, and non-production'
}
if ($dryRun.allowRealModelCalls -ne $false -or
    [int]$dryRun.externalAiCalls -ne 0 -or
    $dryRun.noActiveWrite -ne $true -or
    $dryRun.productionEligible -ne $false -or
    [string]$dryRun.reviewStatus -ne 'pending_review') {
    throw 'AI dry-run defaults must remain local, pending_review, no-active-write, and non-production'
}
if ($appSettings.AiRouting.AllowRealModelCalls -ne $false) {
    throw 'appsettings AiRouting.AllowRealModelCalls must default to false'
}
if ([string]$real005.closureStatus -ne 'not_closed' -or $real005.fullClosureAllowed -ne $false) {
    throw 'REAL005 current evidence must remain not_closed and disallow full closure'
}

$report = [ordered]@{
    status = 'pass'
    checkedAt = (Get-Date).ToString('s')
    defaults = [ordered]@{
        allowRealModelCalls = $false
        externalAiCalls = 0
        reviewStatus = 'pending_review'
        productionEligible = $false
    }
    real005 = [ordered]@{
        currentPath = [string]$real005Entry[0].currentPath
        closureStatus = [string]$real005.closureStatus
        fullClosureAllowed = [bool]$real005.fullClosureAllowed
    }
    boundary = 'Focused configuration/current-evidence guard; product behavior is verified by the API tests run before this Release stage.'
}

$fullReportPath = Join-Path $repoRoot $ReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 6
