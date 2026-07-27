param(
    [string] $ApiUrl = 'http://127.0.0.1:5275',
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $BackupManifest,
    [string] $ReportPath = 'docs\evidence\20260727-guangzhou-physics-v2-review-workflow-smoke.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-JsonRequest([string] $Method, [string] $Uri, [object] $Body) {
    Invoke-RestMethod -Method $Method -Uri $Uri -ContentType 'application/json' `
        -Body ($Body | ConvertTo-Json -Depth 20) -TimeoutSec 20
}

function Get-HttpFailureStatus([string] $Method, [string] $Uri, [object] $Body) {
    try {
        Invoke-WebRequest -Method $Method -Uri $Uri -ContentType 'application/json' `
            -Body ($Body | ConvertTo-Json -Depth 20) -TimeoutSec 20 | Out-Null
        return 200
    }
    catch {
        if ($null -ne $_.Exception.Response) {
            return [int]$_.Exception.Response.StatusCode
        }
        throw
    }
}

function Get-Question([string] $QuestionId) {
    Invoke-RestMethod -Uri "$ApiUrl/questions/$QuestionId" -TimeoutSec 20
}

function Get-Sources([string] $QuestionId) {
    Invoke-RestMethod -Uri "$ApiUrl/questions/$QuestionId/sources" -TimeoutSec 20
}

Assert-Condition (Test-Path -LiteralPath $BackupManifest) 'T7 backup manifest does not exist'
$backupVerification = & (Join-Path $repoRoot 'tools\verify-backup.ps1') -ManifestPath $BackupManifest | ConvertFrom-Json
Assert-Condition ([string]$backupVerification.status -eq 'ok') 'T7 backup verification failed'

$queueUri = "$ApiUrl/review-queue?status=open&reviewType=guangzhou_v2_question_candidate_review&sortBy=year_question_no&order=asc&limit=500"
$initialQueue = Invoke-RestMethod -Uri $queueUri -TimeoutSec 20
Assert-Condition ([int]$initialQueue.totalCount -eq 234) 'T7 requires 234 open v2 review items before smoke'
$review = @($initialQueue.items | Where-Object { [int]$_.payload.year -eq 2015 -and [int]$_.payload.questionNo -eq 1 })[0]
Assert-Condition ($null -ne $review) 'T7 could not find 2015 Q1 review item'

$questionId = [string]$review.payload.questionItemId
$reviewId = [string]$review.id
$initialQuestion = Get-Question $questionId
$initialSources = Get-Sources $questionId
$initialStem = @($initialQuestion.blocks | Where-Object { $_.blockType -eq 'stem' })[0]
$initialAnswer = @($initialQuestion.blocks | Where-Object { $_.blockType -eq 'answer' })[0]
$initialRegion = @($initialSources.sourceRegions | Where-Object { [string]$_.regionType -match 'question' })[0]
Assert-Condition ($null -ne $initialStem) 'T7 question stem block missing'
Assert-Condition ($null -ne $initialAnswer) 'T7 answer block missing'
Assert-Condition ($null -ne $initialRegion) 'T7 question source region missing'

$questionMutated = $false
$regionMutated = $false
$reviewNeedsReopen = $false
$events = [System.Collections.Generic.List[object]]::new()

