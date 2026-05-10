param(
    [string] $SourcesPath = 'configs/technology-refresh.sources.yaml',
    [string] $CapabilityTaxonomyPath = 'configs/capability-taxonomy.yaml',
    [string] $ModelCatalogPath = 'configs/model-admission.catalog.yaml',
    [string] $OcrCatalogPath = 'configs/ocr-engine-admission.catalog.yaml',
    [string] $ReportPath = 'docs/evidence/technology-refresh-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Read-Yaml([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "missing technology refresh file: $Path"
    }

    $json = python -c "import json, pathlib, yaml; print(json.dumps(yaml.safe_load(pathlib.Path(r'$fullPath').read_text(encoding='utf-8')), ensure_ascii=False))"
    if ($LASTEXITCODE -ne 0) {
        throw "failed to parse yaml: $Path"
    }

    return $json | ConvertFrom-Json
}

function Assert-Contains([object[]] $Values, [string] $Expected, [string] $Message) {
    if ($Values -notcontains $Expected) {
        throw $Message
    }
}

Push-Location $repoRoot
try {
    $sources = Read-Yaml $SourcesPath
    $capability = Read-Yaml $CapabilityTaxonomyPath
    $models = Read-Yaml $ModelCatalogPath
    $ocr = Read-Yaml $OcrCatalogPath

    if ($sources.mode -ne 'report_only') { throw 'technology refresh sources must stay report_only' }
    if ($sources.networkAccessDefault -ne $false) { throw 'technology refresh must not require default network access' }
    foreach ($action in @(
        'install_system_dependency',
        'download_model_weights',
        'change_default_ocr_route',
        'change_default_ai_route',
        'process_real_unredacted_material',
        'write_active_production_config'
    )) {
        Assert-Contains -Values $sources.forbiddenActions -Expected $action -Message "missing forbidden action: $action"
    }

    if (($sources.sourceTiers | Where-Object { $_.id -eq 'official_vendor_docs' -and $_.trustLevel -eq 'high' }).Count -lt 1) {
        throw 'missing high-trust official vendor source tier'
    }
    if (($sources.sourceTiers | Where-Object { $_.id -eq 'official_model_cards' -and $_.trustLevel -eq 'high' }).Count -lt 1) {
        throw 'missing high-trust official model card source tier'
    }
    if (($sources.sourceTiers | Where-Object { $_.id -eq 'community_reference_projects' -and $_.trustLevel -eq 'medium' }).Count -lt 1) {
        throw 'missing medium-trust community reference tier'
    }

    foreach ($profile in @('cpu_low', 'cpu_standard', 'gpu_entry', 'gpu_high')) {
        if (($capability.profiles | Where-Object { $_.id -eq $profile }).Count -lt 1) {
            throw "missing capability profile: $profile"
        }
    }

    if ($models.defaultRouteChangeAllowed -ne $false) { throw 'model default route changes must be blocked' }
    if ($models.downloadAllowedByAutomation -ne $false) { throw 'model downloads must require manual confirmation' }
    foreach ($evidence in @('official_model_card_or_owner_release', 'hardware_profile_match', 'golden_set_eval', 'rollback_plan')) {
        Assert-Contains -Values $models.admissionRequiredEvidence -Expected $evidence -Message "missing model admission evidence: $evidence"
    }

    if ($ocr.defaultRouteChangeAllowed -ne $false) { throw 'OCR default route changes must be blocked' }
    if ($ocr.installAllowedByAutomation -ne $false) { throw 'OCR installs must require manual confirmation' }
    foreach ($evidence in @('official_docs_or_owner_release', 'hardware_profile_match', 'golden_set_eval', 'formula_table_figure_regression', 'teacher_takeover_path', 'rollback_plan')) {
        Assert-Contains -Values $ocr.admissionRequiredEvidence -Expected $evidence -Message "missing OCR admission evidence: $evidence"
    }

    $report = [ordered]@{
        status = 'pass'
        task = 'O008'
        mode = 'report_only'
        checkedAt = (Get-Date).ToString('s')
        sources = [ordered]@{
            path = $SourcesPath
            sourceTierCount = @($sources.sourceTiers).Count
            aiApiAllowedUses = @($sources.aiApiAllowedUses)
            forbiddenActions = @($sources.forbiddenActions)
        }
        capabilityTaxonomy = [ordered]@{
            path = $CapabilityTaxonomyPath
            profiles = @($capability.profiles | ForEach-Object { $_.id })
        }
        modelCatalog = [ordered]@{
            path = $ModelCatalogPath
            candidateCount = @($models.candidates).Count
            defaultRouteChangeAllowed = $models.defaultRouteChangeAllowed
            downloadAllowedByAutomation = $models.downloadAllowedByAutomation
        }
        ocrCatalog = [ordered]@{
            path = $OcrCatalogPath
            candidateCount = @($ocr.candidates).Count
            defaultRouteChangeAllowed = $ocr.defaultRouteChangeAllowed
            installAllowedByAutomation = $ocr.installAllowedByAutomation
        }
        boundaries = [ordered]@{
            noInstall = $true
            noDownload = $true
            noDefaultRouteChange = $true
            noRealMaterialProcessing = $true
            noProductionWrite = $true
        }
        rollback = [ordered]@{
            docs = 'git revert O008 roadmap/catalog changes'
            runtime = 'no runtime, dependency, model, OCR route, or production config was changed by this contract'
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $ReportPath) -Force | Out-Null
    $json = $report | ConvertTo-Json -Depth 10
    $json | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    $json
}
finally {
    Pop-Location
}
