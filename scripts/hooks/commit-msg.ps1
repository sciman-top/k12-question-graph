param(
  [Parameter(Mandatory = $true)]
  [string]$CommitMessagePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:GOVERNED_ALLOW_NON_CHINESE_COMMIT -eq "1") {
  Write-Host "commit-msg: non-Chinese commit subject allowed by GOVERNED_ALLOW_NON_CHINESE_COMMIT=1"
  exit 0
}

if (-not (Test-Path -LiteralPath $CommitMessagePath)) {
  throw "Commit message file was not found: $CommitMessagePath"
}

$lines = Get-Content -LiteralPath $CommitMessagePath -Encoding UTF8
$subject = ""
foreach ($line in $lines) {
  $trimmed = ([string]$line).Trim()
  if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) {
    continue
  }
  $subject = $trimmed
  break
}

if ([string]::IsNullOrWhiteSpace($subject)) {
  Write-Error "commit-msg: 提交信息 subject 不能为空。"
  exit 1
}

$allowedGeneratedPrefixes = @(
  "Merge ",
  "Revert ",
  "fixup!",
  "squash!"
)
foreach ($prefix in $allowedGeneratedPrefixes) {
  if ($subject.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "commit-msg: generated commit subject allowed: $prefix"
    exit 0
  }
}

if ($subject -notmatch "\p{IsCJKUnifiedIdeographs}") {
  Write-Error @"
commit-msg: 普通提交信息默认必须中文优先，subject 需要包含中文。
当前 subject: $subject
建议示例: 修复目标仓规则同步的中文提交约束
如确需英文提交，请在确认仓库规范后设置 GOVERNED_ALLOW_NON_CHINESE_COMMIT=1 再提交。
"@
  exit 1
}

Write-Host "commit-msg: Chinese-first subject check passed"