try {
    $identityFailureStatus = Get-HttpFailureStatus 'POST' "$ApiUrl/review-queue/$reviewId/resolve" @{
        reviewedBy = ''
        decision = 'resolved'
        reason = 't7_identity_failure_probe'
    }
    Assert-Condition ($identityFailureStatus -eq 400) 'T7 missing reviewer identity should fail with 400'
    $events.Add([ordered]@{ action = 'identity_failure'; status = $identityFailureStatus; dataChanged = $false })

    $nextDifficulty = [Math]::Min(1.0, [double]$initialQuestion.difficultyEstimated + 0.01)
    $revision = Invoke-JsonRequest 'PATCH' "$ApiUrl/questions/$questionId" @{
        reviewedBy = 't7_reversible_smoke'
        reason = 'temporary_revision_then_restore'
        difficultyEstimated = $nextDifficulty
        primaryKnowledgeLabel = "$([string]$initialQuestion.customFields.primaryKnowledgeLabel) [T7]"
        blocks = @(
            @{
                id = [string]$initialStem.id
                blockType = [string]$initialStem.blockType
                sortOrder = [int]$initialStem.sortOrder
                sourceRegionId = [string]$initialStem.sourceRegionId
                content = @{
                    text = "$([string]$initialStem.content.text) [T7 smoke]"
                    reviewStatus = 'pending_review'
                }
            },
            @{
                id = [string]$initialAnswer.id
                blockType = [string]$initialAnswer.blockType
                sortOrder = [int]$initialAnswer.sortOrder
                sourceRegionId = [string]$initialAnswer.sourceRegionId
                content = $initialAnswer.content
            }
        )
        answer = $initialQuestion.customFields.answer
    }
    $questionMutated = $true
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$revision.auditId)) 'T7 revision audit missing'
    $events.Add([ordered]@{ action = 'revise'; auditId = $revision.auditId })

    $newWidth = [Math]::Max(0.1, [double]$initialRegion.width - 0.1)
    $recrop = Invoke-JsonRequest 'PATCH' "$ApiUrl/source-regions/$([string]$initialRegion.id)" @{
        pageNumber = [int]$initialRegion.pageNumber
        x = [double]$initialRegion.x + 0.1
        y = [double]$initialRegion.y
        width = $newWidth
        height = [double]$initialRegion.height
        coordinateUnit = [string]$initialRegion.coordinateUnit
        regionType = [string]$initialRegion.regionType
        reviewedBy = 't7_reversible_smoke'
        reason = 'temporary_recrop_then_restore'
    }
    $regionMutated = $true
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$recrop.auditId)) 'T7 recrop audit missing'
    $events.Add([ordered]@{ action = 'recrop'; auditId = $recrop.auditId })

    $confirmed = Invoke-JsonRequest 'POST' "$ApiUrl/review-queue/$reviewId/resolve" @{
        reviewedBy = 't7_reversible_smoke'
        decision = 'resolved'
        reason = 'temporary_confirm_then_reopen'
        revision = @{
            textPreview = [string]$initialStem.content.text
            answer = [string]$initialAnswer.content.value
            primaryKnowledgeLabel = [string]$initialQuestion.customFields.primaryKnowledgeLabel
            knowledgeTags = @()
        }
    }
    $reviewNeedsReopen = $true
    Assert-Condition ([string]$confirmed.status -eq 'resolved') 'T7 confirm did not resolve review'
    $events.Add([ordered]@{ action = 'confirm'; status = $confirmed.status })

    $conflictStatus = Get-HttpFailureStatus 'POST' "$ApiUrl/review-queue/$reviewId/resolve" @{
        reviewedBy = 't7_reversible_smoke'
        decision = 'resolved'
        reason = 'conflict_probe'
    }
    Assert-Condition ($conflictStatus -eq 409) 'T7 repeated resolve should fail with 409'
    $events.Add([ordered]@{ action = 'conflict'; status = $conflictStatus; dataChanged = $false })

    $reopenedAfterConfirm = Invoke-JsonRequest 'POST' "$ApiUrl/review-queue/$reviewId/reopen" @{
        reviewedBy = 't7_reversible_smoke'
        reason = 'undo_temporary_confirm'
    }
    $reviewNeedsReopen = $false
    Assert-Condition ([string]$reopenedAfterConfirm.status -eq 'open') 'T7 confirm undo did not reopen review'
    $events.Add([ordered]@{ action = 'undo_confirm'; status = $reopenedAfterConfirm.status })

    $returned = Invoke-JsonRequest 'POST' "$ApiUrl/review-queue/$reviewId/resolve" @{
        reviewedBy = 't7_reversible_smoke'
        decision = 'dismissed'
        reason = 'temporary_return_then_reopen'
    }
    $reviewNeedsReopen = $true
    Assert-Condition ([string]$returned.status -eq 'dismissed') 'T7 return did not dismiss review'
    $events.Add([ordered]@{ action = 'return'; status = $returned.status })

    $reopenedAfterReturn = Invoke-JsonRequest 'POST' "$ApiUrl/review-queue/$reviewId/reopen" @{
        reviewedBy = 't7_reversible_smoke'
        reason = 'undo_temporary_return'
    }
    $reviewNeedsReopen = $false
    Assert-Condition ([string]$reopenedAfterReturn.status -eq 'open') 'T7 return undo did not reopen review'
    Assert-Condition (@($reopenedAfterReturn.payload.reviewAuditHistory).Count -ge 4) 'T7 audit history should preserve confirm/undo/return/undo'
    $events.Add([ordered]@{ action = 'undo_return'; status = $reopenedAfterReturn.status; auditHistoryCount = @($reopenedAfterReturn.payload.reviewAuditHistory).Count })
}
finally {
    if ($reviewNeedsReopen) {
        Invoke-JsonRequest 'POST' "$ApiUrl/review-queue/$reviewId/reopen" @{
            reviewedBy = 't7_reversible_smoke'
            reason = 'finally_restore_review_open'
        } | Out-Null
    }

    if ($questionMutated) {
        Invoke-JsonRequest 'PATCH' "$ApiUrl/questions/$questionId" @{
            reviewedBy = 't7_reversible_smoke'
            reason = 'finally_restore_question_snapshot'
            difficultyEstimated = [double]$initialQuestion.difficultyEstimated
            primaryKnowledgeLabel = [string]$initialQuestion.customFields.primaryKnowledgeLabel
            blocks = @(
                @{
                    id = [string]$initialStem.id
                    blockType = [string]$initialStem.blockType
                    sortOrder = [int]$initialStem.sortOrder
                    sourceRegionId = [string]$initialStem.sourceRegionId
                    content = $initialStem.content
                },
                @{
                    id = [string]$initialAnswer.id
                    blockType = [string]$initialAnswer.blockType
                    sortOrder = [int]$initialAnswer.sortOrder
                    sourceRegionId = [string]$initialAnswer.sourceRegionId
                    content = $initialAnswer.content
                }
            )
            answer = $initialQuestion.customFields.answer
            solution = $initialQuestion.customFields.solution
        } | Out-Null
    }

    if ($regionMutated) {
        Invoke-JsonRequest 'PATCH' "$ApiUrl/source-regions/$([string]$initialRegion.id)" @{
            pageNumber = [int]$initialRegion.pageNumber
            x = [double]$initialRegion.x
            y = [double]$initialRegion.y
            width = [double]$initialRegion.width
            height = [double]$initialRegion.height
            coordinateUnit = [string]$initialRegion.coordinateUnit
            regionType = [string]$initialRegion.regionType
            reviewedBy = 't7_reversible_smoke'
            reason = 'finally_restore_source_region_snapshot'
        } | Out-Null
    }
}

