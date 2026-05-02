param(
    [string] $ManifestPath = 'configs\knowledge\source-material-manifest.example.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$resolvedManifestPath = (Resolve-Path -LiteralPath (Join-Path $repoRoot $ManifestPath)).Path
$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json

if ($manifest.manifestVersion -ne 'knowledge-source-materials.v1') {
    throw "unexpected manifestVersion"
}

if ($manifest.subject -ne 'physics' -or $manifest.stage -ne 'junior_middle_school') {
    throw "C002 source manifest must target junior middle school physics"
}

$materials = @($manifest.materials)
if ($materials.Count -lt 3) {
    throw "C002 source manifest must include at least textbook, curriculum standard, and local exam material entries"
}

$requiredTypes = @('textbook', 'curriculum_standard', 'local_exam_paper')
foreach ($requiredType in $requiredTypes) {
    if (-not ($materials | Where-Object { $_.sourceType -eq $requiredType })) {
        throw "missing required C002 source type: $requiredType"
    }
}

$allowedTypes = @('textbook', 'curriculum_standard', 'local_exam_paper', 'school_paper', 'teacher_original', 'region_exam_point')
foreach ($material in $materials) {
    foreach ($field in @('materialId', 'sourceType', 'title', 'publisherOrAuthority', 'year', 'localPath', 'sha256', 'licenseOrPermission', 'containsStudentPii', 'anonymizationStatus', 'mayUseForKnowledgeExtraction')) {
        if (-not ($material.PSObject.Properties.Name -contains $field)) {
            throw "material $($material.materialId) missing field: $field"
        }
    }

    if ($material.sourceType -notin $allowedTypes) {
        throw "material $($material.materialId) has unsupported sourceType: $($material.sourceType)"
    }

    if ($material.localPath -match '^(?i)(sources/|\.\\/|\.\\\\)' -or $material.localPath -match '(?i)D:/CODE|D:\\CODE') {
        throw "material $($material.materialId) must not point to committed repo source files"
    }

    if ($material.sha256 -notmatch '^(REPLACE_WITH_64_HEX_SHA256|[a-fA-F0-9]{64})$') {
        throw "material $($material.materialId) sha256 must be a 64-char hex digest or placeholder"
    }

    if ($material.containsStudentPii -and $material.anonymizationStatus -notin @('anonymized', 'synthetic')) {
        throw "material $($material.materialId) contains PII without anonymization"
    }

    if ($material.mayUseForKnowledgeExtraction -ne $true) {
        throw "material $($material.materialId) is not approved for knowledge extraction"
    }
}

$gitignore = Get-Content -LiteralPath (Join-Path $repoRoot '.gitignore') -Raw
foreach ($pattern in @('configs/knowledge/source-material-manifest.local.json', 'sources/knowledge-materials/')) {
    if (-not $gitignore.Contains($pattern)) {
        throw ".gitignore missing C002 source material guard pattern: $pattern"
    }
}

[ordered]@{
    status = 'pass'
    manifest = $ManifestPath
    materialCount = $materials.Count
    requiredTypes = $requiredTypes
    realFilesMustStayOutsideGit = $true
} | ConvertTo-Json
