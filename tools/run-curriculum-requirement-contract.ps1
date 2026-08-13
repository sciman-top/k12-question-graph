param(
    [string] $EvidenceAnchorSchemaPath = 'schemas\evidence_anchor.schema.json',
    [string] $CurriculumRequirementSchemaPath = 'schemas\curriculum_requirement.schema.json',
    [string] $TemplatePath = 'configs\knowledge\curriculum-requirement-template.json',
    [string] $ReportPath = 'docs\evidence\cek005-curriculum-requirement-contract.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoFile([string] $Path, [string] $Label) {
    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repoRoot $Path }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "$Label not found: $candidate"
    }

    return (Resolve-Path -LiteralPath $candidate).Path
}

function Copy-JsonValue([object] $Value) {
    return $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
}

function Get-TextSha256([string] $Value) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-NormalizedTextFileSha256([string] $Path) {
    $text = [System.IO.File]::ReadAllText($Path)
    $normalized = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    return Get-TextSha256 -Value $normalized
}

function Get-JsonProperty([object] $Value, [string] $Name) {
    if ($null -eq $Value) {
        return $null
    }

    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Test-SchemaInstance([object] $Value, [string] $SchemaPath) {
    $validationErrors = @()
    $json = $Value | ConvertTo-Json -Depth 100
    $isValid = $json | Test-Json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue -ErrorVariable validationErrors

    return [ordered]@{
        valid = [bool]$isValid
        errors = @($validationErrors | ForEach-Object { $_.Exception.Message })
    }
}

function Test-FacetParentInvariant([object] $Requirement) {
    $errors = [System.Collections.Generic.List[string]]::new()
    $recordType = Get-JsonProperty -Value $Requirement -Name 'record_type'
    $requirementStableId = Get-JsonProperty -Value $Requirement -Name 'stable_id'
    $requirementVersion = Get-JsonProperty -Value $Requirement -Name 'standard_version'
    $requirementItemCode = Get-JsonProperty -Value $Requirement -Name 'official_item_code'
    $requirementType = Get-JsonProperty -Value $Requirement -Name 'requirement_type'
    if ($recordType -ne 'curriculum_requirement') {
        $errors.Add('root record_type must be curriculum_requirement')
    }

    $facetIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($facet in @(Get-JsonProperty -Value $Requirement -Name 'facets')) {
        $facetStableId = Get-JsonProperty -Value $facet -Name 'stable_id'
        $facetParentId = Get-JsonProperty -Value $facet -Name 'parent_requirement_stable_id'
        $facetVersion = Get-JsonProperty -Value $facet -Name 'standard_version'
        $facetItemCode = Get-JsonProperty -Value $facet -Name 'official_item_code'
        $facetRequirementType = Get-JsonProperty -Value $facet -Name 'requirement_type'

        if ([string]::IsNullOrWhiteSpace([string]$facetParentId)) {
            $errors.Add("facet $facetStableId has no parent_requirement_stable_id")
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$requirementStableId) -and $facetParentId -ne $requirementStableId) {
            $errors.Add("facet $facetStableId points outside parent requirement $requirementStableId")
        }

        if ($null -ne $facetVersion -and $null -ne $requirementVersion -and $facetVersion -ne $requirementVersion) {
            $errors.Add("facet $facetStableId standard_version differs from parent")
        }
        if ($null -ne $facetItemCode -and $null -ne $requirementItemCode -and $facetItemCode -ne $requirementItemCode) {
            $errors.Add("facet $facetStableId official_item_code differs from parent")
        }
        if ($null -ne $facetRequirementType -and $null -ne $requirementType -and $facetRequirementType -ne $requirementType) {
            $errors.Add("facet $facetStableId requirement_type differs from parent")
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$facetStableId) -and -not $facetIds.Add([string]$facetStableId)) {
            $errors.Add("duplicate facet stable_id: $facetStableId")
        }
    }

    return [ordered]@{
        valid = $errors.Count -eq 0
        errors = @($errors)
    }
}

function Add-NegativeFixture(
    [System.Collections.Generic.List[object]] $Fixtures,
    [string] $Id,
    [object] $Value,
    [string] $ExpectedRejection
) {
    $Fixtures.Add([ordered]@{
        id = $Id
        value = $Value
        expectedRejection = $ExpectedRejection
    })
}

