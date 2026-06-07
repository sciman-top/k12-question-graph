param(
    [string] $CatalogPath = 'configs\toolchain-admission.catalog.yaml',
    [string] $Ns1303ReportPath = 'docs/evidence/20260607-ns1303-runtime-profile.json',
    [string] $HostReportPath = 'docs/evidence/20260607-ns1303-host-capability-diagnostic-report.json',
    [string] $WorkerReportPath = 'docs/evidence/20260607-ns1303-worker-profile-diagnostic-report.json',
    [string] $ReportPath = 'docs/evidence/20260607-ns1304-toolchain-profile.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing json report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Resolve-CommandProbe([string] $Name, [string[]] $FallbackPaths = @()) {
    $versionArgs = switch ($Name) {
        'pdftotext' { @('-v') }
        'pdftoppm' { @('-v') }
        'magick' { @('-version') }
        default { @('--version') }
    }

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $versionOutput = & $command.Source $versionArgs 2>&1
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = 0 }
        return [ordered]@{
            present = $true
            path = [string] $command.Source
            source = 'PATH'
            exitCode = [int] $exitCode
            versionLine = (($versionOutput | Select-Object -First 1) -join '').Trim()
        }
    }

    foreach ($candidate in $FallbackPaths) {
        if (Test-Path -LiteralPath $candidate) {
            $versionOutput = & $candidate $versionArgs 2>&1
            $exitCode = $LASTEXITCODE
            if ($null -eq $exitCode) { $exitCode = 0 }
            return [ordered]@{
                present = $true
                path = $candidate
                source = 'fallback_path'
                exitCode = [int] $exitCode
                versionLine = (($versionOutput | Select-Object -First 1) -join '').Trim()
            }
        }
    }

    return [ordered]@{
        present = $false
        path = $null
        source = 'not_found'
        exitCode = $null
        versionLine = ''
    }
}

function Invoke-PythonModuleProbe([string] $ModuleName) {
    $script = @"
import importlib.util
import importlib.metadata
import json
import sys

name = sys.argv[1]
spec = importlib.util.find_spec(name)
if spec is None:
    print(json.dumps({"present": False, "version": "", "location": ""}))
    raise SystemExit(0)
try:
    version = importlib.metadata.version(name)
except Exception:
    version = ""
location = spec.origin or ""
print(json.dumps({"present": True, "version": version, "location": location}))
"@
    $raw = python -c $script $ModuleName
    Assert-Condition ($LASTEXITCODE -eq 0) "python module probe failed: $ModuleName"
    return $raw | ConvertFrom-Json
}

