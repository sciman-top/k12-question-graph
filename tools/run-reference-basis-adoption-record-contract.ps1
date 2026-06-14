param(
    [string] $P005TemplatePath = 'docs/templates/p005-pilot-feedback-triage-template.json',
    [string] $P006TemplatePath = 'docs/templates/p006-release-decision-record-template.json',
    [string] $P005ContractPath = 'tools/run-p005-pilot-feedback-backlog-preflight-contract.ps1',
    [string] $P006ContractPath = 'tools/run-p006-release-decision-preflight-contract.ps1',
    [string] $ReportPath = 'tmp/reference-basis-adoption-record-contract/report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string] $Path) {
    return Join-Path $repoRoot ($Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$p005TemplateFullPath = Resolve-RepoPath $P005TemplatePath
$p006TemplateFullPath = Resolve-RepoPath $P006TemplatePath
$p005ContractFullPath = Resolve-RepoPath $P005ContractPath
$p006ContractFullPath = Resolve-RepoPath $P006ContractPath
$reportFullPath = Resolve-RepoPath $ReportPath

foreach ($path in @($p005TemplateFullPath, $p006TemplateFullPath, $p005ContractFullPath, $p006ContractFullPath)) {
    Assert-True (Test-Path -LiteralPath $path) "required adoption record artifact missing: $path"
}

$requiredTemplateKeys = @(
    'referenceContext',
    'impactedSurfaceIds',
    'referencesReviewed',
    'adoptionDecision'
)

$p005Template = Get-Content -LiteralPath $p005TemplateFullPath -Raw | ConvertFrom-Json
$p006Template = Get-Content -LiteralPath $p006TemplateFullPath -Raw | ConvertFrom-Json

foreach ($key in $requiredTemplateKeys) {
    Assert-True ($p005Template.PSObject.Properties.Name -contains $key) "P005 template missing adoption field: $key"
    Assert-True ($p006Template.PSObject.Properties.Name -contains $key) "P006 template missing adoption field: $key"
}

Assert-True (@($p005Template.referencesReviewed).Count -ge 1) 'P005 template must include at least one referencesReviewed sample row'
Assert-True (@($p006Template.referencesReviewed).Count -ge 1) 'P006 template must include at least one referencesReviewed sample row'
Assert-True (@($p005Template.impactedSurfaceIds).Count -ge 1) 'P005 template must include at least one impactedSurfaceIds sample value'
Assert-True (@($p006Template.impactedSurfaceIds).Count -ge 1) 'P006 template must include at least one impactedSurfaceIds sample value'

$p005ContractText = Get-Content -LiteralPath $p005ContractFullPath -Raw
$p006ContractText = Get-Content -LiteralPath $p006ContractFullPath -Raw

foreach ($pattern in @('referenceContext', 'referencesReviewed', 'impactedSurfaceIds', 'adoptionDecision')) {
    Assert-True ($p005ContractText.Contains($pattern)) "P005 contract must validate adoption field: $pattern"
    Assert-True ($p006ContractText.Contains($pattern)) "P006 contract must validate adoption field: $pattern"
}

$report = [ordered]@{
    status = 'pass'
    task = 'reference-basis adoption record contract'
    checkedAt = (Get-Date).ToString('s')
    p005TemplatePath = $P005TemplatePath
    p006TemplatePath = $P006TemplatePath
    p005ContractPath = $P005ContractPath
    p006ContractPath = $P006ContractPath
    requiredTemplateKeys = $requiredTemplateKeys
    conclusion = 'P005/P006 closeout artifacts carry explicit reference-basis adoption record structure'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
