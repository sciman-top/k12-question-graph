param(
    [string] $AdmissionDocPath = 'docs\25_FeatureAdmissionCriteria.md',
    [string] $ReadinessReportPath = 'docs\evidence\c002q0-outer-ai-readiness-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$admissionDoc = Get-Content -LiteralPath (Join-Path $repoRoot $AdmissionDocPath) -Raw
foreach ($keyword in @(
    '功能准入卡',
    '外部模型或第三方工具是否接收数据',
    '涉及学生 PII/成绩/教育记录',
    '合规辖区和告知/授权要求',
    '是否可使用合成或匿名化数据验证',
    '失败接管路径',
    '最低证据要求'
)) {
    Assert-True ($admissionDoc.Contains($keyword)) "L001 admission card doc missing keyword: $keyword"
}

$readinessReport = Get-Content -LiteralPath (Join-Path $repoRoot $ReadinessReportPath) -Raw | ConvertFrom-Json
Assert-True ($readinessReport.status -eq 'pass') 'C002Q0 readiness must pass before L001'
Assert-True ($readinessReport.allowProjectRuntimeRealModelCalls -eq $false) 'project runtime real model calls must stay disabled before L001 rollout'
Assert-True ($readinessReport.noActiveWrite -eq $true) 'L001 requires no active write guard'
Assert-True ($readinessReport.humanReviewRequired -eq $true) 'L001 requires human review boundary'
Assert-True ($readinessReport.cacheHitRequired -eq $true) 'L001 requires cache-hit evidence boundary'
Assert-True ($readinessReport.externalAiCallsInReadiness -eq 0) 'L001 readiness proof must not call external AI'

[ordered]@{
    status = 'pass'
    taskId = 'L001'
    admissionDocPath = $AdmissionDocPath
    readinessReportPath = $ReadinessReportPath
    allowProjectRuntimeRealModelCalls = $readinessReport.allowProjectRuntimeRealModelCalls
    noActiveWrite = $readinessReport.noActiveWrite
    humanReviewRequired = $readinessReport.humanReviewRequired
    cacheHitRequired = $readinessReport.cacheHitRequired
    externalAiCallsInReadiness = $readinessReport.externalAiCallsInReadiness
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json
