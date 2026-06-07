param(
    [string] $ReportPath = '',
    [string] $PackRoot = '',
    [string] $P001ReportPath = '',
    [string] $NS904ReportPath = '',
    [string] $NS1308ReportPath = '',
    [string] $NS803ReportPath = '',
    [string] $NS804ReportPath = '',
    [string] $NS805ReportPath = '',
    [string] $NS806ReportPath = '',
    [string] $NS906ReportPath = '',
    [string] $REAL012ReportPath = 'docs/evidence/20260518-real012-production-flow-quality-report.json',
    [string] $ChecklistPath = 'docs/templates/p001-live-pilot-release-checklist.md',
    [string] $EvidenceTemplatePath = 'docs/templates/p001-isolated-machine-evidence-template.md',
    [string] $EvidenceJsonTemplatePath = 'docs/templates/p001-isolated-machine-evidence-template.json',
    [string] $OperatorOnePagerPath = 'docs/templates/p001-isolated-machine-operator-onepager.md',
    [string] $P005TriageTemplatePath = 'docs/templates/p005-pilot-feedback-triage-template.json',
    [string] $P005TriageRecordPath = 'docs/templates/p005-pilot-feedback-triage-record.md',
    [string] $P006DecisionTemplatePath = 'docs/templates/p006-release-decision-record-template.json',
    [string] $P006DecisionRecordPath = 'docs/templates/p006-release-decision-record.md',
    [string] $ReleaseCardPath = 'docs/109_ReleaseGoNoGoCard.md'
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
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($PathValue)) 'path value must not be empty'
    $fullPath = if ([System.IO.Path]::IsPathRooted($PathValue)) {
        $PathValue
    }
    else {
        Resolve-InRepoPath $PathValue
    }
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing path: $PathValue"
    return (Resolve-Path -LiteralPath $fullPath).Path
}

function Get-LatestEvidencePath([string] $Pattern, [string] $ExplicitPath) {
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $null = Resolve-FlexiblePath $ExplicitPath
        return $ExplicitPath.Replace('\', '/')
    }

    $docsEvidenceRoot = Resolve-InRepoPath 'docs/evidence'
    $candidate = Get-ChildItem -LiteralPath $docsEvidenceRoot -File -Filter $Pattern |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    Assert-Condition ($null -ne $candidate) "missing evidence matching pattern: $Pattern"
    return [System.IO.Path]::GetRelativePath($repoRoot, $candidate.FullName).Replace('\', '/')
}

function Read-Json([string] $Path) {
    $fullPath = Resolve-FlexiblePath $Path
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Copy-AbsoluteFileIntoPack([string] $SourceFullPath, [string] $PackRootFullPath, [string] $TargetRelativePath) {
    Assert-Condition (Test-Path -LiteralPath $SourceFullPath -PathType Leaf) "missing file for pack: $SourceFullPath"
    $targetFullPath = Join-Path $PackRootFullPath $TargetRelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $targetFullPath) -Force | Out-Null
    Copy-Item -LiteralPath $SourceFullPath -Destination $targetFullPath -Force
}

function Copy-FlexibleFileIntoPack([string] $SourcePath, [string] $PackRootFullPath, [string] $TargetRelativePath) {
    $sourceFullPath = Resolve-FlexiblePath $SourcePath
    Copy-AbsoluteFileIntoPack -SourceFullPath $sourceFullPath -PackRootFullPath $PackRootFullPath -TargetRelativePath $TargetRelativePath
}

function Copy-AbsoluteDirectoryIntoPack([string] $SourceDirectoryFullPath, [string] $PackRootFullPath, [string] $TargetRelativePath) {
    Assert-Condition (Test-Path -LiteralPath $SourceDirectoryFullPath -PathType Container) "missing directory for pack: $SourceDirectoryFullPath"
    $targetDirectoryFullPath = Join-Path $PackRootFullPath $TargetRelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $targetDirectoryFullPath) -Force | Out-Null
    if (Test-Path -LiteralPath $targetDirectoryFullPath) {
        Remove-Item -LiteralPath $targetDirectoryFullPath -Recurse -Force
    }
    Copy-Item -LiteralPath $SourceDirectoryFullPath -Destination $targetDirectoryFullPath -Recurse -Force
}