$finalQueue = Invoke-RestMethod -Uri $queueUri -TimeoutSec 20
$finalQuestion = Get-Question $questionId
$finalSources = Get-Sources $questionId
$finalStem = @($finalQuestion.blocks | Where-Object { $_.blockType -eq 'stem' })[0]
$finalRegion = @($finalSources.sourceRegions | Where-Object { [string]$_.id -eq [string]$initialRegion.id })[0]
$finalReview = @($finalQueue.items | Where-Object { [string]$_.id -eq $reviewId })[0]

Assert-Condition ([int]$finalQueue.totalCount -eq 234) 'T7 final open review count must be 234'
Assert-Condition ($null -ne $finalReview -and [string]$finalReview.status -eq 'open') 'T7 final review must be open'
Assert-Condition ([string]$finalQuestion.status -eq 'pending_review') 'T7 final question must remain pending_review'
Assert-Condition ($null -eq $finalQuestion.primaryKnowledgeId) 'T7 must not write primaryKnowledgeId'
Assert-Condition (-not [bool]$finalQuestion.customFields.productionEligible) 'T7 must remain productionEligible=false'
Assert-Condition ([string]$finalStem.content.text -eq [string]$initialStem.content.text) 'T7 question stem was not restored'
Assert-Condition ([double]$finalQuestion.difficultyEstimated -eq [double]$initialQuestion.difficultyEstimated) 'T7 difficulty was not restored'
Assert-Condition ([double]$finalRegion.x -eq [double]$initialRegion.x -and [double]$finalRegion.width -eq [double]$initialRegion.width) 'T7 source region was not restored'

$report = [ordered]@{
    taskId = 'T7'
    status = 'pass'
    checkedAt = (Get-Date).ToString('o')
    materialBatchKey = [string]$review.payload.materialBatchKey
    sourceWorkflowKey = [string]$review.payload.sourceWorkflowKey
    backupManifest = (Resolve-Path -LiteralPath $BackupManifest).Path
    backupVerification = $backupVerification
    reviewQueueItemId = $reviewId
    questionItemId = $questionId
    events = $events
    final = [ordered]@{
        openReviewCount = [int]$finalQueue.totalCount
        reviewStatus = [string]$finalReview.status
        questionStatus = [string]$finalQuestion.status
        productionEligible = [bool]$finalQuestion.customFields.productionEligible
        primaryKnowledgeId = $finalQuestion.primaryKnowledgeId
        stemRestored = ([string]$finalStem.content.text -eq [string]$initialStem.content.text)
        difficultyRestored = ([double]$finalQuestion.difficultyEstimated -eq [double]$initialQuestion.difficultyEstimated)
        sourceRegionRestored = ([double]$finalRegion.x -eq [double]$initialRegion.x -and [double]$finalRegion.width -eq [double]$initialRegion.width)
        auditHistoryCount = @($finalReview.payload.reviewAuditHistory).Count
    }
    rollback = "restore $BackupManifest only if the finally restoration assertions fail"
    truthBoundary = 'reversible local smoke only; no teacher acceptance, production eligibility, C002 activation, onsite validation, or live release'
}

$absoluteReportPath = Join-Path $repoRoot $ReportPath
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $absoluteReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 20
