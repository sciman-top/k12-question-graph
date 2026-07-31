param(
    [string] $TaxonomyPath = 'configs\knowledge\error-pattern-taxonomy.json',
    [string] $ServicePath = 'apps\api\Application\Workflows\KnowledgeEvidenceWorkflowService.cs',
    [string] $TestsPath = 'tests\api\K12QuestionGraph.Api.Tests\ErrorPatternPromotionTests.cs',
    [string] $C002RPlanPath = 'configs\domain-assets\c002r-versioned-revision.sample.json',
    [string] $ReferenceRoot = 'D:\CODE\external\k12-question-graph-references',
    [string] $ReportPath = 'docs\evidence\cek020-error-pattern-promotion-guard.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string] $Path) {
    return (Resolve-Path -LiteralPath (Join-Path $repoRoot $Path)).Path
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$resolvedTaxonomyPath = Resolve-RepoPath $TaxonomyPath
$resolvedServicePath = Resolve-RepoPath $ServicePath
$resolvedTestsPath = Resolve-RepoPath $TestsPath
$resolvedC002RPlanPath = Resolve-RepoPath $C002RPlanPath
$resolvedReportPath = Join-Path $repoRoot $ReportPath
$taxonomy = Get-Content -Raw -LiteralPath $resolvedTaxonomyPath | ConvertFrom-Json
$serviceSource = Get-Content -Raw -LiteralPath $resolvedServicePath
$testSource = Get-Content -Raw -LiteralPath $resolvedTestsPath
$c002rPlan = Get-Content -Raw -LiteralPath $resolvedC002RPlanPath | ConvertFrom-Json

Assert-True ($taxonomy.schemaVersion -eq 'error-pattern-taxonomy.v1') 'CEK-20 taxonomy schemaVersion mismatch'
Assert-True ($taxonomy.assetType -eq 'error_pattern') 'CEK-20 taxonomy assetType mismatch'
Assert-True ($taxonomy.normalizationMethod -eq 'controlled_taxonomy_exact_code_v1') 'CEK-20 normalization method mismatch'
Assert-True ($taxonomy.stability.minimumEvidenceCount -eq 2) 'CEK-20 requires at least two evidence rows'
Assert-True ($taxonomy.stability.semanticMergeMode -eq 'exact_code_only') 'CEK-20 semantic merge must remain exact-code only'
Assert-True ($taxonomy.stability.repeatabilityRule -eq 'distinct_question_count >= 2 OR distinct_exam_year_count >= 2') 'CEK-20 cross-question/year rule mismatch'
Assert-True ($taxonomy.stability.singleEvidenceStable -eq $false) 'CEK-20 single evidence must not be stable'
Assert-True ($taxonomy.stability.unknownCodeAction -eq 'reject') 'CEK-20 unknown taxonomy codes must fail closed'

$categories = @($taxonomy.categories)
$codes = @($categories | ForEach-Object { [string]$_.code })
Assert-True ($categories.Count -ge 8) 'CEK-20 taxonomy category coverage is incomplete'
Assert-True (($codes | Select-Object -Unique).Count -eq $codes.Count) 'CEK-20 taxonomy codes must be unique'
foreach ($requiredCode in @('concept_confusion','model_not_constructed','unit_conversion','graph_interpretation','experimental_operation','data_processing','expression_convention','careless_omission')) {
    Assert-True ($codes -contains $requiredCode) "CEK-20 taxonomy is missing $requiredCode"
}
$misconceptionEligible = @($categories | Where-Object misconceptionEligible)
Assert-True ($misconceptionEligible.Count -gt 0) 'CEK-20 taxonomy needs an explicit misconception-eligible conceptual category'
Assert-True (@($misconceptionEligible | Where-Object semanticType -ne 'conceptual').Count -eq 0) 'Only conceptual categories may be misconception eligible'

$governance = $taxonomy.governance
Assert-True ($governance.status -eq 'candidate') 'CEK-20 outputs must stay candidate'
Assert-True ($governance.reviewerStatus -eq 'pending_review') 'CEK-20 outputs must stay pending_review'
Assert-True ($governance.productionEligible -eq $false) 'CEK-20 outputs must not be production eligible'
Assert-True ($governance.databaseWrite -eq $false) 'CEK-20 guard must not write candidates to the database'
Assert-True ($governance.activeWrite -eq $false) 'CEK-20 guard must not write active assets'
$promotion = $governance.misconceptionPromotion
Assert-True ($promotion.initialStatus -eq 'pending_review') 'Misconception promotion must start pending_review'
Assert-True ($promotion.requiresHumanReview -eq $true) 'Misconception promotion requires human review'
Assert-True ($promotion.requiresC002RImpactReport -eq $true) 'Misconception promotion requires C002R impact report'
Assert-True ($promotion.requiresRollbackSnapshot -eq $true) 'Misconception promotion requires rollback snapshot'
Assert-True ($promotion.autoApplyAllowed -eq $false) 'Misconception promotion must never auto apply'

foreach ($requiredSourceToken in @('BuildErrorPatternCandidates','DomainAssetStatuses.Candidate','DomainAssetReviewStatuses.PendingReview','RequiresC002RImpactReport: true','RequiresRollbackSnapshot: true','AutoApplyAllowed: false')) {
    Assert-True ($serviceSource.Contains($requiredSourceToken, [StringComparison]::Ordinal)) "CEK-20 service is missing contract token: $requiredSourceToken"
}
Assert-True (-not $serviceSource.Contains('SaveChanges', [StringComparison]::Ordinal)) 'CEK-20 workflow service must remain read-only'
foreach ($requiredTestToken in @('RejectsSingleEvidence','RejectsRepeatedEvidenceFromOneQuestionAndYear','DoesNotMergeSemanticallyDifferentCodes','CreatesCandidateForConsistentCrossQuestionEvidence','CreatesCandidateForConsistentCrossYearEvidence','KeepsMisconceptionPromotionPendingAndNonApplying','DoesNotPromoteCarelessPatternToMisconception','FailsClosedForUnknownTaxonomyCode')) {
    Assert-True ($testSource.Contains($requiredTestToken, [StringComparison]::Ordinal)) "CEK-20 test contract is missing: $requiredTestToken"
}

Assert-True ($c002rPlan.noActiveWrite -eq $true) 'C002R must remain no-active-write'
Assert-True ($c002rPlan.reviewWorkflow.initialStatus -eq 'pending_review') 'C002R review must start pending_review'
Assert-True ($c002rPlan.reviewWorkflow.requiresRollbackSnapshotBeforeApproval -eq $true) 'C002R approval requires rollback snapshot'
Assert-True ($c002rPlan.reviewWorkflow.teacherCanApplyActive -eq $false) 'Teacher must not apply C002R active switch'

$trxDirectory = Join-Path $repoRoot 'tmp\cek020'
New-Item -ItemType Directory -Path $trxDirectory -Force | Out-Null
$trxPath = Join-Path $trxDirectory 'error-pattern-promotion.trx'
Push-Location $repoRoot
try {
    dotnet test tests\api\K12QuestionGraph.Api.Tests\K12QuestionGraph.Api.Tests.csproj `
        --filter ErrorPattern `
        --no-restore `
        --logger "trx;LogFileName=$trxPath"
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-20 ErrorPattern tests failed'
}
finally {
    Pop-Location
}

[xml]$trx = Get-Content -Raw -LiteralPath $trxPath
$testResults = @($trx.SelectNodes("//*[local-name()='UnitTestResult']"))
$failedTests = @($testResults | Where-Object outcome -ne 'Passed')
Assert-True ($testResults.Count -ge 8) 'CEK-20 expected at least eight ErrorPattern tests'
Assert-True ($failedTests.Count -eq 0) 'CEK-20 TRX contains failed tests'

$manifestPath = Join-Path $ReferenceRoot 'references.manifest.json'
$referenceManifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$referencePaths = @(
    'official-docs/EntityFramework.Docs',
    'official-docs/npgsql-doc',
    'architecture-samples/CleanArchitecture',
    'education-assessment/moodle',
    'education-assessment/OpenOLAT'
)
$referencesReviewed = foreach ($relativePath in $referencePaths) {
    $entry = @($referenceManifest.entries | Where-Object relativePath -eq $relativePath)
    Assert-True ($entry.Count -eq 1) "Reference manifest entry missing or duplicated: $relativePath"
    $checkoutPath = Join-Path $ReferenceRoot ($relativePath.Replace('/', '\'))
    $actualRevision = (& git -C $checkoutPath rev-parse --short HEAD).Trim()
    Assert-True ($LASTEXITCODE -eq 0) "Unable to read reference revision: $relativePath"
    [ordered]@{
        path = $relativePath
        manifestRevision = [string]$entry[0].lastVerifiedCommit
        actualRevision = $actualRevision
        revisionMatchesManifest = $actualRevision.StartsWith([string]$entry[0].lastVerifiedCommit, [StringComparison]::OrdinalIgnoreCase)
    }
}
$referenceShelfDrift = @($referencesReviewed | Where-Object revisionMatchesManifest -eq $false).Count -gt 0

$report = [ordered]@{
    schemaVersion = 'cek020-error-pattern-promotion-guard.v1'
    status = 'pass'
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    taskId = 'CEK-20'
    taxonomy = [ordered]@{
        categories = $categories.Count
        misconceptionEligibleCategories = $misconceptionEligible.Count
        normalizationMethod = [string]$taxonomy.normalizationMethod
        repeatabilityRule = [string]$taxonomy.stability.repeatabilityRule
    }
    contracts = [ordered]@{
        tests = $testResults.Count
        failed = $failedTests.Count
        singleEvidenceRejected = $true
        singleQuestionSingleYearRejected = $true
        semanticMismatchRejected = $true
        crossQuestionAccepted = $true
        crossYearAccepted = $true
    }
    governance = [ordered]@{
        status = 'candidate'
        reviewerStatus = 'pending_review'
        productionEligible = $false
        databaseWrite = $false
        activeWrite = $false
        misconceptionAutoApplyAllowed = $false
        requiresHumanReview = $true
        requiresC002RImpactReport = $true
        requiresRollbackSnapshot = $true
    }
    referencesReviewed = @($referencesReviewed)
    referenceShelfDrift = $referenceShelfDrift
    adoptionDecision = [ordered]@{
        adopted = @('EF no-tracking read boundary','application workflow isolation','explicit candidate and review lifecycle','fail-closed promotion transition')
        rejected = @('copy Moodle or OpenOLAT data models','infer semantic equivalence from free text','auto-activate misconception assets')
        mode = 'reference_only_no_copy'
    }
    evidence = [ordered]@{
        taxonomy = [IO.Path]::GetRelativePath($repoRoot, $resolvedTaxonomyPath).Replace('\', '/')
        service = [IO.Path]::GetRelativePath($repoRoot, $resolvedServicePath).Replace('\', '/')
        tests = [IO.Path]::GetRelativePath($repoRoot, $resolvedTestsPath).Replace('\', '/')
        trx = [IO.Path]::GetRelativePath($repoRoot, $trxPath).Replace('\', '/')
        report = $ReportPath.Replace('\', '/')
    }
    rollback = 'Delete only CEK-20 candidate pattern/review rows by batch key if later materialized; this guard writes no database or active KnowledgeNode state.'
    completionBoundary = 'CEK-20 proves deterministic error-pattern candidate and misconception promotion contracts only; no pattern is teacher-approved, persisted, production eligible, or active, and REAL005 remains not_closed.'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedReportPath) -Force | Out-Null
[IO.File]::WriteAllText($resolvedReportPath, (($report | ConvertTo-Json -Depth 12) + "`n"), [Text.UTF8Encoding]::new($false))
$report | ConvertTo-Json -Depth 12
