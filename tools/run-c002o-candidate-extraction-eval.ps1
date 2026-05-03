param(
    [string] $SuitePath = 'configs\ai-evals\c002o-candidate-extraction-evals.sample.json',
    [string] $Output = 'docs\evidence\c002o-candidate-extraction-eval-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Get-JsonProperty($Object, [string] $Name) {
    if ($null -eq $Object) { return $null }
    return $Object.PSObject.Properties[$Name]
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Get-C002NAnchors($Report) {
    $anchors = @{}
    foreach ($source in @($Report.sources)) {
        foreach ($chunk in @($source.sampleChunks)) {
            $anchors[$chunk.chunkHash] = [ordered]@{
                sourceHash = [string]$source.sourceHash
                relativePath = [string]$source.relativePath
                pageNumber = [int]$chunk.pageNumber
                chunkHash = [string]$chunk.chunkHash
            }
        }
    }
    return $anchors
}

function Replace-AnchorPlaceholders($Value, $Anchors) {
    $anchorValues = @($Anchors.Values)
    Assert-True ($anchorValues.Count -ge 4) "C002N report must expose at least four sample chunks for C002O eval"

    if ($Value -is [System.Array]) {
        $items = @()
        foreach ($item in $Value) {
            $items += Replace-AnchorPlaceholders $item $Anchors
        }
        return $items
    }

    if ($Value -is [pscustomobject]) {
        $sourceHashProperty = Get-JsonProperty $Value 'source_hash'
        $chunkHashProperty = Get-JsonProperty $Value 'chunk_hash'
        $hasAnchorPlaceholder = (
            ($null -ne $sourceHashProperty -and $sourceHashProperty.Value -eq 'SOURCE_HASH_FROM_C002N_REPORT') -or
            ($null -ne $chunkHashProperty -and $chunkHashProperty.Value -eq 'CHUNK_HASH_FROM_C002N_REPORT')
        )
        $copy = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $copy[$property.Name] = Replace-AnchorPlaceholders $property.Value $Anchors
        }
        if ($hasAnchorPlaceholder) {
            $relativePath = [string]($copy['relative_path'] ?? '')
            $matchingAnchors = @($anchorValues | Where-Object { $_.relativePath -eq $relativePath })
            $anchor = if ($matchingAnchors.Count -gt 0) {
                $matchingAnchors[0]
            }
            else {
                $index = [Math]::Abs($relativePath.GetHashCode()) % $anchorValues.Count
                $anchorValues[$index]
            }
            $copy['source_hash'] = $anchor.sourceHash
            $copy['relative_path'] = $anchor.relativePath
            $copy['page_number'] = $anchor.pageNumber
            $copy['chunk_hash'] = $anchor.chunkHash
        }
        return [pscustomobject]$copy
    }

    if ($Value -eq 'CHUNK_HASH_FROM_C002N_REPORT') {
        return [string]$anchorValues[0].chunkHash
    }
    if ($Value -eq 'SOURCE_HASH_FROM_C002N_REPORT') {
        return [string]$anchorValues[0].sourceHash
    }
    return $Value
}

function Test-C002OSchemaShape($Schema) {
    foreach ($required in @(
        'knowledge_points',
        'curriculum_standard_items',
        'textbook_chapters',
        'exam_points',
        'trend_summaries',
        'mapping_suggestions'
    )) {
        Assert-True ($Schema.required -contains $required) "C002O schema missing required section: $required"
        Assert-True ($null -ne (Get-JsonProperty $Schema.properties $required)) "C002O schema missing property: $required"
    }
}