function Write-TextFile([string] $FullPath, [string] $Content) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $FullPath) -Force | Out-Null
    Set-Content -LiteralPath $FullPath -Value $Content -Encoding UTF8
}

function Get-ManifestEntries([string] $PackRootFullPath) {
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($file in Get-ChildItem -LiteralPath $PackRootFullPath -Recurse -File | Sort-Object FullName) {
        $relativePath = [System.IO.Path]::GetRelativePath($PackRootFullPath, $file.FullName).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $entries.Add([ordered]@{
                path = $relativePath
                size = [int64]$file.Length
                sha256 = $hash
            })
    }
    return $entries
}

Push-Location $repoRoot
try {
    $resolvedP001ReportPath = Get-LatestEvidencePath '*-p001-live-pilot-readiness-preflight-report.json' $P001ReportPath
    $resolvedNS904ReportPath = Get-LatestEvidencePath '*-ns904-p001-readiness.json' $NS904ReportPath
    $resolvedNS1308ReportPath = Get-LatestEvidencePath '*-ns1308-release-evidence-pack.json' $NS1308ReportPath
    $resolvedNS803ReportPath = Get-LatestEvidencePath '*-ns803-installer-host.json' $NS803ReportPath
    $resolvedNS804ReportPath = Get-LatestEvidencePath '*-ns804-windows-service.json' $NS804ReportPath
    $resolvedNS805ReportPath = Get-LatestEvidencePath '*-ns805-health-dashboard.json' $NS805ReportPath
    $resolvedNS806ReportPath = Get-LatestEvidencePath '*-ns806-upgrade-bundle.json' $NS806ReportPath
    $resolvedNS906ReportPath = Get-LatestEvidencePath '*-ns906-visual-surrogate-review-report.json' $NS906ReportPath

    $p001 = Read-Json $resolvedP001ReportPath
    $ns904 = Read-Json $resolvedNS904ReportPath
    $ns1308 = Read-Json $resolvedNS1308ReportPath
    $ns803 = Read-Json $resolvedNS803ReportPath
    $ns804 = Read-Json $resolvedNS804ReportPath
    $ns805 = Read-Json $resolvedNS805ReportPath
    $ns806 = Read-Json $resolvedNS806ReportPath
    $ns906 = Read-Json $resolvedNS906ReportPath
    $real012 = Read-Json $REAL012ReportPath

    foreach ($dependency in @(
        @{ name = 'P001'; report = $p001 },
        @{ name = 'NS904'; report = $ns904 },
        @{ name = 'NS1308'; report = $ns1308 },
        @{ name = 'NS803'; report = $ns803 },
        @{ name = 'NS804'; report = $ns804 },
        @{ name = 'NS805'; report = $ns805 },
        @{ name = 'NS806'; report = $ns806 },
        @{ name = 'NS906'; report = $ns906 },
        @{ name = 'REAL012'; report = $real012 }
    )) {
        Assert-Condition ($dependency.report.status -eq 'pass') "NS1001 dependency $($dependency.name) must pass"
    }

    Assert-Condition ([bool]$p001.readyForIsolatedMachineRun) 'NS1001 execution pack requires readyForIsolatedMachineRun=true'
    Assert-Condition (-not [bool]$p001.p001CanClose) 'NS1001 execution pack must not start from a closed P001 state'
    Assert-Condition (-not [bool]$ns904.releaseReady) 'NS1001 execution pack must inherit releaseReady=false'
    Assert-Condition (-not [bool]$ns904.nonSiteValidated) 'NS1001 execution pack must inherit nonSiteValidated=false'
    Assert-Condition (-not [bool]$ns1308.productionEligible) 'NS1001 execution pack must inherit productionEligible=false'
    Assert-Condition ($real012.real005ClosureStatus -eq 'not_closed') 'NS1001 execution pack must keep REAL005 not_closed'

    $checklistFullPath = Resolve-FlexiblePath $ChecklistPath
    $templateFullPath = Resolve-FlexiblePath $EvidenceTemplatePath
    $templateJsonFullPath = Resolve-FlexiblePath $EvidenceJsonTemplatePath
    $operatorOnePagerFullPath = Resolve-FlexiblePath $OperatorOnePagerPath
    $p005TriageTemplateFullPath = Resolve-FlexiblePath $P005TriageTemplatePath
    $p005TriageRecordFullPath = Resolve-FlexiblePath $P005TriageRecordPath
    $p006DecisionTemplateFullPath = Resolve-FlexiblePath $P006DecisionTemplatePath
    $p006DecisionRecordFullPath = Resolve-FlexiblePath $P006DecisionRecordPath
    $releaseCardFullPath = Resolve-FlexiblePath $ReleaseCardPath

    $packTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    if ([string]::IsNullOrWhiteSpace($PackRoot)) {
        $PackRoot = "tmp/ns1001-execution-pack/$packTimestamp"
    }
    if ([string]::IsNullOrWhiteSpace($ReportPath)) {
        $ReportPath = "docs/evidence/{0}-ns1001-isolated-machine-execution-pack.json" -f (Get-Date -Format 'yyyyMMdd')
    }

    $packRootFullPath = Resolve-InRepoPath $PackRoot
    if (Test-Path -LiteralPath $packRootFullPath) {
        Remove-Item -LiteralPath $packRootFullPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $packRootFullPath -Force | Out-Null

    foreach ($pair in @(
        @{ source = $checklistFullPath; target = 'docs/p001-live-pilot-release-checklist.md' },
        @{ source = $templateFullPath; target = 'docs/p001-isolated-machine-evidence-template.md' },
        @{ source = $operatorOnePagerFullPath; target = 'docs/p001-isolated-machine-operator-onepager.md' },
        @{ source = $p005TriageTemplateFullPath; target = 'docs/p005-pilot-feedback-triage-template.json' },
        @{ source = $p005TriageRecordFullPath; target = 'docs/p005-pilot-feedback-triage-record.md' },
        @{ source = $p006DecisionTemplateFullPath; target = 'docs/p006-release-decision-record-template.json' },
        @{ source = $p006DecisionRecordFullPath; target = 'docs/p006-release-decision-record.md' },
        @{ source = $releaseCardFullPath; target = 'docs/109_ReleaseGoNoGoCard.md' },
        @{ source = Resolve-FlexiblePath $resolvedP001ReportPath; target = 'reports/p001-live-pilot-readiness-preflight-report.json' },
        @{ source = Resolve-FlexiblePath $resolvedNS904ReportPath; target = 'reports/ns904-p001-readiness.json' },
        @{ source = Resolve-FlexiblePath $resolvedNS1308ReportPath; target = 'reports/ns1308-release-evidence-pack.json' },
        @{ source = Resolve-FlexiblePath $resolvedNS803ReportPath; target = 'reports/ns803-installer-host.json' },
        @{ source = Resolve-FlexiblePath $resolvedNS804ReportPath; target = 'reports/ns804-windows-service.json' },
        @{ source = Resolve-FlexiblePath $resolvedNS805ReportPath; target = 'reports/ns805-health-dashboard.json' },
        @{ source = Resolve-FlexiblePath $resolvedNS806ReportPath; target = 'reports/ns806-upgrade-bundle.json' },
        @{ source = Resolve-FlexiblePath $resolvedNS906ReportPath; target = 'reports/ns906-visual-surrogate-review.json' },
        @{ source = Resolve-FlexiblePath $REAL012ReportPath; target = 'reports/real012-production-flow-quality-report.json' }
    )) {
        Copy-AbsoluteFileIntoPack -SourceFullPath $pair.source -PackRootFullPath $packRootFullPath -TargetRelativePath $pair.target
    }

    $supportingFileMap = [ordered]@{
        'reports/p001-preflight-evidence.md' = [string]$p001.evidencePath
        'reports/real005-closure-standard-report.json' = [string]$ns904.dependency.real005
        'reports/host-capability-diagnostic-report.json' = [string]$p001.diagnostics.hostCapability.path
        'reports/worker-profile-diagnostic-report.json' = [string]$p001.diagnostics.workerProfile.path
        'reports/technology-refresh-report.json' = [string]$p001.diagnostics.technologyRefresh.path
        'reports/ns803-pgpass-dry-run-report.json' = [string]$ns803.installer.postgresql.pgpassReport
        'reports/ns803-worker-profile-diagnostic-report.json' = [string]$ns803.installer.workerProfile.report
        'reports/ns803-host-capability-diagnostic-report.json' = [string]$ns803.installer.hostCapability.report
        'reports/ns805-backup-manifest.json' = [string]$ns805.dashboard.backup.manifest
        'reports/o007-ef-migration-bundle-upgrade-drill-report.json' = [string]$ns806.dependency.o007
        'reports/o007-o003-recovery-drill-report.json' = [string]$ns806.dependency.restoreDrill
    }

    foreach ($entry in $supportingFileMap.GetEnumerator()) {
        if (-not [string]::IsNullOrWhiteSpace($entry.Value)) {
            Copy-FlexibleFileIntoPack -SourcePath $entry.Value -PackRootFullPath $packRootFullPath -TargetRelativePath $entry.Key
        }
    }

    Copy-AbsoluteDirectoryIntoPack -SourceDirectoryFullPath (Resolve-FlexiblePath ([string]$ns804.package.packageRoot)) -PackRootFullPath $packRootFullPath -TargetRelativePath 'release/windows-service-package'
    Copy-AbsoluteDirectoryIntoPack -SourceDirectoryFullPath (Resolve-FlexiblePath ([string]$ns806.migrationBundle.releasePackageRoot)) -PackRootFullPath $packRootFullPath -TargetRelativePath 'release/upgrade-bundle'

    foreach ($logPair in @(
        @{ source = [string]$ns804.smoke.stdoutLog; target = 'reports/published-api.out.log' },
        @{ source = [string]$ns804.smoke.stderrLog; target = 'reports/published-api.err.log' },
        @{ source = [string]$ns806.migrationBundle.executionLog; target = 'reports/efbundle-run.log' }
    )) {
        if (-not [string]::IsNullOrWhiteSpace($logPair.source)) {
            Copy-FlexibleFileIntoPack -SourcePath $logPair.source -PackRootFullPath $packRootFullPath -TargetRelativePath $logPair.target
        }
    }

    $commitId = ''
    try {
        $commitId = (& git rev-parse --short HEAD 2>$null).Trim()
    }
    catch {
        $commitId = ''
    }

    $returnEvidenceJson = Get-Content -LiteralPath $templateJsonFullPath -Raw | ConvertFrom-Json
    $returnEvidenceJson.execution.packageVersion = if ([string]::IsNullOrWhiteSpace($commitId)) { '<package-version-or-commit>' } else { $commitId }
    $returnEvidenceJson.anchors.p001PreflightReport = $resolvedP001ReportPath
    $returnEvidenceJson.anchors.ns904ReadinessPack = $resolvedNS904ReportPath
    $returnEvidenceJson.anchors.ns1308ReleasePack = $resolvedNS1308ReportPath
    $returnEvidenceJson.anchors.real012QualityReport = $REAL012ReportPath.Replace('\', '/')
    $returnEvidenceJson.installInit.initLogPaths = @('return/attachments/init/<init-log-file>')
    $returnEvidenceJson.backupRestore.attachmentPaths = @('return/attachments/backup-restore/<backup-or-restore-artifact>')
    $returnEvidenceJson.roleAudit.auditLogPaths = @('return/attachments/audit/<audit-log>')
    $returnEvidenceJson.teacherEntrySmokes.import.attachmentPaths = @('return/attachments/import/<artifact-or-screenshot>')
    $returnEvidenceJson.teacherEntrySmokes.paperAssembly.attachmentPaths = @('return/attachments/paper/<artifact-or-screenshot>')
    $returnEvidenceJson.teacherEntrySmokes.scoreImport.attachmentPaths = @('return/attachments/score/<artifact-or-screenshot>')
    $returnEvidenceJson.teacherEntrySmokes.analysis.attachmentPaths = @('return/attachments/analysis/<artifact-or-screenshot>')
    $returnEvidenceJson.siteSpecific.attachmentPaths = @('return/attachments/site-specific/<printer-network-domain-artifact>')

    $returnEvidenceJsonFullPath = Join-Path $packRootFullPath 'return/p001-isolated-machine-evidence.json'
    Write-TextFile -FullPath $returnEvidenceJsonFullPath -Content ($returnEvidenceJson | ConvertTo-Json -Depth 12)
    Copy-AbsoluteFileIntoPack -SourceFullPath $templateFullPath -PackRootFullPath $packRootFullPath -TargetRelativePath 'return/p001-isolated-machine-evidence.md'
    Write-TextFile -FullPath (Join-Path $packRootFullPath 'return/attachments/README.md') -Content @'
# P001 return attachments

把隔离机现场生成的日志、截图、打印照片、导出文件、审计摘录等放到本目录的子文件夹中。

- `init/`：安装与初始化日志
- `backup-restore/`：备份、校验、恢复输出
- `audit/`：权限与审计相关输出
- `import/`：导入入口 smoke 证据
- `paper/`：组卷与导出证据
- `score/`：成绩入口证据
- `analysis/`：分析入口证据
- `site-specific/`：打印、网络、权限域、签收照片等

回仓后执行：
`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-ns1001-isolated-machine-evidence-import.ps1 -ReturnedPackRoot "<returned-pack-root>"`
'@

    $instructionLines = @(
        '# NS1001 isolated-machine execution pack',
        '',
        "生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "当前提交：$([string]::IsNullOrWhiteSpace($commitId) ? '<unknown>' : $commitId)",
        '',
        '## 本包包含',
        '- `release/windows-service-package/`：Windows Service 运行包',
        '- `release/upgrade-bundle/`：EF migration bundle 与升级演练包',
        '- `docs/`：P001 checklist、现场证据模板、P005/P006 记录模板、Go/No-Go 卡',
        '- `docs/p001-isolated-machine-operator-onepager.md`：给现场执行人的极简操作单',
        '- `reports/`：P001、NS904、NS1308、NS803-NS806、NS906、REAL012 等最新仓内证据',
        '- `return/`：现场回填 markdown/json 模板与附件目录',
        '',
        '## 现场执行顺序',
        '1. 先看 `docs/p001-isolated-machine-operator-onepager.md`，再按 `docs/p001-live-pilot-release-checklist.md` 执行。',
        '2. 把现场事实填入 `return/p001-isolated-machine-evidence.md` 与 `return/p001-isolated-machine-evidence.json`。',
        '3. 把日志、截图、打印照片、导出文件等放入 `return/attachments/` 对应子目录。',
        '4. 若现场已经产生反馈分流或发布裁决材料，同时填写 `docs/p005-pilot-feedback-triage-record.md` / `docs/p006-release-decision-record.md` 与对应 JSON 模板。',
        '5. 将整个执行包目录带回仓库所在机器。',
        '6. 回仓后执行：',
        '   `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-ns1001-isolated-machine-evidence-import.ps1 -ReturnedPackRoot "<returned-pack-root>"`',
        '',
        '## 真相边界',
        '- 该执行包不代表 `P001` 已完成。',
        '- 只有回仓校验报告明确 `closeP001Allowed=true` 且操作者签收允许继续时，才可以继续考虑 `P002`。',
        '- `REAL005` 仍必须保持其自身的 `not_closed` 语义，不得因为现场包存在而误报真卷全闭环完成。'
    )
    Write-TextFile -FullPath (Join-Path $packRootFullPath 'instructions/README.md') -Content ($instructionLines -join [Environment]::NewLine)

    $manifest = [ordered]@{
        schemaVersion = 'ns1001-execution-pack-manifest.v1'
        createdAt = (Get-Date).ToString('s')
        repoRoot = $repoRoot
        packRoot = $PackRoot.Replace('\', '/')
        currentCommit = $commitId
        sourceEvidence = [ordered]@{
            p001 = $resolvedP001ReportPath
            ns904 = $resolvedNS904ReportPath
            ns1308 = $resolvedNS1308ReportPath
            ns803 = $resolvedNS803ReportPath
            ns804 = $resolvedNS804ReportPath
            ns805 = $resolvedNS805ReportPath
            ns806 = $resolvedNS806ReportPath
            ns906 = $resolvedNS906ReportPath
            real012 = $REAL012ReportPath.Replace('\', '/')
        }
        requiredReturnFiles = @(
            'return/p001-isolated-machine-evidence.md',
            'return/p001-isolated-machine-evidence.json'
        )
        fileEntries = Get-ManifestEntries -PackRootFullPath $packRootFullPath
    }
    $manifestRelativePath = 'manifest.json'
    Write-TextFile -FullPath (Join-Path $packRootFullPath $manifestRelativePath) -Content ($manifest | ConvertTo-Json -Depth 12)

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1001'
        checkedAt = (Get-Date).ToString('s')
        mode = 'isolated_machine_execution_pack'
        productionEligible = $false
        readyForIsolatedMachineRun = [bool]$p001.readyForIsolatedMachineRun
        p001CanClose = $false
        packRoot = $PackRoot.Replace('\', '/')
        manifestPath = ($PackRoot.Replace('\', '/') + '/' + $manifestRelativePath)
        dependencies = [ordered]@{
            p001 = $resolvedP001ReportPath
            ns904 = $resolvedNS904ReportPath
            ns1308 = $resolvedNS1308ReportPath
            ns803 = $resolvedNS803ReportPath
            ns804 = $resolvedNS804ReportPath
            ns805 = $resolvedNS805ReportPath
            ns806 = $resolvedNS806ReportPath
            ns906 = $resolvedNS906ReportPath
            real012 = $REAL012ReportPath.Replace('\', '/')
        }
        includedArtifacts = [ordered]@{
            windowsServicePackage = 'release/windows-service-package'
            upgradeBundlePackage = 'release/upgrade-bundle'
            checklist = 'docs/p001-live-pilot-release-checklist.md'
            operatorOnePager = 'docs/p001-isolated-machine-operator-onepager.md'
            p005TriageTemplate = 'docs/p005-pilot-feedback-triage-template.json'
            p005TriageRecord = 'docs/p005-pilot-feedback-triage-record.md'
            p006DecisionTemplate = 'docs/p006-release-decision-record-template.json'
            p006DecisionRecord = 'docs/p006-release-decision-record.md'
            returnEvidenceMarkdown = 'return/p001-isolated-machine-evidence.md'
            returnEvidenceJson = 'return/p001-isolated-machine-evidence.json'
            returnAttachmentRoot = 'return/attachments'
            operatorInstructions = 'instructions/README.md'
        }
        inheritedSiteBlockers = @($ns904.remainingSiteBlockers | ForEach-Object { [string]$_.code })
        acceptance = [ordered]@{
            latestP001ReadinessEvidenceIncluded = $true
            latestNs13ReleaseEvidenceIncluded = $true
            windowsServicePackageIncluded = $true
            upgradeBundleIncluded = $true
            checklistIncluded = $true
            operatorOnePagerIncluded = $true
            p005TriageTemplatesIncluded = $true
            p006DecisionTemplatesIncluded = $true
            returnTemplatesIncluded = $true
            operatorInstructionsIncluded = $true
            p001StillTodo = $true
            releaseReadyStillFalse = $true
        }
        verification = [ordered]@{
            build = 'gate_na: NS1001 execution pack assembles previously-verified release artifacts and evidence'
            test = 'latest readiness/release reports are revalidated and copied into the execution pack with a sha256 manifest'
            contractInvariant = 'execution pack must package release artifacts, checklist, and return templates without claiming isolated-machine execution or P001 closure'
            hotspot = 'gate_na: this script does not execute isolated-machine install, teacher observation, printer/network/domain checks, or operator signoff'
        }
        boundary = 'NS1001 execution pack closes the repo-side collection gap for isolated-machine rehearsal. It does not create real isolated-machine evidence, does not close P001, and does not advance P002.'
        next = 'Transfer the execution pack to the isolated machine, fill the return evidence, then run tools/run-ns1001-isolated-machine-evidence-import.ps1 after the pack returns to the repo host.'
        rollback = "Remove-Item -LiteralPath '$packRootFullPath' -Recurse -Force; git restore tasks/non-site-implementation-plan.csv tools/README.md; git clean -f -- tools/run-ns1001-isolated-machine-execution-pack.ps1 $ReportPath docs/templates/p001-isolated-machine-evidence-template.json"
    }

    $reportFullPath = Resolve-InRepoPath $ReportPath
    Write-TextFile -FullPath $reportFullPath -Content ($report | ConvertTo-Json -Depth 12)
    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}