$anchorSchema = Resolve-RepoFile -Path $EvidenceAnchorSchemaPath -Label 'EvidenceAnchor schema'
$requirementSchema = Resolve-RepoFile -Path $CurriculumRequirementSchemaPath -Label 'CurriculumRequirement schema'
$templateFile = Resolve-RepoFile -Path $TemplatePath -Label 'CurriculumRequirement template'

$anchorSchemaObject = Get-Content -LiteralPath $anchorSchema -Raw | ConvertFrom-Json -Depth 100
$requirementSchemaObject = Get-Content -LiteralPath $requirementSchema -Raw | ConvertFrom-Json -Depth 100
$template = Get-Content -LiteralPath $templateFile -Raw | ConvertFrom-Json -Depth 100

foreach ($entry in @(
    [ordered]@{ label = 'EvidenceAnchor'; schema = $anchorSchemaObject },
    [ordered]@{ label = 'CurriculumRequirement'; schema = $requirementSchemaObject }
)) {
    if ($entry.schema.'$schema' -ne 'https://json-schema.org/draft/2020-12/schema') {
        throw "$($entry.label) schema must declare JSON Schema Draft 2020-12"
    }
    if ($entry.schema.additionalProperties -ne $false) {
        throw "$($entry.label) schema must fail closed on unknown root properties"
    }
}

$positiveRequirement = Test-SchemaInstance -Value $template -SchemaPath $requirementSchema
$positiveParentInvariant = Test-FacetParentInvariant -Requirement $template
if (-not $positiveRequirement.valid -or -not $positiveParentInvariant.valid) {
    $details = @($positiveRequirement.errors) + @($positiveParentInvariant.errors)
    throw "CurriculumRequirement template failed the positive contract: $($details -join '; ')"
}

$positiveAnchor = Test-SchemaInstance -Value $template.evidence_anchors[0] -SchemaPath $anchorSchema
if (-not $positiveAnchor.valid) {
    throw "EvidenceAnchor template failed the positive contract: $($positiveAnchor.errors -join '; ')"
}
if ((Get-TextSha256 -Value $template.source_text) -ne $template.evidence_anchors[0].text_block_sha256 -or
    (Get-TextSha256 -Value $template.facets[0].source_text) -ne $template.facets[0].evidence_anchors[0].text_block_sha256) {
    throw 'CurriculumRequirement template source_text and text_block_sha256 values do not match'
}

$activeFixture = Copy-JsonValue $template
$activeFixture.status = 'active'
$activeFixture.review_status = 'approved'
$activeFixture.production_eligible = $true
$activeFixture.evidence_anchors[0].source_region_id = '00000000-0000-0000-0000-000000000001'
$activeFixture.facets[0].status = 'active'
$activeFixture.facets[0].review_status = 'approved'
$activeFixture.facets[0].production_eligible = $true
$activeFixture.facets[0].evidence_anchors[0].source_region_id = '00000000-0000-0000-0000-000000000002'
$positiveActive = Test-SchemaInstance -Value $activeFixture -SchemaPath $requirementSchema
if (-not $positiveActive.valid) {
    throw "CurriculumRequirement active lifecycle fixture failed the positive contract: $($positiveActive.errors -join '; ')"
}

$negativeFixtures = [System.Collections.Generic.List[object]]::new()

