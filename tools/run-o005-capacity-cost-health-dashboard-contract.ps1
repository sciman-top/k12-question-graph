param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $Report = 'docs\evidence\o005-capacity-cost-health-dashboard-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Push-Location $repoRoot
try {
    $g002Raw = .\tools\run-g002-storage-cleanup-contract.ps1
    $g002 = $g002Raw | ConvertFrom-Json
    Assert-Condition ($g002.status -eq 'pass') 'O005 dependency G002 did not pass'

    $d002Raw = .\tools\run-d002-ai-job-cost-contract.ps1 `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -PgBin $PgBin
    $d002 = $d002Raw | ConvertFrom-Json
    Assert-Condition ($d002.status -eq 'pass') 'O005 dependency D002 did not pass'

    $adminPanel = Get-Content -LiteralPath 'apps\web\src\ui\AdminGovernancePanels.tsx' -Raw
    foreach ($pattern in @(
        'data-flow="admin-storage-dashboard"',
        'data-contract="storage-summary"',
        'data-contract="cache-cleanup-configured-root"',
        'data-contract="no-production-data-delete"',
        'data-flow="knowledge-asset-health-dashboard"'
    )) {
        Assert-Condition ($adminPanel.Contains($pattern)) "O005 dashboard marker missing: $pattern"
    }

    $app = Get-Content -LiteralPath 'apps\web\src\App.tsx' -Raw
    Assert-Condition ($app.Contains("{ state: 'failed', label: '失败'")) 'O005 failed task signal marker missing in App.tsx'

    $l006EvidencePath = 'docs\evidence\20260505-l006-cost-cache-batch-dashboard-pilot.md'
    Assert-Condition (Test-Path -LiteralPath $l006EvidencePath) 'O005 requires L006 pilot evidence markdown'
    $l006Evidence = Get-Content -LiteralPath $l006EvidencePath -Raw
    foreach ($keyword in @('任务成本', 'cache hit', '模型路由', '异常失败原因', '管理员可见')) {
        Assert-Condition ($l006Evidence.Contains($keyword)) "O005 L006 evidence missing keyword: $keyword"
    }

    $reportObject = [ordered]@{
        status = 'pass'
        task = 'O005'
        mode = 'draft_test'
        productionEligible = $false
        dependencies = [ordered]@{
            g002 = 'pass'
            d002 = 'pass'
            l006Evidence = 'present'
        }
        scope = [ordered]@{
            storage = 'file_store/backup/cache/logs size summary'
            cost = 'stub llm tokens/cost/routing metrics in AI job contract'
            failedTasks = 'UI includes failed state signal for operator diagnosis'
            cleanupSuggestion = 'cache-only cleanup with dry-run/apply split'
        }
        uiContracts = @(
            'admin-storage-dashboard',
            'storage-summary',
            'cache-cleanup-configured-root',
            'no-production-data-delete',
            'knowledge-asset-health-dashboard',
            'failed-task-state-signal'
        )
        evidence = [ordered]@{
            g002Report = 'docs/evidence/g002-storage-cleanup-report.json'
            l006Pilot = $l006EvidencePath
        }
        rollback = [ordered]@{
            code = 'git revert this O005 commit'
            data = 'cleanup only synthetic tmp folders created by dependency contracts'
        }
        summaryChinese = [ordered]@{
            title = 'O005 容量和成本健康面板合同报告'
            result = '通过'
            boundary = '管理员可见容量/成本/失败信号与清理建议；仅允许缓存清理，禁止触达正式生产资产。'
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Report) -Force | Out-Null
    $reportObject | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Report -Encoding UTF8
    $reportObject | ConvertTo-Json -Depth 10
}
finally {
    Pop-Location
}
