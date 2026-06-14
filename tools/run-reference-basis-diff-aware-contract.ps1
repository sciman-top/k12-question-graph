param(
    [string] $GuardScriptPath = 'tools/run-reference-basis-guard.ps1',
    [string] $PolicyPath = 'tasks/reference-basis-policy.json',
    [string] $ReportPath = 'tmp/reference-basis-diff-aware-contract/report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string] $Path) {
    return Join-Path $repoRoot $Path
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$guardScriptFullPath = Resolve-RepoPath $GuardScriptPath
$policyFullPath = Resolve-RepoPath $PolicyPath
$reportFullPath = Resolve-RepoPath $ReportPath
$guardReportPath = 'tmp/reference-basis-diff-aware-contract/reference-basis-guard.json'
$guardMarkdownPath = 'tmp/reference-basis-diff-aware-contract/reference-basis-guard.md'
$guardReportFullPath = Resolve-RepoPath $guardReportPath

Assert-True (Test-Path -LiteralPath $guardScriptFullPath) "reference-basis guard missing: $guardScriptFullPath"
Assert-True (Test-Path -LiteralPath $policyFullPath) "reference-basis policy missing: $policyFullPath"

$policy = Get-Content -LiteralPath $policyFullPath -Raw | ConvertFrom-Json
Assert-True ($null -ne $policy.expectedTaskIds) 'reference-basis policy must define expectedTaskIds'
Assert-True ($null -ne $policy.expectedModuleIds) 'reference-basis policy must define expectedModuleIds'
Assert-True ($null -ne $policy.allowedAdoptionModes) 'reference-basis policy must define allowedAdoptionModes'

$changedPaths = @(
    'apps/web/src/App.tsx',
    'workers/document/worker.py'
)

New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null

& $guardScriptFullPath `
    -ValidationMode Ci `
    -PolicyPath $PolicyPath `
    -ChangedPaths $changedPaths `
    -JsonReportPath $guardReportPath `
    -MarkdownReportPath $guardMarkdownPath | Out-Null

Assert-True (Test-Path -LiteralPath $guardReportFullPath) "reference-basis diff-aware guard did not emit report: $guardReportFullPath"
$guardReport = Get-Content -LiteralPath $guardReportFullPath -Raw | ConvertFrom-Json

$moduleIds = @($guardReport.impactedModuleIds)
$taskIds = @($guardReport.impactedTaskIds)
$unmappedPaths = @($guardReport.changedPathsOutsideGuardedModules)

Assert-True ($guardReport.policyPath -eq $PolicyPath) "reference-basis guard must report policyPath = $PolicyPath"
Assert-True ($guardReport.changedPathCount -eq $changedPaths.Count) "reference-basis guard must report changedPathCount = $($changedPaths.Count)"
Assert-True ($moduleIds -contains 'WEB_TEACHER_WORKBENCH') 'reference-basis guard must map apps/web/src/App.tsx to WEB_TEACHER_WORKBENCH'
Assert-True ($moduleIds -contains 'DOCUMENT_IMPORT_OCR_FORMULA') 'reference-basis guard must map workers/document/worker.py to DOCUMENT_IMPORT_OCR_FORMULA'
Assert-True ($taskIds -contains 'NS1301') 'reference-basis guard must expose WEB_TEACHER_WORKBENCH task coverage'
Assert-True ($taskIds -contains 'P005') 'reference-basis guard must expose WEB_TEACHER_WORKBENCH live-pilot task coverage'
Assert-True ($taskIds -contains 'S004') 'reference-basis guard must expose worker OCR task coverage'
Assert-True ($taskIds -contains 'REAL010') 'reference-basis guard must expose formula fidelity task coverage'
Assert-True ($taskIds -contains 'NS1304') 'reference-basis guard must expose toolchain admission task coverage'
Assert-True ($unmappedPaths.Count -eq 0) ('reference-basis guard left changed paths unmapped: ' + ($unmappedPaths -join ', '))

$report = [ordered]@{
    status = 'pass'
    task = 'reference-basis diff-aware contract'
    checkedAt = (Get-Date).ToString('s')
    guardScriptPath = $GuardScriptPath
    policyPath = $PolicyPath
    changedPaths = $changedPaths
    impactedModuleIds = $moduleIds
    impactedTaskIds = $taskIds
    changedPathsOutsideGuardedModules = $unmappedPaths
    conclusion = 'diff-aware reference-basis coverage is wired for representative web and worker paths'
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
