param(
    [string] $AssessmentSchemaPath = 'schemas\assessment_target.schema.json',
    [string] $AlignmentSchemaPath = 'schemas\curriculum_alignment.schema.json',
    [string] $TemplatePath = 'configs\knowledge\assessment-target-template.json',
    [string] $ReportPath = 'docs\evidence\cek011-assessment-target-contract.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Resolve-File([string] $Path) {
    $full = [IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "file missing: $full" }
    return $full
}
function Copy-Json([object] $Value) { $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 }
function Test-Instance([object] $Value, [string] $Schema) {
    $errors = @()
    $valid = ($Value | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $Schema -ErrorAction SilentlyContinue -ErrorVariable errors
    return [ordered]@{ valid = [bool]$valid; errors = @($errors | ForEach-Object { $_.Exception.Message }) }
}
function Sha([string] $Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Assert-True([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }

$assessmentSchema = Resolve-File $AssessmentSchemaPath
$alignmentSchema = Resolve-File $AlignmentSchemaPath
$templateFile = Resolve-File $TemplatePath
$reportFile = [IO.Path]::GetFullPath((Join-Path $repoRoot $ReportPath))
$template = Get-Content -Raw $templateFile | ConvertFrom-Json -Depth 100
$templateResult = Test-Instance $template $assessmentSchema
Assert-True $templateResult.valid 'assessment target template invalid'

$alignment = [ordered]@{
    schema_version = 'curriculum-alignment.v1'; record_type = 'curriculum_alignment'
    alignment_id = 'CA-TEST-01'; target_id = $template.target_id
    curriculum_requirement_stable_id = 'CR-PHY-JM-2022R2025-TEST'; requirement_facet_stable_id = $null
    standard_version = '2022-2025-revision'; alignment_type = 'source_cited'
    evidence_anchors = @($template.evidence_anchors); confidence = 0.8; original_basis = $true
    status = 'candidate'; review_status = 'pending_review'; production_eligible = $false
}
$alignmentResult = Test-Instance $alignment $alignmentSchema
Assert-True $alignmentResult.valid 'curriculum alignment positive fixture invalid'
$targetWithAlignment = Copy-Json $template
$targetWithAlignment.curriculum_alignments = @($alignment)
Assert-True (Test-Instance $targetWithAlignment $assessmentSchema).valid 'target with alignment invalid'

$negativeCases = [System.Collections.Generic.List[object]]::new()
function Add-Negative([string] $Id, [object] $Value, [string] $Schema) {
    $result = Test-Instance $Value $Schema
    $negativeCases.Add([ordered]@{ id=$Id; rejected=(-not $result.valid); errors=$result.errors })
}
$case = Copy-Json $template; $case.question_scope.scope_type='subquestion'; Add-Negative 'non_whole_requires_block' $case $assessmentSchema
$case = Copy-Json $template; $case.question_scope.question_block_id='33333333-3333-3333-3333-333333333333'; Add-Negative 'whole_forbids_block' $case $assessmentSchema
$case = Copy-Json $template; $case.primary_knowledge_id=@('K1','K2'); Add-Negative 'primary_knowledge_is_single' $case $assessmentSchema
$case = Copy-Json $alignment; $case.alignment_type='direct'; Add-Negative 'alignment_type_closed_enum' $case $alignmentSchema
$case = Copy-Json $alignment; $case.PSObject.Properties.Remove('standard_version'); Add-Negative 'standard_version_required' $case $alignmentSchema
$case = Copy-Json $alignment; $case.evidence_anchors=@(); Add-Negative 'alignment_anchor_required' $case $alignmentSchema
$case = Copy-Json $alignment; $case.PSObject.Properties.Remove('status'); Add-Negative 'alignment_status_required' $case $alignmentSchema
$case = Copy-Json $alignment; $case.alignment_type='retrospective_crosswalk'; Add-Negative 'retrospective_not_original_basis' $case $alignmentSchema
$case = Copy-Json $alignment; $case.production_eligible=$true; Add-Negative 'candidate_not_production_eligible' $case $alignmentSchema
Assert-True (@($negativeCases | Where-Object { -not $_.rejected }).Count -eq 0) 'negative fixture accepted'

$report = [ordered]@{
    schemaVersion='cek011-assessment-target-contract.v1'; status='pass'; checkedAt=(Get-Date).ToUniversalTime().ToString('o'); taskId='CEK-11'
    validator=[ordered]@{engine='PowerShell Test-Json';jsonSchemaDialect='https://json-schema.org/draft/2020-12/schema';addedDependency=$false}
    inputHashes=[ordered]@{assessmentTarget=Sha $assessmentSchema;curriculumAlignment=Sha $alignmentSchema;template=Sha $templateFile;contract=Sha $PSCommandPath}
    positiveCases=[ordered]@{candidateTemplate='pass';sourceCitedAlignment='pass';targetWithAlignment='pass'}
    negativeCaseCount=$negativeCases.Count; negativeCases=@($negativeCases)
    invariants=[ordered]@{oneExactScope=$true;singlePrimaryKnowledgeField=$true;nonWholeRequiresQuestionBlock=$true;alignmentTypesClosed=$true;standardVersionAnchorConfidenceRequired=$true;retrospectiveOriginalBasisForbidden=$true;candidatePendingReview=$true;productionEligible=$false}
    referencesReviewed=@([ordered]@{url='https://json-schema.org/draft/2020-12/json-schema-core.html';status='HTTP 200';adoptionDecision='official_semantics_first'})
    localReference=[ordered]@{status='gate_na';reason='reference-basis manifest has no JSON Schema official source mapping';alternative_verification='official JSON Schema 2020-12 specification plus PowerShell Test-Json positive/negative fixtures';evidence_link='docs/evidence/cek011-assessment-target-contract.json';expires_at='next_reference_shelf_governance_update';recovery_condition='add a versioned JSON Schema official source anchor to the reference-basis manifest'}
    executionBoundary=[ordered]@{databaseWrite=$false;activeWrite=$false;externalAiCalls=0;realStudentDataUsed=$false}
    fullGate=[ordered]@{status='gate_na';reason='stateful Release requires CEK-34 authorization because it uses PostgreSQL and isolated backup/restore rehearsal';alternative_verification='Release build, schema fixtures, roadmap/reference guards, and static checks';evidence_link='docs/evidence/cek011-assessment-target-contract.json';expires_at='CEK-34';recovery_condition='obtain current-task authorization and run tools/run-verification.ps1 -Profile Release -AuthorizeStateful at CEK-34'}
    rollback='remove only CEK-11 schemas, template, contract, docs, and evidence; no data restore required'
    completionBoundary='CEK-11 defines repo-side candidate contracts only; it does not create database records, approve alignments, close REAL005, permit release, or establish teacher/live acceptance.'
}
$report | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $reportFile -Encoding utf8
$report | ConvertTo-Json -Depth 100
