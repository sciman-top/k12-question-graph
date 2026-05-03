$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$backlogPath = Join-Path $repoRoot 'tasks\backlog.csv'
$rows = Import-Csv -LiteralPath $backlogPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) {
    $byId[$row.id] = $row
}

foreach ($requiredId in @('C002', 'C002P', 'C002Q0', 'C002Q', 'D001', 'D002', 'D003')) {
    if (-not $byId.ContainsKey($requiredId)) {
        throw "missing backlog task: $requiredId"
    }
}

$c002 = $byId['C002']
$c002q0 = $byId['C002Q0']
$c002q = $byId['C002Q']
$d001 = $byId['D001']
if ($d001.depends_on -eq 'C002') {
    throw "D001 must not depend on formal C002; use the dynamic asset draft/test gate such as C002H"
}

if ($c002q0.depends_on -ne 'C002P') {
    throw "C002Q0 must depend on C002P model budget guard"
}

if ($c002q.depends_on -ne 'C002Q0') {
    throw "C002Q must depend on C002Q0 orchestration readiness"
}

foreach ($pattern in @('subagent', '外层', '真实模型', 'no_active_write', '运行时依赖')) {
    if ($c002q0.acceptance -notmatch $pattern) {
        throw "C002Q0 acceptance missing orchestration boundary: $pattern"
    }
}

if ($c002.status -ne '已完成') {
    $blocked = $rows | Where-Object {
        $_.phase -in @('P3', 'P4', 'P5', 'P6') -and $_.status -eq '已完成'
    }
    if (@($blocked).Count -gt 0) {
        $productionCompleted = $blocked | Where-Object {
            $_.acceptance -notmatch 'draft|test|schema|接口|Evals|成本日志|人工审核|迁移建议|不接真实模型|不进入实现|synthetic|productionEligible=false|不具备生产资格|不等待正式|不依赖正式'
        }
        if (@($productionCompleted).Count -gt 0) {
            $ids = ($productionCompleted | Select-Object -ExpandProperty id) -join ','
            throw "production P3+ tasks cannot be completed before formal C002: $ids"
        }
    }
}

$futureDynamicTasks = $rows | Where-Object {
    $_.phase -in @('P4', 'P5', 'P6') -and $_.status -ne '已完成'
}
$missingDraftPlan = $futureDynamicTasks | Where-Object {
    $_.acceptance -notmatch 'draft|test|synthetic|动态|不等待正式|不要求正式|不使用真实|production'
}
if (@($missingDraftPlan).Count -gt 0) {
    $ids = ($missingDraftPlan | Select-Object -ExpandProperty id) -join ','
    throw "future P4+ tasks must state draft/test no-stop acceptance: $ids"
}

if ($c002.acceptance -notmatch '教师录入|导入|来源|教材|课程标准|真题|draft|迁移|替换') {
    throw "C002 acceptance must preserve draft/test and teacher/source-derived formal upgrade semantics"
}

[ordered]@{
    status = 'pass'
    c002Status = $c002.status
    d001DependsOn = $d001.depends_on
    productionDynamicAssetsBlockedUntilFormalC002 = ($c002.status -ne '已完成')
    draftTestSystemBuildAllowed = $true
    futureNoStopTasksChecked = @($futureDynamicTasks).Count
    noStopPolicy = 'dynamic assets may use draft/test fixtures while production activation remains blocked'
} | ConvertTo-Json
