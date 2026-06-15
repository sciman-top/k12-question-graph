param(
    [string] $CriteriaPath = 'tasks/real-guangzhou-closure-criteria.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $DashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $DetailedSlicePlanPath = 'tasks/real005-detailed-slice-plan.csv',
    [string] $YearlyAdapterDiagnosticsPath = '',
    [string] $QuestionStructureDiagnosticsPath = '',
    [string] $JsonReportPath = '',
    [string] $MarkdownReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'

function Resolve-RepoPath([string] $Path) {
    Join-Path $repoRoot $Path
}

function Try-ReadJson([string] $RelativePath) {
    $fullPath = Resolve-RepoPath $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return $null
    }

    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Test-FileLockException([System.Exception] $Exception) {
    $current = $Exception
    while ($null -ne $current) {
        if ($current -is [System.IO.IOException]) {
            return $true
        }

        if (-not [string]::IsNullOrWhiteSpace($current.Message) -and $current.Message -match 'being used by another process') {
            return $true
        }

        $current = $current.InnerException
    }

    return $false
}

function Write-Utf8FileWithRetry([string] $Path, [object] $Content, [int] $RetryCount = 30, [int] $DelayMilliseconds = 100) {
    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
            return
        }
        catch {
            if ((-not (Test-FileLockException $_.Exception)) -or $attempt -eq $RetryCount) {
                throw
            }

            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }
}

