Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
Import-Module (Join-Path $repoRoot 'tools/verification/TestSelection.psm1') -Force

function Assert-ApiTestCase {
    param(
        [Parameter(Mandatory = $true)][string] $Case,
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][ValidateSet('focused', 'full')][string] $Status,
        [string[]] $ExpectedTests = @()
    )

    $result = Get-ApiTestSelection -RepoRoot $repoRoot -ChangedPaths @($Path)
    if ($result.status -ne $Status) {
        throw "$Case api status expected=$Status actual=$($result.status) reason=$($result.reason)"
    }
    foreach ($test in $ExpectedTests) {
        $found = @($result.testFiles | Where-Object { ([string]$_) -eq $test })
        if ($found.Count -eq 0) { throw "$Case api selection missing test: $test" }
    }
}

function Assert-WebTestCase {
    param(
        [Parameter(Mandatory = $true)][string] $Case,
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][ValidateSet('focused', 'full')][string] $Status,
        [string[]] $ExpectedTests = @()
    )

    $result = Get-FrontendTestSelection -RepoRoot $repoRoot -ChangedPaths @($Path)
    if ($result.status -ne $Status) {
        throw "$Case web status expected=$Status actual=$($result.status) reason=$($result.reason)"
    }
    foreach ($test in $ExpectedTests) {
        $found = @($result.vitestPaths | Where-Object { ([string]$_) -eq $test })
        if ($found.Count -eq 0) { throw "$Case web selection missing test: $test" }
    }
}

Assert-ApiTestCase 'ai-router' 'apps/api/Ai/AiModelRouter.cs' 'focused' @(
    'tests/api/K12QuestionGraph.Api.Tests/AiModelRouterTests.cs')
Assert-ApiTestCase 'ai-provider-store' 'apps/api/Ai/AdminAiProviderSettings.cs' 'focused' @(
    'tests/api/K12QuestionGraph.Api.Tests/AdminAiProviderSettingsStoreTests.cs')
Assert-ApiTestCase 'security' 'apps/api/Security/AdminInternalEndpointGuard.cs' 'focused' @(
    'tests/api/K12QuestionGraph.Api.Tests/AdminInternalEndpointGuardTests.cs')
Assert-ApiTestCase 'paper-workflow' 'apps/api/Application/Workflows/PaperWorkflowService.cs' 'focused' @(
    'tests/api/K12QuestionGraph.Api.Tests/PaperWorkflowServiceTests.cs')
Assert-ApiTestCase 'score-workflow' 'apps/api/Application/Workflows/ScoreAnalysisWorkflowService.cs' 'focused' @(
    'tests/api/K12QuestionGraph.Api.Tests/ScoreEvidenceAnalysisTests.cs')
Assert-ApiTestCase 'program' 'apps/api/Program.cs' 'full'
Assert-ApiTestCase 'migration' 'apps/api/Data/Migrations/AddNext.cs' 'full'
Assert-ApiTestCase 'shared-domain' 'apps/api/Domain/P0Entities.cs' 'full'
Assert-ApiTestCase 'routing-parity' 'apps/api/Ai/AiModelRouter.cs' 'focused'
Assert-ApiTestCase 'test-file-change' 'tests/api/K12QuestionGraph.Api.Tests/Workers/DocumentWorkerClientTests.cs' 'focused' @(
    'tests/api/K12QuestionGraph.Api.Tests/Workers/DocumentWorkerClientTests.cs')

Assert-WebTestCase 'app-shell' 'apps/web/src/App.tsx' 'focused' @('src/App.test.tsx')
Assert-WebTestCase 'api-client' 'apps/web/src/api/client.ts' 'focused' @('src/api/client.test.ts')
Assert-WebTestCase 'teacher-home' 'apps/web/src/ui/TeacherHomePanelContent.tsx' 'focused' @(
    'src/ui/TeacherHomePanelContent.test.tsx')
Assert-WebTestCase 'package-manifest' 'apps/web/package.json' 'full'
Assert-WebTestCase 'unknown-source' 'apps/web/src/ui/DoesNotExist.tsx' 'full'

[ordered]@{
    status = 'pass'
    cases = @(
        'ai-router', 'ai-provider-store', 'security', 'paper-workflow', 'score-workflow',
        'program', 'migration', 'shared-domain', 'routing-parity', 'test-file-change',
        'app-shell', 'api-client', 'teacher-home', 'package-manifest', 'unknown-source'
    )
    boundary = 'Test selection routing only; it does not run the product test suites themselves.'
} | ConvertTo-Json -Depth 4