$fixture = Copy-JsonValue $template
$fixture.PSObject.Properties.Remove('source_text')
Add-NegativeFixture $negativeFixtures 'missing_source_text' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.PSObject.Properties.Remove('source_text')
$fixture | Add-Member -NotePropertyName 'source_summary' -NotePropertyValue 'A summary cannot replace verified source text.'
Add-NegativeFixture $negativeFixtures 'source_summary_cannot_replace_source_text' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.PSObject.Properties.Remove('standard_version')
Add-NegativeFixture $negativeFixtures 'missing_standard_version' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.PSObject.Properties.Remove('official_item_code')
Add-NegativeFixture $negativeFixtures 'missing_official_item_code' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.PSObject.Properties.Remove('requirement_type')
Add-NegativeFixture $negativeFixtures 'missing_requirement_type' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.PSObject.Properties.Remove('evidence_anchors')
Add-NegativeFixture $negativeFixtures 'missing_evidence_anchors' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.PSObject.Properties.Remove('confidence')
Add-NegativeFixture $negativeFixtures 'missing_confidence' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.PSObject.Properties.Remove('review_status')
Add-NegativeFixture $negativeFixtures 'missing_review_status' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.PSObject.Properties.Remove('production_eligible')
Add-NegativeFixture $negativeFixtures 'missing_production_eligible' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.requirement_type = 'knowledge_point'
$fixture.facets[0].requirement_type = 'knowledge_point'
Add-NegativeFixture $negativeFixtures 'unknown_requirement_type' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.status = 'published'
Add-NegativeFixture $negativeFixtures 'unknown_lifecycle_status' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.review_status = 'auto_approved'
Add-NegativeFixture $negativeFixtures 'unknown_review_status' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.evidence_anchors[0].evidence_role = 'summary_only'
Add-NegativeFixture $negativeFixtures 'unknown_evidence_role' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.facets[0].PSObject.Properties.Remove('parent_requirement_stable_id')
Add-NegativeFixture $negativeFixtures 'facet_missing_parent' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.facets[0].PSObject.Properties.Remove('source_text')
Add-NegativeFixture $negativeFixtures 'facet_missing_source_text' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.facets[0].PSObject.Properties.Remove('evidence_anchors')
Add-NegativeFixture $negativeFixtures 'facet_missing_evidence_anchors' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.facets[0].PSObject.Properties.Remove('confidence')
Add-NegativeFixture $negativeFixtures 'facet_missing_confidence' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.facets[0].PSObject.Properties.Remove('review_status')
Add-NegativeFixture $negativeFixtures 'facet_missing_review_status' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.facets[0].PSObject.Properties.Remove('production_eligible')
Add-NegativeFixture $negativeFixtures 'facet_missing_production_eligible' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.facets[0].parent_requirement_stable_id = 'CR-DETACHED-PARENT'
Add-NegativeFixture $negativeFixtures 'facet_detached_from_parent' $fixture 'parent_invariant'

$fixture = Copy-JsonValue $template
$fixture.review_status = 'approved'
Add-NegativeFixture $negativeFixtures 'candidate_cannot_be_approved' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.production_eligible = $true
Add-NegativeFixture $negativeFixtures 'candidate_cannot_be_production_eligible' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.facets[0].review_status = 'approved'
Add-NegativeFixture $negativeFixtures 'facet_candidate_cannot_be_approved' $fixture 'schema'

$fixture = Copy-JsonValue $template
$fixture.facets[0].production_eligible = $true
Add-NegativeFixture $negativeFixtures 'facet_candidate_cannot_be_production_eligible' $fixture 'schema'

$fixture = Copy-JsonValue $activeFixture
$fixture.review_status = 'pending_review'
Add-NegativeFixture $negativeFixtures 'active_cannot_be_pending_review' $fixture 'schema'

$fixture = Copy-JsonValue $activeFixture
$fixture.production_eligible = $false
Add-NegativeFixture $negativeFixtures 'active_must_be_production_eligible' $fixture 'schema'

$fixture = Copy-JsonValue $activeFixture
$fixture.evidence_anchors[0].source_region_id = $null
Add-NegativeFixture $negativeFixtures 'active_requires_materialized_source_region' $fixture 'schema'

$negativeResults = [System.Collections.Generic.List[object]]::new()
foreach ($negative in $negativeFixtures) {
    $schemaResult = Test-SchemaInstance -Value $negative.value -SchemaPath $requirementSchema
    $parentResult = Test-FacetParentInvariant -Requirement $negative.value
    $rejected = -not ($schemaResult.valid -and $parentResult.valid)
    $actualRejection = if (-not $schemaResult.valid) { 'schema' } elseif (-not $parentResult.valid) { 'parent_invariant' } else { 'none' }

    $negativeResults.Add([ordered]@{
        id = $negative.id
        expectedRejection = $negative.expectedRejection
        actualRejection = $actualRejection
        rejected = $rejected
        parentInvariantErrors = @($parentResult.errors)
    })
}

$failedNegativeCases = @($negativeResults | Where-Object {
    -not $_.rejected -or $_.actualRejection -ne $_.expectedRejection
})
if ($failedNegativeCases.Count -gt 0) {
    throw "CurriculumRequirement negative fixtures did not fail closed: $(($failedNegativeCases.id | Sort-Object) -join ', ')"
}

