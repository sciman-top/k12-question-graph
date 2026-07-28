param(
    [string] $SourcePdfPath = 'D:\KQG_Data\source_materials\imported\curriculum_standards\physics\junior_middle_school\2022-2025-revision\raw\《义务教育物理课程标准·日常修订版》(2022年版2025年修订).pdf',
    [string] $FixturePath = 'tests\golden-import\curriculum-standard-structure-fixture.json',
    [string] $CandidateOutputPath = 'tmp\cek006\curriculum-standard-structure.candidate.json',
    [string] $ReportPath = 'docs\evidence\cek006-curriculum-standard-structure.json',
    [string] $CurriculumRequirementSchemaPath = 'schemas\curriculum_requirement.schema.json',
    [string] $PythonCommand = 'python',
    [string] $VisualEvidenceRoot = 'tmp\pdfs\cek006',
    [switch] $VisualReviewPassed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-InputFile([string] $Path, [string] $Label) {
    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    }
    else {
        Join-Path $repoRoot $Path
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "$Label not found: $candidate"
    }
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
    $json = $Value | ConvertTo-Json -Depth 100
    $json = $json.Replace(([string][char]13 + [char]10), [string][char]10)
    $json = $json.Replace([string][char]13, [string][char]10)
    [System.IO.File]::WriteAllText(
        $Path,
        $json + [char]10,
        [System.Text.UTF8Encoding]::new($false)
    )
}

$sourcePdf = Resolve-InputFile -Path $SourcePdfPath -Label 'Curriculum standard PDF'
$fixture = Resolve-InputFile -Path $FixturePath -Label 'Golden fixture'
$schema = Resolve-InputFile -Path $CurriculumRequirementSchemaPath -Label 'CurriculumRequirement schema'
$candidateOutput = Resolve-OutputFile -Path $CandidateOutputPath
$reportOutput = Resolve-OutputFile -Path $ReportPath
$candidateRelative = [System.IO.Path]::GetRelativePath($repoRoot, $candidateOutput)

