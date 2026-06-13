param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
$results = New-Object System.Collections.Generic.List[object]

function Invoke-GateStep([string] $Name, [scriptblock] $Script) {
    $started = Get-Date
    try {
        & $Script
        $global:LASTEXITCODE = 0
        $results.Add([ordered]@{
            name = $Name
            status = 'pass'
            durationMs = [int]((Get-Date) - $started).TotalMilliseconds
        })
    }
    catch {
        $results.Add([ordered]@{
            name = $Name
            status = 'fail'
            durationMs = [int]((Get-Date) - $started).TotalMilliseconds
            error = $_.Exception.Message
        })
        throw
    }
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 0)
    try {
        $listener.Start()
        return $listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

function Wait-ApiReady([System.Diagnostics.Process] $Process, [string] $ApiUrl, [string] $LogErr) {
    for ($i = 0; $i -lt 30; $i++) {
        if ($Process.HasExited) {
            throw "API exited before ready on $ApiUrl; see $LogErr"
        }

        try {
            $health = Invoke-RestMethod -Uri "$ApiUrl/health/ready" -TimeoutSec 2
            if ($health.status -eq 'ok') {
                return
            }
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    throw "API did not become ready on $ApiUrl"
}

function Get-ProcessCommandLine([int] $ProcessId) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        return ''
    }

    return [string]$process.CommandLine
}

function Get-DefaultLocalApiProcess {
    $expectedPath = Join-Path $repoRoot 'apps\api\bin\Release\net10.0\K12QuestionGraph.Api.exe'
    $expectedDllPath = Join-Path $repoRoot 'apps\api\bin\Release\net10.0\K12QuestionGraph.Api.dll'
    $expectedContentRoot = Join-Path $repoRoot 'apps\api'
    $listener = Get-NetTCPConnection -LocalPort 5275 -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -eq $listener) {
        return $null
    }

    $process = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        return $null
    }

    $processPath = $null
    try {
        $processPath = $process.Path
    }
    catch {
        return $null
    }

    if ($process.ProcessName -notin @('K12QuestionGraph.Api', 'dotnet')) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($processPath)) {
        return $null
    }

    if ($process.ProcessName -eq 'K12QuestionGraph.Api') {
        if (-not $processPath.Equals($expectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }
    }
    else {
        if (-not $processPath.Equals((Get-Command dotnet).Source, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }

        $commandLine = Get-ProcessCommandLine -ProcessId $process.Id
        if ([string]::IsNullOrWhiteSpace($commandLine)) {
            return $null
        }

        $normalizedCommandLine = $commandLine.ToLowerInvariant()
        $normalizedExpectedDllPath = $expectedDllPath.ToLowerInvariant()
        $normalizedExpectedContentRoot = $expectedContentRoot.ToLowerInvariant()

        if (-not $normalizedCommandLine.Contains($normalizedExpectedDllPath.ToLowerInvariant())) {
            return $null
        }

        if (-not $normalizedCommandLine.Contains($normalizedExpectedContentRoot)) {
            return $null
        }
    }

    return $process
}

function Get-HostLocalFrontendDebrisPaths {
    $webRoot = Join-Path $repoRoot 'apps\web'
    $debrisDirs = @(Get-ChildItem -Path $webRoot -Directory -Filter 'node_modules_broken_*' -ErrorAction SilentlyContinue)

    return @(
        $debrisDirs |
        ForEach-Object { [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName) -replace '\\', '/' } |
        Sort-Object -Unique
    )
}

Push-Location $repoRoot
$p0LiveRunDate = Get-Date -Format 'yyyyMMdd'
$resumeDefaultLocalApi = $false
$defaultLocalApi = Get-DefaultLocalApiProcess
if ($null -ne $defaultLocalApi) {
    Stop-Process -Id $defaultLocalApi.Id -Force
    Start-Sleep -Milliseconds 800

    if (Test-Path -LiteralPath 'logs\dev-api\api.pid') {
        Remove-Item -LiteralPath 'logs\dev-api\api.pid' -Force
    }

    $stillRunning = Get-Process -Id $defaultLocalApi.Id -ErrorAction SilentlyContinue
    if ($null -ne $stillRunning) {
        throw "failed to pause default local API process $($defaultLocalApi.Id) before full gate"
    }

    $resumeDefaultLocalApi = $true
}

try {
    Invoke-GateStep 'backend build' {
        dotnet build apps\api\K12QuestionGraph.Api.csproj -c Release | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "dotnet build failed" }
    }

    Invoke-GateStep 'frontend host-local debris guard' {
        $debrisPaths = @(Get-HostLocalFrontendDebrisPaths)
        if ($debrisPaths.Count -gt 0) {
            throw ("host-local frontend debris blocks full gate: {0}. Remove or move these temporary directories outside apps/web before rerunning. This is host-local drift, not repo source lint failure." -f ($debrisPaths -join ', '))
        }
    }

    Invoke-GateStep 'frontend build' {
        npm --prefix apps/web run build | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "npm run build failed" }
    }

    Invoke-GateStep 'frontend lint' {
        npm --prefix apps/web run lint | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "npm run lint failed" }
    }

    Invoke-GateStep 'i001 teacher home ui contract' {
        .\tools\run-i001-teacher-home-ui-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'i002 import wizard ui contract' {
        .\tools\run-i002-import-wizard-ui-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'i003 review queue ui contract' {
        .\tools\run-i003-review-queue-ui-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'i004 paper workbench ui contract' {
        .\tools\run-i004-paper-workbench-ui-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'i005 score analysis workbench ui contract' {
        .\tools\run-i005-score-analysis-workbench-ui-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'i006 starter defaults ui contract' {
        .\tools\run-i006-starter-defaults-ui-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'i007 frontend boundary contract' {
        .\tools\run-i007-frontend-boundary-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'i008 teacher simplification contract' {
        .\tools\run-i008-teacher-simplification-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'b004 manual review ui contract' {
        $app = Get-Content -LiteralPath 'apps\web\src\App.tsx' -Raw
        foreach ($pattern in @(
            'data-flow="manual-review"',
            'data-action="merge"',
            'data-action="split"',
            'data-action="associate"',
            'data-action="undo"',
            '修订记录'
        )) {
            if (-not $app.Contains($pattern)) {
                throw "missing B004 UI contract marker: $pattern"
            }
        }
    }

    Invoke-GateStep 'b004a failure takeover ui contract' {
        $app = Get-Content -LiteralPath 'apps\web\src\App.tsx' -Raw
        foreach ($pattern in @(
            'data-flow="failure-takeover"',
            'data-action="manual-box"',
            'data-action="takeover-split"',
            'data-action="takeover-merge"',
            'data-action="skip-page"',
            'data-action="rerun-adapter"',
            'adapter_failed'
        )) {
            if (-not $app.Contains($pattern)) {
                throw "missing B004A UI contract marker: $pattern"
            }
        }
    }

    Invoke-GateStep 'worker smoke' {
        $workerDir = Join-Path $FileStoreRoot 'gate'
        New-Item -ItemType Directory -Path $workerDir -Force | Out-Null
        $workerFile = Join-Path $workerDir 'worker-smoke.txt'
        Set-Content -LiteralPath $workerFile -Value 'worker smoke' -Encoding UTF8
        python workers\document\worker.py --job-id gate --relative-path gate/worker-smoke.txt --file-root $FileStoreRoot | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "worker smoke failed" }
    }

    Invoke-GateStep 'j001 openxml docx adapter contract' {
        .\tools\run-j001-openxml-docx-adapter-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'j002 text pdf adapter contract' {
        .\tools\run-j002-text-pdf-adapter-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'j003 scanned ocr adapter contract' {
        .\tools\run-j003-scanned-ocr-adapter-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'j004 formula table figure fidelity regression' {
        .\tools\run-j004-fidelity-regression-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'j005 adapter diagnostic supply-chain gate' {
        .\tools\run-j005-adapter-diagnostic-supply-chain-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'j006 import accuracy workload baseline' {
        .\tools\run-j006-import-accuracy-workload-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'k001 active c002 production query contract' {
        .\tools\run-k001-active-c002-production-query-contract.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword | Write-Host
    }

    Invoke-GateStep 'k002 c002r teacher revision ux contract' {
        .\tools\run-k002-c002r-teacher-revision-ux-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'k003 mapping review workbench ui contract' {
        .\tools\run-k003-mapping-review-workbench-ui-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'k004 historical version explanation contract' {
        .\tools\run-k004-historical-version-explanation-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'k005 c002 second revision drill contract' {
        .\tools\run-k005-c002-second-revision-drill-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'k006 knowledge asset health dashboard contract' {
        .\tools\run-k006-knowledge-asset-health-dashboard-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'b002 adapter contract smoke' {
        $workerDir = Join-Path $FileStoreRoot 'gate'
        New-Item -ItemType Directory -Path $workerDir -Force | Out-Null
        $workerFile = Join-Path $workerDir 'b002-adapter-contract.txt'
        Set-Content -LiteralPath $workerFile -Value 'adapter contract smoke' -Encoding UTF8
        $json = python workers\document\worker.py --job-id b002-gate --relative-path gate/b002-adapter-contract.txt --file-root $FileStoreRoot | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw "b002 adapter contract worker failed" }
        if ($json.documentModel.schemaVersion -ne 'document-model.v0.1') { throw "missing DocumentModel schemaVersion" }
        if ($json.documentModel.pages.Count -lt 1) { throw "missing PageModel" }
        if ($json.documentModel.pages[0].layoutBlocks.Count -lt 1) { throw "missing LayoutBlock" }
        if ($json.adapterDiagnostics.Count -lt 1) { throw "missing AdapterDiagnostic" }
        if ([string]::IsNullOrWhiteSpace($json.adapterDiagnostics[0].inputSha256)) { throw "missing input hash" }
        if ([string]::IsNullOrWhiteSpace($json.adapterDiagnostics[0].outputSha256)) { throw "missing output hash" }
    }

    Invoke-GateStep 'doc schema config csv' {
        python -c "import csv, json, pathlib, yaml; rows=list(csv.DictReader(open('tasks/backlog.csv', encoding='utf-8-sig'))); [json.loads(p.read_text(encoding='utf-8')) for p in pathlib.Path('schemas').rglob('*.json')]; [yaml.safe_load(p.read_text(encoding='utf-8')) for p in pathlib.Path('configs').rglob('*.yaml')]; print('doc gates ok', len(rows))" | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "doc gates failed" }
    }

    Invoke-GateStep 'roadmap dependency guard' {
        .\tools\run-roadmap-guard.ps1 | Write-Host
    }

    Invoke-GateStep 's001 completion-state dashboard' {
        .\tools\run-s001-completion-state-dashboard.ps1 | Write-Host
    }

    Invoke-GateStep 's0 execution plan guard' {
        .\tools\run-s0-execution-plan-guard.ps1 | Write-Host
    }

    Invoke-GateStep 'automation-first feature contract guard' {
        .\tools\run-automation-first-feature-contract-guard.ps1 | Write-Host
    }

    Invoke-GateStep 'reference basis guard' {
        .\tools\run-reference-basis-guard.ps1 -JsonReportPath ('docs/evidence/{0}-reference-basis-guard.json' -f $p0LiveRunDate) -MarkdownReportPath ('docs/evidence/{0}-reference-basis-guard.md' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'non-site implementation plan guard' {
        .\tools\run-non-site-implementation-plan-guard.ps1 | Write-Host
    }

    Invoke-GateStep 'ns104 application service boundary guard' {
        .\tools\run-ns104-application-service-boundary.ps1 | Write-Host
    }

    Invoke-GateStep 'ns105 teacher route typed client boundary guard' {
        .\tools\run-ns105-teacher-route-client-boundary.ps1 | Write-Host
    }

    Invoke-GateStep 'ns1301 architecture slimming guard' {
        .\tools\run-ns1301-architecture-slimming-guard.ps1 | Write-Host
    }

    Invoke-GateStep 'ns1302 service control panel contract' {
        .\tools\run-ns1302-service-control-panel-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'ns1303 runtime profile contract' {
        .\tools\run-ns1303-runtime-profile-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'ns1304 toolchain admission contract' {
        .\tools\run-ns1304-toolchain-admission-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'ns1305 role routed ai contract' {
        .\tools\run-ns1305-role-routed-ai-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'ns1305a admin ai settings dialog contract' {
        .\tools\run-ns1305a-admin-ai-settings-dialog-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'ns1308 release evidence pack contract' {
        .\tools\run-ns1308-release-evidence-pack-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'ns106 feature profile guard' {
        .\tools\run-ns106-feature-profile-guard.ps1 | Write-Host
    }

    Invoke-GateStep 'ns201 role audit baseline guard' {
        .\tools\run-ns201-role-audit-baseline.ps1 | Write-Host
    }

    Invoke-GateStep 'ns202 admin internal fail closed guard' {
        .\tools\run-ns202-admin-internal-fail-closed.ps1 | Write-Host
    }

    Invoke-GateStep 'ns203 privacy license scan guard' {
        .\tools\run-ns203-privacy-license-scan.ps1 | Write-Host
    }

    Invoke-GateStep 'ns204 no active write guard' {
        .\tools\run-ns204-no-active-write-guard.ps1 | Write-Host
    }

    Invoke-GateStep 'ns0 ns2 runtime closure guard' {
        .\tools\run-ns0-ns2-runtime-closure.ps1 -ReportPath ('docs/evidence/{0}-ns0-ns2-runtime-closure.json' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'ns301 source document evidence smoke' {
        .\tools\run-ns301-source-document-smoke.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'ns302 file dedupe guard' {
        .\tools\run-ns302-file-dedupe.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'ns303 worker profile diagnostic guard' {
        .\tools\run-worker-profile-diagnostic-contract.ps1 -Report 'docs/evidence/20260530-ns303-worker-profile.json' | Write-Host
    }

    Invoke-GateStep 'ns304 docx adapter guard' {
        .\tools\run-ns304-docx-adapter.ps1 | Write-Host
    }

    Invoke-GateStep 'ns305 pdf text adapter guard' {
        .\tools\run-ns305-pdf-text-adapter.ps1 | Write-Host
    }

    Invoke-GateStep 'ns306 scan ocr adapter guard' {
        .\tools\run-ns306-scan-ocr-adapter.ps1 | Write-Host
    }

    Invoke-GateStep 'ns307 source region screenshot guard' {
        .\tools\run-ns307-source-region-screenshot.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'ns308 import quality report guard' {
        .\tools\run-ns308-import-quality-report.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'ns401 cut candidate guard' {
        .\tools\run-ns401-cut-candidate.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'ns402 review queue api guard' {
        .\tools\run-ns402-review-queue-api.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'ns403 review workbench ui guard' {
        .\tools\run-ns403-review-workbench-ui.ps1 | Write-Host
    }

    Invoke-GateStep 'ns404 question asset guard' {
        .\tools\run-ns404-question-asset.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'ns405 table formula block guard' {
        .\tools\run-ns405-table-formula-blocks.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'ns406 question edit audit guard' {
        .\tools\run-ns406-question-edit-audit.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'ns501 c002 active boundary guard' {
        .\tools\run-ns501-c002-active-boundary.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword | Write-Host
    }

    Invoke-GateStep 'ns502 ai schema eval guard' {
        .\tools\run-ns502-ai-schema-eval.ps1 | Write-Host
    }

    Invoke-GateStep 'ns503 model router budget guard' {
        .\tools\run-ns503-model-router-budget.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'ns504 ai suggestion review guard' {
        .\tools\run-ns504-ai-suggestion-review.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'ns505 feedback eval loop guard' {
        .\tools\run-ns505-feedback-eval-loop.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'ns601 question search api guard' {
        .\tools\run-ns601-question-search-api.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'ns602 question card ui guard' {
        .\tools\run-ns602-question-card-ui.ps1 | Write-Host
    }

    Invoke-GateStep 'ns603 paper basket persistence guard' {
        .\tools\run-ns603-paper-basket.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'ns604 paper request understanding guard' {
        .\tools\run-ns604-paper-request-understanding.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'ns605 replace undo guard' {
        .\tools\run-ns605-replace-undo.ps1 | Write-Host
    }

    Invoke-GateStep 'ns606 export preflight guard' {
        .\tools\run-ns606-export-preflight.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'ns607 export artifacts guard' {
        .\tools\run-ns607-export-artifacts.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'ns701 score template mapping guard' {
        .\tools\run-ns701-score-template-mapping.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'ns702 item score mapping guard' {
        .\tools\run-ns702-item-score-mapping.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'ns703 analysis metrics guard' {
        .\tools\run-ns703-analysis-metrics.ps1 | Write-Host
    }

    Invoke-GateStep 'ns704 commentary report guard' {
        .\tools\run-ns704-commentary-report.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'ns705 student data privacy guard' {
        .\tools\run-ns705-student-data-privacy.ps1 | Write-Host
    }

    Invoke-GateStep 'ns801 backup manifest guard' {
        .\tools\run-ns801-backup-manifest.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'ns802 restore drill guard' {
        .\tools\run-ns802-restore-drill.ps1 -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'ns803 installer host diagnostic guard' {
        .\tools\run-ns803-installer-host.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'ns804 windows service package guard' {
        .\tools\run-ns804-windows-service-package.ps1 | Write-Host
    }

    Invoke-GateStep 'local-first ai consumption guard' {
        .\tools\run-local-first-ai-guard.ps1 | Write-Host
    }

    Invoke-GateStep 'c002n source chunk cache guard' {
        .\tools\run-c002n-source-chunk-cache.ps1 | Write-Host
    }

    Invoke-GateStep 'c002o candidate extraction schema/eval guard' {
        .\tools\run-c002o-candidate-extraction-eval.ps1 | Write-Host
    }

    Invoke-GateStep 'c002p model budget guard' {
        .\tools\run-c002p-model-budget-guard.ps1 | Write-Host
    }

    Invoke-GateStep 'c002q0 outer ai readiness guard' {
        .\tools\run-c002q0-outer-ai-readiness.ps1 | Write-Host
    }

    Invoke-GateStep 'c002q ai extract dry-run guard' {
        .\tools\run-c002q-ai-extract-dry-run.ps1 | Write-Host
    }

    Invoke-GateStep 'l001 real model admission card guard' {
        .\tools\run-l001-real-model-admission-card.ps1 | Write-Host
    }

    Invoke-GateStep 'l007 llm security red-team gate' {
        .\tools\run-l007-llm-security-red-team-gate.ps1 | Write-Host
    }

    Invoke-GateStep 'l002 real ai extract pilot gate' {
        .\tools\run-l002-real-ai-extract-pilot.ps1 | Write-Host
    }

    Invoke-GateStep 'l003 ai cut candidate pilot gate' {
        .\tools\run-l003-ai-cut-candidate-pilot.ps1 | Write-Host
    }

    Invoke-GateStep 'l004 knowledge tagging suggestion pilot gate' {
        .\tools\run-l004-knowledge-tagging-suggestion-pilot.ps1 | Write-Host
    }

    Invoke-GateStep 'l005 answer verification quality pilot gate' {
        .\tools\run-l005-answer-verification-quality-pilot.ps1 | Write-Host
    }

    Invoke-GateStep 'l006 cost cache batch dashboard pilot gate' {
        .\tools\run-l006-cost-cache-batch-dashboard-pilot.ps1 | Write-Host
    }

    Invoke-GateStep 'm001 paper basket structure contract' {
        .\tools\run-m001-paper-basket-structure-contract.ps1 | Write-Host
    }
    Invoke-GateStep 'm002 nl to blueprint production chain' {
        .\tools\run-m002-nl-to-blueprint-production-chain.ps1 | Write-Host
    }
    Invoke-GateStep 's009b blueprint review workflow smoke' {
        $port = Get-FreeTcpPort
        .\tools\run-s009b-blueprint-review-workflow-smoke.ps1 -ApiPort $port | Write-Host
    }
    Invoke-GateStep 's009c paper workbench ui contract' {
        .\tools\run-s009c-paper-workbench-ui-contract.ps1 | Write-Host
    }
    Invoke-GateStep 's010a export preflight api smoke' {
        $port = Get-FreeTcpPort
        .\tools\run-s010a-export-preflight-api-smoke.ps1 -ApiPort $port | Write-Host
    }
    Invoke-GateStep 's010b word pdf artifact chain smoke' {
        $port = Get-FreeTcpPort
        .\tools\run-s010b-word-pdf-artifact-chain-smoke.ps1 -ApiPort $port | Write-Host
    }
    Invoke-GateStep 'm003 replacement production constraints' {
        .\tools\run-m003-replacement-production-constraints.ps1 | Write-Host
    }
    Invoke-GateStep 'm004 export preflight contract' {
        .\tools\run-m004-export-preflight-contract.ps1 | Write-Host
    }
    Invoke-GateStep 'm005 export regression extended' {
        .\tools\run-m005-export-regression-extended.ps1 | Write-Host
    }
    Invoke-GateStep 'm006 ten-minute paper workflow acceptance' {
        .\tools\run-m006-ten-minute-paper-workflow-acceptance.ps1 | Write-Host
    }
    Invoke-GateStep 'n001 real privacy boundary admission' {
        .\tools\run-n001-real-privacy-boundary-admission.ps1 | Write-Host
    }
    Invoke-GateStep 'n002 excel template reuse' {
        .\tools\run-n002-excel-template-reuse.ps1 | Write-Host
    }
    Invoke-GateStep 's011a score import api smoke' {
        $port = Get-FreeTcpPort
        .\tools\run-s011a-score-import-api-smoke.ps1 -ApiPort $port | Write-Host
    }
    Invoke-GateStep 's011b item score mapping ui api smoke' {
        $port = Get-FreeTcpPort
        .\tools\run-s011b-item-score-mapping-ui-api-smoke.ps1 -ApiPort $port | Write-Host
    }
    Invoke-GateStep 's011c commentary report export smoke' {
        $port = Get-FreeTcpPort
        .\tools\run-s011c-commentary-report-export-smoke.ps1 -ApiPort $port | Write-Host
    }
    Invoke-GateStep 's012a e2e proxy fixture pack' {
        .\tools\run-s012a-e2e-proxy-fixture-pack.ps1 | Write-Host
    }
    Invoke-GateStep 's012b non-site e2e rehearsal' {
        .\tools\run-s012b-non-site-e2e-rehearsal.ps1 | Write-Host
    }
    Invoke-GateStep 'ns901 non-site scenario pack' {
        .\tools\run-ns901-non-site-scenario-pack.ps1 -SkipS012Refresh | Write-Host
    }
    Invoke-GateStep 'ns906 visual surrogate review' {
        .\tools\run-ns906-visual-surrogate-review.ps1 | Write-Host
    }
    Invoke-GateStep 'ns1307 golden visual llm security gate' {
        .\tools\run-ns1307-golden-visual-llm-security-gate.ps1 -ReportPath ('docs/evidence/{0}-ns1307-golden-visual-llm-security.json' -f $p0LiveRunDate) | Write-Host
    }
    Invoke-GateStep 'ns903 completion dashboard refresh' {
        .\tools\run-ns903-completion-dashboard.ps1 -SkipS001Refresh | Write-Host
    }
    Invoke-GateStep 'n003 item score mapping workbench' {
        .\tools\run-n003-item-score-mapping-workbench.ps1 | Write-Host
    }
    Invoke-GateStep 'n004 class commentary report mvp' {
        .\tools\run-n004-class-commentary-report-mvp.ps1 | Write-Host
    }
    Invoke-GateStep 'n005 tiered practice draft-test' {
        .\tools\run-n005-tiered-practice-draft-test.ps1 | Write-Host
    }
    Invoke-GateStep 'n006 pre-pilot security audit' {
        .\tools\run-n006-pre-pilot-security-audit.ps1 | Write-Host
    }

    Invoke-GateStep 'c002s formalization precheck guard' {
        .\tools\run-c002s-formalization-precheck.ps1 | Write-Host
    }

    Invoke-GateStep 'c002 source material admission guard' {
        .\tools\run-c002-source-material-guard.ps1 | Write-Host
    }

    Invoke-GateStep 'database smoke' {
        $psql = Join-Path $PgBin 'psql.exe'
        & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -c "select count(*) from information_schema.tables where table_schema='public';" | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "database smoke failed" }
    }

    Invoke-GateStep 'c001 knowledge ontology contract' {
        .\tools\run-c001-contract.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'c002a domain asset contract' {
        .\tools\run-c002a-domain-asset-contract.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'c002b replacement mapping contract' {
        .\tools\run-c002b-replacement-mapping-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'c002c migration impact contract' {
        .\tools\run-c002c-migration-impact-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'c002d source-derived admission contract' {
        .\tools\run-c002d-source-derived-admission-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'c002e activation guard contract' {
        .\tools\run-c002e-activation-guard-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'c002h mapping review workbench contract' {
        .\tools\run-c002h-mapping-review-workbench-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'c002i source material workbench contract' {
        .\tools\run-c002i-source-material-workbench-contract.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword | Write-Host
    }

    Invoke-GateStep 'source document dedupe contract' {
        .\tools\run-source-document-dedupe-contract.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword | Write-Host
    }

    Invoke-GateStep 'real guangzhou 2015 ingest slice dry-run' {
        .\tools\run-guangzhou-2015-real-ingest-slice.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -FileStoreRoot $FileStoreRoot -Output 'docs\evidence\20260512-guangzhou-2015-real-ingest-slice-dry-run-report.json' | Write-Host
    }

    Invoke-GateStep 'real guangzhou 2016-2025 batch ingest dry-run' {
        .\tools\run-guangzhou-physics-year-batch-ingest.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'real guangzhou 2015 review queue smoke' {
        .\tools\run-real004-guangzhou-2015-review-smoke.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'real guangzhou 2015 layout quality report' {
        .\tools\run-real007-guangzhou-2015-layout-quality.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'real question asset association smoke' {
        .\tools\run-real008-question-asset-smoke.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'real table structure smoke' {
        .\tools\run-real009-table-structure-smoke.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'real formula fidelity smoke' {
        .\tools\run-real010-formula-fidelity-smoke.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'real question edit audit smoke' {
        .\tools\run-real011-question-edit-smoke.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'real production flow quality smoke' {
        .\tools\run-real012-production-flow-quality-smoke.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'c002l candidate review readiness contract' {
        .\tools\run-c002l-candidate-review-readiness.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword | Write-Host
    }

    Invoke-GateStep 'c002m candidate review apply contract' {
        .\tools\run-c002m-candidate-review-apply-contract.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword | Write-Host
    }

    Invoke-GateStep 'c002t active switch guard' {
        .\tools\run-c002t-active-switch.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword | Write-Host
    }

    Invoke-GateStep 'c002r versioned revision contract' {
        .\tools\run-c002r-versioned-revision-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'generic domain asset activation pipeline guard' {
        .\tools\run-domain-asset-activation.ps1 -ImportKey 'c002_candidate_import_guangzhou_physics_2016_2025_v1' -MaterialBatchKey 'guangzhou_physics_2016_2025' -EvidencePrefix 'c002-domain-activation-pipeline' -ExpectedSourceDocumentCount 33 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword | Write-Host
    }

    Invoke-GateStep 'teacher activation template guard' {
        .\tools\run-teacher-activation-template-guard.ps1 | Write-Host
    }

    Invoke-GateStep 'subject activation workbench ui contract' {
        .\tools\run-subject-activation-workbench-ui-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'c002 junior physics draft bootstrap guard' {
        .\tools\run-c002-seed-validation.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'd001 model router draft-test contract' {
        .\tools\run-d001-model-router-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'd002 ai job cost contract' {
        .\tools\run-d002-ai-job-cost-contract.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'd003 structured output eval contract' {
        .\tools\run-d003-structured-output-eval.ps1 | Write-Host
    }

    Invoke-GateStep 'e001 question search ui contract' {
        $app = Get-Content -LiteralPath 'apps\web\src\App.tsx' -Raw
        foreach ($pattern in @(
            'data-flow="question-search"',
            'data-card="question-card"',
            'draft_test'
        )) {
            if (-not $app.Contains($pattern)) {
                throw "missing E001 UI contract marker: $pattern"
            }
        }

        foreach ($filter in @('knowledge', 'question-type', 'difficulty', 'source')) {
            if ((-not $app.Contains("data-filter=""$filter""")) -and (-not $app.Contains("filter: '$filter'"))) {
                throw "missing E001 UI filter marker: $filter"
            }
        }
    }

    Invoke-GateStep 'e001 question search api contract' {
        .\tools\run-e001-question-search-contract.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'e002 paper request contract' {
        .\tools\run-e002-paper-request-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'e003 question replacement undo contract' {
        .\tools\run-e003-question-replacement-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'e004 paper export contract' {
        .\tools\run-e004-paper-export-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'f001 assessment model contract' {
        .\tools\run-f001-assessment-model-contract.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'f002 score import contract' {
        .\tools\run-f002-score-import-contract.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'f003 knowledge mastery analysis contract' {
        .\tools\run-f003-knowledge-mastery-analysis-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'g001 backup share contract' {
        .\tools\run-g001-backup-share-contract.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'g002 storage cleanup contract' {
        .\tools\run-g002-storage-cleanup-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'o005 capacity cost health dashboard contract' {
        .\tools\run-o005-capacity-cost-health-dashboard-contract.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'ns805 capacity cost health dashboard guard' {
        .\tools\run-ns805-health-dashboard.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin -SkipO005Refresh | Write-Host
    }

    Invoke-GateStep 'g003 winpe emergency copy contract' {
        .\tools\run-g003-winpe-emergency-copy-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'g004 pgpass installer dry-run contract' {
        .\tools\run-g004-pgpass-installer-dry-run.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'o004 admin internal auth boundary contract' {
        .\tools\run-o004-admin-internal-auth-boundary-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'o004b role audit closure contract' {
        .\tools\run-o004b-role-audit-closure-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'o001 windows service publish package contract' {
        .\tools\run-o001-windows-service-publish-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'o002 installer init wizard contract' {
        .\tools\run-o002-installer-init-wizard-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'o003 recovery drill upgrade contract' {
        .\tools\run-o003-recovery-drill-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'o007 ef migration bundle and upgrade drill contract' {
        .\tools\run-o007-ef-migration-bundle-upgrade-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'ns806 ef migration bundle upgrade rehearsal guard' {
        .\tools\run-ns806-upgrade-bundle.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin -O007ReportPath 'docs/evidence/o007-ef-migration-bundle-upgrade-drill-report.json' -SkipO007Refresh | Write-Host
    }

    Invoke-GateStep 'o006 offline emergency runbook and tabletop contract' {
        .\tools\run-o006-offline-emergency-runbook-tabletop-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'o008 technology refresh candidate admission contract' {
        .\tools\run-technology-refresh-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'p001 live pilot readiness preflight contract' {
        .\tools\run-p001-live-pilot-readiness-preflight-contract.ps1 -ReportPath ('docs/evidence/{0}-p001-live-pilot-readiness-preflight-report.json' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'ns904 p001 readiness evidence pack' {
        .\tools\run-ns904-p001-readiness-pack.ps1 -P001ReportPath ('docs/evidence/{0}-p001-live-pilot-readiness-preflight-report.json' -f $p0LiveRunDate) -ReportPath ('docs/evidence/{0}-ns904-p001-readiness.json' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'ns905 status sync audit' {
        .\tools\run-ns905-status-sync-audit.ps1 -P001ReportPath ('docs/evidence/{0}-p001-live-pilot-readiness-preflight-report.json' -f $p0LiveRunDate) -NS904ReportPath ('docs/evidence/{0}-ns904-p001-readiness.json' -f $p0LiveRunDate) -ReportPath ('docs/evidence/{0}-ns905-status-sync.md' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'live pilot closeout plan guard' {
        .\tools\run-live-pilot-closeout-plan-guard.ps1 -JsonReportPath ('docs/evidence/{0}-live-pilot-closeout-plan-guard.json' -f $p0LiveRunDate) -MarkdownReportPath ('docs/evidence/{0}-live-pilot-closeout-plan-guard.md' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'ns1001 isolated machine execution pack contract' {
        .\tools\run-ns1001-isolated-machine-pack-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'p002 teacher proxy pilot preflight contract' {
        .\tools\run-p002-teacher-proxy-pilot-preflight-contract.ps1 -ReportPath ('docs/evidence/{0}-p002-teacher-proxy-pilot-admission-report.json' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'p003 onsite pilot admission preflight contract' {
        .\tools\run-p003-onsite-pilot-admission-preflight-contract.ps1 -ReportPath ('docs/evidence/{0}-p003-onsite-pilot-admission-report.json' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'p004 onsite pilot round1 preflight contract' {
        .\tools\run-p004-onsite-pilot-round1-preflight-contract.ps1 -ReportPath ('docs/evidence/{0}-p004-onsite-pilot-round1-report.json' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'p005 pilot feedback backlog preflight contract' {
        .\tools\run-p005-pilot-feedback-backlog-preflight-contract.ps1 -ReportPath ('docs/evidence/{0}-p005-pilot-feedback-backlog-admission-report.json' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'p006 release decision preflight contract' {
        .\tools\run-p006-release-decision-preflight-contract.ps1 -ReportPath ('docs/evidence/{0}-p006-release-decision-admission-report.json' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'q001 second-subject candidate admission preflight contract' {
        .\tools\run-q001-second-subject-candidate-admission-preflight-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'ns1101 second-subject candidate boundary pack' {
        .\tools\run-ns1101-second-subject-candidate-boundary.ps1 -NS905ReportPath ('docs/evidence/{0}-ns905-status-sync.md' -f $p0LiveRunDate) -ReportPath ('docs/evidence/{0}-ns1101-second-subject-candidate.json' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'q002 second-subject teacher review template preflight contract' {
        .\tools\run-q002-second-subject-teacher-review-template-preflight-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'ns1102 second-subject teacher review template boundary pack' {
        .\tools\run-ns1102-second-subject-review-template-boundary.ps1 -ReportPath ('docs/evidence/{0}-ns1102-second-subject-review-template.json' -f $p0LiveRunDate) -NS1101ReportPath ('docs/evidence/{0}-ns1101-second-subject-candidate.json' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'q003 second-subject active drill preflight contract' {
        .\tools\run-q003-second-subject-active-drill-preflight-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'ns1103 second-subject active dry-run boundary pack' {
        .\tools\run-ns1103-second-subject-active-dry-run-boundary.ps1 -ReportPath ('docs/evidence/{0}-ns1103-second-subject-active-dry-run.json' -f $p0LiveRunDate) -NS1102ReportPath ('docs/evidence/{0}-ns1102-second-subject-review-template.json' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'q004 cross-subject diff report preflight contract' {
        .\tools\run-q004-cross-subject-diff-report-preflight-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'q005 multi-subject ui simplification preflight contract' {
        .\tools\run-q005-multi-subject-ui-simplification-preflight-contract.ps1 | Write-Host
    }

    Invoke-GateStep 'ns1104 cross-subject ui boundary pack' {
        .\tools\run-ns1104-cross-subject-ui-boundary.ps1 -ReportPath ('docs/evidence/{0}-ns1104-cross-subject-ui.json' -f $p0LiveRunDate) -NS1103ReportPath ('docs/evidence/{0}-ns1103-second-subject-active-dry-run.json' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'r001 search semantic retrieval eval preflight contract' {
        .\tools\run-r001-search-semantic-retrieval-eval-preflight-contract.ps1 | Write-Host
    }
    Invoke-GateStep 'ns1201 search semantic retrieval boundary pack' {
        .\tools\run-ns1201-search-eval.ps1 -ReportPath ('docs/evidence/{0}-ns1201-search-eval.json' -f $p0LiveRunDate) | Write-Host
    }
    Invoke-GateStep 'r002 queue worker scale eval preflight contract' {
        .\tools\run-r002-queue-worker-scale-eval-preflight-contract.ps1 | Write-Host
    }
    Invoke-GateStep 'ns1202 queue worker scale boundary pack' {
        .\tools\run-ns1202-queue-eval.ps1 -ReportPath ('docs/evidence/{0}-ns1202-queue-eval.json' -f $p0LiveRunDate) | Write-Host
    }
    Invoke-GateStep 'r003 interop eval preflight contract' {
        .\tools\run-r003-interop-eval-preflight-contract.ps1 | Write-Host
    }
    Invoke-GateStep 'r004 advanced analysis eval preflight contract' {
        .\tools\run-r004-advanced-analysis-eval-preflight-contract.ps1 | Write-Host
    }
    Invoke-GateStep 'ns1204 advanced analysis admission boundary pack' {
        .\tools\run-ns1204-advanced-analysis-admission.ps1 -ReportPath ('docs/evidence/{0}-ns1204-advanced-analysis-admission.json' -f $p0LiveRunDate) | Write-Host
    }
    Invoke-GateStep 'r005 public multischool deploy eval preflight contract' {
        .\tools\run-r005-public-multischool-deploy-eval-preflight-contract.ps1 | Write-Host
    }
    Invoke-GateStep 'ns1205 public multischool deploy admission boundary pack' {
        .\tools\run-ns1205-multischool-admission.ps1 -ReportPath ('docs/evidence/{0}-ns1205-multischool-admission.json' -f $p0LiveRunDate) | Write-Host
    }
    Invoke-GateStep 'r006 techdebt cadence preflight contract' {
        .\tools\run-r006-techdebt-cadence-preflight-contract.ps1 | Write-Host
    }
    Invoke-GateStep 'ns1206 techdebt cadence boundary pack' {
        .\tools\run-ns1206-techdebt-cadence.ps1 -ReportPath ('docs/evidence/{0}-ns1206-techdebt-cadence.json' -f $p0LiveRunDate) | Write-Host
    }
    Invoke-GateStep 'r007 interoperability profile map preflight contract' {
        .\tools\run-r007-interoperability-profile-map-preflight-contract.ps1 | Write-Host
    }
    Invoke-GateStep 'ns1203 interoperability profile map boundary pack' {
        .\tools\run-ns1203-interop-profile-map.ps1 -ReportPath ('docs/evidence/{0}-ns1203-interop-profile-map.json' -f $p0LiveRunDate) | Write-Host
    }
    Invoke-GateStep 'p0 live preflight refresh path contract' {
        .\tools\run-p0-live-preflight-refresh-path-contract.ps1 | Write-Host
    }
    Invoke-GateStep 'pqr preflight pack contract' {
        .\tools\run-pqr-preflight-pack-contract.ps1 | Write-Host
    }
    Invoke-GateStep 'pqr preflight freshness guard' {
        .\tools\run-pqr-preflight-freshness-guard.ps1 | Write-Host
    }
    Invoke-GateStep 'pqr preflight dashboard contract' {
        .\tools\run-pqr-preflight-dashboard-contract.ps1 | Write-Host
    }
    Invoke-GateStep 'pqr orchestration consistency guard' {
        .\tools\run-pqr-orchestration-consistency-guard.ps1 | Write-Host
    }
    Invoke-GateStep 'ns1306 agent tool orchestration contract' {
        .\tools\run-ns1306-agent-tool-orchestration-contract.ps1 -ReportPath ('docs/evidence/{0}-ns1306-agent-tool-orchestration.json' -f $p0LiveRunDate) | Write-Host
    }

    Invoke-GateStep 'b001 duplicate upload smoke' {
        if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
            throw "DatabasePassword or PGPASSWORD is required for API upload smoke"
        }

        $port = Get-FreeTcpPort
        $apiUrl = "http://127.0.0.1:$port"
        $logOut = Join-Path $repoRoot 'docs\evidence\b001-gate-api.out.log'
        $logErr = Join-Path $repoRoot 'docs\evidence\b001-gate-api.err.log'
        $previousConnectionString = $env:KQG_CONNECTION_STRING
        $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
        $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','-c','Release','--no-build','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
        try {
            Wait-ApiReady -Process $process -ApiUrl $apiUrl -LogErr $logErr

            $sample = Join-Path $env:TEMP 'kqg-b001-gate-upload.txt'
            Set-Content -LiteralPath $sample -Value "B001 duplicate upload gate sample $([Guid]::NewGuid())" -Encoding UTF8

            $first = curl.exe -s -F "file=@$sample;filename=physics-paper.docx" -F "sourceType=school_paper" -F "sourceTitle=Gate Source" -F "ownerScope=school" -F "licenseOrPermission=internal_authorized" -F "sharingAllowed=true" -F "containsStudentPii=false" -F "anonymizationStatus=not_applicable" "$apiUrl/files" | ConvertFrom-Json
            $second = curl.exe -s -F "file=@$sample;filename=renamed-paper.pdf" -F "sourceType=unknown" -F "sourceTitle=Unknown Duplicate" -F "ownerScope=teacher_private" -F "licenseOrPermission=unknown" -F "sharingAllowed=true" -F "containsStudentPii=true" -F "anonymizationStatus=none" "$apiUrl/files" | ConvertFrom-Json
            $pending = curl.exe -s -F "file=@$sample;filename=pending-review-source.pdf" -F "sourceType=school_paper" -F "sourceTitle=Pending Review Duplicate" -F "ownerScope=school" -F "licenseOrPermission=pending_source_workbench_review" -F "sharingAllowed=false" -F "containsStudentPii=false" -F "anonymizationStatus=not_applicable" "$apiUrl/files" | ConvertFrom-Json
            $pendingAgain = curl.exe -s -F "file=@$sample;filename=pending-review-source.pdf" -F "sourceType=school_paper" -F "sourceTitle=Pending Review Duplicate" -F "ownerScope=school" -F "licenseOrPermission=pending_source_workbench_review" -F "sharingAllowed=false" -F "containsStudentPii=false" -F "anonymizationStatus=not_applicable" "$apiUrl/files" | ConvertFrom-Json
            $classified = curl.exe -s -F "file=@$sample;filename=2015广州中考.pdf" "$apiUrl/files" | ConvertFrom-Json

            if ($first.isDuplicate) { throw "first upload unexpectedly marked duplicate" }
            if (-not $second.isDuplicate) { throw "second upload was not marked duplicate" }
            if ($first.id -ne $second.id) { throw "duplicate upload returned a different file asset id" }
            if ($pendingAgain.sourceDocument.id -ne $pending.sourceDocument.id) { throw "same file and same source metadata created a duplicate source document" }
            if ($classified.sourceDocument.sourceType -ne 'local_exam_paper') { throw "2015 Guangzhou zhongkao source was not classified as local_exam_paper" }
            if ($classified.sourceDocument.region -ne 'guangzhou') { throw "2015 Guangzhou zhongkao region was not normalized" }
            if ($classified.sourceDocument.year -ne 2015) { throw "2015 Guangzhou zhongkao year was not inferred" }
            if ($classified.sourceDocument.materialBatchKey -ne 'guangzhou_physics_zhongkao') { throw "2015 Guangzhou zhongkao source family was not inferred" }
            if (-not $first.sourceDocument.externalAiAllowed) { throw "authorized non-PII source was not external-AI eligible" }
            if ($second.sourceDocument.sharingAllowed) { throw "unknown PII source remained shareable" }
            if ($second.sourceDocument.externalAiAllowed) { throw "unknown PII source remained external-AI eligible" }
            if ($pending.sourceDocument.sharingAllowed) { throw "pending-review source remained shareable" }
            if ($pending.sourceDocument.externalAiAllowed) { throw "pending-review source remained external-AI eligible" }

            $psql = Join-Path $PgBin 'psql.exe'
            $rowCount = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -c "select count(*) from source_documents where file_asset_id = '$($first.id)';"
            if ($LASTEXITCODE -ne 0) { throw "source document query failed" }
            if ([int]$rowCount -lt 3) { throw "expected at least three source document rows for duplicate upload" }
        }
        finally {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $env:KQG_CONNECTION_STRING = $previousConnectionString
        }
    }

    Invoke-GateStep 'b003 source preview smoke' {
        if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
            throw "DatabasePassword or PGPASSWORD is required for API source preview smoke"
        }

        $port = Get-FreeTcpPort
        $apiUrl = "http://127.0.0.1:$port"
        $logOut = Join-Path $repoRoot 'docs\evidence\b003-gate-api.out.log'
        $logErr = Join-Path $repoRoot 'docs\evidence\b003-gate-api.err.log'
        $previousConnectionString = $env:KQG_CONNECTION_STRING
        $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
        $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','-c','Release','--no-build','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
        try {
            Wait-ApiReady -Process $process -ApiUrl $apiUrl -LogErr $logErr

            $sample = Join-Path $env:TEMP 'kqg-b003-gate-upload.txt'
            Set-Content -LiteralPath $sample -Value "B003 source preview gate sample $([Guid]::NewGuid())" -Encoding UTF8
            $upload = curl.exe -s -F "file=@$sample;filename=preview-source.txt" -F "sourceType=school_paper" -F "sourceTitle=Preview Source" -F "ownerScope=school" -F "licenseOrPermission=internal_authorized" -F "sharingAllowed=true" -F "containsStudentPii=false" -F "anonymizationStatus=not_applicable" "$apiUrl/files" | ConvertFrom-Json
            $sourceDocumentId = $upload.sourceDocument.id
            if ([string]::IsNullOrWhiteSpace($sourceDocumentId)) { throw "upload did not return sourceDocument.id" }

            $screenshotRelativePath = "previews/$sourceDocumentId/page-1.txt"
            $screenshotPath = Join-Path $FileStoreRoot ($screenshotRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            New-Item -ItemType Directory -Path (Split-Path -Parent $screenshotPath) -Force | Out-Null
            Set-Content -LiteralPath $screenshotPath -Value 'page preview placeholder' -Encoding UTF8

            $body = [ordered]@{
                pageNumber = 1
                x = 10
                y = 15
                width = 50
                height = 30
                coordinateUnit = 'percent'
                screenshotRelativePath = $screenshotRelativePath
                regionType = 'preview'
            } | ConvertTo-Json
            $region = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$sourceDocumentId/regions" -ContentType 'application/json' -Body $body
            $preview = Invoke-RestMethod -Method Get -Uri "$apiUrl/source-documents/$sourceDocumentId/preview"

            if ($region.pageNumber -ne 1) { throw "region page number mismatch" }
            if ($region.coordinateUnit -ne 'percent') { throw "region coordinate unit mismatch" }
            if ($region.screenshotRelativePath -ne $screenshotRelativePath) { throw "region screenshot path mismatch" }
            if ($preview.pages.Count -lt 1) { throw "preview did not return any page" }
            if ($preview.pages[0].pageNumber -ne 1) { throw "preview page number mismatch" }
            if ($preview.pages[0].regions.Count -lt 1) { throw "preview did not return source region" }

            $updateBody = [ordered]@{
                pageNumber = 1
                x = 11
                y = 16
                width = 48
                height = 28
                coordinateUnit = 'percent'
                screenshotRelativePath = $screenshotRelativePath
                regionType = 'question'
                reviewedBy = 'gate-source-region-editor'
                reason = 'verify source region bbox edit audit'
            } | ConvertTo-Json
            $updated = Invoke-RestMethod -Method Patch -Uri "$apiUrl/source-regions/$($region.id)" -ContentType 'application/json' -Body $updateBody
            if ($updated.region.x -ne 11) { throw "source region patch did not update x" }
            if ($updated.region.regionType -ne 'question') { throw "source region patch did not update region type" }
            if ([string]::IsNullOrWhiteSpace([string]$updated.auditId)) { throw "source region patch did not create audit id" }
        }
        finally {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $env:KQG_CONNECTION_STRING = $previousConnectionString
        }
    }

    Invoke-GateStep 'b005 save question api smoke' {
        if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
            throw "DatabasePassword or PGPASSWORD is required for API question save smoke"
        }

        $port = Get-FreeTcpPort
        $apiUrl = "http://127.0.0.1:$port"
        $logOut = Join-Path $repoRoot 'docs\evidence\b005-gate-api.out.log'
        $logErr = Join-Path $repoRoot 'docs\evidence\b005-gate-api.err.log'
        $previousConnectionString = $env:KQG_CONNECTION_STRING
        $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
        $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','-c','Release','--no-build','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
        try {
            Wait-ApiReady -Process $process -ApiUrl $apiUrl -LogErr $logErr

            $sample = Join-Path $env:TEMP 'kqg-b005-gate-upload.txt'
            Set-Content -LiteralPath $sample -Value "B005 question save gate sample $([Guid]::NewGuid())" -Encoding UTF8
            $upload = curl.exe -s -F "file=@$sample;filename=question-asset.txt" -F "sourceType=school_paper" -F "sourceTitle=Question Save Source" -F "ownerScope=school" -F "licenseOrPermission=internal_authorized" -F "sharingAllowed=true" -F "containsStudentPii=false" -F "anonymizationStatus=not_applicable" "$apiUrl/files" | ConvertFrom-Json
            $sourceDocumentId = $upload.sourceDocument.id

            $regionBody = [ordered]@{
                pageNumber = 1
                x = 12
                y = 18
                width = 64
                height = 22
                coordinateUnit = 'percent'
                screenshotRelativePath = $null
                regionType = 'question'
            } | ConvertTo-Json
            $region = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$sourceDocumentId/regions" -ContentType 'application/json' -Body $regionBody

            $questionBody = [ordered]@{
                subject = 'physics'
                stage = 'junior_middle_school'
                grade = 'grade_8'
                questionType = 'single_choice'
                defaultScore = 3
                status = 'draft'
                blocks = @(
                    [ordered]@{ blockType = 'text'; sortOrder = 0; content = [ordered]@{ text = '下列关于力的说法正确的是？' }; sourceRegionId = $region.id },
                    [ordered]@{ blockType = 'option'; sortOrder = 1; content = [ordered]@{ key = 'A'; text = '力可以脱离物体存在' }; sourceRegionId = $region.id },
                    [ordered]@{ blockType = 'formula'; sortOrder = 2; content = [ordered]@{ latex = 'F=ma' }; sourceRegionId = $region.id },
                    [ordered]@{ blockType = 'table'; sortOrder = 3; content = [ordered]@{ rows = @(@('物理量','单位'), @('力','N')) }; sourceRegionId = $region.id },
                    [ordered]@{ blockType = 'answer'; sortOrder = 4; content = [ordered]@{ answer = 'B' }; sourceRegionId = $region.id },
                    [ordered]@{ blockType = 'solution'; sortOrder = 5; content = [ordered]@{ text = '力是物体间的相互作用。' }; sourceRegionId = $region.id }
                )
                assets = @(
                    [ordered]@{ fileAssetId = $upload.id; sourceRegionId = $region.id; assetType = 'image'; purpose = 'question_figure'; metadata = [ordered]@{ label = '题图占位' } }
                )
                answer = [ordered]@{ value = 'B' }
                solution = [ordered]@{ text = '力不能脱离物体存在。' }
            } | ConvertTo-Json -Depth 8

            $created = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionBody
            $loaded = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$($created.id)"
            if ($loaded.blocks.Count -lt 6) { throw "question blocks were not saved" }
            if ($loaded.assets.Count -lt 1) { throw "question asset was not saved" }
            if (($loaded.blocks | Where-Object { $_.blockType -eq 'formula' }).Count -lt 1) { throw "formula block missing" }
            if (($loaded.blocks | Where-Object { $_.blockType -eq 'table' }).Count -lt 1) { throw "table block missing" }
            if (($loaded.blocks | Where-Object { $_.sourceRegionId -eq $region.id }).Count -lt 1) { throw "source region link missing" }
            if ($loaded.assets[0].fileAssetId -ne $upload.id) { throw "question asset file link mismatch" }
        }
        finally {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $env:KQG_CONNECTION_STRING = $previousConnectionString
        }
    }

    Invoke-GateStep 'b006 question source review smoke' {
        if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
            throw "DatabasePassword or PGPASSWORD is required for API question source smoke"
        }

        $port = Get-FreeTcpPort
        $apiUrl = "http://127.0.0.1:$port"
        $logOut = Join-Path $repoRoot 'docs\evidence\b006-gate-api.out.log'
        $logErr = Join-Path $repoRoot 'docs\evidence\b006-gate-api.err.log'
        $previousConnectionString = $env:KQG_CONNECTION_STRING
        $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
        $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','-c','Release','--no-build','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
        try {
            Wait-ApiReady -Process $process -ApiUrl $apiUrl -LogErr $logErr

            $sample = Join-Path $env:TEMP 'kqg-b006-gate-upload.txt'
            Set-Content -LiteralPath $sample -Value "B006 source review gate sample $([Guid]::NewGuid())" -Encoding UTF8
            $upload = curl.exe -s -F "file=@$sample;filename=source-review.txt" -F "sourceType=school_paper" -F "sourceTitle=Source Review Paper" -F "ownerScope=school" -F "licenseOrPermission=internal_authorized" -F "sharingAllowed=true" -F "containsStudentPii=false" -F "anonymizationStatus=not_applicable" "$apiUrl/files" | ConvertFrom-Json
            $sourceDocumentId = $upload.sourceDocument.id

            $screenshotRelativePath = "previews/$sourceDocumentId/question-source.txt"
            $screenshotPath = Join-Path $FileStoreRoot ($screenshotRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            New-Item -ItemType Directory -Path (Split-Path -Parent $screenshotPath) -Force | Out-Null
            Set-Content -LiteralPath $screenshotPath -Value 'question source preview placeholder' -Encoding UTF8

            $regionBody = [ordered]@{
                pageNumber = 2
                x = 8
                y = 11
                width = 70
                height = 25
                coordinateUnit = 'percent'
                screenshotRelativePath = $screenshotRelativePath
                regionType = 'question'
            } | ConvertTo-Json
            $region = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$sourceDocumentId/regions" -ContentType 'application/json' -Body $regionBody

            $questionBody = [ordered]@{
                subject = 'physics'
                stage = 'junior_middle_school'
                questionType = 'short_answer'
                blocks = @(
                    [ordered]@{ blockType = 'text'; sortOrder = 0; content = [ordered]@{ text = '请说明惯性的含义。' }; sourceRegionId = $region.id },
                    [ordered]@{ blockType = 'answer'; sortOrder = 1; content = [ordered]@{ answer = '物体保持原有运动状态的性质。' }; sourceRegionId = $region.id }
                )
                assets = @()
                answer = [ordered]@{ value = '物体保持原有运动状态的性质。' }
                solution = [ordered]@{ text = '惯性是物体的固有属性。' }
            } | ConvertTo-Json -Depth 8
            $created = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionBody
            $sources = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$($created.id)/sources"
            if ($sources.sourceRegions.Count -lt 1) { throw "question source regions missing" }
            if ($sources.sourceRegions[0].pageNumber -ne 2) { throw "question source page number mismatch" }
            if ($sources.sourceRegions[0].screenshotRelativePath -ne $screenshotRelativePath) { throw "question source screenshot path mismatch" }

            Remove-Item -LiteralPath $screenshotPath -Force
            try {
                Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$($created.id)/sources" | Out-Null
                throw "missing screenshot did not fail"
            }
            catch {
                if ($_.Exception.Response.StatusCode.value__ -ne 409) {
                    throw
                }
            }
        }
        finally {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $env:KQG_CONNECTION_STRING = $previousConnectionString
        }
    }

    Invoke-GateStep 'b007 golden import regression' {
        .\tools\run-import-golden.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'b008 p1 proxy scenario' {
        .\tools\run-p1-proxy-scenario.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'backup verify' {
        $backup = .\tools\backup.ps1 -PgBin $PgBin -DatabaseName $DatabaseName -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabaseUser $DatabaseUser | ConvertFrom-Json
        .\tools\verify-backup.ps1 -ManifestPath $backup.manifest | Write-Host
    }

    [ordered]@{
        status = 'pass'
        steps = $results
    } | ConvertTo-Json -Depth 6
    exit 0
}
finally {
    if ($resumeDefaultLocalApi) {
        try {
            .\tools\start-local-api.ps1 | Out-Null
        }
        catch {
            throw "full gate finished but failed to restore default local API: $($_.Exception.Message)"
        }
    }

    Pop-Location
}



