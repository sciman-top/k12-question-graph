$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$backlogPath = Join-Path $repoRoot 'tasks\backlog.csv'
$rows = Import-Csv -LiteralPath $backlogPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) {
    $byId[$row.id] = $row
}

foreach ($requiredId in @('C002', 'D001', 'D002', 'D003')) {
    if (-not $byId.ContainsKey($requiredId)) {
        throw "missing backlog task: $requiredId"
    }
}

$c002 = $byId['C002']
$d001 = $byId['D001']
if ($c002.status -ne '已完成') {
    $blocked = $rows | Where-Object {
        $_.phase -in @('P3', 'P4', 'P5', 'P6') -and $_.status -eq '已完成'
    }
    if (@($blocked).Count -gt 0) {
        $productionCompleted = $blocked | Where-Object {
            $_.acceptance -notmatch 'draft|test|schema|接口|Evals|成本日志|人工审核|迁移建议|不接真实模型|不进入实现'
        }
        if (@($productionCompleted).Count -gt 0) {
            $ids = ($productionCompleted | Select-Object -ExpandProperty id) -join ','
            throw "production P3+ tasks cannot be completed before formal C002: $ids"
        }
    }
}

if ($c002.acceptance -notmatch '教师录入|导入|来源|教材|课程标准|真题|draft|迁移|替换') {
    throw "C002 acceptance must preserve draft/test and teacher/source-derived formal upgrade semantics"
}

[ordered]@{
    status = 'pass'
    c002Status = $c002.status
    d001DependsOn = $d001.depends_on
    p3ProductionBlockedUntilFormalC002 = ($c002.status -ne '已完成')
    p3DraftTestAllowed = $true
} | ConvertTo-Json
