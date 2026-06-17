param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/r005-public-multischool-deploy-eval-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-r005-public-multischool-deploy-eval-preflight.md',
    [string] $CompletionDashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $AutomationFirstPath = 'tasks/automation-first-contract.csv',
    [string] $ArchitecturePath = 'docs/03_Architecture.md',
    [string] $SecurityPrivacyPath = 'docs/17_SecurityPrivacyCompliance.md',
    [string] $N001EvidencePath = 'docs/evidence/20260505-n001-real-privacy-boundary-admission.md',
    [string] $P001ReportPath = '',
    [string] $DecisionPath = 'docs/decisions/ADR-007-public-multischool-deploy-admission.md',
    [string] $ReportPath = 'docs/evidence/20260521-r005-public-multischool-deploy-admission-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-RepoPath([string] $Path) {
    return Join-Path $repoRoot ($Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Read-JsonFile([string] $Path) {
    $fullPath = Resolve-RepoPath $Path
    Assert-True (Test-Path -LiteralPath $fullPath) "R005 required JSON evidence missing: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}
function Resolve-LatestEvidencePath([string] $Filter) {
    $evidenceRoot = Resolve-RepoPath 'docs/evidence'
    Assert-True (Test-Path -LiteralPath $evidenceRoot) 'R005 missing docs/evidence directory'
    $latest = @(Get-ChildItem -LiteralPath $evidenceRoot -Filter $Filter -File | Sort-Object Name -Descending | Select-Object -First 1)
    Assert-True ($latest.Count -eq 1) "R005 missing evidence matching filter: $Filter"
    return [System.IO.Path]::GetRelativePath($repoRoot, $latest[0].FullName).Replace('\', '/')
}

if ([string]::IsNullOrWhiteSpace($P001ReportPath)) {
    $P001ReportPath = Resolve-LatestEvidencePath '*-p001-live-pilot-readiness-preflight-report.json'
}


function Write-ContentIfChanged([string] $Path, [string] $Content) {
    $fullPath = Resolve-RepoPath $Path
    $parent = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $fullPath) {
        $existing = Get-Content -LiteralPath $fullPath -Raw
        if ($existing -eq $Content) { return }
    }

    Set-Content -LiteralPath $fullPath -Value $Content -Encoding UTF8
}

$rows = Import-Csv -LiteralPath (Resolve-RepoPath $BacklogPath) -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }
foreach ($id in @('P001', 'P006', 'R005')) {
    Assert-True ($byId.ContainsKey($id)) "R005 prerequisite task missing: $id"
}

$p001 = $byId['P001']
$p006 = $byId['P006']
$r005 = $byId['R005']
Assert-True ($r005.depends_on -eq 'P006') 'R005 must depend on P006'
Assert-True ($p001.status -eq '待办') 'P001 still pending; R005 must not skip isolated-machine pilot evidence'
Assert-True ($p006.status -eq '待办') 'P006 still pending; R005 must remain todo before release decision closes'
Assert-True ($r005.status -eq '待办') 'R005 must remain todo until public/multischool security privacy ADR evidence is completed'
Assert-True ($r005.acceptance -match '数据责任' -and $r005.acceptance -match '采购' -and $r005.acceptance -match '网络' -and $r005.acceptance -match '运维边界') 'R005 acceptance must require data/procurement/network/ops boundaries'

$checklist = Get-Content -LiteralPath (Resolve-RepoPath $ChecklistPath) -Raw
foreach ($keyword in @('SaaS', '多租户', 'security privacy ADR', '采购', '运维边界', 'fail-closed', 'tenant isolation', 'rollback')) {
    Assert-True ($checklist.Contains($keyword)) "R005 checklist missing keyword: $keyword"
}

$evidence = Get-Content -LiteralPath (Resolve-RepoPath $EvidencePath) -Raw
foreach ($keyword in @('preflight', 'R005', 'platform_na', 'gate_na', '公网', '下一步', 'fail-closed')) {
    Assert-True ($evidence.Contains($keyword)) "R005 evidence missing keyword: $keyword"
}

$architecture = Get-Content -LiteralPath (Resolve-RepoPath $ArchitecturePath) -Raw
foreach ($keyword in @('Windows-first', '校本局域网', '公网 SaaS', '数据、采购、隐私和网络约束不匹配')) {
    Assert-True ($architecture.Contains($keyword)) "R005 architecture evidence missing keyword: $keyword"
}

$securityPrivacy = Get-Content -LiteralPath (Resolve-RepoPath $SecurityPrivacyPath) -Raw
foreach ($keyword in @('deployment_jurisdiction', 'data_controller_or_owner', 'operator_or_processor', 'backup_encryption_or_acl_policy', 'retention_and_delete_policy')) {
    Assert-True ($securityPrivacy.Contains($keyword)) "R005 security/privacy evidence missing keyword: $keyword"
}

$n001Evidence = Get-Content -LiteralPath (Resolve-RepoPath $N001EvidencePath) -Raw
foreach ($keyword in @('辖区', '授权', '数据最小化', '外部模型禁用', 'synthetic/anonymized')) {
    Assert-True ($n001Evidence.Contains($keyword)) "N001 privacy evidence missing keyword: $keyword"
}

$decision = Get-Content -LiteralPath (Resolve-RepoPath $DecisionPath) -Raw
foreach ($keyword in @('ADR-007', 'fail-closed', 'Windows-first', 'public internet exposure', 'multi-school shared deployment', 'multi-tenant SaaS', 'tenant isolation', 'rollback')) {
    Assert-True ($decision.Contains($keyword)) "R005 ADR missing keyword: $keyword"
}

$dashboardRows = Import-Csv -LiteralPath (Resolve-RepoPath $CompletionDashboardPath) -Encoding UTF8
$dashboardByArea = @{}
foreach ($row in $dashboardRows) { $dashboardByArea[$row.area_id] = $row }
foreach ($areaId in @('deployment-install', 'live-pilot', 'backup-restore')) {
    Assert-True ($dashboardByArea.ContainsKey($areaId)) "completion dashboard missing area: $areaId"
}

$deploymentDashboard = $dashboardByArea['deployment-install']
$livePilotDashboard = $dashboardByArea['live-pilot']
$backupDashboard = $dashboardByArea['backup-restore']
Assert-True ($deploymentDashboard.current_state -eq 'contract_done') 'deployment-install must stay contract_done before P001'
Assert-True ($deploymentDashboard.usable_today -eq '不可发布使用') 'deployment-install must remain not releasable before isolated-machine proof'
Assert-True ($deploymentDashboard.blocking_gap -match '隔离机器') 'deployment-install must keep isolated-machine blocker'
Assert-True ($livePilotDashboard.current_state -eq 'contract_done') 'live-pilot must stay contract_done before P001/P006'
Assert-True ($livePilotDashboard.usable_today -eq '不可使用') 'live-pilot must remain unavailable before site evidence'
Assert-True ($backupDashboard.blocking_gap -match 'P001') 'backup-restore must keep P001 operational review boundary'

$automationRows = Import-Csv -LiteralPath (Resolve-RepoPath $AutomationFirstPath) -Encoding UTF8
$automationById = @{}
foreach ($row in $automationRows) { $automationById[$row.task_id] = $row }
Assert-True ($automationById.ContainsKey('R005')) 'automation-first contract missing R005 row'
$r005Automation = $automationById['R005']
Assert-True ($r005Automation.deterministic_precheck -match 'data responsibility|procurement|network|ops|boundary') 'R005 automation-first deterministic precheck must include data/procurement/network/ops checks'
Assert-True ($r005Automation.exception_policy -match 'SaaS|multi-tenant|without boundary') 'R005 automation-first exception policy must block SaaS/multi-tenant without boundary evidence'

$p001Report = Read-JsonFile $P001ReportPath
Assert-True ($p001Report.status -eq 'pass') 'P001 preflight report must pass before R005 can cite readiness evidence'
Assert-True ($p001Report.mode -eq 'preflight_only') 'P001 report must remain preflight_only'
Assert-True ($p001Report.p001CanClose -eq $false) 'P001 must not be closeable without isolated-machine proof'
foreach ($blocker in @('isolated_machine_install_wizard_not_executed', 'isolated_machine_backup_restore_not_executed', 'isolated_machine_role_audit_not_executed', 'isolated_machine_four_teacher_entry_smoke_not_executed')) {
    Assert-True (($p001Report.blockers -contains $blocker)) "P001 report missing blocker: $blocker"
}

$admissionMatrix = @(
    [ordered]@{
        deploymentKind = 'single_school_lan'
        currentDecision = 'preferred_default_after_p001_p006'
        currentEvidence = 'architecture default is Windows-first/LAN/single-school; P001/P006 are still pending, so this remains the target route but not release-closeable.'
        requiredBeforeRelease = @('P001 isolated-machine proof', 'P006 release decision', 'backup/restore rehearsal', 'role audit', 'teacher four-entry smoke')
        failClosedRule = '缺 P001/P006 现场证据时不得宣称可发布。'
    }
    [ordered]@{
        deploymentKind = 'public_internet_exposure'
        currentDecision = 'blocked'
        currentEvidence = 'no public exposure threat model, TLS/certificate plan, remote ops boundary, incident response owner, or traffic protection evidence.'
        requiredBeforeAdmission = @('network exposure design', 'TLS/certificate ownership', 'auth/access-control hardening', 'remote-ops runbook', 'incident response plan', 'rollback/disable switch')
        failClosedRule = '不得新增公网默认端口、反向代理、远程访问或公开下载入口。'
    }
    [ordered]@{
        deploymentKind = 'multi_school_shared_deployment'
        currentDecision = 'blocked'
        currentEvidence = 'no cross-school data responsibility, procurement主体, support/SLA boundary, or data export/exit responsibility evidence.'
        requiredBeforeAdmission = @('data controller/processor split', 'procurement owner', 'DPA/SLA', 'support responsibility', 'school-level data export', 'exit plan')
        failClosedRule = '不得把单校数据、账号、备份或学情分析合并成跨校共享事实源。'
    }
    [ordered]@{
        deploymentKind = 'multi_tenant_saas'
        currentDecision = 'blocked'
        currentEvidence = 'no tenant isolation, permission isolation, audit isolation, backup isolation, key rotation, or vendor exit evidence.'
        requiredBeforeAdmission = @('tenant isolation', 'permission isolation', 'audit isolation', 'backup isolation', 'key rotation', 'vendor exit plan')
        failClosedRule = '不得新增多租户生产 schema、跨校账号池、集中备份或 SaaS 默认运行模式。'
    }
)

$blockers = @(
    'R005 remains todo because P006 release decision is not closed.',
    'P001 isolated-machine install/backup/role-audit/four-entry smoke is still not executed.',
    'No procurement owner, DPA/SLA, cross-school data responsibility, or operator/processor contract exists.',
    'No public network exposure threat model, TLS/certificate owner, incident response owner, or rollback/disable switch exists.',
    'No tenant isolation, backup isolation, audit isolation, key rotation, or vendor exit evidence exists.'
)

$report = [ordered]@{
    status = 'pass'
    taskId = 'R005'
    mode = 'admission_preflight'
    checkedAt = (Get-Date).ToString('s')
    p001Status = $p001.status
    p006Status = $p006.status
    r005Status = $r005.status
    closeTaskAllowed = $false
    currentDecision = 'keep_R005_todo_fail_closed_for_public_multischool'
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    referencedEvidence = [ordered]@{
        architecture = $ArchitecturePath
        securityPrivacy = $SecurityPrivacyPath
        n001Evidence = $N001EvidencePath
        p001Report = $P001ReportPath
        completionDashboard = $CompletionDashboardPath
        automationFirstContract = $AutomationFirstPath
        decision = $DecisionPath
    }
    currentState = [ordered]@{
        deploymentInstallState = [string] $deploymentDashboard.current_state
        deploymentInstallUsableToday = [string] $deploymentDashboard.usable_today
        livePilotState = [string] $livePilotDashboard.current_state
        livePilotUsableToday = [string] $livePilotDashboard.usable_today
        p001CanClose = [bool] $p001Report.p001CanClose
        p001ReadyForIsolatedMachineRun = [bool] $p001Report.readyForIsolatedMachineRun
    }
    admissionMatrix = $admissionMatrix
    blockers = $blockers
    nextRequiredEvidence = @(
        'P001 isolated-machine evidence for install wizard, backup/restore, role audit, and four teacher-entry smokes',
        'P006 release decision record with rollback and privacy evidence',
        'security privacy ADR feature admission for public/multischool deployment',
        'procurement/DPA/SLA/operator responsibility evidence',
        'tenant/network/backup/audit isolation design with rollback and exit plan'
    )
    boundary = 'R005 only refreshes public/multischool deployment admission evidence and ADR-007; it performs no network exposure, no deployment config mutation, no tenant schema change, no production write, and no release-state transition.'
    rollback = 'revert tools/run-r005-public-multischool-deploy-eval-preflight-contract.ps1, docs/templates/r005-public-multischool-deploy-eval-checklist.md, docs/decisions/ADR-007-public-multischool-deploy-admission.md, tasks/backlog.csv, and remove the generated R005 admission report.'
}

$json = $report | ConvertTo-Json -Depth 10
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 10
