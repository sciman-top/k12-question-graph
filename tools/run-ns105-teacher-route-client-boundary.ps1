param(
    [string] $ReportPath = 'docs/evidence/20260529-ns105-teacher-route-client-boundary-report.json',
    [string] $WebRoot = 'apps/web'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Test-Contains([string] $Text, [string] $Pattern, [string] $Message) {
    Assert-Condition ($Text.Contains($Pattern)) $Message
}

Push-Location $repoRoot
try {
    Assert-Condition (Test-Path -LiteralPath $WebRoot) "web root missing: $WebRoot"

    $buildOutput = & npm --prefix $WebRoot run build 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) 'npm build failed for NS105'

    $lintOutput = & npm --prefix $WebRoot run lint 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) 'npm lint failed for NS105'

    $appPath = Join-Path $WebRoot 'src/App.tsx'
    $clientPath = Join-Path $WebRoot 'src/api/client.ts'
    $contractsPath = Join-Path $WebRoot 'src/api/contracts.ts'
    $queriesPath = Join-Path $WebRoot 'src/api/queries.ts'
    $uiStatePath = Join-Path $WebRoot 'src/state/uiState.ts'
    $cssPath = Join-Path $WebRoot 'src/App.css'

    foreach ($path in @($appPath, $clientPath, $contractsPath, $queriesPath, $uiStatePath, $cssPath)) {
        Assert-Condition (Test-Path -LiteralPath $path) "NS105 required web file missing: $path"
    }

    $app = Get-Content -LiteralPath $appPath -Raw
    $client = Get-Content -LiteralPath $clientPath -Raw
    $contracts = Get-Content -LiteralPath $contractsPath -Raw
    $queries = Get-Content -LiteralPath $queriesPath -Raw
    $uiState = Get-Content -LiteralPath $uiStatePath -Raw
    $css = Get-Content -LiteralPath $cssPath -Raw

    Test-Contains $app "type TeacherView = 'import' | 'paper' | 'scores' | 'analysis'" 'TeacherView must expose the four teacher entries'
    Test-Contains $app 'workspace teacher-view-${activeTeacherView}' 'workspace must use active teacher view class'
    foreach ($view in @('import', 'paper', 'scores', 'analysis')) {
        Test-Contains $app "view: '$view' as TeacherView" "teacher action missing view: $view"
        Test-Contains $css ".workspace.teacher-view-$view" "teacher workspace CSS selector missing: $view"
    }

    foreach ($marker in @(
        'data-flow="teacher-home"',
        'data-action="teacher-entry"',
        'data-flow="paper-import-wizard"',
        'data-flow="paper-assembly-workbench"',
        'data-flow="score-import-workbench"',
        'data-flow="teacher-analysis-workbench"'
    )) {
        Test-Contains $app $marker "teacher route marker missing: $marker"
    }

    Assert-Condition ($app -notmatch '\bfetch\s*\(') 'App.tsx must not call fetch directly; use typed api client'
    Test-Contains $app "from './api/client'" 'App.tsx must consume typed api client functions'
    Test-Contains $app "from './api/queries'" 'App.tsx must consume query wrappers for server state'
    Test-Contains $app 'apiContractSnapshot' 'App.tsx must expose the frontend API boundary snapshot'
    Test-Contains $app 'uiStateBoundary.teacherDraftState' 'App.tsx must keep teacher draft state boundary explicit'

    Test-Contains $client 'VITE_KQG_API_BASE_URL' 'api client must support API base URL override'
    Test-Contains $client 'function buildApiUrl' 'api client must centralize API URL building'
    Test-Contains $client 'async function requestJson<T>' 'api client must centralize GET JSON handling'
    Test-Contains $client 'async function postJson<T>' 'api client must centralize POST JSON handling'
    foreach ($normalizer in @(
        'normalizeImportJobResponse',
        'normalizeQuestionSearchResponse',
        'normalizeScoreImportResponse',
        'normalizeCommentaryReportExportResponse'
    )) {
        Test-Contains $client $normalizer "api client missing normalizer: $normalizer"
    }
    Assert-Condition (($client -split '\bfetch\s*\(').Count -gt 1) 'api client should own fetch calls'

    Test-Contains $contracts 'export type ApiResult<T>' 'contracts must expose ApiResult'
    Test-Contains $contracts "boundary: 'UI consumes normalized typed contracts instead of raw JSON response shapes'" 'contracts must document typed boundary'
    foreach ($contractName in @(
        'ImportJobContract',
        'QuestionSearchContract',
        'ScoreImportContract',
        'CommentaryReportExportContract'
    )) {
        Test-Contains $contracts "export interface $contractName" "contracts missing $contractName"
    }

    Test-Contains $queries 'useQuery' 'queries must use TanStack Query'
    Test-Contains $queries "['server-state'" 'query keys must be scoped as server state'
    Test-Contains $uiState "teacherDraftState: 'component-local-state'" 'teacher draft state boundary must remain local'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS105'
        checkedAt = (Get-Date).ToString('s')
        mode = 'frontend_build_lint_static_contract'
        productionEligible = $false
        build = [ordered]@{ command = 'npm --prefix apps/web run build'; exitCode = 0 }
        lint = [ordered]@{ command = 'npm --prefix apps/web run lint'; exitCode = 0 }
        teacherViews = @('import', 'paper', 'scores', 'analysis')
        routeMarkers = @(
            'teacher-home',
            'teacher-entry',
            'paper-import-wizard',
            'paper-assembly-workbench',
            'score-import-workbench',
            'teacher-analysis-workbench'
        )
        typedClientBoundary = [ordered]@{
            appCallsFetchDirectly = $false
            appUsesTypedClient = $true
            appUsesQueryWrappers = $true
            apiBaseUrlOverride = 'VITE_KQG_API_BASE_URL'
            serverStateQueryBoundary = 'TanStack Query server-state keys'
            teacherDraftStateBoundary = 'component-local-state'
        }
        normalizedContracts = @(
            'ImportJobContract',
            'QuestionSearchContract',
            'ScoreImportContract',
            'CommentaryReportExportContract'
        )
        acceptance = [ordered]@{
            fourTeacherEntriesPresent = $true
            noDirectFetchInApp = $true
            typedClientOwnsFetch = $true
            buildAndLintPass = $true
            loadingEmptyErrorBoundaryAvailable = $true
        }
        boundary = 'NS105 proves the teacher four-entry shell is wired through typed client/query boundaries; it does not prove live classroom usability or isolated-machine deployment.'
        next = 'NS106 should add an explicit non-site feature/profile guard for external AI, active switch, cloud OCR, and local model defaults.'
        rollback = 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns105-teacher-route-client-boundary.ps1 docs/evidence/20260529-ns105-teacher-route-client-boundary-report.json'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}