function Split-Values([string] $Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    return @(
        $Value.Split(';') |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-ObjectPropertyValue([object] $Object, [string] $Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function New-Real005DetailedSliceCoverage {
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $PlanRows,
        [Parameter(Mandatory = $true)]
        [string] $ParentSliceId,
        [Parameter(Mandatory = $true)]
        [hashtable] $CriterionStatusLookup,
        [AllowEmptyCollection()]
        [Parameter(Mandatory = $true)]
        [string[]] $GlobalCriterionBlockers,
        [Parameter(Mandatory = $true)]
        [bool] $ParentReady
    )

    $parentRows = @($PlanRows | Where-Object { [string] $_.parent_slice -eq $ParentSliceId })
    $coverage = New-Object System.Collections.Specialized.OrderedDictionary
    $previousSlicesPassed = $ParentReady
    $currentActionableNext = $null

    foreach ($row in $parentRows) {
        $criterionIds = @(Split-Values ([string] $row.criterion_ids))
        $criterionStatus = [ordered]@{}
        $reportedStatuses = New-Object System.Collections.Generic.List[string]
        $criterionBlockers = New-Object System.Collections.Generic.List[string]

        foreach ($criterionId in $criterionIds) {
            $status = if ($CriterionStatusLookup.ContainsKey($criterionId)) { [string] $CriterionStatusLookup[$criterionId] } else { 'not_evaluated' }
            $criterionStatus[$criterionId] = $status
            $reportedStatuses.Add($status)
            foreach ($blocker in @($GlobalCriterionBlockers | Where-Object { $_ -like "${criterionId}:*" })) {
                if (-not $criterionBlockers.Contains($blocker)) {
                    $criterionBlockers.Add($blocker)
                }
            }
        }

        $reportedStatus = 'missing'
        if ($reportedStatuses.Count -gt 0) {
            if ($reportedStatuses -contains 'blocked') {
                $reportedStatus = 'blocked'
            }
            elseif ($reportedStatuses -contains 'partial') {
                $reportedStatus = 'partial'
            }
            elseif ($reportedStatuses -contains 'missing') {
                $reportedStatus = 'missing'
            }
            elseif ($reportedStatuses -contains 'not_evaluated') {
                $reportedStatus = 'not_evaluated'
            }
            elseif ((@($reportedStatuses | Select-Object -Unique).Count -eq 1) -and ($reportedStatuses[0] -eq 'pass')) {
                $reportedStatus = 'pass'
            }
            else {
                $reportedStatus = 'mixed'
            }
        }

        $readyToAdvance = $previousSlicesPassed
        $sliceBlockers = New-Object System.Collections.Generic.List[string]
        foreach ($blocker in $criterionBlockers) {
            $sliceBlockers.Add($blocker)
        }

        if ($reportedStatus -eq 'not_evaluated') {
            $sliceBlockers.Add("criteria_not_evaluated:$([string]::Join('+', $criterionIds))")
        }
        elseif ($reportedStatus -eq 'missing') {
            $sliceBlockers.Add("criteria_missing:$([string]::Join('+', $criterionIds))")
        }
        elseif ($reportedStatus -eq 'mixed') {
            $sliceBlockers.Add("criteria_mixed_status:$([string]::Join('+', $criterionIds))")
        }

        if (-not $readyToAdvance) {
            $dependencyId = [string] $row.depends_on
            if ([string]::IsNullOrWhiteSpace($dependencyId)) {
                $dependencyId = $ParentSliceId
            }
            $sliceBlockers.Insert(0, "waiting_for_dependency:$dependencyId")
        }

        $effectiveStatus = if ($readyToAdvance) { $reportedStatus } else { 'blocked_by_previous_slice' }
        if ($readyToAdvance -and ($effectiveStatus -ne 'pass') -and [string]::IsNullOrWhiteSpace($currentActionableNext)) {
            $currentActionableNext = [string] $row.id
        }

        $coverage.Add([string] $row.id, [ordered]@{
            parentSlice = $ParentSliceId
            criterionIds = $criterionIds
            criterionStatus = $criterionStatus
            reportedCriterionStatus = $reportedStatus
            status = $effectiveStatus
            readyToAdvance = $readyToAdvance
            dependsOn = [string] $row.depends_on
            blockers = @($sliceBlockers)
            focus = [string] $row.focus
            planStatus = [string] $row.status
            acceptance = [string] $row.acceptance
            verification = [string] $row.verification
            evidenceAnchor = [string] $row.evidence_anchor
            ownerRole = [string] $row.owner_role
        })

        if (-not ($readyToAdvance -and ($effectiveStatus -eq 'pass'))) {
            $previousSlicesPassed = $false
        }
    }

    $firstNonPass = @(
        $coverage.GetEnumerator() |
            Where-Object { [string] $_.Value.status -ne 'pass' } |
            Select-Object -First 1
    )
    $nextDetailedSlice = if (-not [string]::IsNullOrWhiteSpace($currentActionableNext)) {
        $currentActionableNext
    }
    elseif ($firstNonPass.Count -eq 1) {
        [string] $firstNonPass[0].Key
    }
    else {
        'none'
    }

    return [ordered]@{
        detailedSliceCoverage = $coverage
        nextDetailedSlice = $nextDetailedSlice
        nextDetailedSliceReady = (-not [string]::IsNullOrWhiteSpace($currentActionableNext))
        allPass = (@(
            $coverage.GetEnumerator() |
                Where-Object { [string] $_.Value.status -ne 'pass' }
        ).Count -eq 0)
    }
}

$criteriaFullPath = Resolve-RepoPath $CriteriaPath
$backlogFullPath = Resolve-RepoPath $BacklogPath
$dashboardFullPath = Resolve-RepoPath $DashboardPath
$detailedSlicePlanFullPath = Resolve-RepoPath $DetailedSlicePlanPath

if ([string]::IsNullOrWhiteSpace($JsonReportPath)) {
    $JsonReportPath = ('docs/evidence/{0}-real005-guangzhou-2015-2025-closure-standard-report.json' -f $runDate)
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-real005-guangzhou-2015-2025-closure-standard-report.md' -f $runDate)
}

$jsonFullPath = Resolve-RepoPath $JsonReportPath
$markdownFullPath = Resolve-RepoPath $MarkdownReportPath

foreach ($path in @($criteriaFullPath, $backlogFullPath, $dashboardFullPath, $detailedSlicePlanFullPath)) {
    Assert-True (Test-Path -LiteralPath $path) "required REAL005 input missing: $path"
}

$criteriaRows = @(Import-Csv -LiteralPath $criteriaFullPath -Encoding UTF8)
$backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
$dashboardRows = @(Import-Csv -LiteralPath $dashboardFullPath -Encoding UTF8)
$detailedSlicePlanRows = @(Import-Csv -LiteralPath $detailedSlicePlanFullPath -Encoding UTF8)

$requiredCriteriaColumns = @(
    'criterion_id',
    'category',
    'required_scope',
    'completion_requirement',
    'evidence_required',
    'blocking_gap_policy'
)

foreach ($column in $requiredCriteriaColumns) {
    Assert-True ($criteriaRows.Count -gt 0 -and $criteriaRows[0].PSObject.Properties.Name -contains $column) "criteria missing column: $column"
}

$criteriaById = @{}
foreach ($row in $criteriaRows) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($row.criterion_id)) 'criteria row has blank criterion_id'
    Assert-True (-not $criteriaById.ContainsKey($row.criterion_id)) "duplicate criterion_id: $($row.criterion_id)"
    $criteriaById[$row.criterion_id] = $row
    foreach ($column in $requiredCriteriaColumns) {
        Assert-True (-not [string]::IsNullOrWhiteSpace($row.$column)) "criterion $($row.criterion_id) missing $column"
    }
    Assert-True ($row.blocking_gap_policy -match 'not_closed') "criterion $($row.criterion_id) must fail closed to not_closed"
}

