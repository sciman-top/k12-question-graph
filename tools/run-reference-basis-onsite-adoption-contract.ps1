param(
    [string] $P001TemplatePath = 'docs/templates/p001-isolated-machine-evidence-template.json',
    [string] $P003TemplatePath = 'docs/templates/p003-onsite-pilot-admission-card-template.json',
    [string] $P001ContractPath = 'tools/run-p001-live-pilot-readiness-preflight-contract.ps1',
    [string] $P003ContractPath = 'tools/run-p003-onsite-pilot-admission-preflight-contract.ps1',
    [string] $ReportPath = 'tmp/reference-basis-onsite-adoption-contract/report.json'
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

$p001TemplateFullPath = Resolve-RepoPath $P001TemplatePath
$p003TemplateFullPath = Resolve-RepoPath $P003TemplatePath
$p001ContractFullPath = Resolve-RepoPath $P001ContractPath
$p003ContractFullPath = Resolve-RepoPath $P003ContractPath
$reportFullPath = Resolve-RepoPath $ReportPath

foreach ($path in @($p001TemplateFullPath, $p003TemplateFullPath, $p001ContractFullPath, $p003ContractFullPath)) {
    Assert-True (Test-Path -LiteralPath $path) "required onsite adoption artifact missing: $path"
}

$requiredTemplateKeys = @(
    'referenceContext',
    'impactedSurfaceIds',
    'referencesReviewed',
    'adoptionDecision'
)

$p001Template = Get-Content -LiteralPath $p001TemplateFullPath -Raw | ConvertFrom-Json
$p003Template = Get-Content -LiteralPath $p003TemplateFullPath -Raw | ConvertFrom-Json

foreach ($key in $requiredTemplateKeys) {
    Assert-True ($p001Template.PSObject.Properties.Name -contains $key) "P001 template missing adoption field: $key"
    Assert-True ($p003Template.PSObject.Properties.Name -contains $key) "P003 template missing adoption field: $key"
}

Assert-True (@($p001Template.referencesReviewed).Count -ge 1) 'P001 template must include at least one referencesReviewed sample row'
Assert-True (@($p003Template.referencesReviewed).Count -ge 1) 'P003 template must include at least one referencesReviewed sample row'
Assert-True (@($p001Template.impactedSurfaceIds).Count -ge 1) 'P001 template must include at least one impactedSurfaceIds sample value'
Assert-True (@($p003Template.impactedSurfaceIds).Count -ge 1) 'P003 template must include at least one impactedSurfaceIds sample value'

$p001ContractText = Get-Content -LiteralPath $p001ContractFullPath -Raw
$p003ContractText = Get-Content -LiteralPath $p003ContractFullPath -Raw

foreach ($pattern in @('referenceContext', 'referencesReviewed', 'impactedSurfaceIds', 'adoptionDecision')) {
    Assert-True ($p001ContractText.Contains($pattern)) "P001 contract must validate adoption field: $pattern"
    Assert-True ($p003ContractText.Contains($pattern)) "P003 contract must validate adoption field: $pattern"
}

$report = [ordered]@{
    status = 'pass'
    task = 'reference-basis onsite adoption contract'
    checkedAt = (Get-Date).ToString('s')
    p001TemplatePath = $P001TemplatePath
    p003TemplatePath = $P003TemplatePath
    p001ContractPath = $P001ContractPath
    p003ContractPath = $P003ContractPath
    requiredTemplateKeys = $requiredTemplateKeys
    conclusion = 'P001/P003 onsite closeout artifacts carry explicit reference-basis adoption record structure'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