function Test-C002OOutput($OutputValue, $KnownAnchors) {
    Assert-True ($OutputValue.mode -eq 'draft_test') "C002O output must stay draft_test"
    Assert-True ($OutputValue.production_eligible -eq $false) "C002O output must not be production eligible"
    Assert-True ($OutputValue.review_status -eq 'pending_review') "C002O output must stay pending_review"

    foreach ($section in @(
        'knowledge_points',
        'curriculum_standard_items',
        'textbook_chapters',
        'exam_points',
        'trend_summaries',
        'mapping_suggestions'
    )) {
        Assert-True (@($OutputValue.$section).Count -ge 1) "C002O output missing section item: $section"
        foreach ($item in @($OutputValue.$section)) {
            Assert-True ($item.review_status -eq 'pending_review') "C002O $section item must stay pending_review"
            foreach ($chunkHash in @($item.source_anchor_refs)) {
                Assert-True ($KnownAnchors.ContainsKey([string]$chunkHash)) "C002O $section references unknown chunk hash"
            }
        }
    }

    foreach ($anchor in @($OutputValue.source_anchors)) {
        Assert-True ($KnownAnchors.ContainsKey([string]$anchor.chunk_hash)) "C002O source anchor references unknown chunk hash"
        $known = $KnownAnchors[[string]$anchor.chunk_hash]
        Assert-True ($anchor.source_hash -eq $known.sourceHash) "C002O source anchor hash mismatch"
        Assert-True ($anchor.page_number -eq $known.pageNumber) "C002O source anchor page mismatch"
    }
}

Push-Location $repoRoot
try {
    $resolvedSuite = (Resolve-Path -LiteralPath $SuitePath).Path
    $suite = Get-Content -LiteralPath $resolvedSuite -Raw | ConvertFrom-Json
    Assert-True ($suite.mode -eq 'draft_test') "C002O eval suite must stay draft_test"
    Assert-True ($suite.allowRealModelCalls -eq $false) "C002O eval suite must not allow real model calls"
    Assert-True ($suite.productionEligible -eq $false) "C002O eval suite must not be production eligible"

    $c002nReportPath = Join-Path $repoRoot $suite.sourceChunkReport
    Assert-True (Test-Path -LiteralPath $c002nReportPath) "C002O requires C002N chunk report"
    $c002nReport = Get-Content -LiteralPath $c002nReportPath -Raw | ConvertFrom-Json
    Assert-True ($c002nReport.status -eq 'pass') "C002N report must pass before C002O"
    Assert-True ($c002nReport.externalAiCalls -eq 0) "C002N report must have zero external AI calls"
    $knownAnchors = Get-C002NAnchors $c002nReport

    $caseResults = New-Object System.Collections.Generic.List[object]
    foreach ($case in @($suite.cases)) {
        Assert-True ($case.taskType -eq 'c002_candidate_extraction') "unexpected C002O case taskType"
        Assert-True ($case.expectedReviewStatus -eq 'pending_review') "C002O eval case must stay pending_review"
        $schemaPath = Join-Path $repoRoot $case.schemaPath
        Assert-True (Test-Path -LiteralPath $schemaPath) "C002O schema does not exist: $($case.schemaPath)"
        $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
        Test-C002OSchemaShape $schema

        $expectedOutput = Replace-AnchorPlaceholders $case.expectedOutput $knownAnchors
        Test-C002OOutput $expectedOutput $knownAnchors

        $caseResults.Add([ordered]@{
            caseId = [string]$case.caseId
            schemaPath = [string]$case.schemaPath
            knowledgePoints = @($expectedOutput.knowledge_points).Count
            curriculumStandardItems = @($expectedOutput.curriculum_standard_items).Count
            textbookChapters = @($expectedOutput.textbook_chapters).Count
            examPoints = @($expectedOutput.exam_points).Count
            trendSummaries = @($expectedOutput.trend_summaries).Count
            mappingSuggestions = @($expectedOutput.mapping_suggestions).Count
            reviewStatus = [string]$expectedOutput.review_status
        })
    }

    $report = [ordered]@{
        status = 'pass'
        task = 'C002O'
        suiteId = [string]$suite.suiteId
        mode = [string]$suite.mode
        allowRealModelCalls = [bool]$suite.allowRealModelCalls
        productionEligible = [bool]$suite.productionEligible
        sourceChunkReport = [string]$suite.sourceChunkReport
        checkedAnchorCount = $knownAnchors.Count
        cases = $caseResults
        summaryChinese = [ordered]@{
            title = 'C002O 大模型提炼 schema/eval 报告'
            result = '通过'
            boundary = '仅验证结构化输出 schema 与 golden fixture，不调用真实模型，不写入 active。'
            next = '下一步可进入 C002P 分层模型路由预算门禁完整收口。'
        }
    }
    $outputPath = Join-Path $repoRoot $Output
    New-Item -ItemType Directory -Path (Split-Path -Parent $outputPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}