foreach ($id in @('RG001','RG002','RG003','RG004','RG005','RG006','RG007','RG008','RG009','RG010','RG011','RG012')) {
    Assert-True ($criteriaById.ContainsKey($id)) "required closure criterion missing: $id"
}

$backlogById = @{}
foreach ($row in $backlogRows) { $backlogById[$row.id] = $row }
foreach ($id in @('REAL001','REAL002','REAL003','REAL004','REAL005')) {
    Assert-True ($backlogById.ContainsKey($id)) "backlog missing $id"
}

$dashboardRow = $dashboardRows | Where-Object { $_.area_id -eq 'real-guangzhou-2015-2025' } | Select-Object -First 1
Assert-True ($null -ne $dashboardRow) 'completion dashboard missing real-guangzhou-2015-2025 row'
Assert-True ($dashboardRow.next_task -eq 'REAL005') 'real-guangzhou-2015-2025 dashboard row must point to REAL005'
Assert-True ($dashboardRow.current_state -ne 'teacher_validated' -and $dashboardRow.current_state -ne 'release_ready') '2015-2025 closure cannot be marked teacher_validated/release_ready before all REAL criteria pass'

$real001ReportPath = 'docs/evidence/20260512-guangzhou-2015-real-ingest-slice-report.json'
$real002ReportPath = 'docs/evidence/20260512-guangzhou-2015-visual-region-slice-report.json'
$real003ReportPath = 'docs/evidence/20260514-real003-guangzhou-physics-year-batch-ingest-report.json'

$real001Report = Try-ReadJson $real001ReportPath
$real002Report = Try-ReadJson $real002ReportPath
$real003Report = Try-ReadJson $real003ReportPath

function Test-AnswerLikeSource([object] $SourceHashRow) {
    $label = '{0} {1}' -f [string]$SourceHashRow.title, [string]$SourceHashRow.fileName
    return $label -match '答案|解析|含答案'
}

function Test-CombinedPaperAnswerSource([object] $SourceHashRow) {
    $label = '{0} {1}' -f [string]$SourceHashRow.title, [string]$SourceHashRow.fileName
    return $label -match '含答案|解析版'
}

$rg001YearCoverage = New-Object System.Collections.Generic.List[object]

if ($null -ne $real001Report -and $null -ne $real001Report.sourceDocuments) {
    $rg001YearCoverage.Add([ordered]@{
        year = 2015
        localExamSourceCount = 2
        hasDistinctPaperSource = $true
        hasDistinctAnswerSource = $true
        evidencePath = $real001ReportPath
        note = 'REAL001 sourceDocuments provide distinct paper and answer files for 2015.'
    })
}

if ($null -ne $real003Report) {
    foreach ($yearRow in @($real003Report.years)) {
        $localExamRows = @($yearRow.sourceHashes | Where-Object { [string]$_.sourceType -eq 'local_exam_paper' })
        $paperRows = @($localExamRows | Where-Object { (-not (Test-AnswerLikeSource $_)) -or (Test-CombinedPaperAnswerSource $_) })
        $answerRows = @($localExamRows | Where-Object { Test-AnswerLikeSource $_ })
        $rg001YearCoverage.Add([ordered]@{
            year = [int]$yearRow.year
            localExamSourceCount = $localExamRows.Count
            hasDistinctPaperSource = ($paperRows.Count -ge 1)
            hasDistinctAnswerSource = ($answerRows.Count -ge 1)
            evidencePath = $real003ReportPath
            note = if (($paperRows.Count -ge 1) -and ($answerRows.Count -ge 1)) {
                if (@($localExamRows | Where-Object { Test-CombinedPaperAnswerSource $_ }).Count -ge 1) {
                    'REAL003 sourceHashes include a combined paper+answer local_exam_paper anchor such as 含答案/解析版.'
                }
                else {
                    'REAL003 sourceHashes include distinct local_exam_paper paper+answer anchors.'
                }
            }
            else {
                'REAL003 sourceHashes do not yet prove distinct paper+answer local_exam_paper anchors.'
            }
        })
    }
}

$rg001BlockedYears = @(
    $rg001YearCoverage |
        Where-Object { (-not [bool]$_.hasDistinctPaperSource) -or (-not [bool]$_.hasDistinctAnswerSource) } |
        ForEach-Object { [int]$_.year }
)

$rg002YearCoverage = New-Object System.Collections.Generic.List[object]

