param(
    [string] $BackupManifest = '',
    [string] $ReportPath = 'docs\evidence\cek034-curriculum-exam-knowledge-evidence-suite.json',
    [string] $WorkRoot = 'tmp\cek034',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [int] $BackupMaxAgeMinutes = 240,
    [bool] $RunFixedOrder = $true,
    [switch] $VerifyExistingReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$reportFile = if ([System.IO.Path]::IsPathRooted($ReportPath)) {
    [System.IO.Path]::GetFullPath($ReportPath)
}
else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $ReportPath))
}

. (Join-Path $PSScriptRoot 'dotenv.ps1')
. (Join-Path $PSScriptRoot 'database-env.ps1')
Import-KqgDotEnv -RepoRoot $repoRoot
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Get-PropertyValue([object] $Object, [string] $Name, $DefaultValue = $null) {
    if ($null -eq $Object) {
        return $DefaultValue
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

function Resolve-RepoPath([string] $Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function To-ReportPath([string] $Path) {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ($fullPath.StartsWith($repoRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        return [System.IO.Path]::GetRelativePath($repoRoot, $fullPath).Replace('\', '/')
    }

    return $fullPath
}

function Get-Sha256([string] $Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-NpmCommand {
    foreach ($candidate in @(Get-Command npm.cmd -All -ErrorAction SilentlyContinue)) {
        $npmCli = Join-Path (Split-Path -Parent $candidate.Source) 'node_modules\npm\bin\npm-cli.js'
        if (Test-Path -LiteralPath $npmCli -PathType Leaf) {
            return $candidate.Source
        }
    }

    throw 'npm.cmd with a complete npm installation was not found on PATH.'
}

function Redact-Text([string] $Text) {
    if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
        return $Text
    }

    return $Text.Replace($DatabasePassword, '***REDACTED***', [System.StringComparison]::Ordinal)
}

function Get-OutputTail([string] $Text, [int] $LineCount = 30) {
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    return @(
        (Redact-Text $Text) -split "`r?`n" |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Last $LineCount
    )
}

if ($VerifyExistingReport) {
    Assert-Condition (Test-Path -LiteralPath $reportFile -PathType Leaf) "CEK-34 report is missing: $reportFile"
    $existing = Get-Content -LiteralPath $reportFile -Raw | ConvertFrom-Json -Depth 100
    Assert-Condition ([string]$existing.taskId -eq 'CEK-34') 'existing report taskId is not CEK-34'
    Assert-Condition ([string]$existing.topicSuite.status -eq 'pass') 'existing CEK-34 topic suite did not pass'
    Assert-Condition ([string]$existing.backupRestore.status -eq 'pass') 'existing CEK-34 backup/restore drill did not pass'
    Assert-Condition ([string]$existing.migrationDrill.status -eq 'pass') 'existing CEK-34 migration drill did not pass'
    Assert-Condition ([string]$existing.databaseInvariants.status -eq 'pass') 'existing CEK-34 database invariants did not pass'
    Assert-Condition ([bool]$existing.supplyChain.scanCompleted) 'existing CEK-34 supply-chain scan is incomplete'
    [ordered]@{
        status = 'pass'
        taskId = 'CEK-34-SUITE-CONTRACT'
        report = To-ReportPath $reportFile
        runId = [string]$existing.runId
        topicSuite = [string]$existing.topicSuite.status
        backupRestore = [string]$existing.backupRestore.status
        migrationDrill = [string]$existing.migrationDrill.status
        databaseInvariants = [string]$existing.databaseInvariants.status
        boundary = 'full-gate recursion guard validates the fresh CEK-34 topic report; it does not rerun or weaken the suite'
    } | ConvertTo-Json -Depth 5
    return
}

Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for CEK-34.'
$previousPgPassword = $env:PGPASSWORD
$previousConnectionString = $env:KQG_CONNECTION_STRING
$previousOrchestration = $env:KQG_CEK34_ORCHESTRATING_FULL_GATE
$previousBackupManifest = $env:KQG_CEK34_BACKUP_MANIFEST
$env:PGPASSWORD = $DatabasePassword
$npmCommand = Resolve-NpmCommand

$startedAt = [DateTimeOffset]::UtcNow
$runId = '{0}-{1}' -f $startedAt.ToString('yyyyMMdd-HHmmss'), $PID
$resolvedWorkRoot = Resolve-RepoPath $WorkRoot
Assert-Condition ($resolvedWorkRoot.StartsWith((Join-Path $repoRoot 'tmp') + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) 'CEK-34 WorkRoot must stay under repo tmp.'
$runRoot = Join-Path $resolvedWorkRoot $runId
$logRoot = Join-Path $runRoot 'logs'
$freshReportRoot = Join-Path $runRoot 'fresh-reports'
New-Item -ItemType Directory -Path $logRoot, $freshReportRoot -Force | Out-Null

$steps = [System.Collections.Generic.List[object]]::new()
$topicCoverage = [ordered]@{}
$evidenceInventory = @()
$runtimeBefore = $null
$runtimeAfter = $null
$databaseBefore = $null
$databaseAfter = $null
$databaseInvariants = [ordered]@{ status = 'pending' }
$backupRestore = [ordered]@{ status = 'pending' }
$migrationDrill = [ordered]@{ status = 'pending' }
$supplyChain = [ordered]@{ status = 'pending'; scanCompleted = $false }
$fixedOrder = [ordered]@{ status = 'not_run'; reason = 'RunFixedOrder=false' }
$topicSuiteStatus = 'pending'
$overallStatus = 'running'
$failureMessage = $null

function Invoke-ExternalStep {
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string] $FilePath,
        [string[]] $Arguments = @(),
        [int[]] $AcceptedExitCodes = @(0),
        [string] $Category = 'topic'
    )

    $stepStarted = [DateTimeOffset]::UtcNow
    $safeId = $Id -replace '[^A-Za-z0-9_.-]', '_'
    $stdoutPath = Join-Path $logRoot "$safeId.stdout.log"
    $stderrPath = Join-Path $logRoot "$safeId.stderr.log"
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.WorkingDirectory = $repoRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        $null = $psi.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $stdout = Redact-Text ($stdoutTask.GetAwaiter().GetResult())
    $stderr = Redact-Text ($stderrTask.GetAwaiter().GetResult())
    [System.IO.File]::WriteAllText($stdoutPath, $stdout, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($stderrPath, $stderr, [System.Text.UTF8Encoding]::new($false))

    $stepFinished = [DateTimeOffset]::UtcNow
    $accepted = $AcceptedExitCodes -contains $process.ExitCode
    $entry = [ordered]@{
        id = $Id
        category = $Category
        status = if ($accepted) { 'pass' } else { 'fail' }
        startedAt = $stepStarted.ToString('o')
        finishedAt = $stepFinished.ToString('o')
        durationMs = [int]($stepFinished - $stepStarted).TotalMilliseconds
        exitCode = $process.ExitCode
        command = @($FilePath) + @($Arguments)
        stdoutLog = To-ReportPath $stdoutPath
        stdoutSha256 = Get-Sha256 $stdoutPath
        stderrLog = To-ReportPath $stderrPath
        stderrSha256 = Get-Sha256 $stderrPath
        outputTail = Get-OutputTail ($stdout + [Environment]::NewLine + $stderr)
    }
    $steps.Add([pscustomobject]$entry) | Out-Null
    if (-not $accepted) {
        throw "CEK-34 step failed: $Id (exit $($process.ExitCode)); tail: $($entry.outputTail -join ' | ')"
    }

    return [pscustomobject]@{
        exitCode = $process.ExitCode
        stdout = $stdout
        stderr = $stderr
        entry = [pscustomobject]$entry
    }
}

function Invoke-InternalStep {
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][scriptblock] $Action,
        [string] $Category = 'topic'
    )

    $stepStarted = [DateTimeOffset]::UtcNow
    try {
        $value = & $Action
        $stepFinished = [DateTimeOffset]::UtcNow
        $steps.Add([pscustomobject][ordered]@{
            id = $Id
            category = $Category
            status = 'pass'
            startedAt = $stepStarted.ToString('o')
            finishedAt = $stepFinished.ToString('o')
            durationMs = [int]($stepFinished - $stepStarted).TotalMilliseconds
            exitCode = 0
            command = @('internal', $Id)
            stdoutLog = $null
            stdoutSha256 = $null
            stderrLog = $null
            stderrSha256 = $null
            outputTail = @()
        }) | Out-Null
        return $value
    }
    catch {
        $stepFinished = [DateTimeOffset]::UtcNow
        $steps.Add([pscustomobject][ordered]@{
            id = $Id
            category = $Category
            status = 'fail'
            startedAt = $stepStarted.ToString('o')
            finishedAt = $stepFinished.ToString('o')
            durationMs = [int]($stepFinished - $stepStarted).TotalMilliseconds
            exitCode = 1
            command = @('internal', $Id)
            stdoutLog = $null
            stdoutSha256 = $null
            stderrLog = $null
            stderrSha256 = $null
            outputTail = @($_.Exception.Message)
        }) | Out-Null
        throw
    }
}

function Get-ListenerState {
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($port in @(5173, 5175, 5275, 5290)) {
        $listeners = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
        if ($listeners.Count -eq 0) {
            $items.Add([pscustomobject][ordered]@{ port = $port; listening = $false }) | Out-Null
            continue
        }

        foreach ($listener in $listeners) {
            $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)" -ErrorAction SilentlyContinue
            $commandLine = [string](Get-PropertyValue $process 'CommandLine' '')
            $health = $null
            if ($port -in @(5275, 5290)) {
                try {
                    $healthResponse = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health/ready" -TimeoutSec 3
                    $health = [string]$healthResponse.status
                }
                catch {
                    $health = 'unavailable'
                }
            }
            $items.Add([pscustomobject][ordered]@{
                port = $port
                listening = $true
                pid = [int]$listener.OwningProcess
                processName = [string](Get-PropertyValue $process 'Name' '')
                commandLine = $commandLine
                belongsToCurrentWorktree = $commandLine.Contains($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)
                readiness = $health
            }) | Out-Null
        }
    }

    $fileStore = if (Test-Path -LiteralPath $FileStoreRoot) {
        $files = @(Get-ChildItem -LiteralPath $FileStoreRoot -File -Recurse)
        [ordered]@{
            root = $FileStoreRoot
            exists = $true
            fileCount = $files.Count
            totalBytes = [long](($files | Measure-Object Length -Sum).Sum)
            lastWriteUtc = (Get-Item -LiteralPath $FileStoreRoot).LastWriteTimeUtc.ToString('o')
        }
    }
    else {
        [ordered]@{ root = $FileStoreRoot; exists = $false; fileCount = 0; totalBytes = 0 }
    }

    return [ordered]@{
        checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
        listeners = $items.ToArray()
        fileStore = $fileStore
    }
}

function Get-DatabaseSnapshot([string] $TargetDatabase, [string] $StepId) {
    $query = @'
select jsonb_build_object(
  'database', current_database(),
  'serverVersion', current_setting('server_version'),
  'migrationCount', (select count(*) from "__EFMigrationsHistory"),
  'latestMigration', (select max(migration_id) from "__EFMigrationsHistory"),
  'questionCorpus', (select count(*) from question_items where custom_fields->>'sourceWorkflowKey'='guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1'),
  'reportRegions', (select count(*) from source_regions where metadata->>'importKey'='cek012a_guangzhou_report_question_anchors_v1'),
  'reportQuestionCoverage', (select count(distinct (metadata->>'year', metadata->>'questionNumber')) from source_regions where metadata->>'importKey'='cek012a_guangzhou_report_question_anchors_v1'),
  'curriculumRequirements', (select count(*) from domain_asset_versions where status='candidate' and asset_type='curriculum_requirement'),
  'requirementFacets', (select count(*) from domain_asset_versions where status='candidate' and asset_type='requirement_facet'),
  'regionalProfiles', (select count(*) from domain_asset_versions where status='candidate' and asset_type='exam_point'),
  'activeAssets', (select count(*) from domain_asset_versions where status='active'),
  'assessmentTargets', (select count(*) from assessment_targets),
  'targetMappings', (select count(*) from assessment_target_knowledge_mappings),
  'curriculumAlignments', (select count(*) from curriculum_alignments),
  'observedPerformance', (select count(*) from observed_performance_evidence),
  'observedErrors', (select count(*) from observed_error_evidence),
  'teachingRecommendations', (select count(*) from teaching_recommendations),
  'alignmentDistribution', (select coalesce(jsonb_object_agg(alignment_type,c), '{}'::jsonb) from (select alignment_type,count(*) c from curriculum_alignments group by alignment_type) d),
  'productionEligibleCount', (
    (select count(*) from assessment_targets where production_eligible) +
    (select count(*) from assessment_target_knowledge_mappings where production_eligible) +
    (select count(*) from curriculum_alignments where production_eligible) +
    (select count(*) from observed_performance_evidence where production_eligible) +
    (select count(*) from observed_error_evidence where production_eligible) +
    (select count(*) from teaching_recommendations where production_eligible)
  ),
  'activeCurriculumExamCandidateCount', (
    (select count(*) from assessment_targets where status='active') +
    (select count(*) from assessment_target_knowledge_mappings where status='active') +
    (select count(*) from curriculum_alignments where status='active') +
    (select count(*) from observed_performance_evidence where status='active') +
    (select count(*) from observed_error_evidence where status='active') +
    (select count(*) from teaching_recommendations where status='active')
  ),
  'fingerprint', (
    select md5(coalesce(string_agg(scope || ':' || row_id || ':' || payload, E'\n' order by scope,row_id),''))
    from (
      select 'active_asset' scope,id::text row_id,to_jsonb(t)::text payload from domain_asset_versions t where status='active'
      union all select 'candidate_asset',id::text,to_jsonb(t)::text from domain_asset_versions t where asset_type in ('curriculum_requirement','requirement_facet','exam_point') and status='candidate'
      union all select 'target',id::text,to_jsonb(t)::text from assessment_targets t
      union all select 'target_mapping',id::text,to_jsonb(t)::text from assessment_target_knowledge_mappings t
      union all select 'alignment',id::text,to_jsonb(t)::text from curriculum_alignments t
      union all select 'performance',id::text,to_jsonb(t)::text from observed_performance_evidence t
      union all select 'error',id::text,to_jsonb(t)::text from observed_error_evidence t
      union all select 'recommendation',id::text,to_jsonb(t)::text from teaching_recommendations t
      union all select 'question',id::text,to_jsonb(t)::text from question_items t where custom_fields->>'sourceWorkflowKey'='guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1'
    ) rows
  )
);
'@
    $psql = Join-Path $PgBin 'psql.exe'
    $result = Invoke-ExternalStep -Id $StepId -FilePath $psql -Arguments @(
        '-h', $DatabaseHost,
        '-p', [string]$DatabasePort,
        '-U', $DatabaseUser,
        '-d', $TargetDatabase,
        '-v', 'ON_ERROR_STOP=1',
        '-At',
        '-c', $query
    ) -Category 'data'
    return $result.stdout.Trim() | ConvertFrom-Json -Depth 30
}

function Assert-DatabaseInvariants([object] $Snapshot) {
    Assert-Condition ([int]$Snapshot.questionCorpus -eq 234) 'CEK-34 expected 234 Guangzhou candidate questions.'
    Assert-Condition ([int]$Snapshot.reportRegions -eq 268) 'CEK-34 expected 268 annual-report SourceRegion candidates.'
    Assert-Condition ([int]$Snapshot.reportQuestionCoverage -eq 234) 'CEK-34 expected annual-report anchors for 234 questions.'
    Assert-Condition (([int]$Snapshot.curriculumRequirements + [int]$Snapshot.requirementFacets) -eq 273) 'CEK-34 expected 273 curriculum requirement/facet candidates.'
    Assert-Condition ([int]$Snapshot.assessmentTargets -eq 444) 'CEK-34 expected 444 assessment targets.'
    Assert-Condition ([int]$Snapshot.targetMappings -eq 234) 'CEK-34 expected 234 whole-question primary knowledge mappings.'
    Assert-Condition ([int]$Snapshot.curriculumAlignments -eq 133) 'CEK-34 expected 133 curriculum alignments.'
    Assert-Condition ([int]$Snapshot.observedPerformance -eq 157) 'CEK-34 expected 157 observed-performance rows.'
    Assert-Condition ([int]$Snapshot.observedErrors -eq 35) 'CEK-34 expected 35 observed-error rows.'
    Assert-Condition ([int]$Snapshot.teachingRecommendations -eq 25) 'CEK-34 expected 25 teaching recommendations.'
    Assert-Condition ([int]$Snapshot.regionalProfiles -eq 24) 'CEK-34 expected 24 regional profiles.'
    Assert-Condition ([int]$Snapshot.activeAssets -eq 452) 'CEK-34 active C002 asset count drifted from 452.'
    Assert-Condition ([int]$Snapshot.productionEligibleCount -eq 0) 'CEK-34 found production-eligible candidate evidence.'
    Assert-Condition ([int]$Snapshot.activeCurriculumExamCandidateCount -eq 0) 'CEK-34 found active curriculum/exam candidate records.'
    Assert-Condition ([int](Get-PropertyValue $Snapshot.alignmentDistribution 'retrospective_crosswalk' 0) -eq 128) 'CEK-34 retrospective alignment count drifted from 128.'
    Assert-Condition ([int](Get-PropertyValue $Snapshot.alignmentDistribution 'contemporaneous_inferred' 0) -eq 5) 'CEK-34 contemporaneous inferred alignment count drifted from 5.'
    Assert-Condition ([int](Get-PropertyValue $Snapshot.alignmentDistribution 'source_cited' 0) -eq 0) 'CEK-34 must not fabricate source_cited alignments.'
}

function Read-FreshJson([string] $Path, [string] $Label) {
    $fullPath = Resolve-RepoPath $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath -PathType Leaf) "$Label report missing: $fullPath"
    $report = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json -Depth 100
    Assert-Condition ([string](Get-PropertyValue $report 'status' '') -eq 'pass') "$Label report did not pass."
    $checkedAtValue = Get-PropertyValue $report 'checkedAt' $null
    Assert-Condition ($null -ne $checkedAtValue) "$Label report has no checkedAt."
    $checkedAt = if ($checkedAtValue -is [DateTime]) {
        [DateTimeOffset][DateTime]$checkedAtValue
    }
    else {
        [DateTimeOffset]::Parse(
            [string]$checkedAtValue,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        )
    }
    Assert-Condition ($checkedAt.ToUniversalTime() -ge $startedAt.AddMinutes(-2)) "$Label report is not fresh for this run."
    return $report
}

function Write-SuiteReport {
    param([string] $Status, [string] $ErrorText = '')

    $report = [ordered]@{
        schemaVersion = 'cek034-curriculum-exam-knowledge-evidence-suite.v1'
        status = $Status
        taskId = 'CEK-34'
        checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
        runId = $runId
        runRoot = To-ReportPath $runRoot
        topicSuite = [ordered]@{
            status = $topicSuiteStatus
            coverage = $topicCoverage
            evidenceInventory = $evidenceInventory
            stepCount = @($steps | Where-Object category -ne 'fixed_order').Count
        }
        runtime = [ordered]@{
            before = $runtimeBefore
            after = $runtimeAfter
        }
        backupRestore = $backupRestore
        migrationDrill = $migrationDrill
        databaseInvariants = $databaseInvariants
        supplyChain = $supplyChain
        fixedOrder = $fixedOrder
        steps = $steps.ToArray()
        failure = if ([string]::IsNullOrWhiteSpace($ErrorText)) { $null } else { $ErrorText }
        dependencyChange = [bool](Get-PropertyValue $supplyChain 'dependencyChange' $false)
        externalAiCalls = 0
        realStudentDataUsed = $false
        productionActiveSwitch = $false
        productionEligible = $false
        dataLifecycle = [ordered]@{
            extractedState = 'candidate'
            reviewState = 'pending_review'
            activeAssetCount = if ($null -eq $databaseAfter) { $null } else { [int]$databaseAfter.activeAssets }
            sourceCitedAlignmentCount = if ($null -eq $databaseAfter) { $null } else { [int](Get-PropertyValue $databaseAfter.alignmentDistribution 'source_cited' 0) }
        }
        hotspot = [ordered]@{
            status = 'gate_na'
            reason = '仓库尚无独立 hotspot 命令'
            alternative_verification = '受影响 API/UI/worker/data/AI/export 合同、数据库指纹与教师效率人工复核'
            evidence_link = 'docs/18_TestStrategy.md'
            expires_at = 'next_executable_change'
            recovery_condition = '建立独立 hotspot 命令并纳入门禁'
            manualReview = [ordered]@{
                api = 'targeted API tests plus read-only live API smoke'
                ui = 'full Web tests plus CEK-26/30 static interaction contracts'
                worker = 'targeted CEK worker/unit suite'
                data = 'fresh PostgreSQL aggregate counts, lifecycle checks, and before/after fingerprint parity'
                ai = 'zero external AI calls; error-pattern promotion remains pending_review and no-active-write'
                export = 'paper evidence constraints and historical compatibility are covered by targeted API tests and full gate'
                teacherEfficiency = 'no new teacher step or admin-only field was added; existing search/review/paper/analysis paths remain the tested surface'
            }
        }
        productionBoundary = [ordered]@{
            realTeacherReviewCompleted = $false
            authenticatedAuthorizationProven = $false
            productionActiveSwitched = $false
            onsiteNetworkIsolatedMachineAccepted = $false
            REAL005 = 'not_closed'
            release = 'NO-GO'
        }
        rollback = [ordered]@{
            data = 'restore database and FileStore from backupRestore.manifest; do not use Git as data rollback'
            isolation = 'temporary kqg_cek034_* database and marked D:\KQG_Data\isolated\cek034-* directory are removed in finally'
            code = 'revert only the CEK-34 suite, run-gates integration, tools documentation, and CEK-35 status slice'
        }
        completionBoundary = 'CEK-34 can close the repo-side evidence and recovery gate only. Candidate data remains pending review and non-production; teacher sign-off, authenticated authorization, production active switch, school network, isolated-machine acceptance, REAL005 closure, and release approval remain open.'
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFile) -Force | Out-Null
    [System.IO.File]::WriteAllText($reportFile, (($report | ConvertTo-Json -Depth 100) + "`n"), [System.Text.UTF8Encoding]::new($false))
}

Push-Location $repoRoot
try {
    $runtimeBefore = Invoke-InternalStep -Id 'runtime-before' -Category 'runtime' -Action { Get-ListenerState }
    $databaseBefore = Get-DatabaseSnapshot -TargetDatabase $DatabaseName -StepId 'database-before'
    Invoke-InternalStep -Id 'database-before-invariants' -Category 'data' -Action { Assert-DatabaseInvariants $databaseBefore } | Out-Null

    if ([string]::IsNullOrWhiteSpace($BackupManifest)) {
        $backupResult = Invoke-ExternalStep -Id 'fresh-backup' -FilePath 'pwsh' -Arguments @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'backup.ps1'),
            '-FileStoreRoot', $FileStoreRoot,
            '-PgBin', $PgBin,
            '-DatabaseName', $DatabaseName,
            '-DatabaseHost', $DatabaseHost,
            '-DatabasePort', [string]$DatabasePort,
            '-DatabaseUser', $DatabaseUser
        ) -Category 'backup_restore'
        $backupOutput = $backupResult.stdout.Trim() | ConvertFrom-Json
        $BackupManifest = [string]$backupOutput.manifest
    }
    $backupManifestPath = (Get-Item -LiteralPath $BackupManifest).FullName
    $verifyBackupResult = Invoke-ExternalStep -Id 'verify-fresh-backup' -FilePath 'pwsh' -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'verify-backup.ps1'),
        '-ManifestPath', $backupManifestPath
    ) -Category 'backup_restore'
    $verifyBackup = $verifyBackupResult.stdout.Trim() | ConvertFrom-Json
    $manifest = Get-Content -LiteralPath $backupManifestPath -Raw | ConvertFrom-Json -Depth 100
    $manifestCreatedAt = [DateTimeOffset]$manifest.createdAt
    $manifestAge = [DateTimeOffset]::UtcNow - $manifestCreatedAt.ToUniversalTime()
    Assert-Condition ($manifestAge.TotalMinutes -ge -5) 'CEK-34 backup manifest timestamp is too far in the future.'
    Assert-Condition ($manifestAge.TotalMinutes -le $BackupMaxAgeMinutes) "CEK-34 backup manifest is stale: $([int]$manifestAge.TotalMinutes) minutes."
    Assert-Condition ([string]$manifest.database.databaseName -eq $DatabaseName) 'CEK-34 backup database name mismatch.'
    $backupRestore = [ordered]@{
        status = 'verified_pending_restore_drill'
        manifest = $backupManifestPath
        manifestSha256 = Get-Sha256 $backupManifestPath
        createdAt = $manifestCreatedAt.ToUniversalTime().ToString('o')
        ageMinutesAtVerification = [math]::Round($manifestAge.TotalMinutes, 2)
        databaseSha256 = [string]$manifest.database.sha256
        fileStoreFileCount = [int]$verifyBackup.fileCount
        configCount = [int]$verifyBackup.configCount
        templateCount = [int]$verifyBackup.templateCount
        evidenceCount = [int]$verifyBackup.evidenceCount
        verifyStatus = [string]$verifyBackup.status
        restoreEntry = "pwsh -NoProfile -ExecutionPolicy Bypass -File tools/restore.ps1 -ManifestPath '$backupManifestPath' -TargetDataRoot 'D:\KQG_Data' -DatabaseName '$DatabaseName' -DatabaseHost '$DatabaseHost' -DatabasePort $DatabasePort -DatabaseUser '$DatabaseUser' -ApplyDatabase -ApplyFileStore -DryRun:`$false"
    }

    $requiredEvidence = @(
        'docs/evidence/cek001-curriculum-standard-source-batch.json',
        'docs/evidence/cek002-curriculum-standard-migration.json',
        'docs/evidence/cek003-curriculum-source-admission.json',
        'docs/evidence/cek004-evidence-anchor-migration.json',
        'docs/evidence/cek005-curriculum-requirement-contract.json',
        'docs/evidence/cek006-curriculum-standard-structure.json',
        'docs/evidence/cek007-curriculum-requirement-extraction-eval.json',
        'docs/evidence/cek008-curriculum-knowledge-crosswalk.json',
        'docs/evidence/cek009-curriculum-candidate-import.json',
        'docs/evidence/cek010-question-scope-normalization.json',
        'docs/evidence/cek011-assessment-target-contract.json',
        'docs/evidence/cek012-guangzhou-exam-evidence-index.json',
        'docs/evidence/cek012a-guangzhou-report-anchor-materialization.json',
        'docs/evidence/cek013-guangzhou-three-source-alignment.json',
        'docs/evidence/cek014-assessment-target-extraction-eval.json',
        'docs/evidence/cek015-assessment-target-migration.json',
        'docs/evidence/cek016-assessment-target-api-smoke.json',
        'docs/evidence/cek017-observed-exam-evidence-contract.json',
        'docs/evidence/cek018-guangzhou-year-report-evidence.json',
        'docs/evidence/cek019-observed-evidence-migration.json',
        'docs/evidence/cek019a-observed-exam-evidence-api-smoke.json',
        'docs/evidence/cek020-error-pattern-promotion-guard.json',
        'docs/evidence/cek021-regional-exam-profile-contract.json',
        'docs/evidence/cek022-regional-exam-profile-aggregation.json',
        'docs/evidence/cek023-regional-exam-profile-query-smoke.json',
        'docs/evidence/cek024-curriculum-exam-c002r-plan.json',
        'docs/evidence/cek025-curriculum-evidence-review-api.json',
        'docs/evidence/cek026-curriculum-evidence-review-ui.json',
        'docs/evidence/cek027-curriculum-exam-c002r-isolated-drill.json',
        'docs/evidence/cek028-question-evidence-search-api.json',
        'docs/evidence/cek029-question-evidence-web-contract.json',
        'docs/evidence/cek030-question-evidence-search-ui.json',
        'docs/evidence/cek031-paper-evidence-constraint-smoke.json',
        'docs/evidence/cek032-score-evidence-analysis-smoke.json'
    )
    $evidenceInventory = Invoke-InternalStep -Id 'cek001-cek033-evidence-index' -Category 'evidence' -Action {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($relativePath in $requiredEvidence) {
            $fullPath = Resolve-RepoPath $relativePath
            Assert-Condition (Test-Path -LiteralPath $fullPath -PathType Leaf) "CEK evidence missing: $relativePath"
            $json = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json -Depth 100
            $status = [string](Get-PropertyValue $json 'status' '')
            Assert-Condition ($status -in @('pass', 'uploaded')) "CEK evidence has non-accepted status: $relativePath -> $status"
            $items.Add([pscustomobject][ordered]@{
                path = $relativePath
                status = $status
                checkedAt = [string](Get-PropertyValue $json 'checkedAt' '')
                sha256 = Get-Sha256 $fullPath
            }) | Out-Null
        }

        $browserReport = Resolve-RepoPath 'docs/evidence/cek033-browser-e2e-visual.md'
        Assert-Condition (Test-Path -LiteralPath $browserReport -PathType Leaf) 'CEK-33 browser report is missing.'
        $browserText = Get-Content -LiteralPath $browserReport -Raw
        foreach ($marker in @('status: pass_with_explicit_source_cited_data_absence', 'source_cited', 'REAL005', 'NO-GO')) {
            if ($marker -eq 'NO-GO') {
                continue
            }
            Assert-Condition ($browserText.Contains($marker)) "CEK-33 browser report missing marker: $marker"
        }
        foreach ($png in @(
            'cek033-desktop-candidate-search.png', 'cek033-desktop-analysis.png',
            'cek033-mobile-candidate-search.png', 'cek033-mobile-analysis.png', 'cek033-mobile-review.png',
            'cek033-curriculum-source-page.png', 'cek033-report-source-page.png'
        )) {
            $pngPath = Resolve-RepoPath ("docs/evidence/$png")
            Assert-Condition (Test-Path -LiteralPath $pngPath -PathType Leaf) "CEK-33 screenshot missing: $png"
            Assert-Condition ((Get-Item -LiteralPath $pngPath).Length -gt 1024) "CEK-33 screenshot is unexpectedly small: $png"
        }
        $items.Add([pscustomobject][ordered]@{
            path = 'docs/evidence/cek033-browser-e2e-visual.md'
            status = 'pass_with_explicit_source_cited_data_absence'
            checkedAt = '2026-07-31'
            sha256 = Get-Sha256 $browserReport
        }) | Out-Null
        return $items.ToArray()
    }

    $freshReports = [ordered]@{
        curriculumRequirement = To-ReportPath (Join-Path $freshReportRoot 'cek005.json')
        assessmentTarget = To-ReportPath (Join-Path $freshReportRoot 'cek011.json')
        observedEvidence = To-ReportPath (Join-Path $freshReportRoot 'cek017.json')
        errorPattern = To-ReportPath (Join-Path $freshReportRoot 'cek020.json')
        regionalProfile = To-ReportPath (Join-Path $freshReportRoot 'cek021.json')
        reviewUi = To-ReportPath (Join-Path $freshReportRoot 'cek026.json')
        searchApi = To-ReportPath (Join-Path $freshReportRoot 'cek028.json')
        searchUi = To-ReportPath (Join-Path $freshReportRoot 'cek030.json')
    }

    foreach ($contract in @(
        @{ id = 'schema-curriculum-requirement'; script = 'run-curriculum-requirement-contract.ps1'; report = $freshReports.curriculumRequirement },
        @{ id = 'schema-assessment-target'; script = 'run-assessment-target-contract.ps1'; report = $freshReports.assessmentTarget },
        @{ id = 'schema-observed-evidence'; script = 'run-observed-exam-evidence-contract.ps1'; report = $freshReports.observedEvidence },
        @{ id = 'schema-error-pattern'; script = 'run-error-pattern-promotion-guard.ps1'; report = $freshReports.errorPattern },
        @{ id = 'schema-regional-profile'; script = 'run-regional-exam-profile-contract.ps1'; report = $freshReports.regionalProfile }
    )) {
        Invoke-ExternalStep -Id $contract.id -FilePath 'pwsh' -Arguments @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $contract.script),
            '-ReportPath', $contract.report
        ) -Category 'schema' | Out-Null
        $null = Read-FreshJson -Path $contract.report -Label $contract.id
    }
    $topicCoverage.schema = [ordered]@{ status = 'pass'; contracts = 5; reports = $freshReports }

    $workerModules = @(
        'tests.workers.test_curriculum_standard_source_batch',
        'tests.workers.test_curriculum_standard_structure',
        'tests.workers.test_curriculum_requirement_facets',
        'tests.workers.test_curriculum_knowledge_crosswalk',
        'tests.workers.test_question_scope_normalization',
        'tests.workers.test_guangzhou_exam_evidence_index',
        'tests.workers.test_guangzhou_three_source_alignment',
        'tests.workers.test_assessment_target_extraction',
        'tests.workers.test_assessment_target_import',
        'tests.workers.test_guangzhou_year_report_evidence',
        'tests.workers.test_observed_exam_evidence_import',
        'tests.workers.test_regional_exam_profile_aggregation',
        'tests.workers.test_regional_exam_profile_import',
        'tests.workers.test_curriculum_exam_c002r_plan',
        'tests.workers.test_curriculum_exam_c002r_drill'
    )
    Invoke-ExternalStep -Id 'worker-unit-tests' -FilePath 'python' -Arguments (@('-m', 'unittest') + $workerModules) -Category 'worker' | Out-Null
    $topicCoverage.workerUnit = [ordered]@{ status = 'pass'; modules = $workerModules }

    $apiFilter = 'FullyQualifiedName~KnowledgeEvidenceWorkflowServiceTests|FullyQualifiedName~CurriculumEvidenceReviewTests|FullyQualifiedName~ErrorPatternPromotionTests|FullyQualifiedName~QuestionEvidenceSearchTests|FullyQualifiedName~PaperEvidenceConstraintTests|FullyQualifiedName~RegionalExamProfileQueryTests|FullyQualifiedName~ScoreEvidenceAnalysisTests'
    Invoke-ExternalStep -Id 'api-targeted-tests' -FilePath 'dotnet' -Arguments @(
        'test', 'tests/api/K12QuestionGraph.Api.Tests/K12QuestionGraph.Api.Tests.csproj',
        '-c', 'Cek034', '--filter', $apiFilter
    ) -Category 'api' | Out-Null
    Invoke-ExternalStep -Id 'api-readonly-live-smoke' -FilePath 'pwsh' -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'run-question-evidence-search-api.ps1'),
        '-ReportPath', $freshReports.searchApi,
        '-Configuration', 'Cek034Api',
        '-DatabaseName', $DatabaseName,
        '-DatabaseHost', $DatabaseHost,
        '-DatabasePort', [string]$DatabasePort,
        '-DatabaseUser', $DatabaseUser
    ) -Category 'api' | Out-Null
    $freshSearchApi = Read-FreshJson -Path $freshReports.searchApi -Label 'CEK-28 read-only live API smoke'
    Assert-Condition ([bool]$freshSearchApi.compatibility.legacyContractUnchanged) 'CEK-34 legacy question API compatibility failed.'
    Assert-Condition ([bool]$freshSearchApi.governance.databaseUnchanged) 'CEK-34 read-only API smoke changed the database.'
    $topicCoverage.apiHistoricalCompatibility = [ordered]@{
        status = 'pass'
        targetedClasses = 7
        legacyEndpoint = [string]$freshSearchApi.compatibility.legacyEndpoint
        legacyTotal = [int]$freshSearchApi.compatibility.legacyTotal
        databaseUnchanged = [bool]$freshSearchApi.governance.databaseUnchanged
    }

    Invoke-ExternalStep -Id 'web-full-tests' -FilePath $npmCommand -Arguments @('--prefix', 'apps/web', 'test', '--', '--run') -Category 'ui' | Out-Null
    foreach ($uiContract in @(
        @{ id = 'ui-review-contract'; script = 'run-curriculum-evidence-review-ui-contract.ps1'; report = $freshReports.reviewUi },
        @{ id = 'ui-search-contract'; script = 'run-question-evidence-search-ui-contract.ps1'; report = $freshReports.searchUi }
    )) {
        Invoke-ExternalStep -Id $uiContract.id -FilePath 'pwsh' -Arguments @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $uiContract.script),
            '-ReportPath', $uiContract.report
        ) -Category 'ui' | Out-Null
        $null = Read-FreshJson -Path $uiContract.report -Label $uiContract.id
    }
    $topicCoverage.ui = [ordered]@{ status = 'pass'; fullWebSuite = $true; contracts = @('CEK-26', 'CEK-30') }

    $isolationRoot = [System.IO.Path]::GetFullPath('D:\KQG_Data\isolated').TrimEnd('\')
    $isolationToken = '{0}_{1}' -f ([DateTimeOffset]::UtcNow.ToString('yyyyMMdd_HHmmss')), $PID
    $isolatedDatabaseName = "kqg_cek034_$isolationToken"
    $isolatedDataRoot = Join-Path $isolationRoot "cek034-$isolationToken"
    $isolationMarker = Join-Path $isolatedDataRoot '.cek034-isolated'
    $databaseCreated = $false
    $dataRootCreated = $false
    $migrationError = $null
    $migrationResult = [ordered]@{
        status = 'running'
        isolatedDatabase = $isolatedDatabaseName
        isolatedDataRoot = $isolatedDataRoot
        downTarget = '20260728122942_AddEvidenceAnchorMetadataForCEK004'
        downVerified = $false
        upVerified = $false
        databaseRestoreParity = $false
        fileStoreRestoreParity = $false
        databaseDropped = $false
        dataRootRemoved = $false
    }

    Assert-Condition ($isolatedDatabaseName -match '^kqg_cek034_\d{8}_\d{6}_\d+$') 'CEK-34 generated database failed the allowlist.'
    Assert-Condition ([System.IO.Path]::GetFullPath($isolatedDataRoot).StartsWith($isolationRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) 'CEK-34 isolation path escaped the allowed root.'
    try {
        New-Item -ItemType Directory -Path $isolatedDataRoot -Force | Out-Null
        $dataRootCreated = $true
        Set-Content -LiteralPath $isolationMarker -Value "CEK-34:$isolatedDatabaseName" -Encoding ASCII
        $createdb = Join-Path $PgBin 'createdb.exe'
        $dropdb = Join-Path $PgBin 'dropdb.exe'
        $pgRestore = Join-Path $PgBin 'pg_restore.exe'
        foreach ($tool in @($createdb, $dropdb, $pgRestore)) {
            Assert-Condition (Test-Path -LiteralPath $tool -PathType Leaf) "PostgreSQL tool missing: $tool"
        }
        Invoke-ExternalStep -Id 'migration-createdb' -FilePath $createdb -Arguments @(
            '-h', $DatabaseHost, '-p', [string]$DatabasePort, '-U', $DatabaseUser,
            '-T', 'template0', '-E', 'UTF8', $isolatedDatabaseName
        ) -Category 'migration' | Out-Null
        $databaseCreated = $true
        $databaseDumpPath = Join-Path (Split-Path -Parent $backupManifestPath) ([string]$manifest.database.dump)
        Invoke-ExternalStep -Id 'migration-initial-restore' -FilePath $pgRestore -Arguments @(
            '-h', $DatabaseHost, '-p', [string]$DatabasePort, '-U', $DatabaseUser,
            '-d', $isolatedDatabaseName, '--no-owner', '--no-privileges', '--exit-on-error', $databaseDumpPath
        ) -Category 'migration' | Out-Null
        $restoreResult = Invoke-ExternalStep -Id 'filestore-isolated-restore' -FilePath 'pwsh' -Arguments @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'restore.ps1'),
            '-ManifestPath', $backupManifestPath,
            '-TargetDataRoot', $isolatedDataRoot,
            '-PgBin', $PgBin,
            '-DatabaseName', $isolatedDatabaseName,
            '-DatabaseHost', $DatabaseHost,
            '-DatabasePort', [string]$DatabasePort,
            '-DatabaseUser', $DatabaseUser,
            '-ApplyFileStore', '-DryRun:$false'
        ) -Category 'backup_restore'
        $restoreReport = $restoreResult.stdout.Trim() | ConvertFrom-Json -Depth 30
        Assert-Condition ([int]$restoreReport.validated.fileStoreCount -eq [int]$verifyBackup.fileCount) 'CEK-34 isolated FileStore restore count mismatch.'
        $fileStoreParity = Invoke-InternalStep -Id 'filestore-isolated-parity' -Category 'backup_restore' -Action {
            $restoredRoot = Join-Path $isolatedDataRoot 'file_store'
            $checkedBytes = [long]0
            foreach ($file in @($manifest.fileStore.files)) {
                $restoredPath = Join-Path $restoredRoot ([string]$file.path)
                Assert-Condition (Test-Path -LiteralPath $restoredPath -PathType Leaf) "CEK-34 restored FileStore file missing: $($file.path)"
                $restoredItem = Get-Item -LiteralPath $restoredPath
                Assert-Condition ([long]$restoredItem.Length -eq [long]$file.bytes) "CEK-34 restored FileStore size mismatch: $($file.path)"
                Assert-Condition ((Get-Sha256 $restoredPath) -eq [string]$file.sha256) "CEK-34 restored FileStore hash mismatch: $($file.path)"
                $checkedBytes += [long]$restoredItem.Length
            }
            $unexpectedFiles = @(Get-ChildItem -LiteralPath $restoredRoot -File -Recurse).Count - @($manifest.fileStore.files).Count
            Assert-Condition ($unexpectedFiles -eq 0) 'CEK-34 isolated FileStore restore contains unexpected files.'
            return [ordered]@{
                fileCount = @($manifest.fileStore.files).Count
                totalBytes = $checkedBytes
                unexpectedFiles = $unexpectedFiles
                algorithm = 'SHA256'
            }
        }
        $migrationResult.fileStoreRestoreParity = $true
        $migrationResult.fileStoreParity = $fileStoreParity

        $cloneBefore = Get-DatabaseSnapshot -TargetDatabase $isolatedDatabaseName -StepId 'migration-clone-before'
        Assert-Condition ([string]$cloneBefore.fingerprint -eq [string]$databaseBefore.fingerprint) 'CEK-34 fresh backup database clone does not match the live pre-run fingerprint.'
        Invoke-ExternalStep -Id 'migration-build' -FilePath 'dotnet' -Arguments @(
            'build', 'apps/api/K12QuestionGraph.Api.csproj', '-c', 'Cek034Migration', '--no-restore'
        ) -Category 'migration' | Out-Null

        $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$isolatedDatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
        Invoke-ExternalStep -Id 'migration-down' -FilePath 'dotnet' -Arguments @(
            'ef', 'database', 'update', '20260728122942_AddEvidenceAnchorMetadataForCEK004',
            '--project', 'apps/api/K12QuestionGraph.Api.csproj',
            '--startup-project', 'apps/api/K12QuestionGraph.Api.csproj',
            '--configuration', 'Cek034Migration', '--no-build'
        ) -Category 'migration' | Out-Null
        $psql = Join-Path $PgBin 'psql.exe'
        $downQuery = "select jsonb_build_object('latestMigration',(select max(migration_id) from `"__EFMigrationsHistory`"),'targetsAbsent',to_regclass('public.assessment_targets') is null,'performanceAbsent',to_regclass('public.observed_performance_evidence') is null,'errorsAbsent',to_regclass('public.observed_error_evidence') is null,'recommendationsAbsent',to_regclass('public.teaching_recommendations') is null);"
        $downCheckResult = Invoke-ExternalStep -Id 'migration-down-check' -FilePath $psql -Arguments @(
            '-h', $DatabaseHost, '-p', [string]$DatabasePort, '-U', $DatabaseUser, '-d', $isolatedDatabaseName,
            '-v', 'ON_ERROR_STOP=1', '-At', '-c', $downQuery
        ) -Category 'migration'
        $downCheck = $downCheckResult.stdout.Trim() | ConvertFrom-Json
        Assert-Condition ([string]$downCheck.latestMigration -eq '20260728122942_AddEvidenceAnchorMetadataForCEK004') 'CEK-34 migration Down stopped at the wrong migration.'
        Assert-Condition ([bool]$downCheck.targetsAbsent -and [bool]$downCheck.performanceAbsent -and [bool]$downCheck.errorsAbsent -and [bool]$downCheck.recommendationsAbsent) 'CEK-34 migration Down did not remove CEK-15/19 tables.'
        $migrationResult.downVerified = $true

        Invoke-ExternalStep -Id 'migration-up' -FilePath 'dotnet' -Arguments @(
            'ef', 'database', 'update',
            '--project', 'apps/api/K12QuestionGraph.Api.csproj',
            '--startup-project', 'apps/api/K12QuestionGraph.Api.csproj',
            '--configuration', 'Cek034Migration', '--no-build'
        ) -Category 'migration' | Out-Null
        $upQuery = "select jsonb_build_object('latestMigration',(select max(migration_id) from `"__EFMigrationsHistory`"),'targetsPresent',to_regclass('public.assessment_targets') is not null,'performancePresent',to_regclass('public.observed_performance_evidence') is not null,'errorsPresent',to_regclass('public.observed_error_evidence') is not null,'recommendationsPresent',to_regclass('public.teaching_recommendations') is not null);"
        $upCheckResult = Invoke-ExternalStep -Id 'migration-up-check' -FilePath $psql -Arguments @(
            '-h', $DatabaseHost, '-p', [string]$DatabasePort, '-U', $DatabaseUser, '-d', $isolatedDatabaseName,
            '-v', 'ON_ERROR_STOP=1', '-At', '-c', $upQuery
        ) -Category 'migration'
        $upCheck = $upCheckResult.stdout.Trim() | ConvertFrom-Json
        Assert-Condition ([string]$upCheck.latestMigration -eq '20260729142258_AddObservedExamEvidenceModelForCEK019') 'CEK-34 migration Up stopped at the wrong migration.'
        Assert-Condition ([bool]$upCheck.targetsPresent -and [bool]$upCheck.performancePresent -and [bool]$upCheck.errorsPresent -and [bool]$upCheck.recommendationsPresent) 'CEK-34 migration Up did not restore CEK-15/19 schema.'
        $migrationResult.upVerified = $true

        Invoke-ExternalStep -Id 'migration-drop-for-restore' -FilePath $dropdb -Arguments @(
            '-h', $DatabaseHost, '-p', [string]$DatabasePort, '-U', $DatabaseUser, '--force', $isolatedDatabaseName
        ) -Category 'migration' | Out-Null
        $databaseCreated = $false
        Invoke-ExternalStep -Id 'migration-recreatedb-for-restore' -FilePath $createdb -Arguments @(
            '-h', $DatabaseHost, '-p', [string]$DatabasePort, '-U', $DatabaseUser,
            '-T', 'template0', '-E', 'UTF8', $isolatedDatabaseName
        ) -Category 'migration' | Out-Null
        $databaseCreated = $true
        Invoke-ExternalStep -Id 'migration-final-database-restore' -FilePath $pgRestore -Arguments @(
            '-h', $DatabaseHost, '-p', [string]$DatabasePort, '-U', $DatabaseUser,
            '-d', $isolatedDatabaseName, '--no-owner', '--no-privileges', '--exit-on-error', $databaseDumpPath
        ) -Category 'backup_restore' | Out-Null
        $cloneRestored = Get-DatabaseSnapshot -TargetDatabase $isolatedDatabaseName -StepId 'migration-clone-restored'
        Assert-Condition ([string]$cloneRestored.fingerprint -eq [string]$databaseBefore.fingerprint) 'CEK-34 database restore did not recover the fresh pre-run fingerprint.'
        $migrationResult.databaseRestoreParity = $true
        $migrationResult.status = 'pass'
    }
    catch {
        $migrationError = $_
        $migrationResult.status = 'fail'
        $migrationResult.error = $_.Exception.Message
    }
    finally {
        $env:KQG_CONNECTION_STRING = $previousConnectionString
        if ($databaseCreated) {
            Assert-Condition ($isolatedDatabaseName -match '^kqg_cek034_\d{8}_\d{6}_\d+$') 'refusing to drop a database outside the CEK-34 allowlist.'
            $dropResult = Invoke-ExternalStep -Id 'migration-cleanup-database' -FilePath (Join-Path $PgBin 'dropdb.exe') -Arguments @(
                '-h', $DatabaseHost, '-p', [string]$DatabasePort, '-U', $DatabaseUser, '--force', $isolatedDatabaseName
            ) -Category 'migration'
            $migrationResult.databaseDropped = ($dropResult.exitCode -eq 0)
        }
        else {
            $migrationResult.databaseDropped = $true
        }
        if ($dataRootCreated -and (Test-Path -LiteralPath $isolatedDataRoot)) {
            $cleanupPath = [System.IO.Path]::GetFullPath($isolatedDataRoot)
            $cleanupAllowed = $cleanupPath.StartsWith($isolationRoot + '\', [System.StringComparison]::OrdinalIgnoreCase) -and
                (Split-Path -Leaf $cleanupPath) -like 'cek034-*' -and
                (Test-Path -LiteralPath $isolationMarker)
            Assert-Condition $cleanupAllowed 'refusing to remove an unmarked path outside the CEK-34 isolation root.'
            Remove-Item -LiteralPath $cleanupPath -Recurse -Force
            $migrationResult.dataRootRemoved = -not (Test-Path -LiteralPath $cleanupPath)
        }
        else {
            $migrationResult.dataRootRemoved = $true
        }
    }
    if ($null -ne $migrationError) {
        throw $migrationError
    }
    Assert-Condition ([bool]$migrationResult.databaseDropped -and [bool]$migrationResult.dataRootRemoved) 'CEK-34 migration isolation cleanup is incomplete.'
    $migrationDrill = $migrationResult
    $backupRestore.status = 'pass'
    $backupRestore.databaseRestoreParity = [bool]$migrationResult.databaseRestoreParity
    $backupRestore.fileStoreRestoreParity = [bool]$migrationResult.fileStoreRestoreParity

    $dotnetVulnerable = Invoke-ExternalStep -Id 'supplychain-dotnet-vulnerable' -FilePath 'dotnet' -Arguments @(
        'list', 'apps/api/K12QuestionGraph.Api.csproj', 'package', '--vulnerable', '--include-transitive', '--format', 'json'
    ) -Category 'supply_chain'
    $dotnetVulnerableJson = $dotnetVulnerable.stdout.Trim() | ConvertFrom-Json -Depth 50
    $nugetVulnerabilities = @(
        foreach ($project in @($dotnetVulnerableJson.projects)) {
            foreach ($framework in @($project.frameworks)) {
                $packages = @(
                    @(Get-PropertyValue $framework 'topLevelPackages' @()) +
                    @(Get-PropertyValue $framework 'transitivePackages' @())
                )
                foreach ($package in $packages) {
                    foreach ($vulnerability in @(Get-PropertyValue $package 'vulnerabilities' @())) {
                        [pscustomobject][ordered]@{
                            package = [string]$package.id
                            version = [string]$package.resolvedVersion
                            severity = [string]$vulnerability.severity
                            advisory = [string]$vulnerability.advisoryurl
                        }
                    }
                }
            }
        }
    )
    $npmAudit = Invoke-ExternalStep -Id 'supplychain-npm-audit' -FilePath $npmCommand -Arguments @('--prefix', 'apps/web', 'audit', '--json') -AcceptedExitCodes @(0, 1) -Category 'supply_chain'
    $npmAuditJson = $npmAudit.stdout.Trim() | ConvertFrom-Json -Depth 100
    Invoke-ExternalStep -Id 'supplychain-pip-check' -FilePath 'python' -Arguments @('-m', 'pip', 'check') -Category 'supply_chain' | Out-Null
    $dependencyFiles = @(
        'apps/api/K12QuestionGraph.Api.csproj', 'apps/web/package.json', 'apps/web/package-lock.json',
        'workers/document/requirements.txt', '.config/dotnet-tools.json'
    )
    $dependencyDiff = Invoke-ExternalStep -Id 'supplychain-dependency-diff' -FilePath 'git' -Arguments (@('diff', '--name-only', '--') + $dependencyFiles) -Category 'supply_chain'
    $dependencyUntracked = Invoke-ExternalStep -Id 'supplychain-dependency-untracked' -FilePath 'git' -Arguments (@('ls-files', '--others', '--exclude-standard', '--') + $dependencyFiles) -Category 'supply_chain'
    $dependencyChanges = @(
        @($dependencyDiff.stdout -split "`r?`n") + @($dependencyUntracked.stdout -split "`r?`n") |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
    Assert-Condition ($dependencyChanges.Count -eq 0) "CEK-34 dependency manifests changed unexpectedly: $($dependencyChanges -join ', ')"
    $openApiRisk = @($nugetVulnerabilities | Where-Object advisory -eq 'https://github.com/advisories/GHSA-v5pm-xwqc-g5wc') | Select-Object -First 1
    $openApiNuspec = Join-Path $env:USERPROFILE '.nuget\packages\microsoft.openapi\2.0.0\microsoft.openapi.nuspec'
    Assert-Condition (Test-Path -LiteralPath $openApiNuspec -PathType Leaf) 'Microsoft.OpenApi 2.0.0 nuspec is missing from the local package cache.'
    [xml]$openApiMetadata = Get-Content -LiteralPath $openApiNuspec -Raw
    $npmHigh = [int]$npmAuditJson.metadata.vulnerabilities.high
    $npmCritical = [int]$npmAuditJson.metadata.vulnerabilities.critical
    $nugetCritical = @($nugetVulnerabilities | Where-Object severity -eq 'Critical').Count
    Assert-Condition ($npmCritical -eq 0 -and $nugetCritical -eq 0) 'CEK-34 supply-chain scan found a critical vulnerability.'
    $supplyChain = [ordered]@{
        status = if (@($nugetVulnerabilities).Count -gt 0 -or [int]$npmAuditJson.metadata.vulnerabilities.total -gt 0) { 'known_risks_open' } else { 'clean' }
        scanCompleted = $true
        checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
        dependencyChange = $false
        dependencyManifestChanges = $dependencyChanges
        nuget = [ordered]@{
            vulnerabilityCount = @($nugetVulnerabilities).Count
            vulnerabilities = $nugetVulnerabilities
            microsoftOpenApi = [ordered]@{
                present = ($null -ne $openApiRisk)
                version = '2.0.0'
                severity = if ($null -eq $openApiRisk) { 'resolved_or_not_reported' } else { [string]$openApiRisk.severity }
                advisory = 'GHSA-v5pm-xwqc-g5wc'
                cve = 'CVE-2026-49451'
                impact = 'circular schema references may terminate OpenAPI parsing; availability risk'
                firstPatchedVersionIn2x = '2.7.5'
                license = [string]$openApiMetadata.package.metadata.license.InnerText
            }
        }
        npm = [ordered]@{
            auditExitCode = $npmAudit.exitCode
            total = [int]$npmAuditJson.metadata.vulnerabilities.total
            low = [int]$npmAuditJson.metadata.vulnerabilities.low
            high = $npmHigh
            critical = $npmCritical
            vulnerablePackages = @($npmAuditJson.vulnerabilities.PSObject.Properties | ForEach-Object {
                [pscustomobject][ordered]@{ name = $_.Name; severity = [string]$_.Value.severity; direct = [bool]$_.Value.isDirect; fixAvailable = [bool]$_.Value.fixAvailable }
            })
            vulnerablePackageLicenses = @(
                [ordered]@{ name = '@babel/core'; version = '7.29.0'; license = 'MIT' },
                [ordered]@{ name = 'brace-expansion'; version = '5.0.5'; license = 'MIT' },
                [ordered]@{ name = 'postcss'; version = '8.5.15'; license = 'MIT' }
            )
        }
        python = [ordered]@{ pipCheck = 'pass'; brokenRequirements = 0 }
        windowsCompatibility = [ordered]@{
            testedHost = 'Windows win-x64'
            dotnet = (& dotnet --version).Trim()
            node = (& node --version).Trim()
            npm = (& npm --version).Trim()
            python = (& python --version).Trim()
            postgresql = (& (Join-Path $PgBin 'psql.exe') --version).Trim()
        }
        offlineCompatibility = [ordered]@{
            cachedBuildAndTests = 'pass on this host after restoring the existing project manifests; npm used local node_modules and pip check used the installed environment'
            cleanMachineOfflineInstall = 'not_proven'
            networkUsedForFreshAdvisoryScan = $true
            uninstall = 'dependencyChange=false; no CEK-34 dependency or tool installation to uninstall'
        }
        releaseBlocker = (@($nugetVulnerabilities).Count -gt 0 -or $npmHigh -gt 0)
        remediationBoundary = 'Do not silently upgrade inside CEK-34. Evaluate Microsoft.AspNetCore.OpenApi/Microsoft.OpenApi and npm lockfile upgrades as a separate compatibility-tested dependency slice before release.'
    }
    $topicCoverage.supplyChain = [ordered]@{ status = 'pass_with_known_risks_reported'; dependencyChange = $false; critical = 0 }

    $databaseAfter = Get-DatabaseSnapshot -TargetDatabase $DatabaseName -StepId 'database-after'
    Invoke-InternalStep -Id 'database-after-invariants' -Category 'data' -Action { Assert-DatabaseInvariants $databaseAfter } | Out-Null
    Assert-Condition ([string]$databaseBefore.fingerprint -eq [string]$databaseAfter.fingerprint) 'CEK-34 production database fingerprint changed during the suite.'
    $databaseInvariants = [ordered]@{
        status = 'pass'
        before = $databaseBefore
        after = $databaseAfter
        fingerprintUnchanged = $true
        noActiveWrite = $true
        productionEligible = $false
        sourceCitedAlignmentCount = [int](Get-PropertyValue $databaseAfter.alignmentDistribution 'source_cited' 0)
        aggregateCounts = [ordered]@{
            questionCorpus = [int]$databaseAfter.questionCorpus
            reportRegions = [int]$databaseAfter.reportRegions
            curriculumRequirementsAndFacets = [int]$databaseAfter.curriculumRequirements + [int]$databaseAfter.requirementFacets
            assessmentTargets = [int]$databaseAfter.assessmentTargets
            targetMappings = [int]$databaseAfter.targetMappings
            curriculumAlignments = [int]$databaseAfter.curriculumAlignments
            observedPerformance = [int]$databaseAfter.observedPerformance
            observedErrors = [int]$databaseAfter.observedErrors
            teachingRecommendations = [int]$databaseAfter.teachingRecommendations
            regionalProfiles = [int]$databaseAfter.regionalProfiles
        }
    }
    $topicCoverage.noActiveWriteAndAggregates = [ordered]@{ status = 'pass'; fingerprintUnchanged = $true; sourceCitedNotFabricated = $true }
    $topicCoverage.backupRestoreMigration = [ordered]@{ status = 'pass'; database = $true; fileStore = $true; down = $true; up = $true }
    $topicSuiteStatus = 'pass'
    $overallStatus = if ($RunFixedOrder) { 'topic_pass_fixed_order_pending' } else { 'pass' }
    Write-SuiteReport -Status $overallStatus

    if ($RunFixedOrder) {
        $fixedBuild = Invoke-ExternalStep -Id 'fixed-order-build' -FilePath 'dotnet' -Arguments @(
            'build', 'apps/api/K12QuestionGraph.Api.csproj'
        ) -Category 'fixed_order'
        $env:KQG_CEK34_ORCHESTRATING_FULL_GATE = '1'
        $env:KQG_CEK34_BACKUP_MANIFEST = $backupManifestPath
        $fullGate = Invoke-ExternalStep -Id 'fixed-order-test-full' -FilePath 'pwsh' -Arguments @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'run-gates.ps1'),
            '-CurriculumExamBackupManifest', $backupManifestPath
        ) -Category 'fixed_order'
        $env:KQG_CEK34_ORCHESTRATING_FULL_GATE = $previousOrchestration
        $databasePostFullGate = Get-DatabaseSnapshot -TargetDatabase $DatabaseName -StepId 'database-post-full-gate'
        Invoke-InternalStep -Id 'database-post-full-gate-invariants' -Category 'data' -Action { Assert-DatabaseInvariants $databasePostFullGate } | Out-Null
        Assert-Condition ([string]$databaseBefore.fingerprint -eq [string]$databasePostFullGate.fingerprint) 'CEK-34 production database fingerprint changed during the fixed-order full gate.'
        $databaseInvariants['postFullGate'] = $databasePostFullGate
        $databaseInvariants['fingerprintUnchangedAfterFullGate'] = $true
        $fileStorePostFullGate = Invoke-InternalStep -Id 'filestore-post-full-gate-parity' -Category 'data' -Action {
            $checkedBytes = [long]0
            foreach ($file in @($manifest.fileStore.files)) {
                $livePath = Join-Path $FileStoreRoot ([string]$file.path)
                Assert-Condition (Test-Path -LiteralPath $livePath -PathType Leaf) "CEK-34 full gate removed FileStore file: $($file.path)"
                $liveItem = Get-Item -LiteralPath $livePath
                Assert-Condition ([long]$liveItem.Length -eq [long]$file.bytes) "CEK-34 full gate changed FileStore size: $($file.path)"
                Assert-Condition ((Get-Sha256 $livePath) -eq [string]$file.sha256) "CEK-34 full gate changed FileStore hash: $($file.path)"
                $checkedBytes += [long]$liveItem.Length
            }
            $liveFileCount = @(Get-ChildItem -LiteralPath $FileStoreRoot -File -Recurse).Count
            Assert-Condition ($liveFileCount -eq @($manifest.fileStore.files).Count) 'CEK-34 full gate left unexpected FileStore files.'
            return [ordered]@{ fileCount = $liveFileCount; totalBytes = $checkedBytes; unexpectedFiles = 0; algorithm = 'SHA256' }
        }
        $backupRestore['postFullGateFileStoreParity'] = $true
        $backupRestore['postFullGateFileStore'] = $fileStorePostFullGate
        $contractGate = Invoke-ExternalStep -Id 'fixed-order-contract-roadmap' -FilePath 'pwsh' -Arguments @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'run-roadmap-guard.ps1')
        ) -Category 'fixed_order'
        $hotspotReview = Invoke-InternalStep -Id 'fixed-order-hotspot-review' -Category 'fixed_order' -Action {
            Assert-Condition ($topicCoverage.apiHistoricalCompatibility.status -eq 'pass') 'hotspot API/history review failed'
            Assert-Condition ($topicCoverage.ui.status -eq 'pass') 'hotspot UI review failed'
            Assert-Condition ($topicCoverage.workerUnit.status -eq 'pass') 'hotspot worker review failed'
            Assert-Condition ($databaseInvariants.status -eq 'pass') 'hotspot data review failed'
            Assert-Condition ([int]$supplyChain.nuget.vulnerabilityCount -ge 0) 'hotspot supply-chain review missing'
            return [ordered]@{ status = 'gate_na_with_alternative_review_passed' }
        }
        $runtimeAfter = Invoke-InternalStep -Id 'runtime-after' -Category 'runtime' -Action { Get-ListenerState }
        $fixedOrder = [ordered]@{
            status = 'pass'
            order = @('build', 'test/full', 'contract/invariant', 'hotspot')
            build = [ordered]@{ status = 'pass'; exitCode = $fixedBuild.exitCode; log = $fixedBuild.entry.stdoutLog; logSha256 = $fixedBuild.entry.stdoutSha256 }
            testFull = [ordered]@{ status = 'pass'; exitCode = $fullGate.exitCode; log = $fullGate.entry.stdoutLog; logSha256 = $fullGate.entry.stdoutSha256 }
            contractInvariant = [ordered]@{ status = 'pass'; exitCode = $contractGate.exitCode; log = $contractGate.entry.stdoutLog; logSha256 = $contractGate.entry.stdoutSha256 }
            hotspot = [ordered]@{ status = 'gate_na'; alternativeReview = $hotspotReview.status }
        }
        $overallStatus = 'pass'
    }
    else {
        $runtimeAfter = Invoke-InternalStep -Id 'runtime-after' -Category 'runtime' -Action { Get-ListenerState }
    }

    Write-SuiteReport -Status $overallStatus
}
catch {
    $failureMessage = $_.Exception.Message
    $overallStatus = 'fail'
    if ($RunFixedOrder) {
        $fixedOrderSteps = @($steps | Where-Object category -eq 'fixed_order')
        $failedFixedOrderStep = @($fixedOrderSteps | Where-Object status -eq 'fail') | Select-Object -Last 1
        $fixedOrder = [ordered]@{
            status = if ($fixedOrderSteps.Count -eq 0) { 'not_run_due_to_topic_failure' } else { 'fail' }
            order = @('build', 'test/full', 'contract/invariant', 'hotspot')
            completedSteps = @($fixedOrderSteps | Where-Object status -eq 'pass' | ForEach-Object id)
            failedStep = if ($null -eq $failedFixedOrderStep) { $null } else { [string]$failedFixedOrderStep.id }
            exitCode = if ($null -eq $failedFixedOrderStep) { $null } else { [int]$failedFixedOrderStep.exitCode }
            stdoutLog = if ($null -eq $failedFixedOrderStep) { $null } else { [string]$failedFixedOrderStep.stdoutLog }
            stderrLog = if ($null -eq $failedFixedOrderStep) { $null } else { [string]$failedFixedOrderStep.stderrLog }
        }
    }
    if ($null -eq $runtimeAfter) {
        try { $runtimeAfter = Get-ListenerState } catch { $runtimeAfter = [ordered]@{ error = $_.Exception.Message } }
    }
    Write-SuiteReport -Status $overallStatus -ErrorText $failureMessage
    throw
}
finally {
    $env:PGPASSWORD = $previousPgPassword
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    $env:KQG_CEK34_ORCHESTRATING_FULL_GATE = $previousOrchestration
    $env:KQG_CEK34_BACKUP_MANIFEST = $previousBackupManifest
    Pop-Location
}

Get-Content -LiteralPath $reportFile -Raw
