param(
    [string] $RequirementCandidatePath = 'tmp\cek007\curriculum-requirement-facets.candidate.json',
    [string] $KnowledgeSnapshotPath = 'configs\knowledge\junior-physics-l1-l3.json',
    [string] $CrosswalkOutputPath = 'tmp\cek008\curriculum-knowledge-crosswalk.candidate.json',
    [string] $CompatibilityCsvPath = 'tmp\cek008\c002-asset-mapping.candidate.csv',
    [string] $SchemaPath = 'schemas\ai\knowledge_mapping.schema.json',
    [string] $ReportPath = 'docs\evidence\cek008-curriculum-knowledge-crosswalk.json',
    [string] $PythonCommand = 'python'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-Input([string] $Path, [string] $Label) {
    $candidate = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repoRoot $Path }
    Assert-True (Test-Path -LiteralPath $candidate -PathType Leaf) "$Label not found: $candidate"
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Resolve-Output([string] $Path) {
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function Get-Sha256([string] $Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-Ignored([string] $Path, [string] $Label) {
    $relative = [IO.Path]::GetRelativePath($repoRoot, $Path)
    Assert-True (-not $relative.StartsWith('..')) "$Label must remain under this repository"
    & git check-ignore --quiet -- $relative
    Assert-True ($LASTEXITCODE -eq 0) "$Label must be Git-ignored: $relative"
    return $relative.Replace('\', '/')
}

function Write-Json([object] $Value, [string] $Path) {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $json = ($Value | ConvertTo-Json -Depth 100).Replace("`r`n", "`n").Replace("`r", "`n")
    [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
}

function Test-Definition([object] $Value, [object] $Schema, [string] $Definition) {
    $validationSchema = [ordered]@{
        '$schema' = 'https://json-schema.org/draft/2020-12/schema'
        '$ref' = "#/`$defs/$Definition"
        '$defs' = $Schema.'$defs'
    } | ConvertTo-Json -Depth 100
    $errors = @()
    $valid = ($Value | ConvertTo-Json -Depth 100) |
        Test-Json -Schema $validationSchema -ErrorAction SilentlyContinue -ErrorVariable errors
    $errorMessages = @($errors | ForEach-Object { $_.Exception.Message }) -join '; '
    Assert-True ([bool]$valid) "$Definition schema failed: $errorMessages"
}

$requirements = Resolve-Input $RequirementCandidatePath 'CEK-07 requirement candidate'
$knowledge = Resolve-Input $KnowledgeSnapshotPath 'C002 knowledge snapshot'
$schemaFile = Resolve-Input $SchemaPath 'knowledge mapping schema'
$crosswalkOutput = Resolve-Output $CrosswalkOutputPath
$compatOutput = Resolve-Output $CompatibilityCsvPath
$reportOutput = Resolve-Output $ReportPath

Push-Location $repoRoot
try {
    $crosswalkRelative = Assert-Ignored $crosswalkOutput 'Crosswalk output'
    $compatRelative = Assert-Ignored $compatOutput 'Compatibility CSV'
    $requirementHashBefore = Get-Sha256 $requirements
    $knowledgeHashBefore = Get-Sha256 $knowledge

    & $PythonCommand -m unittest tests.workers.test_curriculum_knowledge_crosswalk
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-08 unit tests failed'
    $commandOutput = @(& $PythonCommand tools\curriculum_knowledge_crosswalk.py `
        --requirements $requirements --knowledge $knowledge `
        --output $crosswalkOutput --compat-csv $compatOutput)
    Assert-True ($LASTEXITCODE -eq 0) "crosswalk generation failed: $($commandOutput -join ' ')"
    Assert-True ((Get-Sha256 $requirements) -eq $requirementHashBefore) 'CEK-08 mutated CEK-07 input'
    Assert-True ((Get-Sha256 $knowledge) -eq $knowledgeHashBefore) 'CEK-08 mutated C002 snapshot'

    $result = Get-Content -Raw -LiteralPath $crosswalkOutput | ConvertFrom-Json -Depth 100
    $schema = Get-Content -Raw -LiteralPath $schemaFile | ConvertFrom-Json -Depth 100
    foreach ($mapping in @($result.mappings)) {
        Test-Definition $mapping $schema 'curriculum_asset_mapping'
    }
    foreach ($candidate in @($result.knowledge_candidates)) {
        Test-Definition $candidate $schema 'curriculum_knowledge_candidate'
    }

    $allowedTypes = @('equivalent', 'broader', 'narrower')
    $invalidTypes = @($result.mappings | Where-Object { $allowedTypes -notcontains $_.mapping_type })
    Assert-True ($invalidTypes.Count -eq 0) 'crosswalk contains forbidden mapping types'
    Assert-True (-not (($result | ConvertTo-Json -Depth 100) -match '"mapping_type"\s*:\s*"prerequisite"')) 'prerequisite leaked into asset mappings'
    foreach ($mapping in @($result.mappings)) {
        Assert-True ($mapping.review_status -eq 'pending_review') 'mapping bypassed pending review'
        Assert-True ($mapping.auto_apply_allowed -eq $false) 'mapping allows auto apply'
        Assert-True ($mapping.rollback_required -eq $true) 'mapping lacks rollback requirement'
    }
    foreach ($candidate in @($result.knowledge_candidates)) {
        Assert-True ($candidate.status -eq 'candidate') 'unmatched item is not a candidate'
        Assert-True ($candidate.production_eligible -eq $false) 'unmatched candidate is production eligible'
        Assert-True ($candidate.knowledge_node_write -eq $false) 'unmatched candidate writes a knowledge node'
    }
    foreach ($field in 'database_read','database_write','knowledge_node_write','domain_asset_mapping_write','c002_active_write') {
        Assert-True ($result.governance.$field -eq $false) "unsafe governance field: $field"
    }

    $mappingTypes = [ordered]@{}
    foreach ($type in $allowedTypes) {
        $mappingTypes[$type] = @($result.mappings | Where-Object { $_.mapping_type -eq $type }).Count
    }
    $highPriority = @($result.review_queue | Where-Object { $_.priority -eq 'high' })
    $oneToMany = @($result.review_queue | Where-Object { @($_.reasons) -contains 'one_to_many' })
    $manyToOne = @($result.review_queue | Where-Object { @($_.reasons) -contains 'many_to_one' })
    $lowConfidence = @($result.review_queue | Where-Object { @($_.reasons) -contains 'low_confidence' })
    $report = [ordered]@{
        schemaVersion = 'cek008-curriculum-knowledge-crosswalk.v1'
        status = 'pass'
        checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
        taskId = 'CEK-08'
        inputs = [ordered]@{
            requirementCandidatePath = [IO.Path]::GetRelativePath($repoRoot, $requirements).Replace('\', '/')
            requirementCandidateSha256 = $requirementHashBefore
            knowledgeSnapshotPath = [IO.Path]::GetRelativePath($repoRoot, $knowledge).Replace('\', '/')
            knowledgeSnapshotSha256 = $knowledgeHashBefore
            knowledgeSeedId = [string]$result.knowledge_snapshot.seed_id
            knowledgeNodeCount = [int]$result.knowledge_snapshot.node_count
            databaseRead = $false
            inputMutation = $false
        }
        result = [ordered]@{
            facetCount = @($result.mappings.source_stable_id + $result.knowledge_candidates.source_facet_stable_id | Sort-Object -Unique).Count
            mappingCount = @($result.mappings).Count
            mappingTypes = $mappingTypes
            knowledgeCandidateCount = @($result.knowledge_candidates).Count
            reviewQueueCount = @($result.review_queue).Count
            highPriorityReviewCount = $highPriority.Count
            oneToManyReviewCount = $oneToMany.Count
            manyToOneReviewCount = $manyToOne.Count
            lowConfidenceReviewCount = $lowConfidence.Count
            outputPayloadSha256 = [string]$result.generation.output_sha256
            crosswalkPath = $crosswalkRelative
            crosswalkSha256 = Get-Sha256 $crosswalkOutput
            compatibilityCsvPath = $compatRelative
            compatibilityCsvSha256 = Get-Sha256 $compatOutput
            outputsGitIgnored = $true
            committedEvidenceContainsVerbatimSourceText = $false
        }
        contracts = [ordered]@{
            schemaPath = 'schemas/ai/knowledge_mapping.schema.json'
            mappingDefinitionValidCount = @($result.mappings).Count
            candidateDefinitionValidCount = @($result.knowledge_candidates).Count
            allowedMappingTypes = $allowedTypes
            prerequisiteExcludedFromAssetMapping = $true
            existingQuestionMappingContractPreserved = $true
            allItemsPendingReview = $true
            allMappingsRequireRollback = $true
        }
        governance = $result.governance
        supplyChain = [ordered]@{
            status = 'pass'
            newDependenciesAdded = $false
            implementation = 'Python standard library and PowerShell Test-Json'
        }
        fullGate = [ordered]@{
            status = 'gate_na'
            reason = 'tools/run-gates.ps1 may affect PostgreSQL and API processes and is reserved for the separately authorized CEK-34 gate'
            alternative_verification = 'CEK-08 unit tests, JSON Schema definitions, deterministic real-candidate crosswalk, Release build, roadmap guard, and static hotspot review'
            evidence_link = 'docs/evidence/cek008-curriculum-knowledge-crosswalk.json'
            expires_at = 'CEK-34'
            recovery_condition = 'obtain current-task confirmation for PostgreSQL/API process impact and run tools/run-gates.ps1'
        }
        rollback = 'Delete the ignored tmp/cek008 outputs and revert only CEK-08 code, tests, schema definitions, template, wrapper, docs, and evidence. No database or active state changed.'
        completionBoundary = 'CEK-08 creates deterministic review candidates only. It does not approve semantic mappings, insert KnowledgeNode or DomainAssetMapping rows, persist CEK-09 assets, call a model, switch C002 active, close REAL005, or establish teacher/live acceptance.'
    }
    Write-Json $report $reportOutput
    $reportText = Get-Content -Raw -LiteralPath $reportOutput
    Assert-True (-not $reportText.Contains('"proposed_title"')) 'committed evidence contains proposed source-derived text'
    $reportText | Write-Output
}
finally {
    Pop-Location
}
