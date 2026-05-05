param(
  [string] $SecurityDocPath = 'docs\17_SecurityPrivacyCompliance.md',
  [string] $N001EvidencePath = 'docs\evidence\20260505-n001-real-privacy-boundary-admission.md'
)
$ErrorActionPreference='Stop'
$repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$c,[string]$m){ if(-not $c){ throw $m } }

$doc=Get-Content -LiteralPath (Join-Path $repoRoot $SecurityDocPath) -Raw
foreach($k in @('deployment_jurisdiction','data_controller_or_owner','student_pii_allowed_in_external_ai','retention_and_delete_policy','外部模型默认不接收学生身份和成绩明文')){
  Assert-True ($doc.Contains($k)) "N001 security doc missing keyword: $k"
}
$e=Get-Content -LiteralPath (Join-Path $repoRoot $N001EvidencePath) -Raw
foreach($k in @('辖区','授权','数据最小化','保留','删除','外部模型禁用策略')){
  Assert-True ($e.Contains($k)) "N001 evidence missing keyword: $k"
}
[ordered]@{status='pass';taskId='N001';securityDocPath=$SecurityDocPath;n001EvidencePath=$N001EvidencePath;checkedAt=(Get-Date).ToString('s')}|ConvertTo-Json