$reportCandidate = if ([System.IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $repoRoot $ReportPath }
$reportDirectory = Split-Path -Parent $reportCandidate
if (-not (Test-Path -LiteralPath $reportDirectory -PathType Container)) {
    throw "report directory not found: $reportDirectory"
}

$report = [ordered]@{
    schemaVersion = 'cek005-curriculum-requirement-contract.v1'
    status = 'pass'
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    taskId = 'CEK-05'
    validator = [ordered]@{
        engine = 'PowerShell Test-Json'
        powerShellVersion = $PSVersionTable.PSVersion.ToString()
        jsonSchemaDialect = 'https://json-schema.org/draft/2020-12/schema'
        addedDependency = $false
    }
    inputHashes = [ordered]@{
        normalization = 'UTF-8 text normalized to LF without BOM'
        evidenceAnchorSchemaSha256 = Get-NormalizedTextFileSha256 -Path $anchorSchema
        curriculumRequirementSchemaSha256 = Get-NormalizedTextFileSha256 -Path $requirementSchema
        candidateTemplateSha256 = Get-NormalizedTextFileSha256 -Path $templateFile
        contractScriptSha256 = Get-NormalizedTextFileSha256 -Path $PSCommandPath
    }
    contracts = [ordered]@{
        evidenceAnchorSchema = 'schemas/evidence_anchor.schema.json'
        curriculumRequirementSchema = 'schemas/curriculum_requirement.schema.json'
        candidateTemplate = 'configs/knowledge/curriculum-requirement-template.json'
        sourceRegionMetadataProjection = [ordered]@{
            source_region_id = 'SourceRegion.Id'
            source_document_id = 'SourceRegion.SourceDocumentId'
            pdf_page_number = 'SourceRegion.PageNumber'
            printed_page_number = 'SourceRegion.Metadata.printedPageNumber'
            section_path = 'SourceRegion.Metadata.sectionPath'
            official_item_code = 'SourceRegion.Metadata.officialItemCode'
            text_block_sha256 = 'SourceRegion.Metadata.textBlockSha256'
            evidence_role = 'SourceRegion.Metadata.evidenceRole'
        }
    }
    positiveCases = [ordered]@{
        evidenceAnchor = 'pass'
        curriculumRequirement = 'pass'
        facetParentInvariant = 'pass'
        activeLifecycle = 'pass'
        templateTextBlockHashes = 'pass'
    }
    negativeCaseCount = $negativeResults.Count
    negativeCases = @($negativeResults)
    safeDefaults = [ordered]@{
        requirement = [ordered]@{
            status = $template.status
            reviewStatus = $template.review_status
            productionEligible = $template.production_eligible
        }
        facet = [ordered]@{
            status = $template.facets[0].status
            reviewStatus = $template.facets[0].review_status
            productionEligible = $template.facets[0].production_eligible
        }
    }
    executionBoundary = [ordered]@{
        aiRun = $false
        databaseWrite = $false
        sourceRegionWrite = $false
        knowledgeAssetWrite = $false
        c002ActiveWrite = $false
    }
    productionInvariant = [ordered]@{
        activeRequiresApprovedReview = $true
        activeRequiresProductionEligibility = $true
        activeRequiresMaterializedSourceRegion = $true
    }
    fullGate = [ordered]@{
        status = 'gate_na'
        reason = 'stateful Release requires explicit authorization because it uses PostgreSQL and isolated backup/restore rehearsal'
        alternative_verification = 'JSON Schema positive and negative fixtures, Release build, roadmap guard, and static scope review'
        evidence_link = 'docs/evidence/cek005-curriculum-requirement-contract.json'
        expires_at = 'CEK-34'
        recovery_condition = 'obtain current-task authorization and run tools/run-verification.ps1 -Profile Release -AuthorizeStateful'
    }
    rollback = 'remove only the CEK-05 schemas, template, contract, documentation, and evidence; no data restore is required'
    completionBoundary = 'CEK-05 defines candidate contracts only. It does not extract curriculum text, write SourceRegion metadata, create or activate domain assets, switch C002 active, close REAL005, or establish live acceptance.'
}

$report | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $reportCandidate -Encoding UTF8
$report | ConvertTo-Json -Depth 100
