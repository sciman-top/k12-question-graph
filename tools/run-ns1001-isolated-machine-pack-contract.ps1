param(
    [string] $PackReportPath = '',
    [string] $ExecutionPackScriptPath = 'tools/run-ns1001-isolated-machine-execution-pack.ps1',
    [string] $ImportScriptPath = 'tools/run-ns1001-isolated-machine-evidence-import.ps1',
    [string] $EvidenceTemplatePath = 'docs/templates/p001-isolated-machine-evidence-template.md',
    [string] $EvidenceJsonTemplatePath = 'docs/templates/p001-isolated-machine-evidence-template.json',
    [string] $ChecklistPath = 'docs/templates/p001-live-pilot-release-checklist.md',
    [string] $ReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Resolve-InRepoPath([string] $RelativePath) {
    return Join-Path $repoRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Resolve-FlexiblePath([string] $PathValue) {
    $fullPath = if ([System.IO.Path]::IsPathRooted($PathValue)) {
        $PathValue
    }
    else {
        Resolve-InRepoPath $PathValue
    }
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing path: $PathValue"
    return (Resolve-Path -LiteralPath $fullPath).Path
}

Push-Location $repoRoot
try {
    if ([string]::IsNullOrWhiteSpace($ReportPath)) {
        $ReportPath = 'docs/evidence/{0}-ns1001-isolated-machine-pack-contract.json' -f (Get-Date -Format 'yyyyMMdd')
    }

    if ([string]::IsNullOrWhiteSpace($PackReportPath)) {
        $latestPackReport = Get-ChildItem -LiteralPath (Resolve-InRepoPath 'docs/evidence') -File -Filter '*-ns1001-isolated-machine-execution-pack.json' |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -eq $latestPackReport) {
            $executionPackScriptFullPath = Resolve-FlexiblePath $ExecutionPackScriptPath
            & $executionPackScriptFullPath | Out-Null
            $latestPackReport = Get-ChildItem -LiteralPath (Resolve-InRepoPath 'docs/evidence') -File -Filter '*-ns1001-isolated-machine-execution-pack.json' |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
        }
        Assert-Condition ($null -ne $latestPackReport) 'missing NS1001 execution-pack report after pack generation'
        $PackReportPath = [System.IO.Path]::GetRelativePath($repoRoot, $latestPackReport.FullName).Replace('\', '/')
    }

    $packReportFullPath = Resolve-FlexiblePath $PackReportPath
    $importScriptFullPath = Resolve-FlexiblePath $ImportScriptPath
    $templateFullPath = Resolve-FlexiblePath $EvidenceTemplatePath
    $templateJsonFullPath = Resolve-FlexiblePath $EvidenceJsonTemplatePath
    $checklistFullPath = Resolve-FlexiblePath $ChecklistPath

    $packReport = Get-Content -LiteralPath $packReportFullPath -Raw | ConvertFrom-Json
    $templateText = Get-Content -LiteralPath $templateFullPath -Raw
    $templateJson = Get-Content -LiteralPath $templateJsonFullPath -Raw | ConvertFrom-Json
    $checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
    $importScriptText = Get-Content -LiteralPath $importScriptFullPath -Raw

    Assert-Condition ($packReport.status -eq 'pass') 'NS1001 pack report must pass'
    Assert-Condition ($packReport.mode -eq 'isolated_machine_execution_pack') 'NS1001 pack report mode mismatch'
    Assert-Condition ([bool]$packReport.readyForIsolatedMachineRun) 'NS1001 pack report must keep readyForIsolatedMachineRun=true'
    Assert-Condition (-not [bool]$packReport.p001CanClose) 'NS1001 pack report must keep p001CanClose=false'

    $packRootFullPath = Resolve-FlexiblePath ([string]$packReport.packRoot)
    $manifestFullPath = Resolve-FlexiblePath ([string]$packReport.manifestPath)
    $manifest = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json
    Assert-Condition ($manifest.schemaVersion -eq 'ns1001-execution-pack-manifest.v1') 'NS1001 manifest schema mismatch'

    foreach ($relativePath in @(
        'docs/p001-live-pilot-release-checklist.md',
        'docs/p001-isolated-machine-evidence-template.md',
        'return/p001-isolated-machine-evidence.md',
        'return/p001-isolated-machine-evidence.json',
        'instructions/README.md',
        'release/windows-service-package/api/K12QuestionGraph.Api.exe',
        'release/upgrade-bundle/migrations/efbundle.exe'
    )) {
        Assert-Condition (Test-Path -LiteralPath (Join-Path $packRootFullPath $relativePath)) "NS1001 pack missing file: $relativePath"
    }

    foreach ($keyword in @(
        'P001 / NS1001',
        '操作者签收',
        '打印 / 网络 / 权限域',
        'docs/evidence/<date>-p001-isolated-machine.md'
    )) {
        Assert-Condition ($templateText.Contains($keyword)) "NS1001 template missing keyword: $keyword"
    }

    Assert-Condition ($templateJson.schemaVersion -eq 'p001-isolated-machine-evidence.v1') 'NS1001 json template schema mismatch'
    foreach ($keyword in @(
        '隔离机器',
        '安装向导',
        '备份',
        '恢复',
        '权限审计',
        'p001-isolated-machine-evidence-template.md'
    )) {
        Assert-Condition ($checklistText.Contains($keyword)) "NS1001 checklist missing keyword: $keyword"
    }

    foreach ($keyword in @(
        'closeP001Allowed',
        'returned attachments must include at least one real file',
        'signoff.decision must be continue_p002 or keep_blocked',
        'NS1001 import validates and archives returned isolated-machine evidence'
    )) {
        Assert-Condition ($importScriptText.Contains($keyword)) "NS1001 import script missing keyword: $keyword"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1001'
        checkedAt = (Get-Date).ToString('s')
        mode = 'isolated_machine_pack_contract'
        packReportPath = $PackReportPath
        manifestPath = [string]$packReport.manifestPath
        importScriptPath = $ImportScriptPath
        acceptance = [ordered]@{
            packReportPasses = $true
            manifestPresent = $true
            releaseArtifactsPresent = $true
            returnTemplatesPresent = $true
            importScriptPresent = $true
            p001StillOpen = $true
        }
        verification = [ordered]@{
            build = 'gate_na: NS1001 pack contract validates packaged artifacts only'
            test = 'execution-pack report + manifest + return-template + import-script keyword checks'
            contractInvariant = 'execution pack and import script must both exist before isolated-machine rehearsal can be handed off'
            hotspot = 'gate_na: contract does not execute isolated-machine install or import returned field evidence'
        }
        boundary = 'NS1001 pack contract proves the repo now has both a handoff pack and a return-import validator. It does not create live field evidence and does not close P001.'
        reportPath = $ReportPath
        rollback = "git restore tools/run-gates.ps1 tools/README.md tasks/non-site-implementation-plan.csv; git clean -f -- tools/run-ns1001-isolated-machine-pack-contract.ps1 tools/run-ns1001-isolated-machine-execution-pack.ps1 tools/run-ns1001-isolated-machine-evidence-import.ps1 docs/templates/p001-isolated-machine-evidence-template.json"
    }

    $reportFullPath = Resolve-InRepoPath $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    Pop-Location
}
