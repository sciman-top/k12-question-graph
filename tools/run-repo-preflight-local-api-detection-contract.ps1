param(
    [string] $PreflightScriptPath = 'tools/run-repo-preflight.ps1',
    [string] $FullGateScriptPath = 'tools/run-gates.ps1',
    [string] $StartLocalApiScriptPath = 'tools/start-local-api.ps1',
    [string] $ReportPath = 'docs/evidence/20260614-repo-preflight-local-api-detection-contract.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Write-ContentIfChanged([string] $Path, [string] $Content) {
    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw
        if ($existing -eq $Content) {
            return
        }
    }

    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Assert-ContainsAll([string] $ScriptPath, [string] $Text, [string[]] $Patterns) {
    foreach ($pattern in $Patterns) {
        Assert-True ($Text.Contains($pattern)) "$ScriptPath missing local API detection pattern: $pattern"
    }
}

$preflightScriptFullPath = Join-Path $repoRoot $PreflightScriptPath
$fullGateScriptFullPath = Join-Path $repoRoot $FullGateScriptPath
$startLocalApiScriptFullPath = Join-Path $repoRoot $StartLocalApiScriptPath
$reportFullPath = Join-Path $repoRoot $ReportPath

Assert-True (Test-Path -LiteralPath $preflightScriptFullPath) "missing repo preflight script: $PreflightScriptPath"
Assert-True (Test-Path -LiteralPath $fullGateScriptFullPath) "missing full gate script: $FullGateScriptPath"
Assert-True (Test-Path -LiteralPath $startLocalApiScriptFullPath) "missing local API launcher script: $StartLocalApiScriptPath"

$preflightText = Get-Content -LiteralPath $preflightScriptFullPath -Raw
$fullGateText = Get-Content -LiteralPath $fullGateScriptFullPath -Raw
$startLocalApiText = Get-Content -LiteralPath $startLocalApiScriptFullPath -Raw

$requiredDetectionPatterns = @(
    "function Get-ProcessCommandLine",
    "function Get-RepoApiProcesses",
    "`$expectedDllPath = Join-Path `$repoRoot 'apps\api\bin\Release\net10.0\K12QuestionGraph.Api.dll'",
    "`$expectedContentRoot = Join-Path `$repoRoot 'apps\api'",
    "`$process.ProcessName -notin @('K12QuestionGraph.Api', 'dotnet')",
    "Get-ProcessCommandLine -ProcessId `$process.Id",
    "`$normalizedExpectedDllPath = `$expectedDllPath.ToLowerInvariant()",
    "`$normalizedExpectedContentRoot = `$expectedContentRoot.ToLowerInvariant()",
    "Contains(`$normalizedExpectedDllPath.ToLowerInvariant())",
    "Contains(`$normalizedExpectedContentRoot)",
    "`$repoApiProcesses = @(Get-RepoApiProcesses)",
    "Stop-Process -Id `$repoProcess.ProcessId -Force -ErrorAction SilentlyContinue"
)

Assert-ContainsAll -ScriptPath $FullGateScriptPath -Text $fullGateText -Patterns $requiredDetectionPatterns
Assert-ContainsAll -ScriptPath $PreflightScriptPath -Text $preflightText -Patterns $requiredDetectionPatterns

$requiredLauncherPatterns = @(
    "-FilePath 'dotnet'",
    "`$apiDllPath",
    "'--contentRoot',",
    "`$apiContentRoot"
)
Assert-ContainsAll -ScriptPath $StartLocalApiScriptPath -Text $startLocalApiText -Patterns $requiredLauncherPatterns

$requiredPreflightOrchestrationPatterns = @(
    "Invoke-PreflightStep 'repo preflight local api detection contract'",
    "run-repo-preflight-local-api-detection-contract.ps1",
    "-ReportPath (Join-Path `$ReportRoot 'repo-preflight-local-api-detection-contract.json')"
)
Assert-ContainsAll -ScriptPath $PreflightScriptPath -Text $preflightText -Patterns $requiredPreflightOrchestrationPatterns

$report = [ordered]@{
    status = 'pass'
    taskId = 'REPO_PREFLIGHT_LOCAL_API_DETECTION_CONTRACT'
    checkedAt = (Get-Date).ToString('s')
    preflightScript = $PreflightScriptPath
    fullGateScript = $FullGateScriptPath
    startLocalApiScript = $StartLocalApiScriptPath
    boundary = 'guards repo preflight and full gate against drifting away from the dotnet+dll+contentRoot local API launcher shape'
}

$reportJson = $report | ConvertTo-Json -Depth 5
Write-ContentIfChanged -Path $reportFullPath -Content $reportJson
$reportJson
