param(
    [string] $ReportPath = 'docs/evidence/20260606-ns1307-golden-visual-llm-security.json',
    [string] $S004AReportPath = 'docs/evidence/20260506-s004a-golden-registry-report.json',
    [string] $J001ReportPath = 'docs/evidence/j001-openxml-docx-adapter-report.json',
    [string] $J002ReportPath = 'docs/evidence/j002-text-pdf-adapter-report.json',
    [string] $J003ReportPath = 'docs/evidence/j003-scanned-ocr-adapter-report.json',
    [string] $J004ReportPath = 'docs/evidence/j004-fidelity-regression-report.json',
    [string] $J005ReportPath = 'docs/evidence/j005-adapter-diagnostic-supply-chain-report.json',
    [string] $J006ReportPath = 'docs/evidence/j006-import-accuracy-workload-report.json',
    [string] $NS906ReportPath = 'docs/evidence/20260528-ns906-visual-surrogate-review-report.json',
    [string] $C002Q0ReportPath = 'docs/evidence/c002q0-outer-ai-readiness-report.json',
    [string] $C002QReportPath = 'docs/evidence/c002q-ai-extract-dry-run-report.json',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $NonSitePlanPath = 'tasks/non-site-implementation-plan.csv',
    [string] $AutomationContractPath = 'tasks/automation-first-contract.csv'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-InRepoPath([string] $RelativePath) {
    return Join-Path $repoRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Read-JsonFile([string] $RelativePath) {
    $fullPath = Resolve-InRepoPath $RelativePath
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing json file: $RelativePath"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json -Depth 30
}

function Get-RequiredRow([object[]] $Rows, [string] $Id, [string] $Column = 'id') {
    $matches = @($Rows | Where-Object { [string]$_.$Column -eq $Id })
    Assert-Condition ($matches.Count -eq 1) "expected exactly one $Column=$Id row"
    return $matches[0]
}

Push-Location $repoRoot
try {
    $s004aGate = & (Join-Path $PSScriptRoot 'run-s004a-golden-registry-guard.ps1') | ConvertFrom-Json -Depth 10
    $l007Gate = & (Join-Path $PSScriptRoot 'run-l007-llm-security-red-team-gate.ps1') | ConvertFrom-Json -Depth 10

    $s004aReport = Read-JsonFile $S004AReportPath
    $j001 = Read-JsonFile $J001ReportPath
    $j002 = Read-JsonFile $J002ReportPath
    $j003 = Read-JsonFile $J003ReportPath
    $j004 = Read-JsonFile $J004ReportPath
    $j005 = Read-JsonFile $J005ReportPath
    $j006 = Read-JsonFile $J006ReportPath
    $ns906 = Read-JsonFile $NS906ReportPath
    $c002q0 = Read-JsonFile $C002Q0ReportPath
    $c002q = Read-JsonFile $C002QReportPath

    Assert-Condition ([string]$s004aGate.status -eq 'pass') 'NS1307 requires S004A registry guard to pass'
    Assert-Condition ([string]$l007Gate.status -eq 'pass') 'NS1307 requires L007 gate to pass'

    Assert-Condition ([string]$j001.status -eq 'pass') 'J001 must pass'
    Assert-Condition ([bool]$j001.hasFormula -and [bool]$j001.hasTable -and [bool]$j001.formulaOmmlPreserved) 'J001 must preserve OMML formula and table coverage'

    Assert-Condition ([string]$j002.status -eq 'pass') 'J002 must pass'
    Assert-Condition ([int]$j002.pageCount -ge 1 -and [bool]$j002.sourceRegionsPresent) 'J002 must preserve PDF page/source-region evidence'

    Assert-Condition ([string]$j003.status -eq 'pass') 'J003 must pass'
    Assert-Condition ([string]$j003.reviewStatus -eq 'pending_review') 'J003 must keep pending_review boundary'
    Assert-Condition ([bool]$j003.takeoverRequired -and [bool]$j003.realOcrTextRecognized) 'J003 must preserve fail-closed takeover and local OCR recognition'

    Assert-Condition ([string]$j004.status -eq 'pass') 'J004 must pass'
    Assert-Condition ([bool]$j004.importChecks.hasFormulaBlock -and [bool]$j004.importChecks.hasTableBlock -and [bool]$j004.importChecks.hasImageBlock) 'J004 import checks must cover formula/table/image'
    Assert-Condition ([bool]$j004.exportChecks.docx.hasDocumentXml -and [bool]$j004.exportChecks.docx.hasTable -and [bool]$j004.exportChecks.docx.hasFigureMedia -and [bool]$j004.exportChecks.pdf.hasPdfHeader) 'J004 export checks must cover DOCX/PDF artifact fidelity'

    Assert-Condition ([string]$j005.status -eq 'pass') 'J005 must pass'
    Assert-Condition ([bool]$j005.supplyChain.localOcrEngineInvoked -and -not [bool]$j005.supplyChain.externalOcrEngineInvoked -and -not [bool]$j005.supplyChain.networkAccessRequired) 'J005 must remain local-only OCR supply-chain evidence'

    Assert-Condition ([string]$j006.status -eq 'pass') 'J006 must pass'
    Assert-Condition (@($j006.accuracy.goldenSamples).Count -ge 5) 'J006 must cover at least 5 golden samples'
    Assert-Condition ($null -eq $j006.accuracy.autoCutAccuracy) 'J006 must not overclaim automatic cut accuracy before real measurement'
    Assert-Condition ([int]$j006.accuracy.failClosedCaseCount -ge 1 -and [int]$j006.accuracy.scannedCaseCount -ge 1) 'J006 must keep fail-closed and scanned coverage'
    Assert-Condition ([bool]$j006.teacherWorkload.manualReviewRequired) 'J006 must keep manual review requirement'

    Assert-Condition ([string]$ns906.status -eq 'pass') 'NS906 must pass'
    Assert-Condition ([bool]$ns906.aiVisionBoundary.canReplaceEarlyManualLook) 'NS906 must prove early manual look can be replaced'
    foreach ($blockedBoundary in @('真实教师偏好','学校隔离机','打印机','权限域','真实网络','最终发布裁决')) {
        Assert-Condition ((@($ns906.aiVisionBoundary.cannotReplace) | ForEach-Object { [string]$_ }) -contains $blockedBoundary) "NS906 cannotReplace boundary missing: $blockedBoundary"
    }
    Assert-Condition ([string]$ns906.exportArtifactReview.artifactStatus -eq 'pass') 'NS906 export artifact review must pass'
    Assert-Condition ([string]$ns906.analysisReview.analysisStatus -eq 'ready') 'NS906 analysis review must stay ready'
    Assert-Condition ([string]$ns906.analysisReview.real005ClosureStatus -eq 'not_closed') 'NS906 must keep REAL005 not_closed'
    Assert-Condition (@($ns906.blockers).Count -eq 0) 'NS906 must have zero blockers'

    Assert-Condition ([string]$c002q0.status -eq 'pass' -and -not [bool]$c002q0.allowProjectRuntimeRealModelCalls -and [bool]$c002q0.noActiveWrite -and [bool]$c002q0.humanReviewRequired) 'C002Q0 must remain runtime-readiness only'
    Assert-Condition ([string]$c002q.status -eq 'pass' -and -not [bool]$c002q.allowRealModelCalls -and [int]$c002q.externalAiCalls -eq 0 -and [bool]$c002q.noActiveWrite -and [string]$c002q.reviewStatus -eq 'pending_review') 'C002Q must remain dry-run only'

    $backlogRows = @(Import-Csv -LiteralPath (Resolve-InRepoPath $BacklogPath) -Encoding UTF8)
    $planRows = @(Import-Csv -LiteralPath (Resolve-InRepoPath $NonSitePlanPath) -Encoding UTF8)
    $automationRows = @(Import-Csv -LiteralPath (Resolve-InRepoPath $AutomationContractPath) -Encoding UTF8)

    $ns1307Backlog = Get-RequiredRow $backlogRows 'NS1307'
    $ns1307Plan = Get-RequiredRow $planRows 'NS1307'
    $ns1307Automation = Get-RequiredRow $automationRows 'NS1307' 'task_id'
    Assert-Condition ([string]$ns1307Backlog.depends_on -eq 'NS1306') 'NS1307 backlog row must depend on NS1306'
    Assert-Condition ([string]$ns1307Plan.depends_on -eq 'NS1306') 'NS1307 plan row must depend on NS1306'
    Assert-Condition ([string]$ns1307Automation.deterministic_precheck -match 'golden OCR import fixture visual surrogate privacy schema output validation prompt injection') 'NS1307 automation contract must keep combined gate wording'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1307'
        checkedAt = (Get-Date).ToString('s')
        mode = 'golden_visual_llm_security_gate'
        productionEligible = $false
        realStudentDataUsed = $false
        externalAiCalls = 0
        gateInputs = [ordered]@{
            s004a = $S004AReportPath
            j001 = $J001ReportPath
            j002 = $J002ReportPath
            j003 = $J003ReportPath
            j004 = $J004ReportPath
            j005 = $J005ReportPath
            j006 = $J006ReportPath
            ns906 = $NS906ReportPath
            c002q0 = $C002Q0ReportPath
            c002q = $C002QReportPath
        }
        goldenCoverage = [ordered]@{
            formats = @($s004aReport.coverage.formats | ForEach-Object { [string]$_ })
            focus = @($s004aReport.coverage.focus | ForEach-Object { [string]$_ })
            sampleCount = @($j006.accuracy.goldenSamples).Count
            failClosedCaseCount = [int]$j006.accuracy.failClosedCaseCount
            scannedCaseCount = [int]$j006.accuracy.scannedCaseCount
        }
        visualBoundary = [ordered]@{
            canReplaceEarlyManualLook = [bool]$ns906.aiVisionBoundary.canReplaceEarlyManualLook
            cannotReplace = @($ns906.aiVisionBoundary.cannotReplace | ForEach-Object { [string]$_ })
            artifactStatus = [string]$ns906.exportArtifactReview.artifactStatus
            analysisStatus = [string]$ns906.analysisReview.analysisStatus
            real005ClosureStatus = [string]$ns906.analysisReview.real005ClosureStatus
        }
        llmSecurity = [ordered]@{
            status = [string]$l007Gate.status
            noActiveWrite = [bool]$l007Gate.noActiveWrite
            humanReviewRequired = [bool]$l007Gate.humanReviewRequired
            dryRunExternalAiCalls = [int]$l007Gate.dryRunExternalAiCalls
            c002qReviewStatus = [string]$c002q.reviewStatus
            c002qProductionEligible = [bool]$c002q.productionEligible
        }
        acceptance = [ordered]@{
            goldenRegistryLocked = $true
            ommlFormulaPreserved = $true
            scannedFailClosedPreserved = $true
            exportArtifactFidelityChecked = $true
            localOnlyOcrSupplyChain = $true
            manualReviewStillRequired = $true
            visualSurrogateCannotReplaceReleaseDecision = $true
            llmSecurityNoActiveWrite = $true
            llmSecurityPendingReview = $true
        }
        summaryChinese = [ordered]@{
            title = 'NS1307 Golden OCR/import + visual surrogate + LLM security 组合门禁'
            result = '通过'
            boundary = '当前组合门禁已覆盖黄金样本、OCR/导出保真、视觉代理不可替代边界和 LLM no-active-write/pending_review 安全约束。'
            next = '后续可在保持这些组合门禁不退化的前提下继续推进 NS1308 release evidence pack。'
        }
        rollback = 'git restore tools/run-ns1307-golden-visual-llm-security-gate.ps1 tools/run-gates.ps1 tools/README.md configs/agent-tool-orchestration.allowlist.json'
    }

    $reportFullPath = Resolve-InRepoPath $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}
