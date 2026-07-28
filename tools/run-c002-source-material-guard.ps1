param(
    [string] $ManifestPath = 'configs\knowledge\source-material-manifest.example.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$manifestCandidate = if ([System.IO.Path]::IsPathRooted($ManifestPath)) { $ManifestPath } else { Join-Path $repoRoot $ManifestPath }
$resolvedManifestPath = (Resolve-Path -LiteralPath $manifestCandidate).Path
$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json

function Assert-Fields([object] $Value, [string[]] $Fields, [string] $Label) {
    foreach ($field in $Fields) {
        if (-not ($Value.PSObject.Properties.Name -contains $field)) {
            throw "$Label missing field: $field"
        }
    }
}

function Get-PdfFacts([string] $Path) {
    $inspector = @'
import json
import pathlib
import sys
from pypdf import PdfReader

path = pathlib.Path(sys.argv[1])
reader = PdfReader(str(path))
texts = [page.extract_text() or "" for page in reader.pages]
print(json.dumps({
    "pageCount": len(reader.pages),
    "textCharacterCount": sum(len(text) for text in texts),
    "nonEmptyPageCount": sum(bool(text.strip()) for text in texts),
}))
'@
    $output = & python -c $inspector $Path
    if ($LASTEXITCODE -ne 0) {
        throw "failed to inspect curriculum PDF text layer: $Path"
    }
    return $output | ConvertFrom-Json
}

if ($manifest.manifestVersion -ne 'knowledge-source-materials.v1') {
    throw 'unexpected manifestVersion'
}

if ($manifest.subject -ne 'physics' -or $manifest.stage -ne 'junior_middle_school') {
    throw 'C002 source manifest must target junior middle school physics'
}

$materials = @($manifest.materials)
if ($materials.Count -lt 1) {
    throw 'C002 source manifest must include at least one material entry'
}
$duplicateIds = @($materials | Group-Object materialId | Where-Object Count -gt 1)
if ($duplicateIds.Count -gt 0) {
    throw "C002 source manifest contains duplicate materialId values: $(($duplicateIds.Name | Sort-Object) -join ',')"
}

$fixedCurriculumId = 'curriculum-physics-junior-2022-2025-revision'
$curriculumOnly = $materials.Count -eq 1 -and
    $materials[0].materialId -eq $fixedCurriculumId -and
    $materials[0].sourceType -eq 'curriculum_standard'
$requiredTypes = if ($curriculumOnly) {
    @('curriculum_standard')
}
else {
    @('textbook', 'curriculum_standard', 'local_exam_paper')
}
foreach ($requiredType in $requiredTypes) {
    if (-not ($materials | Where-Object { $_.sourceType -eq $requiredType })) {
        throw "missing required C002 source type: $requiredType"
    }
}

$allowedTypes = @('textbook', 'curriculum_standard', 'local_exam_paper', 'exam_analysis_report', 'school_paper', 'teacher_original', 'region_exam_point')
$verifiedFileCount = 0
$verifiedPdfCount = 0
foreach ($material in $materials) {
    Assert-Fields -Value $material -Label "material $($material.materialId)" -Fields @(
        'materialId',
        'sourceType',
        'title',
        'publisherOrAuthority',
        'editionOrVersion',
        'year',
        'region',
        'gradeOrScope',
        'localPath',
        'sha256',
        'licenseOrPermission',
        'sharingAllowed',
        'containsStudentPii',
        'anonymizationStatus',
        'mayUseForKnowledgeExtraction',
        'mayUseForExamPointExtraction',
        'mayUseForTrendAnalysis'
    )

    if ([string]::IsNullOrWhiteSpace([string]$material.materialId)) {
        throw 'source materialId must not be blank'
    }
    if ($material.sourceType -notin $allowedTypes) {
        throw "material $($material.materialId) has unsupported sourceType: $($material.sourceType)"
    }
    if ($material.localPath -match '^(?i)(sources/|\.\/|\.\\)' -or $material.localPath -match '(?i)D:/CODE|D:\\CODE') {
        throw "material $($material.materialId) must not point to committed repo source files"
    }
    if ($material.sha256 -notmatch '^(REPLACE_WITH_64_HEX_SHA256|[a-fA-F0-9]{64})$') {
        throw "material $($material.materialId) sha256 must be a 64-char hex digest or placeholder"
    }

    $isTemplate = $material.sha256 -eq 'REPLACE_WITH_64_HEX_SHA256'
    if (-not $isTemplate) {
        if (-not [System.IO.Path]::IsPathRooted([string]$material.localPath)) {
            throw "material $($material.materialId) real localPath must be absolute"
        }
        if (-not (Test-Path -LiteralPath $material.localPath -PathType Leaf)) {
            throw "material $($material.materialId) localPath does not exist: $($material.localPath)"
        }
        $actualHash = (Get-FileHash -LiteralPath $material.localPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne ([string]$material.sha256).ToLowerInvariant()) {
            throw "material $($material.materialId) localPath hash mismatch"
        }
        $verifiedFileCount++
    }

    if ($material.containsStudentPii -and $material.anonymizationStatus -notin @('anonymized', 'synthetic')) {
        throw "material $($material.materialId) contains PII without anonymization"
    }
    if ($material.sourceType -in @('textbook', 'curriculum_standard') -and $material.mayUseForKnowledgeExtraction -ne $true) {
        throw "material $($material.materialId) is not approved for knowledge extraction"
    }
    if ($material.sourceType -in @('local_exam_paper', 'exam_analysis_report') -and $material.mayUseForExamPointExtraction -ne $true) {
        throw "material $($material.materialId) is not approved for exam point extraction"
    }

    if ($material.sourceType -eq 'curriculum_standard') {
        Assert-Fields -Value $material -Label "curriculum material $($material.materialId)" -Fields @(
            'sizeBytes',
            'modifiedAtUtc',
            'pageCount',
            'textLayer'
        )
        Assert-Fields -Value $material.textLayer -Label "curriculum material $($material.materialId) textLayer" -Fields @(
            'present',
            'nonEmptyPageCount',
            'characterCount',
            'extractor'
        )
        if ($material.sharingAllowed -ne $false -or $material.containsStudentPii -ne $false) {
            throw "curriculum material $($material.materialId) must remain local-only and non-PII"
        }
        if ($material.mayUseForExamPointExtraction -ne $false -or $material.mayUseForTrendAnalysis -ne $false) {
            throw "curriculum material $($material.materialId) cannot authorize exam-point or trend extraction"
        }
        if ($material.textLayer.present -ne $true -or
            [int]$material.pageCount -lt 1 -or
            [int]$material.textLayer.nonEmptyPageCount -ne [int]$material.pageCount -or
            [int]$material.textLayer.characterCount -lt 1) {
            throw "curriculum material $($material.materialId) does not have a complete OCR text-layer contract"
        }

        if ($material.materialId -eq $fixedCurriculumId) {
            if ($material.title -ne '义务教育物理课程标准 日常修订版' -or
                $material.publisherOrAuthority -ne '中华人民共和国教育部' -or
                $material.editionOrVersion -ne '2022_2025_revision' -or
                [int]$material.year -ne 2025 -or
                $material.region -ne 'China' -or
                $material.gradeOrScope -ne 'junior_middle_school' -or
                [long]$material.sizeBytes -ne 1689021 -or
                [int]$material.pageCount -ne 67 -or
                [int]$material.textLayer.nonEmptyPageCount -ne 67 -or
                [int]$material.textLayer.characterCount -ne 37615) {
                throw "fixed curriculum material $fixedCurriculumId facts drifted"
            }
            if (-not $isTemplate -and ([string]$material.sha256).ToLowerInvariant() -ne 'e00a5665e7e17ea6bdd6236d9366c51c63bbe6cc0eabf83ac3d0a529c487dd8c') {
                throw "fixed curriculum material $fixedCurriculumId SHA-256 drifted"
            }
        }

        if (-not $isTemplate) {
            if ([string]::IsNullOrWhiteSpace([string]$material.licenseOrPermission) -or
                $material.licenseOrPermission -match '^(?i)(unknown|none|pending_source_workbench_review|REPLACE_)') {
                throw "curriculum material $($material.materialId) is not authorized for local knowledge extraction"
            }
            $item = Get-Item -LiteralPath $material.localPath
            if ($item.Length -ne [long]$material.sizeBytes) {
                throw "curriculum material $($material.materialId) size mismatch"
            }
            try {
                $expectedModifiedAt = if ($material.modifiedAtUtc -is [DateTime]) {
                    [DateTimeOffset]::new($material.modifiedAtUtc.ToUniversalTime(), [TimeSpan]::Zero)
                }
                elseif ($material.modifiedAtUtc -is [DateTimeOffset]) {
                    $material.modifiedAtUtc.ToUniversalTime()
                }
                else {
                    [DateTimeOffset]::Parse([string]$material.modifiedAtUtc).ToUniversalTime()
                }
            }
            catch {
                throw "curriculum material $($material.materialId) modifiedAtUtc is invalid"
            }
            $actualModifiedAt = [DateTimeOffset]$item.LastWriteTimeUtc
            if ([Math]::Abs(($actualModifiedAt - $expectedModifiedAt).TotalMilliseconds) -ge 1) {
                throw "curriculum material $($material.materialId) modified time mismatch"
            }
            $stream = [System.IO.File]::OpenRead($item.FullName)
            try {
                $magic = New-Object byte[] 5
                $read = $stream.Read($magic, 0, $magic.Length)
                if ($read -ne 5 -or [System.Text.Encoding]::ASCII.GetString($magic) -ne '%PDF-') {
                    throw "curriculum material $($material.materialId) has invalid PDF magic"
                }
            }
            finally {
                $stream.Dispose()
            }

            $pdfFacts = Get-PdfFacts -Path $item.FullName
            if ($pdfFacts.pageCount -ne [int]$material.pageCount -or
                $pdfFacts.nonEmptyPageCount -ne [int]$material.textLayer.nonEmptyPageCount -or
                $pdfFacts.textCharacterCount -ne [int]$material.textLayer.characterCount) {
                throw "curriculum material $($material.materialId) PDF/text facts mismatch"
            }
            $verifiedPdfCount++
        }
    }
}

$gitignore = Get-Content -LiteralPath (Join-Path $repoRoot '.gitignore') -Raw
foreach ($pattern in @(
    'configs/knowledge/source-material-manifest.local.json',
    'configs/knowledge/c002-formal-knowledge.local.csv',
    'configs/knowledge/c002-exam-point.local.csv',
    'configs/knowledge/c002-textbook-chapter.local.csv',
    'configs/knowledge/c002-curriculum-standard.local.csv',
    'configs/knowledge/c002-asset-mapping.local.csv',
    'configs/knowledge/c002-external-ai-candidate.local.csv',
    'sources/knowledge-materials/'
)) {
    if (-not $gitignore.Contains($pattern)) {
        throw ".gitignore missing C002 source material guard pattern: $pattern"
    }
}

[ordered]@{
    status = 'pass'
    manifest = $ManifestPath
    admissionProfile = if ($curriculumOnly) { 'single_curriculum_standard' } else { 'c002_source_bundle' }
    materialCount = $materials.Count
    requiredTypes = @($requiredTypes)
    optionalTypes = @('exam_analysis_report', 'school_paper', 'teacher_original')
    verifiedFileCount = $verifiedFileCount
    verifiedPdfCount = $verifiedPdfCount
    realFilesMustStayOutsideGit = $true
    curriculumUseBoundaryEnforced = $true
} | ConvertTo-Json