if ([string]::IsNullOrWhiteSpace($YearlyAdapterDiagnosticsPath)) {
    $latestAdapterDiagnostics = @(
        Get-ChildItem -LiteralPath (Resolve-RepoPath 'docs/evidence') -Filter '*-real005-yearly-adapter-diagnostics.json' -File -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            Select-Object -First 1
    )
    if ($latestAdapterDiagnostics.Count -eq 1) {
        $YearlyAdapterDiagnosticsPath = [System.IO.Path]::GetRelativePath($repoRoot, $latestAdapterDiagnostics[0].FullName).Replace('\', '/')
    }
}

$yearlyAdapterDiagnostics = if ([string]::IsNullOrWhiteSpace($YearlyAdapterDiagnosticsPath)) { $null } else { Try-ReadJson $YearlyAdapterDiagnosticsPath }

if ($null -ne $yearlyAdapterDiagnostics -and [string]$yearlyAdapterDiagnostics.status -eq 'pass') {
    foreach ($yearRow in @($yearlyAdapterDiagnostics.years)) {
        $documents = @($yearRow.documents)
        $paperDocs = @($documents | Where-Object { @($_.roles) -contains 'paper' -and [string]$_.diagnosticStatus -eq 'pass' })
        $answerDocs = @($documents | Where-Object { @($_.roles) -contains 'answer' -and [string]$_.diagnosticStatus -eq 'pass' })
        $diagnostics = @($documents | ForEach-Object { @($_.adapterDiagnostics) })
        $hasRequiredFields = $diagnostics.Count -ge 1 -and (@($diagnostics | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.adapterName) -and
            -not [string]::IsNullOrWhiteSpace([string]$_.adapterVersion) -and
            -not [string]::IsNullOrWhiteSpace([string]$_.inputSha256) -and
            -not [string]::IsNullOrWhiteSpace([string]$_.outputSha256) -and
            $null -ne $_.warnings -and
            $null -ne $_.errors -and
            $null -ne $_.durationMs
        }).Count -eq $diagnostics.Count)
        $rg002YearCoverage.Add([ordered]@{
            year = [int]$yearRow.year
            hasAdapterNames = $diagnostics.Count -ge 1
            hasAdapterVersion = $hasRequiredFields
            hasInputOutputHashes = $hasRequiredFields
            hasWarningsErrorsElapsed = $hasRequiredFields
            hasPaperDiagnostic = ($paperDocs.Count -ge 1)
            hasAnswerDiagnostic = ($answerDocs.Count -ge 1)
            evidencePath = $YearlyAdapterDiagnosticsPath
            note = if ($hasRequiredFields -and $paperDocs.Count -ge 1 -and $answerDocs.Count -ge 1) {
                'REAL005 yearly adapter diagnostics include adapter name/version, input/output hashes, warnings/errors, and durationMs for paper and answer anchors.'
            }
            else {
                'REAL005 yearly adapter diagnostics are present but incomplete.'
            }
        })
    }
}
else {
    if ($null -ne $real001Report -and $null -ne $real002Report) {
        $rg002YearCoverage.Add([ordered]@{
            year = 2015
            hasAdapterNames = (-not [string]::IsNullOrWhiteSpace([string]$real001Report.worker.paperAdapter)) -and (-not [string]::IsNullOrWhiteSpace([string]$real001Report.worker.answerAdapter))
            hasAdapterVersion = $false
            hasInputOutputHashes = $true
            hasWarningsErrorsElapsed = $false
            hasPaperDiagnostic = $false
            hasAnswerDiagnostic = $false
            evidencePath = $real001ReportPath
            note = 'REAL001/REAL002 expose adapter names and input hashes, but not full per-year adapter diagnostics with version/warnings/errors/elapsed_ms.'
        })
    }

    if ($null -ne $real003Report) {
        foreach ($yearRow in @($real003Report.years)) {
            $rg002YearCoverage.Add([ordered]@{
                year = [int]$yearRow.year
                hasAdapterNames = $false
                hasAdapterVersion = $false
                hasInputOutputHashes = $false
                hasWarningsErrorsElapsed = $false
                hasPaperDiagnostic = $false
                hasAnswerDiagnostic = $false
                evidencePath = $real003ReportPath
                note = [string]$yearRow.adapterQuality.workerProbe
            })
        }
    }
}

$rg002BlockedYears = @(
    $rg002YearCoverage |
        Where-Object {
            (-not [bool]$_.hasAdapterNames) -or
            (-not [bool]$_.hasAdapterVersion) -or
            (-not [bool]$_.hasInputOutputHashes) -or
            (-not [bool]$_.hasWarningsErrorsElapsed) -or
            (-not [bool]$_.hasPaperDiagnostic) -or
            (-not [bool]$_.hasAnswerDiagnostic)
        } |
        ForEach-Object { [int]$_.year }
)

