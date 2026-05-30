param(
    [string] $ReportPath = 'docs/evidence/20260530-ns402-review-queue-api-report.json',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 0)
    try {
        $listener.Start()
        return $listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

function Wait-ApiReady([System.Diagnostics.Process] $Process, [string] $ApiUrl, [string] $LogErr) {
    for ($i = 0; $i -lt 30; $i++) {
        if ($Process.HasExited) {
            throw "API exited before NS402 review queue smoke on $ApiUrl; see $LogErr"
        }

        try {
            $health = Invoke-RestMethod -Uri "$ApiUrl/health" -TimeoutSec 2
            if ($health.status -eq 'ok') {
                return
            }
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    throw "API did not become ready for NS402 review queue smoke on $ApiUrl"
}

function Invoke-PsqlScalar([string] $Sql) {
    $psql = Join-Path $PgBin 'psql.exe'
    Assert-Condition (Test-Path -LiteralPath $psql) "psql.exe missing: $psql"
    $value = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -c $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "psql query failed: $Sql"
    }

    $lines = @($value | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -and $_ -notmatch '^INSERT\s+\d+\s+\d+$' })
    return ([string]($lines | Select-Object -First 1)).Trim()
}

function New-ReviewItem([string] $RunId, [int] $QuestionNo, [decimal] $Confidence, [string] $Reason) {
    $payload = [ordered]@{
        ns402RunId = $RunId
        questionNo = $QuestionNo
        confidence = $Confidence
        requiredAction = 'manual_review'
        reason = $Reason
        textPreview = "NS402 review queue fixture $QuestionNo"
        answer = 'B'
        knowledgeTags = @('ns402_fixture')
    } | ConvertTo-Json -Depth 6 -Compress
    $safePayload = $payload.Replace("'", "''")
    return Invoke-PsqlScalar "insert into review_queue_items (review_type, status, payload, created_at) values ('ns402_review', 'open', '$safePayload'::jsonb, now()) returning id;"
}

Push-Location $repoRoot
try {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS402 review queue smoke'

    $buildOutput = dotnet build 'apps/api/K12QuestionGraph.Api.csproj' -c Release 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) 'dotnet build failed before NS402 review queue smoke'

    $runId = [Guid]::NewGuid().ToString('N')
    $confirmId = ([Guid](New-ReviewItem -RunId $runId -QuestionNo 1 -Confidence 0.92 -Reason 'confirm_with_revision')).ToString()
    $dismissId = ([Guid](New-ReviewItem -RunId $runId -QuestionNo 2 -Confidence 0.70 -Reason 'dismiss_after_review')).ToString()
    $batchMediumId = ([Guid](New-ReviewItem -RunId $runId -QuestionNo 3 -Confidence 0.72 -Reason 'batch_medium')).ToString()
    $batchHighId = ([Guid](New-ReviewItem -RunId $runId -QuestionNo 4 -Confidence 0.40 -Reason 'batch_high_should_skip')).ToString()
    $allIds = @($confirmId, $dismissId, $batchMediumId, $batchHighId)

    $port = Get-FreeTcpPort
    $apiUrl = "http://127.0.0.1:$port"
    $logOut = Join-Path $repoRoot 'docs/evidence/ns402-api.out.log'
    $logErr = Join-Path $repoRoot 'docs/evidence/ns402-api.err.log'

    $previousConnectionString = $env:KQG_CONNECTION_STRING
    $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"

    $process = Start-Process -FilePath dotnet -ArgumentList @(
        'run',
        '--project',
        'apps\api\K12QuestionGraph.Api.csproj',
        '-c',
        'Release',
        '--no-build',
        '--urls',
        $apiUrl,
        '--no-launch-profile'
    ) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

    try {
        Wait-ApiReady -Process $process -ApiUrl $apiUrl -LogErr $logErr

        $openQueue = Invoke-RestMethod -Uri "$apiUrl/review-queue?status=open&reviewType=ns402_review&sortBy=question_no&order=asc&limit=20" -TimeoutSec 15
        $openItems = @($openQueue.items | Where-Object { [string]$_.payload.ns402RunId -eq $runId })
        Assert-Condition ($openItems.Count -eq 4) 'NS402 filtered open queue did not return four fixture items'
        Assert-Condition (@($openItems | ForEach-Object { [int]$_.payload.questionNo })[0] -eq 1) 'NS402 question_no sort did not preserve ascending order'
        Assert-Condition (@($openItems | Where-Object { $_.riskLevel -eq 'high' }).Count -eq 1) 'NS402 riskLevel high derivation missing'
        Assert-Condition (@($openItems | Where-Object { $_.requiredAction -eq 'manual_review' }).Count -eq 4) 'NS402 requiredAction derivation missing'

        $confirmBody = [ordered]@{
            reviewedBy = 'ns402_smoke'
            decision = 'confirmed'
            reason = 'teacher confirmed after editing'
            revision = [ordered]@{
                textPreview = 'NS402 revised stem'
                answer = 'C'
                primaryKnowledgeLabel = '力与运动'
                knowledgeTags = @('ns402_fixture', 'teacher_revision')
            }
        } | ConvertTo-Json -Depth 8
        $confirmed = Invoke-RestMethod -Method Post -Uri "$apiUrl/review-queue/$confirmId/resolve" -ContentType 'application/json' -Body $confirmBody -TimeoutSec 15
        Assert-Condition ($confirmed.status -eq 'resolved') 'NS402 confirm did not resolve item'
        Assert-Condition ($confirmed.payload.reviewAudit.decision -eq 'confirmed') 'NS402 confirm audit decision missing'
        Assert-Condition ($confirmed.payload.reviewAudit.revision.answer -eq 'C') 'NS402 confirm revision answer missing'
        Assert-Condition (@($confirmed.payload.reviewAudit.revision.knowledgeTags) -contains 'teacher_revision') 'NS402 confirm revision tags missing'

        $dismissBody = [ordered]@{
            reviewedBy = 'ns402_smoke'
            decision = 'dismissed'
            reason = 'teacher rejected candidate'
            revision = $null
        } | ConvertTo-Json -Depth 5
        $dismissed = Invoke-RestMethod -Method Post -Uri "$apiUrl/review-queue/$dismissId/resolve" -ContentType 'application/json' -Body $dismissBody -TimeoutSec 15
        Assert-Condition ($dismissed.status -eq 'dismissed') 'NS402 dismiss did not dismiss item'
        Assert-Condition ($dismissed.payload.reviewAudit.decision -eq 'dismissed') 'NS402 dismiss audit decision missing'

        $batchBody = [ordered]@{
            itemIds = @($batchMediumId, $batchHighId)
            reviewedBy = 'ns402_batch'
            decision = 'confirmed'
            reason = 'batch medium only'
        } | ConvertTo-Json -Depth 5
        $batch = Invoke-RestMethod -Method Post -Uri "$apiUrl/review-queue/batch-resolve" -ContentType 'application/json' -Body $batchBody -TimeoutSec 15
        Assert-Condition (@($batch.resolvedIds) -contains $batchMediumId) 'NS402 batch did not resolve medium item'
        Assert-Condition (@($batch.skippedHighRiskIds) -contains $batchHighId) 'NS402 batch did not skip high-risk item'

        $resolvedQueue = Invoke-RestMethod -Uri "$apiUrl/review-queue?status=resolved&reviewType=ns402_review&limit=20" -TimeoutSec 15
        $resolvedItems = @($resolvedQueue.items | Where-Object { [string]$_.payload.ns402RunId -eq $runId })
        Assert-Condition ($resolvedItems.Count -ge 2) 'NS402 resolved queue did not expose audit items'
        $remainingOpen = Invoke-RestMethod -Uri "$apiUrl/review-queue?status=open&reviewType=ns402_review&limit=20" -TimeoutSec 15
        $remainingOpenItems = @($remainingOpen.items | Where-Object { [string]$_.payload.ns402RunId -eq $runId })
        Assert-Condition (@($remainingOpenItems | Where-Object { [string]$_.id -eq $batchHighId }).Count -eq 1) 'NS402 high-risk skipped item should remain open'

        $idList = ($allIds | ForEach-Object { "'$_'" }) -join ','
        Invoke-PsqlScalar "delete from review_queue_items where id in ($idList);" | Out-Null
        $cleanupCount = [int](Invoke-PsqlScalar "select count(*) from review_queue_items where id in ($idList);")
        Assert-Condition ($cleanupCount -eq 0) 'NS402 cleanup left review queue rows behind'

        $report = [ordered]@{
            status = 'pass'
            taskId = 'NS402'
            checkedAt = (Get-Date).ToString('s')
            mode = 'api_review_queue_filter_resolve_batch_audit_smoke'
            productionEligible = $false
            runId = $runId
            filtering = [ordered]@{
                openFilteredCount = $openItems.Count
                sortByQuestionNo = $true
                riskDerived = $true
                requiredActionDerived = $true
            }
            decisions = [ordered]@{
                confirmedId = $confirmId
                dismissedId = $dismissId
                batchResolvedIds = @($batch.resolvedIds)
                batchSkippedHighRiskIds = @($batch.skippedHighRiskIds)
            }
            audit = [ordered]@{
                confirmAuditDecision = [string]$confirmed.payload.reviewAudit.decision
                confirmRevisionAnswer = [string]$confirmed.payload.reviewAudit.revision.answer
                dismissAuditDecision = [string]$dismissed.payload.reviewAudit.decision
                resolvedAuditQueryable = $true
            }
            cleanup = [ordered]@{
                dbRowsRemoved = $true
                cleanupCount = $cleanupCount
            }
            acceptance = [ordered]@{
                queueFilterWorks = $true
                pendingItemsQueryable = $true
                confirmWritesAudit = $true
                dismissWritesAudit = $true
                revisionPersistsInAudit = $true
                highRiskBatchSkipWorks = $true
            }
            boundary = 'NS402 proves ReviewQueue API filtering, pending/open queries, confirm, dismiss, revision audit, and high-risk batch skip using isolated synthetic review items.'
            next = 'NS403 can continue review workbench UI evidence.'
            rollback = 'Test review_queue_items are removed by this script; if interrupted, delete rows by the reported runId in payload or restore DB snapshot.'
        }

        $reportFullPath = Join-Path $repoRoot $ReportPath
        New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
        $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
        $report | ConvertTo-Json -Depth 7
    }
    finally {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $env:KQG_CONNECTION_STRING = $previousConnectionString
    }
}
finally {
    Pop-Location
}
