param(
    [string] $BaseCsvRoot = 'guangzhou-physics-full-research-package-2016-2025\csv',
    [string] $QualityReviewRoot = 'guangzhou-physics-full-research-package-2016-2025\quality-review-complete-csv-package',
    [string] $OutputRoot = 'D:\KQG_Data\candidate_packages\c003-merged-quality-review-2016-2025',
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string] $Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return (Join-Path $repoRoot $Path)
}

function Read-CsvRows([string] $Path) {
    return @(Import-Csv -LiteralPath $Path -Encoding utf8BOM)
}

$baseRoot = Resolve-RepoPath $BaseCsvRoot
$reviewRoot = Resolve-RepoPath $QualityReviewRoot
$output = Resolve-RepoPath $OutputRoot

if (-not (Test-Path -LiteralPath $baseRoot)) {
    throw "Base C003 CSV root does not exist: $baseRoot"
}
if (-not (Test-Path -LiteralPath $reviewRoot)) {
    throw "Quality review CSV root does not exist: $reviewRoot"
}
if ((Test-Path -LiteralPath $output) -and -not $Force) {
    throw "Output root already exists. Pass -Force to replace: $output"
}

if (Test-Path -LiteralPath $output) {
    Remove-Item -LiteralPath $output -Recurse -Force
}
New-Item -ItemType Directory -Path $output -Force | Out-Null

Copy-Item -Path (Join-Path $baseRoot '*.csv') -Destination $output
Copy-Item -Path (Join-Path $reviewRoot '*.csv') -Destination $output -Force

$requiredFiles = @(
    'c003-knowledge-node-full.csv',
    'c003-exam-point-full.csv',
    'c003-curriculum-standard-full.csv',
    'c003-textbook-node-full.csv',
    'c003-asset-mapping.csv',
    'c003-quality-issue-registry.csv',
    'c003-quality-issue-review-evidence.csv',
    'c003-question-item-full.csv',
    'c003-year-report-observation.csv',
    'c003-answer-scoring-point.csv',
    'c003-source-material.csv'
)

$missing = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $output $_)) })
if ($missing.Count -gt 0) {
    throw "Merged C003 package is missing required files: $($missing -join ', ')"
}

$qualityIssues = Read-CsvRows (Join-Path $output 'c003-quality-issue-registry.csv')
$reviewEvidence = Read-CsvRows (Join-Path $output 'c003-quality-issue-review-evidence.csv')
$openIssues = @($qualityIssues | Where-Object {
    $_.review_status -ne 'resolved' -or [string]$_.production_eligible -ne 'true'
})

if ($qualityIssues.Count -ne 210) {
    throw "Expected 210 C003 quality issues, got $($qualityIssues.Count)"
}
if ($reviewEvidence.Count -ne 210) {
    throw "Expected 210 C003 quality review evidence rows, got $($reviewEvidence.Count)"
}
if ($openIssues.Count -gt 0) {
    throw "Quality review package still has $($openIssues.Count) open production blockers"
}

$rowsByFile = [ordered]@{}
foreach ($file in $requiredFiles) {
    $rowsByFile[$file] = (Read-CsvRows (Join-Path $output $file)).Count
}

[ordered]@{
    status = 'pass'
    outputRoot = $output
    baseCsvRoot = $baseRoot
    qualityReviewRoot = $reviewRoot
    requiredFiles = $requiredFiles
    rowsByFile = $rowsByFile
    qualityIssuesTotal = $qualityIssues.Count
    qualityIssuesOpenForProduction = $openIssues.Count
    reviewEvidenceRows = $reviewEvidence.Count
} | ConvertTo-Json -Depth 6