if ([string]::IsNullOrWhiteSpace($QuestionStructureDiagnosticsPath)) {
    $latestQuestionStructureDiagnostics = @(
        Get-ChildItem -LiteralPath (Resolve-RepoPath 'docs/evidence') -Filter '*-real005b-question-structure-diagnostics.json' -File -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            Select-Object -First 1
    )
    if ($latestQuestionStructureDiagnostics.Count -eq 1) {
        $QuestionStructureDiagnosticsPath = [System.IO.Path]::GetRelativePath($repoRoot, $latestQuestionStructureDiagnostics[0].FullName).Replace('\', '/')
    }
}

$questionStructureDiagnostics = if ([string]::IsNullOrWhiteSpace($QuestionStructureDiagnosticsPath)) { $null } else { Try-ReadJson $QuestionStructureDiagnosticsPath }

$knownEvidence = [ordered]@{
    REAL001 = @(
        'docs/evidence/20260512-guangzhou-2015-real-ingest-slice-report.json',
        'docs/evidence/20260512-guangzhou-2015-real-ingest-slice-dry-run-report.json'
    )
    REAL002 = @(
        'docs/evidence/20260512-guangzhou-2015-visual-region-slice-report.json'
    )
    REAL003 = @(
        'docs/evidence/20260514-real003-guangzhou-physics-year-batch-ingest-report.json'
    )
    REAL004 = @(
        'docs/evidence/20260512-real004-guangzhou-2015-review-smoke-report.json'
    )
}

$gaps = New-Object System.Collections.Generic.List[object]
foreach ($id in @('REAL002','REAL003','REAL004')) {
    if ($backlogById[$id].status -ne '已完成') {
        $gaps.Add([ordered]@{
            id = $id
            reason = "backlog status is $($backlogById[$id].status)"
            nextAction = $backlogById[$id].verification
        })
    }
}

foreach ($scriptPath in @(
    'tools/run-guangzhou-2015-visual-region-slice.ps1',
    'tools/run-guangzhou-physics-year-batch-ingest.ps1'
)) {
    if (-not (Test-Path -LiteralPath (Resolve-RepoPath $scriptPath))) {
        $gaps.Add([ordered]@{
            id = $scriptPath
            reason = 'required implementation gate script is missing'
            nextAction = 'implement script with dry-run default, evidence report, and rollback policy'
        })
    }
}

foreach ($item in $knownEvidence.GetEnumerator()) {
    foreach ($evidencePath in $item.Value) {
        if (-not (Test-Path -LiteralPath (Resolve-RepoPath $evidencePath))) {
            $gaps.Add([ordered]@{
                id = $evidencePath
                reason = "expected evidence for $($item.Key) is missing"
                nextAction = "rerun $($item.Key) guard"
            })
        }
    }
}

if ($dashboardRow.current_state -ne 'teacher_validated' -and $dashboardRow.current_state -ne 'release_ready') {
    $gaps.Add([ordered]@{
        id = 'real-guangzhou-2015-2025-dashboard'
        reason = "dashboard state is $($dashboardRow.current_state); gap=$($dashboardRow.blocking_gap)"
        nextAction = 'complete yearly question evidence and update dashboard only after every REAL005 criterion is satisfied'
    })
}

$closureStatus = if ($gaps.Count -eq 0 -and $backlogById['REAL005'].status -eq '已完成') { 'closed' } else { 'not_closed' }
$gapItems = @($gaps | ForEach-Object { $_ })
$criteriaItems = @($criteriaRows | ForEach-Object {
    [ordered]@{
        criterionId = $_.criterion_id
        category = $_.category
        requiredScope = $_.required_scope
        evidenceRequired = $_.evidence_required
        blockingGapPolicy = $_.blocking_gap_policy
    }
})
$unfinishedRealTasks = @('REAL002','REAL003','REAL004') | Where-Object { $backlogById[$_].status -ne '已完成' }
$unfinishedText = if ($unfinishedRealTasks.Count -gt 0) { $unfinishedRealTasks -join '/' } else { '逐年逐题闭环证据' }
$summaryChinese = if ($closureStatus -eq 'closed') {
    'REAL005 判定标准全部满足，才允许宣称 2015-2025 真卷全流程闭环。'
}
else {
    "REAL005 判定标准已安装并通过自检；当前真实状态是 not_closed，仍需完成 $unfinishedText。"
}

$rg001Status = if ($rg001YearCoverage.Count -eq 11 -and $rg001BlockedYears.Count -eq 0) { 'pass' } else { 'blocked' }
$rg002Status = if ($rg002YearCoverage.Count -eq 11 -and $rg002BlockedYears.Count -eq 0) { 'pass' } else { 'blocked' }
$rg001CoveredYears = @($rg001YearCoverage | ForEach-Object { [int]$_.year })
$rg002CoveredYears = @($rg002YearCoverage | ForEach-Object { [int]$_.year })
$rg001EvidencePaths = @($rg001YearCoverage | ForEach-Object { [string]$_.evidencePath } | Sort-Object -Unique)
$rg002EvidencePaths = @($rg002YearCoverage | ForEach-Object { [string]$_.evidencePath } | Sort-Object -Unique)

$criteriaCoverage = New-Object System.Collections.Specialized.OrderedDictionary
$rg001Coverage = @{}
$rg001Coverage['status'] = $rg001Status
$rg001Coverage['coveredYears'] = $rg001CoveredYears
$rg001Coverage['blockedYears'] = @($rg001BlockedYears)
$rg001Coverage['evidencePaths'] = $rg001EvidencePaths
$rg001Coverage['details'] = @($rg001YearCoverage | ForEach-Object { $_ })
$criteriaCoverage.Add('RG001', $rg001Coverage)

$rg002Coverage = @{}
$rg002Coverage['status'] = $rg002Status
$rg002Coverage['coveredYears'] = $rg002CoveredYears
$rg002Coverage['blockedYears'] = @($rg002BlockedYears)
$rg002Coverage['evidencePaths'] = $rg002EvidencePaths
$rg002Coverage['details'] = @($rg002YearCoverage | ForEach-Object { $_ })
$criteriaCoverage.Add('RG002', $rg002Coverage)

$real005ABlockers = New-Object System.Collections.Generic.List[string]
if ($rg001Status -ne 'pass') {
    $real005ABlockers.Add("RG001 source manifest coverage is still blocked for years: $($rg001BlockedYears -join ', ')")
}
if ($rg002Status -ne 'pass') {
    $real005ABlockers.Add("RG002 adapter diagnostics are incomplete for years: $($rg002BlockedYears -join ', ')")
}

$real005AStatus = if ($real005ABlockers.Count -eq 0) { 'pass' } else { 'blocked' }
$real005ANext = if ($real005ABlockers.Count -eq 0) { 'REAL005A evidence is ready for manual closeout review.' } else { '补齐逐年 paper+answer source anchors and per-year adapter diagnostics before advancing REAL005A.' }
$sliceCoverage = New-Object System.Collections.Specialized.OrderedDictionary
$real005ACoverage = @{}
$real005ACoverage['criteriaIds'] = @('RG001', 'RG002')
$real005ACoverage['status'] = $real005AStatus
$real005ACoverage['blockers'] = @($real005ABlockers)
$real005ACoverage['evidencePaths'] = @(($rg001EvidencePaths + $rg002EvidencePaths) | Sort-Object -Unique)
$real005ACoverage['next'] = $real005ANext
$sliceCoverage.Add('REAL005A', $real005ACoverage)

$real005BCoverage = @{}
$real005BCoverage['criteriaIds'] = @('RG003', 'RG004', 'RG005', 'RG006', 'RG007', 'RG008', 'RG009')
if ($real005AStatus -ne 'pass') {
    $real005BCoverage['status'] = 'blocked_by_previous_slice'
    $real005BCoverage['blockers'] = @('REAL005A is not yet closed; do not interpret question-structure and review coverage as a closeable slice yet.')
    $real005BCoverage['evidencePaths'] = @($real002ReportPath, 'docs/evidence/20260512-real004-guangzhou-2015-review-smoke-report.json')
    $real005BCoverage['criteriaStatus'] = @{}
    $real005BCoverage['next'] = 'Only evaluate per-question structure/review closure after REAL005A source+adapter coverage is complete.'
}
elseif ($null -ne $questionStructureDiagnostics -and [string]$questionStructureDiagnostics.status -eq 'pass') {
    $real005BCoverage['status'] = [string]$questionStructureDiagnostics.real005BStatus
    $real005BCoverage['blockers'] = @($questionStructureDiagnostics.blockers)
    $real005BCoverage['evidencePaths'] = @($questionStructureDiagnostics.sourceEvidence + @($QuestionStructureDiagnosticsPath) | Sort-Object -Unique)
    $criteriaStatus = [ordered]@{}
    foreach ($criterionId in @('RG003', 'RG004', 'RG005', 'RG006', 'RG007', 'RG008', 'RG009')) {
        $criterion = $questionStructureDiagnostics.criteria.$criterionId
        $criteriaStatus[$criterionId] = if ($null -eq $criterion) { 'missing' } else { [string]$criterion.status }
    }
    $real005BCoverage['criteriaStatus'] = $criteriaStatus
    $real005BCoverage['next'] = 'REAL005B remains partial until RG004-RG009 have per-question source anchors, structured fields, teacher review terminal status, and source-review save/detail evidence.'
}
else {
    $real005BCoverage['status'] = 'blocked'
    $real005BCoverage['blockers'] = @('REAL005B question-structure diagnostics report is missing or not passing.')
    $real005BCoverage['evidencePaths'] = @($real002ReportPath, 'docs/evidence/20260512-real004-guangzhou-2015-review-smoke-report.json')
    $real005BCoverage['criteriaStatus'] = @{}
    $real005BCoverage['next'] = 'Run tools/run-real005b-question-structure-diagnostics.ps1 to classify RG003-RG009 before advancing REAL005B.'
}
$sliceCoverage.Add('REAL005B', $real005BCoverage)

$real005CCoverage = @{}
$real005CCoverage['criteriaIds'] = @('RG010', 'RG011', 'RG012', 'RG013', 'RG014', 'RG015', 'RG016')
$real005CCoverage['status'] = 'blocked_by_previous_slice'
$real005CCoverage['blockers'] = @('REAL005A and REAL005B remain open; usage/export/analysis closure cannot be promoted ahead of earlier slices.')
$real005CCoverage['evidencePaths'] = @('docs/evidence/20260518-real012-production-flow-quality-report.json', 'docs/evidence/20260516-real007-guangzhou-2015-layout-quality-report.json')
$real005CCoverage['next'] = 'Keep REAL005C blocked until source coverage and per-question review closure are both complete.'
$sliceCoverage.Add('REAL005C', $real005CCoverage)

$real005DCoverage = @{}
$real005DCoverage['criteriaIds'] = @('DOCS', 'README', 'GO_NO_GO_CARD')
$real005DCoverage['status'] = 'blocked'
$real005DCoverage['blockers'] = @("closureStatus remains $closureStatus; truthful docs must continue to say not_closed")
$real005DCoverage['evidencePaths'] = @('docs/112_CurrentClosureStatus_20260609.md', 'docs/109_ReleaseGoNoGoCard.md', 'README.md')
$real005DCoverage['next'] = 'Do not rewrite outward completion wording until REAL005A/B/C are all closed.'
$sliceCoverage.Add('REAL005D', $real005DCoverage)

$real005BCriterionStatusLookup = @{}
foreach ($criterionEntry in $real005BCoverage['criteriaStatus'].GetEnumerator()) {
    $real005BCriterionStatusLookup[[string] $criterionEntry.Key] = [string] $criterionEntry.Value
}

$real005BDetailedCoverage = New-Real005DetailedSliceCoverage `
    -PlanRows $detailedSlicePlanRows `
    -ParentSliceId 'REAL005B' `
    -CriterionStatusLookup $real005BCriterionStatusLookup `
    -GlobalCriterionBlockers @($real005BCoverage['blockers']) `
    -ParentReady ($real005AStatus -eq 'pass')
$real005BCoverage['detailedSliceCoverage'] = $real005BDetailedCoverage['detailedSliceCoverage']
$real005BCoverage['nextDetailedSlice'] = $real005BDetailedCoverage['nextDetailedSlice']
$real005BCoverage['nextDetailedSliceReady'] = $real005BDetailedCoverage['nextDetailedSliceReady']

$real005CGlobalBlockers = [string[]]@()
$real005CDetailedCoverage = New-Real005DetailedSliceCoverage `
    -PlanRows $detailedSlicePlanRows `
    -ParentSliceId 'REAL005C' `
    -CriterionStatusLookup @{} `
    -GlobalCriterionBlockers $real005CGlobalBlockers `
    -ParentReady ($real005BCoverage['status'] -eq 'pass')
$real005CCoverage['detailedSliceCoverage'] = $real005CDetailedCoverage['detailedSliceCoverage']
$real005CCoverage['nextDetailedSlice'] = $real005CDetailedCoverage['nextDetailedSlice']
$real005CCoverage['nextDetailedSliceReady'] = $real005CDetailedCoverage['nextDetailedSliceReady']

$nextDetailedCandidates = @(
    [ordered]@{
        parentSlice = 'REAL005B'
        sliceId = [string] $real005BCoverage['nextDetailedSlice']
        ready = [bool] $real005BCoverage['nextDetailedSliceReady']
    },
    [ordered]@{
        parentSlice = 'REAL005C'
        sliceId = [string] $real005CCoverage['nextDetailedSlice']
        ready = [bool] $real005CCoverage['nextDetailedSliceReady']
    }
)
$readyDetailedCandidate = @(
    $nextDetailedCandidates |
        Where-Object { $_.sliceId -ne 'none' -and $_.ready } |
        Select-Object -First 1
)
$fallbackDetailedCandidate = @(
    $nextDetailedCandidates |
        Where-Object { $_.sliceId -ne 'none' } |
        Select-Object -First 1
)
$nextDetailedOpen = if ($readyDetailedCandidate.Count -eq 1) {
    $readyDetailedCandidate[0]
}
elseif ($fallbackDetailedCandidate.Count -eq 1) {
    $fallbackDetailedCandidate[0]
}
else {
    [ordered]@{
        parentSlice = 'none'
        sliceId = 'none'
        ready = $false
    }
}

$report = [ordered]@{
    status = 'pass'
    task = 'REAL005'
    checkedAt = (Get-Date).ToString('s')
    closureStatus = $closureStatus
    criteriaPath = $CriteriaPath
    criteriaCount = $criteriaRows.Count
    requiredYears = @(2015..2025)
    fullClosureAllowed = ($closureStatus -eq 'closed')
    currentTruth = 'S012/REAL001/REAL002/REAL003 dry-run/REAL004 review smoke evidence is not enough to claim 2015-2025 full workflow closure'
    criteriaCoverage = $criteriaCoverage
    sliceCoverage = $sliceCoverage
    nextDetailedOpen = $nextDetailedOpen
    gaps = $gapItems
    requiredCriteria = $criteriaItems
    rollback = 'git restore tracked files; remove generated REAL005 evidence reports if this standard is reverted'
    summaryChinese = $summaryChinese
}

New-Item -ItemType Directory -Path (Split-Path -Parent $jsonFullPath) -Force | Out-Null
$reportJson = $report | ConvertTo-Json -Depth 12
Write-Utf8FileWithRetry -Path $jsonFullPath -Content $reportJson

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# REAL005 广州 2015-2025 真卷全流程闭环判定标准')
$lines.Add('')
$lines.Add("- status: $($report.status)")
$lines.Add("- closure_status: $($report.closureStatus)")
$lines.Add("- criteria_count: $($report.criteriaCount)")
$lines.Add("- full_closure_allowed: $($report.fullClosureAllowed)")
$lines.Add('')
$lines.Add('## 当前结论')
$lines.Add($report.summaryChinese)
$lines.Add('')
$lines.Add('## Closeout slices')
foreach ($sliceEntry in $sliceCoverage.GetEnumerator()) {
    $sliceId = [string]$sliceEntry.Key
    $slice = $sliceEntry.Value
    $criteriaText = @($slice.criteriaIds) -join ', '
    $blockerText = if (@($slice.blockers).Count -eq 0) { '无' } else { @($slice.blockers) -join ' | ' }
    $lines.Add(('- {0}: status={1}; criteria={2}; blockers={3}; next={4}' -f $sliceId, $slice.status, $criteriaText, $blockerText, $slice.next))
}
$lines.Add('')
$lines.Add('## REAL005 细化切片')
foreach ($parentSliceId in @('REAL005B', 'REAL005C')) {
    $parentSlice = $sliceCoverage[$parentSliceId]
    $lines.Add("- $($parentSliceId): next_detailed_slice=$($parentSlice.nextDetailedSlice); ready=$($parentSlice.nextDetailedSliceReady)")
    foreach ($detailedEntry in $parentSlice.detailedSliceCoverage.GetEnumerator()) {
        $detailedSlice = $detailedEntry.Value
        $criteriaText = @($detailedSlice.criterionIds) -join ', '
        $blockerText = if (@($detailedSlice.blockers).Count -eq 0) { '无' } else { @($detailedSlice.blockers) -join ' | ' }
        $lines.Add("  - $($detailedEntry.Key): status=$($detailedSlice.status); reported=$($detailedSlice.reportedCriterionStatus); ready=$($detailedSlice.readyToAdvance); criteria=$criteriaText; blockers=$blockerText")
    }
}
$lines.Add('')
$lines.Add('## 阻断缺口')
if ($gaps.Count -eq 0) {
    $lines.Add('- 无')
}
else {
    foreach ($gap in $gaps) {
        $lines.Add("- $($gap.id): $($gap.reason); next=$($gap.nextAction)")
    }
}
$lines.Add('')
$lines.Add('## 判定标准')
foreach ($criterion in $criteriaRows) {
    $lines.Add("- $($criterion.criterion_id) $($criterion.category): $($criterion.evidence_required)")
}
Write-Utf8FileWithRetry -Path $markdownFullPath -Content $lines

$report | ConvertTo-Json -Depth 12
