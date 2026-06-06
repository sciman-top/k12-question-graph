param(
    [string] $ReportPath = 'docs/evidence/20260606-ns1306-agent-tool-orchestration.json',
    [string] $ManifestPath = 'configs/agent-tool-orchestration.allowlist.json',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $NonSitePlanPath = 'tasks/non-site-implementation-plan.csv',
    [string] $AutomationContractPath = 'tasks/automation-first-contract.csv',
    [string] $ArchitecturePath = 'docs/03_Architecture.md',
    [string] $TechnologyStackPath = 'docs/04_TechnologyStack.md',
    [string] $TaskBreakdownPath = 'docs/20_TaskBreakdown.md',
    [string] $ProductizationPlanPath = 'docs/99_ProductizationFullRoadmapAndTaskPlan.md',
    [string] $ToolsReadmePath = 'tools/README.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-InRepoPath([string] $RelativePath) {
    return Join-Path $repoRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Read-JsonFile([string] $RelativePath) {
    $fullPath = Resolve-InRepoPath $RelativePath
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing json file: $RelativePath"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json -Depth 20
}

function Get-RequiredRow([object[]] $Rows, [string] $Id, [string] $Column = 'id') {
    $matches = @($Rows | Where-Object { [string]$_.$Column -eq $Id })
    Assert-Condition ($matches.Count -eq 1) "expected exactly one $Column=$Id row"
    return $matches[0]
}

function Assert-TextContains([string] $Text, [string[]] $Needles, [string] $Label) {
    foreach ($needle in $Needles) {
        Assert-Condition ($Text.Contains($needle)) "$Label missing text: $needle"
    }
}

Push-Location $repoRoot
try {
    $manifest = Read-JsonFile $ManifestPath
    Assert-Condition ([string]$manifest.manifestVersion -eq 'agent-tool-orchestration-allowlist.v1') 'unexpected NS1306 manifest version'
    Assert-Condition ([string]$manifest.role -eq 'tool_orchestration_agent') 'NS1306 manifest role must be tool_orchestration_agent'
    Assert-Condition ([bool]$manifest.allOtherToolsBlockedByDefault) 'NS1306 manifest must block all non-allowlisted tools by default'

    $allowedTools = @($manifest.allowedTools)
    $allowedRunbooks = @($manifest.allowedRunbooks)
    $blockedScripts = @($manifest.blockedScripts | ForEach-Object { [string]$_ })

    Assert-Condition ($allowedTools.Count -ge 12) 'NS1306 requires at least 12 allowlisted tools'
    Assert-Condition ($allowedRunbooks.Count -ge 6) 'NS1306 requires runbook/checklist inventory'
    Assert-Condition ($blockedScripts.Count -ge 5) 'NS1306 requires explicit blocked high-risk scripts'

    $toolIds = @{}
    $categorySet = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($tool in $allowedTools) {
        $toolId = [string]$tool.id
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($toolId)) 'NS1306 allowlisted tool id must not be blank'
        Assert-Condition (-not $toolIds.ContainsKey($toolId)) "duplicate NS1306 allowlisted tool id: $toolId"
        $toolIds[$toolId] = $true

        $toolPath = [string]$tool.path
        Assert-Condition ($toolPath.StartsWith('tools/')) "allowlisted tool must live under tools/: $toolPath"
        Assert-Condition (Test-Path -LiteralPath (Resolve-InRepoPath $toolPath)) "allowlisted tool missing: $toolPath"
        Assert-Condition (-not [bool]$tool.writesProductionData) "allowlisted tool must not write production data: $toolPath"
        Assert-Condition (-not [bool]$tool.handlesRealStudentData) "allowlisted tool must not handle real student data: $toolPath"
        Assert-Condition (-not [bool]$tool.allowActiveWrite) "allowlisted tool must not allow active write: $toolPath"
        Assert-Condition (-not [bool]$tool.allowExternalAiCalls) "allowlisted tool must not allow external AI calls: $toolPath"

        $category = [string]$tool.category
        $null = $categorySet.Add($category)

        $evidencePaths = @($tool.evidencePaths | ForEach-Object { [string]$_ })
        Assert-Condition ($evidencePaths.Count -ge 1) "allowlisted tool missing evidence path: $toolPath"
        foreach ($evidencePath in $evidencePaths) {
            Assert-Condition (Test-Path -LiteralPath (Resolve-InRepoPath $evidencePath)) "allowlisted tool evidence missing: $evidencePath"
        }
    }

    foreach ($requiredCategory in @(
        'preflight_refresh',
        'preflight_dashboard',
        'status_sync',
        'environment_diagnostic',
        'report_generation',
        'golden_registry',
        'candidate_dry_run',
        'security_eval',
        'visual_review'
    )) {
        Assert-Condition ($categorySet.Contains($requiredCategory)) "NS1306 allowlist missing category: $requiredCategory"
    }

    foreach ($runbook in $allowedRunbooks) {
        $runbookPath = [string]$runbook.path
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($runbookPath)) 'NS1306 allowlisted runbook path must not be blank'
        Assert-Condition (Test-Path -LiteralPath (Resolve-InRepoPath $runbookPath)) "allowlisted runbook missing: $runbookPath"
    }

    foreach ($blockedScript in $blockedScripts) {
        Assert-Condition (Test-Path -LiteralPath (Resolve-InRepoPath $blockedScript)) "blocked script missing: $blockedScript"
    }

    $backlogRows = @(Import-Csv -LiteralPath (Resolve-InRepoPath $BacklogPath) -Encoding UTF8)
    $planRows = @(Import-Csv -LiteralPath (Resolve-InRepoPath $NonSitePlanPath) -Encoding UTF8)
    $automationRows = @(Import-Csv -LiteralPath (Resolve-InRepoPath $AutomationContractPath) -Encoding UTF8)

    $ns1306Backlog = Get-RequiredRow $backlogRows 'NS1306'
    $ns1306Plan = Get-RequiredRow $planRows 'NS1306'
    $ns1306Automation = Get-RequiredRow $automationRows 'NS1306' 'task_id'

    Assert-Condition ([string]$ns1306Backlog.depends_on -eq 'NS1305') 'NS1306 backlog row must depend on NS1305'
    Assert-Condition ([string]$ns1306Plan.depends_on -eq 'NS1305') 'NS1306 non-site plan row must depend on NS1305'
    Assert-Condition ([string]$ns1306Backlog.acceptance -match 'allowlisted tool runbook') 'NS1306 backlog acceptance must keep allowlisted tool/runbook boundary'
    Assert-Condition ([string]$ns1306Automation.deterministic_precheck -match 'allowlisted tool runbook') 'NS1306 automation-first deterministic precheck must mention allowlisted tool/runbook'
    Assert-Condition ([string]$ns1306Automation.exception_policy -match 'allowlist|production active write|real data') 'NS1306 exception policy must block out-of-allowlist or production actions'

    foreach ($docPath in @($ArchitecturePath, $TechnologyStackPath, $TaskBreakdownPath, $ProductizationPlanPath)) {
        $docText = Get-Content -LiteralPath (Resolve-InRepoPath $docPath) -Raw
        Assert-TextContains $docText @('allowlisted tool/runbook') $docPath
    }

    $toolsReadmeText = Get-Content -LiteralPath (Resolve-InRepoPath $ToolsReadmePath) -Raw
    Assert-Condition ($toolsReadmeText.Contains('NS904') -and $toolsReadmeText.Contains('NS906')) 'tools/README must already expose NS904 and NS906 evidence chain'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1306'
        checkedAt = (Get-Date).ToString('s')
        mode = 'agent_tool_orchestration_boundary'
        productionEligible = $false
        realStudentDataUsed = $false
        externalAiCalls = 0
        allowlistedToolCount = $allowedTools.Count
        allowlistedRunbookCount = $allowedRunbooks.Count
        blockedScriptCount = $blockedScripts.Count
        categoryCoverage = @($categorySet | Sort-Object)
        allowlistedToolIds = @($allowedTools | ForEach-Object { [string]$_.id })
        blockedScripts = $blockedScripts
        boundary = [ordered]@{
            allOtherToolsBlockedByDefault = [bool]$manifest.allOtherToolsBlockedByDefault
            allowActiveWrite = [bool]$manifest.defaultBoundary.allowActiveWrite
            allowRestoreApply = [bool]$manifest.defaultBoundary.allowRestoreApply
            allowReleaseSignoff = [bool]$manifest.defaultBoundary.allowReleaseSignoff
            allowExternalAiCalls = [bool]$manifest.defaultBoundary.allowExternalAiCalls
            requiresHumanApprovalFor = @($manifest.defaultBoundary.requiresHumanApprovalFor | ForEach-Object { [string]$_ })
        }
        acceptance = [ordered]@{
            inventoryLocked = $true
            outOfAllowlistBlocked = $true
            productionActionsBlocked = $true
            realStudentDataBlocked = $true
            reportEvidenceAvailable = $true
            backlogAndPlanAligned = $true
        }
        summaryChinese = [ordered]@{
            title = 'NS1306 AI agent 工具执行编排边界报告'
            result = '通过'
            boundary = '当前只允许 agent 编排低风险、只读或 dry-run 工具；默认阻断 active switch、restore apply、release sign-off 和真实学生数据外传。'
            next = '下一步进入 NS1307，把 golden set、visual surrogate 和 LLM security 串成组合 gate。'
        }
        rollback = 'git restore configs/agent-tool-orchestration.allowlist.json tools/run-ns1306-agent-tool-orchestration-contract.ps1 tools/run-gates.ps1 tools/README.md'
    }

    $reportFullPath = Resolve-InRepoPath $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}
