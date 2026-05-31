param(
    [string] $Ns803ReportPath = 'docs/evidence/20260530-ns803-installer-host.json',
    [string] $OutputRoot = 'tmp/ns804/windows-service-package',
    [string] $ReportPath = 'docs/evidence/20260530-ns804-windows-service.json',
    [string] $Runtime = 'win-x64',
    [switch] $SelfContained,
    [switch] $SkipWebBuild
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
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Convert-OutputToJson([object[]] $Output, [string] $Label) {
    $lines = @($Output | ForEach-Object { [string]$_ })
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].TrimStart().StartsWith('{')) {
            $start = $i
            break
        }
    }

    Assert-Condition ($start -ge 0) "$Label did not emit a JSON object"
    $jsonText = ($lines[$start..($lines.Count - 1)] -join [Environment]::NewLine)
    return $jsonText | ConvertFrom-Json
}

Push-Location $repoRoot
try {
    $ns803 = Read-Json $Ns803ReportPath
    Assert-Condition ($ns803.status -eq 'pass') 'NS804 dependency NS803 report did not pass'
    Assert-Condition ([bool]$ns803.acceptance.noDependencyInstall) 'NS804 requires NS803 noDependencyInstall evidence'
    Assert-Condition ([bool]$ns803.acceptance.noProductionDefaultChanged) 'NS804 requires NS803 production default guard'
    Assert-Condition ([bool]$ns803.acceptance.noLocalAiDefaultChanged) 'NS804 requires NS803 local AI default guard'
    Assert-Condition ([bool]$ns803.acceptance.noPlaintextPasswordInEvidence) 'NS804 requires NS803 secret evidence guard'

    $publishArgs = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        'tools/run-o001-windows-service-publish-contract.ps1',
        '-OutputRoot',
        $OutputRoot,
        '-Runtime',
        $Runtime
    )
    if ($SelfContained) {
        $publishArgs += '-SelfContained'
    }
    if ($SkipWebBuild) {
        $publishArgs += '-SkipWebBuild'
    }

    $o001Output = & pwsh @publishArgs
    Assert-Condition ($LASTEXITCODE -eq 0) 'NS804 embedded O001 publish package contract failed'
    $o001 = Convert-OutputToJson $o001Output 'O001 publish package contract'
    Assert-Condition ($o001.status -eq 'pass') 'NS804 O001 contract report did not pass'

    $packageRoot = [string]$o001.packageRoot
    $apiPublishRoot = [string]$o001.apiPublishRoot
    $webPublishRoot = [string]$o001.webPublishRoot
    $workerScript = [string]$o001.workerScript
    $apiExe = Join-Path $apiPublishRoot 'K12QuestionGraph.Api.exe'
    $webIndex = Join-Path $webPublishRoot 'index.html'
    Assert-Condition (Test-Path -LiteralPath $packageRoot) "missing package root: $packageRoot"
    Assert-Condition (Test-Path -LiteralPath $apiPublishRoot) "missing api publish root: $apiPublishRoot"
    Assert-Condition (Test-Path -LiteralPath $webPublishRoot) "missing web publish root: $webPublishRoot"
    Assert-Condition (Test-Path -LiteralPath $workerScript) "missing packaged worker script: $workerScript"
    Assert-Condition (Test-Path -LiteralPath $apiExe) "missing api executable: $apiExe"
    Assert-Condition ((Test-Path -LiteralPath $webIndex) -or [bool]$SkipWebBuild) "missing web index: $webIndex"

    $contentRoot = [string]$o001.smoke.contentRoot
    $dataRoot = [string]$o001.smoke.dataRoot
    $runWorkingDirectory = [string]$o001.smoke.runWorkingDirectory
    Assert-Condition ($contentRoot -eq (Resolve-Path -LiteralPath $apiPublishRoot).Path) 'NS804 contentRoot must be the published API directory'
    Assert-Condition ($dataRoot -ne $contentRoot) 'NS804 data root must be separated from program/content root'
    Assert-Condition (-not $runWorkingDirectory.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) 'NS804 smoke run working directory must be outside repository root'
    Assert-Condition ([bool]$o001.smoke.workerScriptCheck.ok) 'NS804 readiness must pass document worker script check'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS804'
        checkedAt = (Get-Date).ToString('s')
        mode = 'windows_service_publish_package'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns803 = $Ns803ReportPath
            o001 = 'tools/run-o001-windows-service-publish-contract.ps1'
        }
        package = [ordered]@{
            packageRoot = $packageRoot
            apiPublishRoot = $apiPublishRoot
            webPublishRoot = $webPublishRoot
            workerScript = $workerScript
            runtime = [string]$o001.runtime
            selfContained = [bool]$o001.selfContained
            apiExecutable = $apiExe
            webIndex = $webIndex
        }
        smoke = [ordered]@{
            runWorkingDirectory = $runWorkingDirectory
            contentRoot = $contentRoot
            dataRoot = $dataRoot
            workerScriptCheck = $o001.smoke.workerScriptCheck
            stdoutLog = [string]$o001.evidence.stdoutLog
            stderrLog = [string]$o001.evidence.stderrLog
        }
        acceptance = [ordered]@{
            ns803EvidencePassed = $true
            o001PublishContractPassed = $true
            apiPublishArtifactExists = $true
            webPublishArtifactExists = -not [bool]$SkipWebBuild
            workerPackaged = $true
            explicitContentRootSmokePassed = $true
            runWorkingDirectoryOutsideRepo = $true
            dataRootSeparatedFromProgramRoot = $true
            healthReadinessPassed = $true
            noWindowsServiceInstalled = $true
            noFirewallChanged = $true
            noDependencyInstall = $true
            noProductionDefaultChanged = $true
            noActiveWrite = $true
        }
        verification = [ordered]@{
            build = 'dotnet publish apps/api/K12QuestionGraph.Api.csproj via O001; npm run build unless -SkipWebBuild is set'
            test = 'published API boot smoke from a temp working directory with explicit --contentRoot'
            contractInvariant = 'package must contain API/Web/worker, use package-local worker path, keep KqgPaths absolute, separate data root from content root, and pass health/readiness'
            hotspot = 'gate_na: this non-site slice does not install a Windows Service, change firewall, or rehearse isolated target-machine service startup; NS1001/P001 own live install validation'
        }
        boundary = 'NS804 proves a Windows Service-ready publish package and contentRoot smoke without installing a service or changing host firewall/system configuration.'
        rollback = "Remove-Item -LiteralPath '$packageRoot' -Recurse -Force; git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns804-windows-service-package.ps1 $ReportPath"
        next = 'NS805 can continue capacity/cost/health dashboard; NS806 can continue EF migration bundle after NS804.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    Pop-Location
}
