param(
    [Parameter(Mandatory)] [string] $BackupManifest,
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres',
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 5289,
    [ValidateSet('Debug', 'Release', 'Cek025')] [string] $Configuration = 'Debug',
    [string] $ReportPath = 'docs\evidence\cek025-curriculum-evidence-review-api.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'
$profileImportKey = 'cek023_regional_exam_profile_candidate_v1'
$questionWorkflowKey = 'guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1'

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Write-Json([object] $Value, [string] $Path) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 50) + "`n"), [Text.UTF8Encoding]::new($false))
}

function Invoke-PsqlJson([string] $Sql) {
    $raw = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $Sql
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-25 database query failed'
    $jsonLine = @($raw | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1)
    Assert-True ($jsonLine.Count -eq 1) 'CEK-25 database query did not return one JSON object'
    return ($jsonLine[0] | ConvertFrom-Json)
}

function Get-DatabaseState {
    $sql = @"
select json_build_object(
  'activeAssets', (select count(*) from domain_asset_versions where status='active'),
  'activeExamPointId', (select id from domain_asset_versions where status='active' and asset_type='exam_point' order by id limit 1),
  'activeFingerprint', (select md5(string_agg(to_jsonb(a)::text, E'\n' order by id)) from domain_asset_versions a where status='active'),
  'profiles', (select count(*) from domain_asset_versions where source_evidence->>'importKey'='$profileImportKey'),
  'profileFingerprint', (select md5(string_agg(to_jsonb(a)::text, E'\n' order by id)) from domain_asset_versions a where source_evidence->>'importKey'='$profileImportKey'),
  'questions', (select count(*) from question_items where custom_fields->>'sourceWorkflowKey'='$questionWorkflowKey'),
  'questionFingerprint', (select md5(string_agg(to_jsonb(q)::text, E'\n' order by id)) from question_items q where custom_fields->>'sourceWorkflowKey'='$questionWorkflowKey'),
  'targetFingerprint', (select md5(string_agg(to_jsonb(t)::text, E'\n' order by id)) from assessment_targets t),
  'alignmentFingerprint', (select md5(string_agg(to_jsonb(a)::text, E'\n' order by id)) from curriculum_alignments a),
  'mappingFingerprint', (select md5(string_agg(to_jsonb(m)::text, E'\n' order by id)) from domain_asset_mappings m),
  'decisionAudits', (select count(*) from review_queue_items where review_type='curriculum_evidence_decision')
);
"@
    return Invoke-PsqlJson $sql
}

function Invoke-ApiPost([string] $Path, [object] $Body) {
    return Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$ApiPort$Path" `
        -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Depth 20 -Compress) -TimeoutSec 20
}

function Undo-Decision([object] $Decision, [string] $Reason) {
    $undo = Invoke-ApiPost "/knowledge-evidence/reviews/decisions/$($Decision.decisionId)/undo" ([ordered]@{
        reviewer = 'cek025-smoke-admin'
        reason = $Reason
        actorRole = 'administrator'
    })
    Assert-True (-not $undo.activeApply) 'CEK-25 undo unexpectedly allowed active apply'
    Assert-True (-not $undo.productionEligible) 'CEK-25 undo unexpectedly became production eligible'
    Assert-True (-not $undo.audit.undo.allowed) 'CEK-25 undo audit did not close the undo token'
    return $undo
}

. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword $DatabasePassword
Assert-True (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'database password required'
Assert-True (Test-Path -LiteralPath $BackupManifest -PathType Leaf) 'backup manifest missing'
Assert-True (Test-Path -LiteralPath $psql -PathType Leaf) 'psql missing'
$existingListener = Get-NetTCPConnection -State Listen -LocalPort $ApiPort -ErrorAction SilentlyContinue
Assert-True ($null -eq $existingListener) "CEK-25 API port already in use: $ApiPort"

$env:PGPASSWORD = $DatabasePassword
$report = [IO.Path]::GetFullPath((Join-Path $repoRoot $ReportPath))
$tmpRoot = Join-Path $repoRoot 'tmp\cek025'
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$apiProcess = $null
$oldConnection = $env:ConnectionStrings__KqgDatabase
$oldEnvironment = $env:ASPNETCORE_ENVIRONMENT

Push-Location $repoRoot
try {
    $backup = pwsh -NoProfile -ExecutionPolicy Bypass -File tools\verify-backup.ps1 -ManifestPath $BackupManifest | ConvertFrom-Json
    Assert-True ($backup.status -eq 'ok') 'CEK-25 backup verification failed'

    dotnet build apps/api/K12QuestionGraph.Api.csproj --configuration $Configuration --no-restore | Write-Host
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-25 API build failed'
    dotnet test tests/api/K12QuestionGraph.Api.Tests/K12QuestionGraph.Api.Tests.csproj `
        --configuration $Configuration --filter CurriculumEvidenceReview --no-restore | Write-Host
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-25 API tests failed'

    $env:ConnectionStrings__KqgDatabase = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
    $env:ASPNETCORE_ENVIRONMENT = 'Development'
    $outLog = Join-Path $tmpRoot 'api.out.log'
    $errLog = Join-Path $tmpRoot 'api.err.log'
    $apiProcess = Start-Process -FilePath 'dotnet' -ArgumentList @(
        'run', '--no-build', '--configuration', $Configuration,
        '--project', 'apps/api/K12QuestionGraph.Api.csproj', '--urls', "http://127.0.0.1:$ApiPort"
    ) -PassThru -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        if ($apiProcess.HasExited) { break }
        try {
            $probe = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/health/ready" -TimeoutSec 2
            if ($probe.status -eq 'ok') { $ready = $true; break }
        }
        catch { Start-Sleep -Milliseconds 250 }
    }
    Assert-True $ready 'CEK-25 API did not become ready'

    $interrupted = Invoke-PsqlJson @"
select json_build_object(
  'ids', coalesce(json_agg(id order by created_at), '[]'::json)
)
from review_queue_items
where review_type='curriculum_evidence_decision'
  and status='resolved'
  and payload->>'reviewer'='cek025-smoke-teacher'
  and payload->'undo'->>'allowed'='true';
"@
    $recoveredDecisionIds = @()
    foreach ($interruptedId in @($interrupted.ids)) {
        $recovered = Invoke-ApiPost "/knowledge-evidence/reviews/decisions/$interruptedId/undo" ([ordered]@{
            reviewer = 'cek025-recovery-admin'
            reason = 'Restore an interrupted CEK-25 smoke decision from its before snapshot.'
            actorRole = 'administrator'
        })
        Assert-True (-not $recovered.audit.undo.allowed) 'CEK-25 interrupted decision recovery did not close undo'
        $recoveredDecisionIds += [string]$interruptedId
    }

    $before = Get-DatabaseState
    Assert-True ($before.activeAssets -eq 452) 'CEK-25 active asset baseline is not 452'
    Assert-True ($before.profiles -eq 24) 'CEK-25 regional profile baseline is not 24'
    Assert-True ($before.questions -eq 234) 'CEK-25 Guangzhou question baseline is not 234'

    $page = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/reviews?page=1&pageSize=10" -TimeoutSec 20
    Assert-True ($page.page -eq 1 -and $page.pageSize -eq 10) 'CEK-25 pagination contract mismatch'
    Assert-True ($page.totalCount -eq 968 -and $page.totalPages -gt 1) 'CEK-25 review total does not include every CEK-09 requirement candidate'
    Assert-True ($page.sort -eq 'impact_desc,confidence_asc,stable_key_asc') 'CEK-25 default sort contract mismatch'
    Assert-True (@($page.items | Where-Object { $_.impactLevel -ne 'high' }).Count -eq 0) 'CEK-25 high-impact items were not first'
    Assert-True (-not $page.productionEligible) 'CEK-25 list unexpectedly became production eligible'

    $complex = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/reviews?groupId=complex_mappings&page=1&pageSize=500" -TimeoutSec 20
    $requirements = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/reviews?groupId=curriculum_requirements&page=1&pageSize=500" -TimeoutSec 20
    $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/reviews?groupId=assessment_targets&page=1&pageSize=500" -TimeoutSec 20
    $profiles = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/reviews?groupId=regional_profiles&page=1&pageSize=500" -TimeoutSec 20
    $errorPatterns = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/reviews?groupId=error_patterns&page=1&pageSize=500" -TimeoutSec 20
    Assert-True ($complex.totalCount -eq 92) 'CEK-25 complex mapping review group does not match CEK-24'
    Assert-True ($requirements.totalCount -eq 273) 'CEK-25 curriculum requirement review group does not match CEK-24'
    Assert-True ($targets.totalCount -eq 444 -and $targets.items.Count -eq 444) 'CEK-25 assessment target review group is incomplete'
    Assert-True ($profiles.totalCount -eq 24) 'CEK-25 regional profile review group does not match CEK-24'
    Assert-True ($errorPatterns.totalCount -eq 0) 'CEK-25 fabricated error-pattern review candidates'

    $targetsWithPrimaryKnowledge = @($targets.items | Where-Object { @($_.summary.primaryKnowledge).Count -gt 0 })
    $targetsWithEstimatedDifficulty = @($targets.items | Where-Object { $null -ne $_.summary.estimatedDifficulty })
    $observedDifficultyEntries = @($targets.items | ForEach-Object { @($_.summary.observedDifficulty) })
    $observedDifficultyWithSourceRegion = @($observedDifficultyEntries | Where-Object {
        $null -ne $_.value -and -not [string]::IsNullOrWhiteSpace([string]$_.sourceRegionId)
    })
    Assert-True ($targetsWithPrimaryKnowledge.Count -gt 0) 'CEK-25 target summaries contain no primary knowledge'
    Assert-True ($targetsWithEstimatedDifficulty.Count -gt 0) 'CEK-25 target summaries contain no estimated question difficulty'
    Assert-True ($observedDifficultyWithSourceRegion.Count -gt 0) 'CEK-25 target summaries contain no source-anchored observed difficulty'

    $readinessBefore = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/reviews/readiness" -TimeoutSec 20
    Assert-True ($readinessBefore.errorPatternStatus -eq 'blocked_no_persisted_candidates') 'CEK-25 error-pattern readiness did not fail closed'
    Assert-True (-not $readinessBefore.reviewComplete) 'CEK-25 readiness incorrectly reported complete'
    Assert-True (-not $readinessBefore.activeApplyAllowed) 'CEK-25 readiness incorrectly allowed active apply'

    $target = $targets.items[0]
    $decisionBodies = @(
        [ordered]@{ decision = 'approve'; reason = 'Smoke approval with sufficient target evidence.' },
        [ordered]@{ decision = 'return'; reason = 'Smoke return to verify rejected candidate state.' },
        [ordered]@{ decision = 'keep_pending'; reason = 'Smoke hold for additional teacher evidence.' }
    )
    $decisionEvidence = @()
    foreach ($case in $decisionBodies) {
        $decision = Invoke-ApiPost '/knowledge-evidence/reviews/decisions' ([ordered]@{
            candidateType = $target.candidateType
            candidateId = $target.candidateId
            decision = $case.decision
            reviewer = 'cek025-smoke-teacher'
            reason = $case.reason
            actorRole = 'teacher'
        })
        Assert-True (-not $decision.activeApply) "CEK-25 $($case.decision) unexpectedly allowed active apply"
        Assert-True (-not $decision.productionEligible) "CEK-25 $($case.decision) unexpectedly became production eligible"
        Assert-True ($decision.audit.reviewer -eq 'cek025-smoke-teacher') 'CEK-25 reviewer audit missing'
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$decision.audit.reason)) 'CEK-25 reason audit missing'
        Assert-True ($null -ne $decision.audit.before -and $null -ne $decision.audit.after -and $null -ne $decision.audit.evidence) 'CEK-25 before/after/evidence audit missing'
        $undo = Undo-Decision $decision "Undo $($case.decision) smoke decision."
        $decisionEvidence += [ordered]@{ decision = $case.decision; decisionId = $decision.decisionId; undoClosed = (-not $undo.audit.undo.allowed) }
    }

    $staleFirst = Invoke-ApiPost '/knowledge-evidence/reviews/decisions' ([ordered]@{
        candidateType = $target.candidateType
        candidateId = $target.candidateId
        decision = 'approve'
        reviewer = 'cek025-smoke-teacher'
        reason = 'First decision for stale undo concurrency proof.'
        actorRole = 'teacher'
    })
    $staleSecond = Invoke-ApiPost '/knowledge-evidence/reviews/decisions' ([ordered]@{
        candidateType = $target.candidateType
        candidateId = $target.candidateId
        decision = 'return'
        reviewer = 'cek025-smoke-teacher'
        reason = 'Second decision must supersede the first undo snapshot.'
        actorRole = 'teacher'
    })
    $staleUndoBody = [ordered]@{
        reviewer = 'cek025-smoke-admin'
        reason = 'Stale undo must not overwrite the newer decision.'
        actorRole = 'administrator'
    } | ConvertTo-Json -Compress
    $staleUndo = Invoke-WebRequest -Method Post `
        -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/reviews/decisions/$($staleFirst.decisionId)/undo" `
        -ContentType 'application/json' -Body $staleUndoBody -SkipHttpErrorCheck -TimeoutSec 20
    Assert-True ($staleUndo.StatusCode -eq 409) 'CEK-25 stale undo was not rejected'
    $staleSecondUndo = Undo-Decision $staleSecond 'Undo the newer decision before restoring the original baseline.'
    $staleFirstUndo = Undo-Decision $staleFirst 'Undo the original decision after its after-snapshot is current again.'

    $lowRisk = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/reviews?groupId=low_risk_mappings&page=1&pageSize=1" -TimeoutSec 20
    Assert-True ($lowRisk.items.Count -eq 1 -and $lowRisk.items[0].batchApprovalEligible) 'CEK-25 batch-approval fixture missing or unsafe'
    $batch = Invoke-ApiPost '/knowledge-evidence/reviews/batch-approve' ([ordered]@{
        items = @([ordered]@{ candidateType = $lowRisk.items[0].candidateType; candidateId = $lowRisk.items[0].candidateId })
        reviewer = 'cek025-smoke-teacher'
        reason = 'High-confidence low-risk reversible one-to-one mapping.'
        actorRole = 'teacher'
    })
    Assert-True ($batch.approvedCount -eq 1 -and -not $batch.activeApply) 'CEK-25 batch approval response mismatch'
    $batchUndo = Undo-Decision $batch.decisions[0] 'Undo batch approval smoke decision.'

    $mapping = $lowRisk.items[0]
    $change = Invoke-ApiPost '/knowledge-evidence/reviews/decisions' ([ordered]@{
        candidateType = $mapping.candidateType
        candidateId = $mapping.candidateId
        decision = 'change_mapping'
        reviewer = 'cek025-smoke-teacher'
        reason = 'Exercise governed mapping revision while keeping the candidate pending.'
        actorRole = 'teacher'
        replacementAssetVersionId = $mapping.summary.targetAssetVersionId
    })
    Assert-True ($change.reviewStatus -eq 'pending_review') 'CEK-25 changed mapping did not remain pending review'
    $changeUndo = Undo-Decision $change 'Undo mapping revision smoke decision.'

    $invalidActiveBody = [ordered]@{
        candidateType = $target.candidateType
        candidateId = $target.candidateId
        decision = 'apply_active'
        reviewer = 'cek025-smoke-teacher'
        reason = 'This must be rejected.'
        actorRole = 'teacher'
    } | ConvertTo-Json -Compress
    $invalidActive = Invoke-WebRequest -Method Post -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/reviews/decisions" `
        -ContentType 'application/json' -Body $invalidActiveBody -SkipHttpErrorCheck -TimeoutSec 20
    Assert-True ($invalidActive.StatusCode -eq 400) 'CEK-25 ordinary teacher active-apply request was not rejected'

    $invalidTargetMappingBody = [ordered]@{
        candidateType = $target.candidateType
        candidateId = $target.candidateId
        decision = 'change_mapping'
        reviewer = 'cek025-smoke-teacher'
        reason = 'Mapping changes must be restricted to alignment candidates.'
        actorRole = 'teacher'
        replacementAssetVersionId = $mapping.summary.targetAssetVersionId
    } | ConvertTo-Json -Compress
    $invalidTargetMapping = Invoke-WebRequest -Method Post `
        -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/reviews/decisions" `
        -ContentType 'application/json' -Body $invalidTargetMappingBody -SkipHttpErrorCheck -TimeoutSec 20
    Assert-True ($invalidTargetMapping.StatusCode -eq 400) 'CEK-25 target candidate accepted change_mapping'

    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$before.activeExamPointId)) 'CEK-25 active exam-point fixture missing'
    $activeAssetBody = [ordered]@{
        candidateType = 'profile'
        candidateId = $before.activeExamPointId
        decision = 'approve'
        reviewer = 'cek025-smoke-teacher'
        reason = 'Direct active asset ID must not bypass the candidate review list.'
        actorRole = 'teacher'
    } | ConvertTo-Json -Compress
    $activeAssetDecision = Invoke-WebRequest -Method Post `
        -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/reviews/decisions" `
        -ContentType 'application/json' -Body $activeAssetBody -SkipHttpErrorCheck -TimeoutSec 20
    Assert-True ($activeAssetDecision.StatusCode -eq 404) 'CEK-25 active asset ID bypassed candidate eligibility'

    $activeReplacementBody = [ordered]@{
        candidateType = $mapping.candidateType
        candidateId = $mapping.candidateId
        decision = 'change_mapping'
        reviewer = 'cek025-smoke-teacher'
        reason = 'Direct mapping replacement must reject active or foreign assets.'
        actorRole = 'teacher'
        replacementAssetVersionId = $before.activeExamPointId
    } | ConvertTo-Json -Compress
    $activeReplacementDecision = Invoke-WebRequest -Method Post `
        -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/reviews/decisions" `
        -ContentType 'application/json' -Body $activeReplacementBody -SkipHttpErrorCheck -TimeoutSec 20
    Assert-True ($activeReplacementDecision.StatusCode -eq 404) 'CEK-25 active asset bypassed mapping replacement eligibility'

    $after = Get-DatabaseState
    Assert-True ($after.activeAssets -eq $before.activeAssets -and $after.activeFingerprint -eq $before.activeFingerprint) 'CEK-25 active C002 changed'
    Assert-True ($after.profiles -eq $before.profiles -and $after.profileFingerprint -eq $before.profileFingerprint) 'CEK-25 regional profiles changed'
    Assert-True ($after.questions -eq $before.questions -and $after.questionFingerprint -eq $before.questionFingerprint) 'CEK-25 historical questions changed'
    Assert-True ($after.targetFingerprint -eq $before.targetFingerprint) 'CEK-25 target undo did not restore the baseline'
    Assert-True ($after.alignmentFingerprint -eq $before.alignmentFingerprint) 'CEK-25 curriculum alignment baseline changed'
    Assert-True ($after.mappingFingerprint -eq $before.mappingFingerprint) 'CEK-25 domain mapping undo did not restore the baseline'
    Assert-True ($after.decisionAudits -eq ($before.decisionAudits + 7)) 'CEK-25 decision audit count mismatch'

    $readinessAfter = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/reviews/readiness" -TimeoutSec 20
    $evidence = [ordered]@{
        schemaVersion = 'cek025-curriculum-evidence-review-api.v1'
        status = 'pass'
        checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
        taskId = 'CEK-25'
        backup = [ordered]@{ manifest = $BackupManifest; verified = $true }
        api = [ordered]@{
            ready = $true
            configuration = $Configuration
            pagination = [ordered]@{ page = $page.page; pageSize = $page.pageSize; totalCount = $page.totalCount; sort = $page.sort }
            reviewGroups = [ordered]@{
                complexMappings = $complex.totalCount
                curriculumRequirements = $requirements.totalCount
                assessmentTargets = $targets.totalCount
                regionalProfiles = $profiles.totalCount
                errorPatterns = $errorPatterns.totalCount
            }
            targetEvidenceSummary = [ordered]@{
                primaryKnowledgeTargets = $targetsWithPrimaryKnowledge.Count
                estimatedDifficultyTargets = $targetsWithEstimatedDifficulty.Count
                sourceAnchoredObservedDifficultyEntries = $observedDifficultyWithSourceRegion.Count
            }
            decisions = $decisionEvidence
            batchApproval = [ordered]@{ approved = $batch.approvedCount; undoClosed = (-not $batchUndo.audit.undo.allowed) }
            mappingRevision = [ordered]@{ stayedPending = ($change.reviewStatus -eq 'pending_review'); undoClosed = (-not $changeUndo.audit.undo.allowed) }
            teacherActiveApplyRejected = $true
            targetMappingChangeRejected = $true
            activeAssetIdBypassRejected = $true
            activeReplacementBypassRejected = $true
            staleUndoRejected = $true
            staleUndoChainRestored = (-not $staleSecondUndo.audit.undo.allowed -and -not $staleFirstUndo.audit.undo.allowed)
        }
        readiness = [ordered]@{
            pendingCount = $readinessAfter.pendingCount
            approvedCount = $readinessAfter.approvedCount
            rejectedCount = $readinessAfter.rejectedCount
            reviewComplete = $readinessAfter.reviewComplete
            errorPatternStatus = $readinessAfter.errorPatternStatus
            activeApplyAllowed = $readinessAfter.activeApplyAllowed
        }
        compatibility = [ordered]@{
            activeAssetCount = $after.activeAssets
            activeFingerprintUnchanged = ($after.activeFingerprint -eq $before.activeFingerprint)
            profileCount = $after.profiles
            profileFingerprintUnchanged = ($after.profileFingerprint -eq $before.profileFingerprint)
            questionCount = $after.questions
            historicalQuestionFingerprintUnchanged = ($after.questionFingerprint -eq $before.questionFingerprint)
            targetAlignmentMappingRestored = $true
        }
        governance = [ordered]@{
            sameReviewQueue = $true
            decisionAuditCountAdded = 7
            productionEligible = $false
            activeWrite = $false
            errorPatternFailClosed = $true
            retrospectiveAlignmentTypePreserved = $true
        }
        rollback = [ordered]@{
            interruptedDecisionsRecovered = $recoveredDecisionIds
            decisionsUndone = 7
            baselineFingerprintsRestored = $true
            fallbackManifest = $BackupManifest
        }
        fullGate = [ordered]@{
            status = 'gate_na'
            reason = 'stateful Release requires current explicit authorization because it uses PostgreSQL and isolated backup/restore rehearsal'
            alternative_verification = 'CEK-25 backup verification, API build, targeted red-green tests, live decision/undo smoke, database fingerprint parity, roadmap/reference guards, and static hotspot audit'
            evidence_link = 'docs/evidence/cek025-curriculum-evidence-review-api.json'
            expires_at = 'CEK-34'
            recovery_condition = 'obtain current-task authorization and run tools/run-verification.ps1 -Profile Release -AuthorizeStateful at CEK-34'
        }
        identityBoundary = 'reviewer and actorRole are request audit fields in the current local API; authenticated identity and authorization are not proven by CEK-25.'
        completionBoundary = 'CEK-25 proves local candidate review, audit, batch admission, readiness, stale-undo rejection, and undo only. C002R migration/active switch, authenticated identity/authorization, CEK-20 persistence, teacher UI acceptance, and REAL005 remain open.'
    }
    Write-Json $evidence $report
    $evidence | ConvertTo-Json -Depth 50
}
finally {
    if ($null -ne $apiProcess -and -not $apiProcess.HasExited) {
        Stop-Process -Id $apiProcess.Id -Force
        $apiProcess.WaitForExit()
    }
    $env:ConnectionStrings__KqgDatabase = $oldConnection
    $env:ASPNETCORE_ENVIRONMENT = $oldEnvironment
    Pop-Location
}