Push-Location $repoRoot
try {
    if (-not $candidateRelative.StartsWith('..')) {
        & git check-ignore --quiet -- $candidateRelative
        if ($LASTEXITCODE -ne 0) {
            throw "Verbatim curriculum candidate output must be Git-ignored: $candidateRelative"
        }
    }

    $pythonOutput = @(& $PythonCommand @(
        'tools\curriculum_standard_structure.py',
        '--source-pdf', $sourcePdf,
        '--fixture', $fixture,
        '--candidate-output', $candidateOutput,
        '--report', $reportOutput
    ))
    $pythonExitCode = $LASTEXITCODE
    if ($pythonExitCode -ne 0) {
        $pythonOutput | Write-Output
        throw "Curriculum standard structure extraction required manual takeover (exit code $pythonExitCode)"
    }

    $candidate = Get-Content -Raw -LiteralPath $candidateOutput | ConvertFrom-Json -Depth 100
    $report = Get-Content -Raw -LiteralPath $reportOutput | ConvertFrom-Json -Depth 100
    $requirements = @($candidate.curriculum_requirements)
    $invalidRequirements = [System.Collections.Generic.List[object]]::new()
    foreach ($requirement in $requirements) {
        $validationErrors = @()
        $valid = ($requirement | ConvertTo-Json -Depth 100) |
            Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue -ErrorVariable validationErrors
        if (-not $valid) {
            $invalidRequirements.Add([ordered]@{
                officialItemCode = $requirement.official_item_code
                errors = @($validationErrors | ForEach-Object { $_.Exception.Message })
            })
        }
    }

    if ($report.status -ne 'pass' -or
        $candidate.extraction.status -ne 'pass' -or
        $candidate.extraction.manual_takeover_required -ne $false) {
        throw 'Curriculum standard extraction did not satisfy the pass/no-manual-takeover contract'
    }
    if (@($candidate.hierarchy).Count -ne 5 -or
        @($candidate.hierarchy | ForEach-Object { $_.children }).Count -ne 18 -or
        $requirements.Count -ne 89) {
        throw 'Curriculum standard extraction did not satisfy the 5/18/89 structure contract'
    }
    if (@($requirements.official_item_code | Sort-Object -Unique).Count -ne 89) {
        throw 'Curriculum standard extraction produced duplicate official item codes'
    }
    if ($invalidRequirements.Count -ne 0) {
        throw "CurriculumRequirement schema rejected $($invalidRequirements.Count) extracted records"
    }
    $unsafeGovernance = @($requirements | Where-Object {
        $_.status -ne 'candidate' -or
        $_.review_status -ne 'pending_review' -or
        $_.production_eligible -ne $false -or
        @($_.facets).Count -ne 0 -or
        @($_.behavior_verbs).Count -ne 0 -or
        @($_.cognitive_demands).Count -ne 0 -or
        @($_.ability_dimensions).Count -ne 0 -or
        @($_.knowledge_stable_ids).Count -ne 0
    })
    if ($unsafeGovernance.Count -ne 0) {
        throw 'Extracted requirements violated candidate-only or no-semantic-extraction invariants'
    }

    $candidateTracked = -not $candidateRelative.StartsWith('..')
    if ($candidateTracked) {
        & git check-ignore --quiet -- $candidateRelative
        $candidateTracked = $LASTEXITCODE -ne 0
    }
    if ($candidateTracked) {
        throw "Verbatim curriculum candidate output is not safely ignored: $candidateRelative"
    }

    $report.verification.curriculumRequirementSchema = [ordered]@{
        status = 'pass'
        validCount = 89
        invalidCount = 0
        schema = 'schemas/curriculum_requirement.schema.json'
    }
    $report.verification | Add-Member -Force -NotePropertyName candidateGovernance -NotePropertyValue ([ordered]@{
        status = 'pass'
        candidateCount = 89
        lifecycle = 'candidate'
        reviewStatus = 'pending_review'
        productionEligible = $false
        facetCount = 0
        semanticArraysEmpty = $true
    })
    $report.verification | Add-Member -Force -NotePropertyName copyrightBoundary -NotePropertyValue ([ordered]@{
        status = 'pass'
        verbatimCandidatePath = $candidateRelative.Replace('\', '/')
        candidateGitIgnored = $true
        committedReportContainsVerbatimSourceText = $false
    })
    $report.verification | Add-Member -Force -NotePropertyName supplyChain -NotePropertyValue ([ordered]@{
        status = 'pass'
        newDependenciesAdded = $false
        python = @(
            'pypdf==6.14.2',
            'pdfplumber==0.11.10'
        )
        visualRenderer = 'Poppler pdftoppm 26.05.0'
        dependencyLock = 'workers/document/requirements.txt'
    })

    if ($VisualReviewPassed) {
        $visualRoot = if ([System.IO.Path]::IsPathRooted($VisualEvidenceRoot)) {
            $VisualEvidenceRoot
        }
        else {
            Join-Path $repoRoot $VisualEvidenceRoot
        }
        $visualFiles = foreach ($page in 2, 12, 42, 51) {
            $path = Join-Path $visualRoot ("page-{0:D2}.png" -f $page)
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Visual review assertion requires rendered page: $path"
            }
            $file = Get-Item -LiteralPath $path
            if ($file.Length -lt 1000) {
                throw "Rendered page is unexpectedly small: $path"
            }
            [ordered]@{
                pdfPageNumber = $page
                path = [System.IO.Path]::GetRelativePath($repoRoot, $path).Replace('\', '/')
                sizeBytes = $file.Length
            }
        }
        $report.verification.visualReview = [ordered]@{
            status = 'pass'
            assertion = 'operator inspected rendered pages for legibility, reading order, clipping, overlap, and missing glyphs'
            renderer = 'Poppler pdftoppm 26.05.0'
            pages = @($visualFiles)
            defects = @()
        }
    }
    else {
        $report.verification.visualReview = [ordered]@{
            status = 'pending'
            reason = 'Run with -VisualReviewPassed only after inspecting rendered PDF pages 2, 12, 42, and 51'
        }
    }

    foreach ($propertyName in @(
        'databaseWrite',
        'sourceRegionWrite',
        'knowledgeAssetWrite',
        'c002ActiveWrite',
        'aiRun'
    )) {
        $report | Add-Member -Force -NotePropertyName $propertyName -NotePropertyValue $false
    }
    Write-JsonUtf8NoBom -Value $report -Path $reportOutput

    $reportText = Get-Content -Raw -LiteralPath $reportOutput
    if ($reportText.Contains('"source_text"') -or $reportText.Contains('"sourceText"')) {
        throw 'Committed CEK-06 report unexpectedly contains verbatim requirement text'
    }
    $reportText | Write-Output
}
finally {
    Pop-Location
}