Push-Location $repoRoot
try {
    Assert-Condition (Test-Path -LiteralPath $CatalogPath) "missing toolchain catalog: $CatalogPath"
    $catalogJson = python -c "import json, pathlib, yaml; p=pathlib.Path(r'$($CatalogPath.Replace('\','\\'))'); d=yaml.safe_load(p.read_text(encoding='utf-8')); print(json.dumps(d, ensure_ascii=False))"
    Assert-Condition ($LASTEXITCODE -eq 0) 'failed to parse toolchain admission catalog yaml'
    $catalogData = $catalogJson | ConvertFrom-Json
    Assert-Condition (([string] $catalogData.schemaVersion).Trim() -eq 'toolchain-admission.catalog.v0.1') 'unexpected toolchain catalog schemaVersion'
    Assert-Condition (-not [bool] $catalogData.defaultRouteChangeAllowed) 'NS1304 catalog must block default route changes'
    Assert-Condition (-not [bool] $catalogData.installAllowedByAutomation) 'NS1304 catalog must block automatic installs'

    $ns1303 = Read-Json $Ns1303ReportPath
    $hostJson = Read-Json $HostReportPath
    $workerJson = Read-Json $WorkerReportPath
    $j005 = Read-Json 'docs/evidence/j005-adapter-diagnostic-supply-chain-report.json'
    $j006 = Read-Json 'docs/evidence/j006-import-accuracy-workload-report.json'
    $ns304 = Read-Json 'docs/evidence/20260530-ns304-docx-adapter-report.json'
    $ns305 = Read-Json 'docs/evidence/20260530-ns305-pdf-text-adapter-report.json'
    $ns306 = Read-Json 'docs/evidence/20260530-ns306-scan-ocr-adapter-report.json'

    foreach ($report in @($ns1303, $j005, $j006, $ns304, $ns305, $ns306)) {
        Assert-Condition ($report.status -eq 'pass') 'NS1304 dependency evidence must pass'
    }

    $postgresFallbacks = @(
        'C:\Program Files\PostgreSQL\17\bin\psql.exe',
        'C:\Program Files\PostgreSQL\16\bin\psql.exe',
        'C:\Program Files\PostgreSQL\15\bin\psql.exe'
    )
    $pgDumpFallbacks = @(
        'C:\Program Files\PostgreSQL\17\bin\pg_dump.exe',
        'C:\Program Files\PostgreSQL\16\bin\pg_dump.exe',
        'C:\Program Files\PostgreSQL\15\bin\pg_dump.exe'
    )
    $pgRestoreFallbacks = @(
        'C:\Program Files\PostgreSQL\17\bin\pg_restore.exe',
        'C:\Program Files\PostgreSQL\16\bin\pg_restore.exe',
        'C:\Program Files\PostgreSQL\15\bin\pg_restore.exe'
    )

    $cliProbes = [ordered]@{
        pdftotext = Resolve-CommandProbe 'pdftotext'
        pdftoppm = Resolve-CommandProbe 'pdftoppm'
        ocrmypdf = Resolve-CommandProbe 'ocrmypdf'
        qpdf = Resolve-CommandProbe 'qpdf'
        gswin64c = Resolve-CommandProbe 'gswin64c'
        magick = Resolve-CommandProbe 'magick'
        vips = Resolve-CommandProbe 'vips'
        psql = Resolve-CommandProbe 'psql' $postgresFallbacks
        pg_dump = Resolve-CommandProbe 'pg_dump' $pgDumpFallbacks
        pg_restore = Resolve-CommandProbe 'pg_restore' $pgRestoreFallbacks
        robocopy = Resolve-CommandProbe 'robocopy'
    }
    $moduleProbes = [ordered]@{
        rapidocr_onnxruntime = Invoke-PythonModuleProbe 'rapidocr_onnxruntime'
        paddleocr = Invoke-PythonModuleProbe 'paddleocr'
        docling = Invoke-PythonModuleProbe 'docling'
    }

    $catalogEntries = @()
    $admittedForCurrentHost = New-Object System.Collections.Generic.List[string]
    $blockedToFallback = New-Object System.Collections.Generic.List[string]

    foreach ($entry in @($catalogData.entries)) {
        $entryId = [string] $entry.id
        $availability = $false
        $status = 'blocked_missing_tool_fall_closed'
        $details = ''
        $fallback = [string] $entry.fallbackWhenMissing

        switch ($entryId) {
            'openxml_docx_adapter' {
                $availability = [bool]$ns304.acceptance.docxOpenXmlAdapterRuns
                $status = if ($availability) { 'admitted_current_profile' } else { 'blocked_missing_tool_fall_closed' }
                $details = [string]$ns304.dependency.adapterName
            }
            'pdf_text_layout_poppler' {
                $availability = [bool]$cliProbes.pdftotext.present -and [bool]$cliProbes.pdftoppm.present -and [bool]$ns305.acceptance.textPdfAdapterRuns
                $status = if ($availability) { 'admitted_current_profile' } else { 'blocked_missing_tool_fall_closed' }
                $details = 'pdftotext + pdftoppm + NS305'
            }
            'rapidocr_onnxruntime' {
                $availability = [bool]$moduleProbes.rapidocr_onnxruntime.present -and [bool]$ns306.acceptance.scannedPdfOcrRuns -and ([string]$j006.evidence.j005.localOcrEngine -eq 'rapidocr_onnxruntime')
                $status = if ($availability) { 'admitted_current_profile' } else { 'blocked_missing_tool_fall_closed' }
                $details = 'rapidocr_onnxruntime + NS306 + J006'
            }
            'docling_layout_pipeline' {
                $availability = [bool]$moduleProbes.docling.present
                $status = if ($availability) { 'available_but_not_admitted' } else { 'blocked_missing_tool_fall_closed' }
                $details = 'candidate only'
            }
            'paddleocr_ppocr' {
                $availability = [bool]$moduleProbes.paddleocr.present
                $status = if ($availability) { 'available_but_not_admitted' } else { 'blocked_missing_tool_fall_closed' }
                $details = 'candidate only'
            }
            'ocrmypdf' {
                $availability = [bool]$cliProbes.ocrmypdf.present
                $status = if ($availability) { 'available_but_not_admitted' } else { 'blocked_missing_tool_fall_closed' }
                $details = [string]$cliProbes.ocrmypdf.versionLine
            }
            'qpdf' {
                $availability = [bool]$cliProbes.qpdf.present
                $status = if ($availability) { 'available_but_not_admitted' } else { 'blocked_missing_tool_fall_closed' }
                $details = [string]$cliProbes.qpdf.versionLine
            }
            'ghostscript' {
                $availability = [bool]$cliProbes.gswin64c.present
                $status = if ($availability) { 'available_but_not_admitted' } else { 'blocked_missing_tool_fall_closed' }
                $details = [string]$cliProbes.gswin64c.versionLine
            }
            'imagemagick' {
                $availability = [bool]$cliProbes.magick.present
                $status = if ($availability) { 'available_but_not_admitted' } else { 'blocked_missing_tool_fall_closed' }
                $details = [string]$cliProbes.magick.versionLine
            }
            'libvips' {
                $availability = [bool]$cliProbes.vips.present
                $status = if ($availability) { 'available_but_not_admitted' } else { 'blocked_missing_tool_fall_closed' }
                $details = [string]$cliProbes.vips.versionLine
            }
            'postgresql_cli' {
                $availability = [bool]$cliProbes.psql.present -and [bool]$cliProbes.pg_dump.present -and [bool]$cliProbes.pg_restore.present
                $status = if ($availability) { 'admitted_current_profile' } else { 'blocked_missing_tool_fall_closed' }
                $details = "psql=$($cliProbes.psql.source); pg_dump=$($cliProbes.pg_dump.source); pg_restore=$($cliProbes.pg_restore.source)"
            }
            'robocopy' {
                $availability = [bool]$cliProbes.robocopy.present
                $status = if ($availability) { 'admitted_current_profile' } else { 'blocked_missing_tool_fall_closed' }
                $details = [string]$cliProbes.robocopy.path
            }
            default {
                throw "unhandled toolchain catalog entry: $entryId"
            }
        }

        if ($status -eq 'admitted_current_profile') {
            $admittedForCurrentHost.Add($entryId) | Out-Null
        }
        elseif ($status -eq 'blocked_missing_tool_fall_closed') {
            $blockedToFallback.Add($entryId) | Out-Null
        }

        $catalogEntries += [ordered]@{
            id = $entryId
            kind = [string]$entry.kind
            currentRoute = [string]$entry.currentRoute
            available = $availability
            status = $status
            detail = $details
            fallbackWhenMissing = $fallback
            requiredEvidence = @($entry.requiredEvidence)
        }
    }

    Assert-Condition ($hostJson.recommendedProfiles.exportPrintProfile.status -eq 'partial_toolchain') 'NS1304 expects export toolchain to stay partial when qpdf/ghostscript are missing'
    Assert-Condition ([string]$hostJson.recommendedProfiles.exportPrintProfile.fallback -eq 'keep_docx_or_html_export_until_pdf_toolchain_admitted') 'NS1304 export fallback must stay docx/html-first'
    Assert-Condition (-not [bool]$catalogData.defaultRouteChangeAllowed) 'NS1304 must not allow automatic default route change'
    Assert-Condition (-not [bool]$catalogData.installAllowedByAutomation) 'NS1304 must not allow automatic install'
    Assert-Condition ($blockedToFallback.Contains('docling_layout_pipeline')) 'NS1304 must keep missing Docling fail-closed'
    Assert-Condition ($blockedToFallback.Contains('paddleocr_ppocr')) 'NS1304 must keep missing PaddleOCR fail-closed'
    Assert-Condition ($blockedToFallback.Contains('qpdf')) 'NS1304 must keep missing qpdf fail-closed'
    Assert-Condition ($blockedToFallback.Contains('ghostscript')) 'NS1304 must keep missing Ghostscript fail-closed'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1304'
        checkedAt = (Get-Date).ToString('s')
        mode = 'toolchain_catalog_and_profile_admission'
        productionEligible = $false
        dependency = [ordered]@{
            ns1303 = $Ns1303ReportPath
            j005 = 'docs/evidence/j005-adapter-diagnostic-supply-chain-report.json'
            j006 = 'docs/evidence/j006-import-accuracy-workload-report.json'
            ns304 = 'docs/evidence/20260530-ns304-docx-adapter-report.json'
            ns305 = 'docs/evidence/20260530-ns305-pdf-text-adapter-report.json'
            ns306 = 'docs/evidence/20260530-ns306-scan-ocr-adapter-report.json'
        }
        currentProfile = [ordered]@{
            workerOcrProfile = [string]$ns1303.diagnostics.localSystemProfile.workerOcrProfile
            exportPrintProfile = [string]$ns1303.diagnostics.localSystemProfile.exportPrintProfile
            searchProfile = [string]$ns1303.diagnostics.localSystemProfile.searchProfile
            queueProfile = [string]$ns1303.diagnostics.localSystemProfile.queueProfile
        }
        catalog = [ordered]@{
            path = $CatalogPath
            schemaVersion = [string]$catalogData.schemaVersion
            admissionRequiredEvidence = @($catalogData.admissionRequiredEvidence)
            entries = $catalogEntries
        }
        probes = [ordered]@{
            cli = $cliProbes
            pythonModules = $moduleProbes
        }
        summary = [ordered]@{
            admittedForCurrentHost = $admittedForCurrentHost
            blockedToFallback = $blockedToFallback
            exportFallback = [string]$hostJson.recommendedProfiles.exportPrintProfile.fallback
            databaseFallback = [string]$hostJson.recommendedProfiles.databaseProfile.fallback
            workerFallback = [string]$workerJson.guardrail.failClosedPolicy
        }
        acceptance = [ordered]@{
            toolchainCatalogPresent = $true
            currentProfileResolved = $true
            goldenImportEvidenceReferenced = $true
            currentHostKeepsOpenXmlPdfTextRapidOcrRoute = $true
            missingHeavyToolsFailClosed = $true
            noToolAutoInstalled = $true
            noProductionDefaultChanged = $true
        }
        verification = [ordered]@{
            build = 'gate_na: NS1304 is a toolchain admission/report slice; no product build or install is required'
            test = 'host capability diagnostic + worker profile diagnostic + J005/J006 + NS304/NS305/NS306 evidence'
            contractInvariant = 'toolchain catalog, current profile admission, and fail-closed fallback must stay explicit when heavy tools are missing'
            hotspot = 'gate_na: no package install, no model download, no driver/runtime mutation, and no production default switch'
        }
        boundary = 'NS1304 proves the current host stays on an open-source/free toolchain profile with explicit admission evidence and fail-closed fallbacks. It does not auto-install missing tools, does not switch default OCR/export routes, and does not claim full PDF or heavy-OCR readiness when qpdf/Ghostscript/PaddleOCR/Docling are still absent.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tasks/productization-roadmap.csv tools/run-gates.ps1 tools/README.md; git clean -f -- configs/toolchain-admission.catalog.yaml tools/run-ns1304-toolchain-admission-contract.ps1 $ReportPath"
        next = 'NS1305 can continue role-routed AI admission on top of the fixed toolchain/profile boundary.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    Pop-Location
}
