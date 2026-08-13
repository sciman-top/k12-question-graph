param(
    [string] $InputCandidatePath = 'tmp\cek006\curriculum-standard-structure.candidate.json',
    [string] $RuleCandidateOutputPath = 'tmp\cek007\curriculum-requirement-facets.candidate.json',
    [string] $EvalSuitePath = 'configs\ai-evals\curriculum-requirement-extraction.sample.json',
    [string] $HydratedEvalOutputPath = 'tmp\cek007\curriculum-requirement-extraction.eval-hydrated.json',
    [string] $ExtractionSchemaPath = 'schemas\ai\curriculum_requirement_extraction.schema.json',
    [string] $CurriculumRequirementSchemaPath = 'schemas\curriculum_requirement.schema.json',
    [string] $ReportPath = 'docs\evidence\cek007-curriculum-requirement-extraction-eval.json',
    [string] $PythonCommand = 'python',
    [int] $ExpectedRequirementCount = 89,
    [int] $ExpectedFacetCount = 184,
    [decimal] $ReviewThreshold = 0.85
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Resolve-InputFile([string] $Path, [string] $Label) {
    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repoRoot $Path }
    Assert-True (Test-Path -LiteralPath $candidate -PathType Leaf) "$Label not found: $candidate"
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Resolve-OutputFile([string] $Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function Write-JsonUtf8NoBom([object] $Value, [string] $Path) {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $json = ($Value | ConvertTo-Json -Depth 100).Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText($Path, $json + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Copy-JsonValue([object] $Value) {
    return ($Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100)
}

function Get-FileSha256([string] $Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-GitIgnoredRepoOutput([string] $Path, [string] $Label) {
    $relative = [System.IO.Path]::GetRelativePath($repoRoot, $Path)
    Assert-True (-not $relative.StartsWith('..')) "$Label must stay under the repository Git-ignored tmp tree"
    & git check-ignore --quiet -- $relative
    Assert-True ($LASTEXITCODE -eq 0) "$Label must be Git-ignored: $relative"
    return $relative.Replace('\', '/')
}

function Test-SchemaValue([object] $Value, [string] $SchemaPath) {
    $validationErrors = @()
    $valid = ($Value | ConvertTo-Json -Depth 100) |
        Test-Json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue -ErrorVariable validationErrors
    return [ordered]@{
        valid = [bool]$valid
        errors = @($validationErrors | ForEach-Object { $_.Exception.Message })
    }
}

function Assert-EnvelopeInvariants([object] $Envelope, [decimal] $Threshold) {
    Assert-True ($Envelope.mode -eq 'draft_test') 'extraction envelope must stay draft_test'
    Assert-True ($Envelope.generation.external_model_calls -eq 0) 'extraction envelope made an external model call'
    Assert-True ($Envelope.governance.status -eq 'candidate') 'extraction envelope must stay candidate'
    Assert-True ($Envelope.governance.review_status -eq 'pending_review') 'extraction envelope must stay pending_review'
    Assert-True ($Envelope.governance.production_eligible -eq $false) 'extraction envelope must not be production eligible'
    foreach ($field in 'database_write', 'source_region_write', 'knowledge_asset_write', 'c002_active_write') {
        Assert-True ($Envelope.governance.$field -eq $false) "unsafe governance field: $field"
    }

    $queueByFacet = @{}
    foreach ($item in @($Envelope.review_queue)) {
        if ($null -ne $item.facet_stable_id) {
            $queueByFacet[[string]$item.facet_stable_id] = $item
        }
    }
    $requiredProvenance = @(
        'facet_statement',
        'behavior_verb',
        'content_object',
        'condition_or_performance',
        'cognitive_demands',
        'ability_dimensions'
    )
    foreach ($requirement in @($Envelope.requirements)) {
        $parentAnchorHashes = @($requirement.source_anchor_sha256s)
        if (@($requirement.unresolved_reasons).Count -gt 0) {
            $blocked = @($Envelope.review_queue | Where-Object {
                $_.parent_requirement_stable_id -eq $requirement.parent_requirement_stable_id -and
                $null -eq $_.facet_stable_id -and
                $_.priority -eq 'blocked'
            })
            Assert-True ($blocked.Count -ge 1) 'unresolved requirement lacks blocked review routing'
        }
        foreach ($candidate in @($requirement.facets)) {
            $facet = $candidate.facet
            Assert-True ($facet.parent_requirement_stable_id -eq $requirement.parent_requirement_stable_id) 'facet detached from parent requirement'
            Assert-True ($facet.official_item_code -eq $requirement.official_item_code) 'facet official item code differs from parent'
            Assert-True ($facet.status -eq 'candidate') 'facet must stay candidate'
            Assert-True ($facet.review_status -eq 'pending_review') 'facet must stay pending_review'
            Assert-True ($facet.production_eligible -eq $false) 'facet must not be production eligible'
            Assert-True (@($facet.knowledge_stable_ids).Count -eq 0) 'CEK-07 must not create CEK-08 knowledge mappings'
            foreach ($anchor in @($facet.evidence_anchors)) {
                Assert-True ($parentAnchorHashes -contains $anchor.text_block_sha256) 'facet lost its parent evidence anchor'
                Assert-True ($anchor.evidence_role -eq 'curriculum_facet_source') 'facet anchor has the wrong evidence role'
            }
            $actualProvenance = @($candidate.field_provenance.field | Sort-Object -Unique)
            Assert-True (@(Compare-Object ($requiredProvenance | Sort-Object) $actualProvenance).Count -eq 0) 'facet field provenance is incomplete'
            foreach ($provenance in @($candidate.field_provenance)) {
                Assert-True ($provenance.generation_method -eq $Envelope.generation.method) 'field provenance generation method differs from envelope'
                foreach ($anchorHash in @($provenance.anchor_sha256s)) {
                    Assert-True ($parentAnchorHashes -contains $anchorHash) 'field provenance lost its source anchor'
                }
                if ($Envelope.generation.method -eq 'rules') {
                    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$provenance.rule_id)) 'rule provenance is missing rule_id'
                    Assert-True ($null -eq $provenance.model_output_path) 'rule provenance must not contain model_output_path'
                }
                if ($Envelope.generation.method -eq 'ai') {
                    Assert-True ($null -eq $provenance.rule_id) 'AI provenance must not contain rule_id'
                    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$provenance.model_output_path)) 'AI provenance is missing model_output_path'
                }
            }
            Assert-True ($candidate.review.required -eq $true) 'facet must require review'
            Assert-True ($candidate.review.status -eq 'pending_review') 'facet review must stay pending'
            $reasons = @($candidate.review.reasons)
            if ([decimal]$facet.confidence -lt $Threshold) {
                Assert-True ($reasons -contains 'low_confidence') 'low-confidence facet lacks review routing'
            }
            if (@($requirement.facets).Count -gt 1) {
                Assert-True ($reasons -contains 'multiple_facets') 'multi-facet requirement lacks review routing'
            }
            if ($Envelope.generation.method -eq 'ai') {
                Assert-True ($reasons -contains 'ai_generated') 'AI facet lacks AI review routing'
            }
            Assert-True ($queueByFacet.ContainsKey([string]$facet.stable_id)) 'facet lacks review queue item'
            Assert-True (@(Compare-Object ($reasons | Sort-Object) (@($queueByFacet[[string]$facet.stable_id].reasons) | Sort-Object)).Count -eq 0) 'facet review queue reasons differ from candidate reasons'
        }
    }
}

function Test-InvariantRejected([object] $Envelope, [decimal] $Threshold) {
    try {
        Assert-EnvelopeInvariants -Envelope $Envelope -Threshold $Threshold
        return $false
    }
    catch {
        return $true
    }
}

$inputCandidate = Resolve-InputFile -Path $InputCandidatePath -Label 'CEK-06 candidate'
$evalSuite = Resolve-InputFile -Path $EvalSuitePath -Label 'CEK-07 eval suite'
$extractionSchema = Resolve-InputFile -Path $ExtractionSchemaPath -Label 'CEK-07 extraction schema'
$requirementSchema = Resolve-InputFile -Path $CurriculumRequirementSchemaPath -Label 'CurriculumRequirement schema'
$ruleOutput = Resolve-OutputFile -Path $RuleCandidateOutputPath
$hydratedEvalOutput = Resolve-OutputFile -Path $HydratedEvalOutputPath
$reportOutput = Resolve-OutputFile -Path $ReportPath

Push-Location $repoRoot
try {
    $ruleRelative = Assert-GitIgnoredRepoOutput -Path $ruleOutput -Label 'Rule candidate output'
    $evalRelative = Assert-GitIgnoredRepoOutput -Path $hydratedEvalOutput -Label 'Hydrated AI eval output'
    $inputRelative = [System.IO.Path]::GetRelativePath($repoRoot, $inputCandidate).Replace('\', '/')
    $inputSha256Before = Get-FileSha256 -Path $inputCandidate

    $ruleCommandOutput = @(& $PythonCommand @(
        'tools\curriculum_requirement_facets.py',
        '--input', $inputCandidate,
        '--output', $ruleOutput
    ))
    Assert-True ($LASTEXITCODE -eq 0) "rule extraction failed: $($ruleCommandOutput -join ' ')"

    $evalCommandOutput = @(& $PythonCommand @(
        'tools\curriculum_requirement_facets.py',
        '--eval-suite', $evalSuite,
        '--output', $hydratedEvalOutput
    ))
    Assert-True ($LASTEXITCODE -eq 0) "AI eval hydration failed: $($evalCommandOutput -join ' ')"
    $inputSha256After = Get-FileSha256 -Path $inputCandidate
    Assert-True ($inputSha256Before -eq $inputSha256After) 'CEK-07 mutated the CEK-06 input candidate'

    $source = Get-Content -Raw -LiteralPath $inputCandidate | ConvertFrom-Json -Depth 100
    $rules = Get-Content -Raw -LiteralPath $ruleOutput | ConvertFrom-Json -Depth 100
    $hydratedEval = Get-Content -Raw -LiteralPath $hydratedEvalOutput | ConvertFrom-Json -Depth 100
    $suite = Get-Content -Raw -LiteralPath $evalSuite | ConvertFrom-Json -Depth 100
    Assert-True ($suite.allowRealModelCalls -eq $false) 'AI eval suite enables real model calls'
    Assert-True ($suite.productionEligible -eq $false) 'AI eval suite enables production eligibility'

    $rulesSchema = Test-SchemaValue -Value $rules -SchemaPath $extractionSchema
    Assert-True $rulesSchema.valid "rule output failed extraction schema: $($rulesSchema.errors -join '; ')"
    Assert-EnvelopeInvariants -Envelope $rules -Threshold $ReviewThreshold

    $sourceByStableId = @{}
    foreach ($requirement in @($source.curriculum_requirements)) {
        $sourceByStableId[[string]$requirement.stable_id] = $requirement
    }
    $invalidRequirementProjections = [System.Collections.Generic.List[object]]::new()
    foreach ($result in @($rules.requirements)) {
        Assert-True ($sourceByStableId.ContainsKey([string]$result.parent_requirement_stable_id)) 'rule result references an unknown parent requirement'
        $projection = Copy-JsonValue $sourceByStableId[[string]$result.parent_requirement_stable_id]
        $projection.facets = @($result.facets | ForEach-Object { $_.facet })
        $projection.behavior_verbs = @($projection.facets | ForEach-Object { $_.behavior_verb } | Sort-Object -Unique)
        $projection.cognitive_demands = @($projection.facets | ForEach-Object { @($_.cognitive_demands) } | Sort-Object -Unique)
        $projection.ability_dimensions = @($projection.facets | ForEach-Object { @($_.ability_dimensions) } | Sort-Object -Unique)
        $validation = Test-SchemaValue -Value $projection -SchemaPath $requirementSchema
        if (-not $validation.valid) {
            $invalidRequirementProjections.Add([ordered]@{
                officialItemCode = $result.official_item_code
                errors = $validation.errors
            })
        }
    }
    Assert-True ($invalidRequirementProjections.Count -eq 0) "$($invalidRequirementProjections.Count) CEK-05 parent/facet projections failed schema"

    $aiCaseResults = [System.Collections.Generic.List[object]]::new()
    foreach ($case in @($hydratedEval.cases)) {
        $aiOutput = $case.output
        $validation = Test-SchemaValue -Value $aiOutput -SchemaPath $extractionSchema
        Assert-True $validation.valid "AI golden output failed extraction schema: $($validation.errors -join '; ')"
        Assert-EnvelopeInvariants -Envelope $aiOutput -Threshold $ReviewThreshold
        Assert-True ($aiOutput.generation.method -eq 'ai') 'AI golden output has the wrong generation method'
        Assert-True ($aiOutput.generation.prompt_version -eq $case.prompt_version) 'AI golden prompt version drift'
        foreach ($field in 'role', 'name', 'version') {
            Assert-True (-not [string]::IsNullOrWhiteSpace([string]$aiOutput.generation.model.$field)) "AI golden model $field is missing"
        }
        foreach ($field in 'input_tokens', 'output_tokens', 'estimated_usd', 'currency') {
            Assert-True ($null -ne $aiOutput.generation.cost.PSObject.Properties[$field]) "AI golden cost field is missing: $field"
        }
        Assert-True ([string]$aiOutput.generation.input_sha256 -match '^[0-9a-f]{64}$') 'AI golden input hash is invalid'
        Assert-True ([string]$aiOutput.generation.output_sha256 -match '^[0-9a-f]{64}$') 'AI golden output hash is invalid'
        $aiCaseResults.Add([ordered]@{
            caseId = [string]$case.case_id
            schemaStatus = 'pass'
            invariantStatus = 'pass'
            modelTrace = 'pass'
            costTrace = 'pass'
            hashTrace = 'pass'
            externalModelCalls = 0
        })
    }

    $golden = $hydratedEval.cases[0].output
    $schemaNegativeCases = [System.Collections.Generic.List[object]]::new()
    $missingCost = Copy-JsonValue $golden
    $missingCost.generation.PSObject.Properties.Remove('cost')
    $schemaNegativeCases.Add([ordered]@{ id = 'missing_cost'; rejected = -not (Test-SchemaValue $missingCost $extractionSchema).valid })
    $unsafeProduction = Copy-JsonValue $golden
    $unsafeProduction.governance.production_eligible = $true
    $schemaNegativeCases.Add([ordered]@{ id = 'production_eligible_true'; rejected = -not (Test-SchemaValue $unsafeProduction $extractionSchema).valid })
    $missingAnchor = Copy-JsonValue $golden
    $missingAnchor.requirements[0].facets[0].facet.PSObject.Properties.Remove('evidence_anchors')
    $schemaNegativeCases.Add([ordered]@{ id = 'facet_missing_anchor'; rejected = -not (Test-SchemaValue $missingAnchor $extractionSchema).valid })
    $mismatchedProvenance = Copy-JsonValue $golden
    $mismatchedProvenance.requirements[0].facets[0].field_provenance[0].generation_method = 'rules'
    $schemaNegativeCases.Add([ordered]@{ id = 'ai_provenance_claims_rules'; rejected = -not (Test-SchemaValue $mismatchedProvenance $extractionSchema).valid })
    $detachedParent = Copy-JsonValue $golden
    $detachedParent.requirements[0].facets[0].facet.parent_requirement_stable_id = 'DETACHED'
    $schemaNegativeCases.Add([ordered]@{ id = 'facet_detached_parent'; rejected = Test-InvariantRejected $detachedParent $ReviewThreshold })
    $missingLowRoute = Copy-JsonValue $golden
    $candidateReasons = [System.Collections.Generic.List[string]]::new()
    foreach ($reason in @($missingLowRoute.requirements[0].facets[0].review.reasons)) {
        if ($reason -ne 'low_confidence') { $candidateReasons.Add([string]$reason) }
    }
    $missingLowRoute.requirements[0].facets[0].review.reasons = @($candidateReasons)
    $missingLowRoute.review_queue[0].reasons = @($candidateReasons)
    $schemaNegativeCases.Add([ordered]@{ id = 'low_confidence_without_route'; rejected = Test-InvariantRejected $missingLowRoute $ReviewThreshold })
    $failedNegativeCases = @($schemaNegativeCases | Where-Object { $_.rejected -ne $true })
    $failedNegativeCaseIds = @($failedNegativeCases | ForEach-Object { $_.id }) -join ', '
    Assert-True ($failedNegativeCases.Count -eq 0) "CEK-07 negative cases did not fail closed: $failedNegativeCaseIds"

    $ruleRequirements = @($rules.requirements)
    $ruleFacets = @($ruleRequirements | ForEach-Object { $_.facets })
    $reviewQueue = @($rules.review_queue)
    Assert-True ($ruleRequirements.Count -eq $ExpectedRequirementCount) "expected $ExpectedRequirementCount requirements, found $($ruleRequirements.Count)"
    Assert-True ($ruleFacets.Count -eq $ExpectedFacetCount) "expected $ExpectedFacetCount facets, found $($ruleFacets.Count)"
    $unresolvedRequirements = @($ruleRequirements | Where-Object { @($_.unresolved_reasons).Count -gt 0 })
    Assert-True ($unresolvedRequirements.Count -eq 0) 'real rule extraction has unresolved clauses'
    Assert-True ($reviewQueue.Count -eq $ruleFacets.Count) 'each real rule facet must have exactly one review queue item'

    $lowConfidence = @($ruleFacets | Where-Object { [decimal]$_.facet.confidence -lt $ReviewThreshold })
    $compositeRequirements = @($ruleRequirements | Where-Object { $_.composite -eq $true })
    $highPriority = @($reviewQueue | Where-Object { $_.priority -eq 'high' })
    $blocked = @($reviewQueue | Where-Object { $_.priority -eq 'blocked' })
    $normalPriority = @($reviewQueue | Where-Object { $_.priority -eq 'normal' })
    $sourceDocumentSha256 = [string]$source.source.source_document_sha256
    $report = [ordered]@{
        schemaVersion = 'cek007-curriculum-requirement-extraction-eval.v1'
        status = 'pass'
        checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
        taskId = 'CEK-07'
        inputs = [ordered]@{
            cek006CandidatePath = $inputRelative
            cek006CandidateSha256 = $inputSha256Before
            sourceDocumentSha256 = $sourceDocumentSha256
            sourceRequirementCount = @($source.curriculum_requirements).Count
            inputMutation = $false
        }
        ruleExtraction = [ordered]@{
            engine = [string]$rules.generation.engine_name
            engineVersion = [string]$rules.generation.engine_version
            promptVersion = [string]$rules.generation.prompt_version
            schemaVersion = [string]$rules.schema_version
            outputPayloadSha256 = [string]$rules.generation.output_sha256
            candidateOutputPath = $ruleRelative
            candidateOutputSha256 = Get-FileSha256 -Path $ruleOutput
            candidateOutputGitIgnored = $true
            containsVerbatimSourceText = $true
            requirementCount = $ruleRequirements.Count
            facetCount = $ruleFacets.Count
            compositeRequirementCount = $compositeRequirements.Count
            lowConfidenceFacetCount = $lowConfidence.Count
            reviewQueueCount = $reviewQueue.Count
            normalPriorityCount = $normalPriority.Count
            highPriorityCount = $highPriority.Count
            blockedCount = $blocked.Count
            unresolvedRequirementCount = 0
            externalModelCalls = 0
            estimatedUsd = 0
        }
        aiEval = [ordered]@{
            suiteId = [string]$hydratedEval.suite_id
            hydratedOutputPath = $evalRelative
            caseCount = @($hydratedEval.cases).Count
            cases = @($aiCaseResults)
            schemaPositiveCaseCount = 1
            negativeCaseCount = $schemaNegativeCases.Count
            negativeCases = @($schemaNegativeCases)
            allowRealModelCalls = $false
            externalModelCalls = 0
            productionEligible = $false
        }
        contracts = [ordered]@{
            extractionSchema = 'schemas/ai/curriculum_requirement_extraction.schema.json'
            curriculumRequirementSchema = 'schemas/curriculum_requirement.schema.json'
            ruleEnvelopeSchema = 'pass'
            aiEnvelopeSchema = 'pass'
            parentFacetProjectionSchemaValidCount = $ruleRequirements.Count
            detachedParentFailsClosed = $true
            sourceAnchorsRetained = $true
            fieldProvenanceComplete = $true
            fieldProvenanceMethodConsistent = $true
            lowConfidenceThreshold = [decimal]$ReviewThreshold
            allCandidatesRequireReview = $true
        }
        governance = [ordered]@{
            status = 'candidate'
            reviewStatus = 'pending_review'
            productionEligible = $false
            databaseWrite = $false
            sourceRegionWrite = $false
            knowledgeAssetWrite = $false
            c002ActiveWrite = $false
            realModelCall = $false
        }
        copyrightBoundary = [ordered]@{
            committedReportContainsVerbatimSourceText = $false
            verbatimRuleCandidateGitIgnored = $true
            hydratedEvalUsesSyntheticTextOnly = $true
        }
        supplyChain = [ordered]@{
            status = 'pass'
            newDependenciesAdded = $false
            implementation = 'Python standard library'
            schemaValidator = "PowerShell Test-Json $($PSVersionTable.PSVersion)"
        }
        fullGate = [ordered]@{
            status = 'gate_na'
            reason = 'stateful Release requires explicit authorization because it uses PostgreSQL and isolated backup/restore rehearsal'
            alternative_verification = 'CEK-07 unit tests, rule/AI JSON Schema validation, fail-closed negative cases, Release build, roadmap guard, and static hotspot review'
            evidence_link = 'docs/evidence/cek007-curriculum-requirement-extraction-eval.json'
            expires_at = 'CEK-34'
            recovery_condition = 'obtain current-task authorization and run tools/run-verification.ps1 -Profile Release -AuthorizeStateful'
        }
        rollback = 'Delete the ignored CEK-07 candidates and revert only the CEK-07 schema, eval fixture, parser, tests, wrapper, documentation, and evidence. The CEK-06 source candidate, SourceRegion, database, and C002 active remain unchanged.'
        completionBoundary = 'CEK-07 proves reviewable rule facets and an offline AI output contract only. It does not call a real model, approve facets, create CEK-08 knowledge mappings, persist CEK-09 assets, write SourceRegion or database rows, switch C002 active, close REAL005, or establish teacher/live acceptance.'
    }
    Write-JsonUtf8NoBom -Value $report -Path $reportOutput
    $reportText = Get-Content -Raw -LiteralPath $reportOutput
    Assert-True (-not $reportText.Contains('"source_text"')) 'committed CEK-07 report contains a verbatim source field'
    Assert-True (-not $reportText.Contains('"facet_statement"')) 'committed CEK-07 report contains a derived facet statement'
    $reportText | Write-Output
}
finally {
    Pop-Location
}
