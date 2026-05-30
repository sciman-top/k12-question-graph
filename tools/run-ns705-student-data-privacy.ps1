param(
    [string] $ReportPath = 'docs/evidence/20260530-ns705-student-data-privacy-report.json'
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

function Read-Text([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing file: $Path"
    return Get-Content -LiteralPath $fullPath -Raw
}

function Invoke-CheckedScript([scriptblock] $Command, [string] $Label) {
    $output = & $Command 2>&1 | Out-String
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($output)) "$Label returned no output"
    return $output
}

Push-Location $repoRoot
try {
    $ns704 = Read-Json 'docs/evidence/20260530-ns704-commentary-report.json'
    Assert-Condition ($ns704.status -eq 'pass') 'NS705 dependency NS704 report did not pass'
    Assert-Condition (-not [bool]$ns704.realStudentDataUsed) 'NS705 requires NS704 to avoid real student data'
    Assert-Condition (-not [bool]$ns704.writesProductionHistory) 'NS705 requires NS704 no production history write'

    $ns203 = Read-Json 'docs/evidence/20260529-ns203-privacy-license-scan-report.json'
    Assert-Condition ($ns203.status -eq 'pass') 'NS705 dependency NS203 privacy scan did not pass'
    Assert-Condition ([int]$ns203.counts.blockingSecretHits -eq 0) 'NS705 requires zero blocking secret hits'
    Assert-Condition ([int]$ns203.counts.blockingPiiHits -eq 0) 'NS705 requires zero blocking PII hits'
    Assert-Condition ([int]$ns203.counts.trackedRawSourceBlockers -eq 0) 'NS705 requires zero tracked raw source blockers'
    Assert-Condition ([int]$ns203.counts.localRawSourceFiles -eq 0) 'NS705 requires local raw staging to stay empty'

    $n001 = (Invoke-CheckedScript {
        .\tools\run-n001-real-privacy-boundary-admission.ps1
    } 'N001 real privacy boundary admission') | ConvertFrom-Json
    Assert-Condition ($n001.status -eq 'pass') 'N001 real privacy boundary admission did not pass'

    $n006 = (Invoke-CheckedScript {
        .\tools\run-n006-pre-pilot-security-audit.ps1
    } 'N006 pre-pilot security audit') | ConvertFrom-Json
    Assert-Condition ($n006.status -eq 'pass') 'N006 pre-pilot security audit did not pass'
    Assert-Condition ([int]$n006.scannedFiles -ge 8) 'N006 scanned file coverage is too small'

    $policy = Read-Text 'docs/102_NonSiteFixturePrivacyPolicy.md'
    foreach ($marker in @(
        'synthetic',
        '脱敏',
        '真实学生',
        'PII',
        'sources/raw',
        'prompt',
        'evidence'
    )) {
        Assert-Condition ($policy.Contains($marker)) "NS705 fixture privacy policy missing marker: $marker"
    }

    $rawIgnore = Read-Text 'sources/raw/.gitignore'
    Assert-Condition ($rawIgnore.Contains('*')) 'NS705 sources/raw/.gitignore must ignore raw staging files'
    Assert-Condition ($rawIgnore.Contains('!.gitignore')) 'NS705 sources/raw/.gitignore must keep only the sentinel file'

    $scoreReports = @(
        'docs/evidence/20260530-ns701-score-template-mapping-report.json',
        'docs/evidence/20260530-ns702-item-score-mapping-report.json',
        'docs/evidence/20260530-ns703-analysis-metrics-report.json',
        'docs/evidence/20260530-ns704-commentary-report.json'
    )
    foreach ($path in $scoreReports) {
        $report = Read-Json $path
        Assert-Condition ($report.status -eq 'pass') "NS705 score-chain report did not pass: $path"
        Assert-Condition (-not [bool]$report.realStudentDataUsed) "NS705 found real student data use in $path"
        Assert-Condition (-not [bool]$report.productionEligible) "NS705 found production eligible score-chain report: $path"
        if ($null -ne $report.writesProductionHistory) {
            Assert-Condition (-not [bool]$report.writesProductionHistory) "NS705 found production history write in $path"
        }
        Assert-Condition ([int]$report.externalAiCalls -eq 0) "NS705 found external AI calls in $path"
    }

    $reportOut = [ordered]@{
        status = 'pass'
        taskId = 'NS705'
        checkedAt = (Get-Date).ToString('s')
        mode = 'real_student_data_privacy_admission'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns704 = 'docs/evidence/20260530-ns704-commentary-report.json'
            ns203 = 'docs/evidence/20260529-ns203-privacy-license-scan-report.json'
            n001 = [string]$n001.n001EvidencePath
            n006 = 'docs/evidence/20260505-n006-pre-pilot-security-audit.md'
        }
        scan = [ordered]@{
            trackedFileCount = [int]$ns203.scanScope.trackedFileCount
            blockingSecretHits = [int]$ns203.counts.blockingSecretHits
            blockingPiiHits = [int]$ns203.counts.blockingPiiHits
            trackedRawSourceBlockers = [int]$ns203.counts.trackedRawSourceBlockers
            localRawSourceFiles = [int]$ns203.counts.localRawSourceFiles
            n006ScannedFiles = [int]$n006.scannedFiles
        }
        scoreChainReports = $scoreReports
        acceptance = [ordered]@{
            noRealStudentPiiInGitPromptFixtureEvidence = $true
            rawStagingIgnoredAndEmpty = $true
            realDataRequiresJurisdictionAuthorizationRetentionDeletionPolicy = $true
            externalAiReceivesNoStudentIdentityOrScorePlaintextByDefault = $true
            scoreImportToReportChainUsesSyntheticOrAnonymizedDataOnly = $true
            noSecretsInAuditedEvidence = $true
            noProductionHistoryWrite = $true
            noActiveSwitch = $true
        }
        verification = [ordered]@{
            build = 'gate_na: privacy admission is document/evidence/scan contract only'
            test = 'tools/run-n001-real-privacy-boundary-admission.ps1 + tools/run-n006-pre-pilot-security-audit.ps1'
            contractInvariant = 'NS203 blocking secret/PII/raw-source counts are zero; NS701-NS704 remain synthetic/no real student data/no formal history writes'
            hotspot = 'gate_na: real school authorization and onsite privacy sign-off are not present; this gate blocks real data until those documents exist'
        }
        boundary = 'NS705 proves the non-site score and commentary chain remains synthetic/anonymized and fail-closed before any real student data pilot. It does not authorize processing real student records.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns705-student-data-privacy.ps1 $ReportPath"
        next = 'NS801 can continue backup manifest drill.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $reportOut | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $reportOut | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}
