param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 5298,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $ReportPath = 'docs\evidence\20260508-s011a-score-import-api-smoke-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) { throw 'DatabasePassword or PGPASSWORD is required for S011A smoke' }

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-ScalarSql([string] $Sql) {
    $psql = Join-Path $PgBin 'psql.exe'
    $value = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "S011A SQL failed: $Sql" }
    return (($value | Select-Object -First 1) ?? '').Trim()
}

$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/s011a-smoke-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/s011a-smoke-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
$process = $null
$pushedLocation = $false

try {
    Push-Location $repoRoot
    $pushedLocation = $true
    dotnet ef database update --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj | Write-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet ef database update failed' }

    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\\api\\K12QuestionGraph.Api.csproj','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
    $ready = $false
    for ($i = 0; $i -lt 120; $i++) {
        try { if ((Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 2).status -eq 'ok') { $ready = $true; break } } catch {}
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw "API did not become ready on $apiUrl" }

    $validBody = @{
        assessmentKey = 's011a-score-import-smoke'
        assessmentTitle = 'S011A 成绩导入 smoke'
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_8'
        templateKey = 's011a-score-template-v1'
        templateDisplayName = 'S011A 成绩导入模板'
        sourceFileName = 's011a-score-import-smoke.xlsx'
        containsStudentPii = $false
        productionEligible = $false
        maxTotalScore = 100
        fieldMapping = @{
            studentKey = 'student_code'
            totalScore = 'total_score'
            itemScores = @{
                Q1 = 'q1_score'
                Q2 = 'q2_score'
            }
        }
        itemMaxScores = @{
            Q1 = 40
            Q2 = 60
        }
        rows = @(
            @{ rowNumber = 2; values = @{ student_code = 'SYN-001'; total_score = '88'; q1_score = '34'; q2_score = '54' } },
            @{ rowNumber = 3; values = @{ student_code = 'SYN-002'; total_score = '76'; q1_score = '30'; q2_score = '46' } },
            @{ rowNumber = 4; values = @{ student_code = 'SYN-003'; total_score = '104'; q1_score = '41'; q2_score = '63' } }
        )
    } | ConvertTo-Json -Depth 10

    $import = Invoke-RestMethod -Method Post -Uri "$apiUrl/score-imports" -ContentType 'application/json' -Body $validBody -TimeoutSec 10
    Assert-True ([string]$import.status -eq 'imported') 'S011A import should return imported'
    Assert-True ([string]$import.mode -eq 'draft_test') 'S011A import must stay draft_test'
    Assert-True (-not [bool]$import.productionEligible) 'S011A import must not be production eligible'
    Assert-True (-not [bool]$import.realStudentDataUsed) 'S011A import must not use real student data'
    Assert-True (-not [bool]$import.containsStudentPii) 'S011A import must not contain PII'
    Assert-True ([int]$import.rowCount -eq 3) 'S011A row count mismatch'
    Assert-True ([int]$import.importedCount -eq 2) 'S011A imported count mismatch'
    Assert-True ([int]$import.errorCount -eq 1) 'S011A error count mismatch'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$import.assessmentId)) 'S011A assessment id missing'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$import.templateId)) 'S011A template id missing'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$import.batchId)) 'S011A batch id missing'
    $errorCodes = @($import.errors | ForEach-Object { $_.code })
    Assert-True ($errorCodes -contains 'item_score_out_of_range') 'S011A abnormal row should be centralized with item_score_out_of_range'
    Assert-True (@($import.auditTrail) -contains 'no_ai_runtime_dependency') 'S011A audit trail must record no AI runtime dependency'

    $batchId = [string]$import.batchId
    $batchCount = [int](Invoke-ScalarSql "select count(*) from score_import_batches where id='$batchId';")
    $recordCount = [int](Invoke-ScalarSql "select count(*) from score_records where import_batch_id='$batchId';")
    $itemScoreCount = [int](Invoke-ScalarSql "select count(*) from item_scores i join score_records r on r.id=i.score_record_id where r.import_batch_id='$batchId';")
    $piiRecordCount = [int](Invoke-ScalarSql "select count(*) from score_records r join students s on s.id=r.student_id where r.import_batch_id='$batchId' and (r.contains_student_pii or s.contains_student_pii);")
    Assert-True ($batchCount -eq 1) 'S011A batch DB count mismatch'
    Assert-True ($recordCount -eq 2) 'S011A score record DB count mismatch'
    Assert-True ($itemScoreCount -eq 4) 'S011A item score DB count mismatch'
    Assert-True ($piiRecordCount -eq 0) 'S011A must not write PII records'

    $blockedBody = @{
        assessmentKey = 's011a-pii-blocked'
        assessmentTitle = 'S011A PII blocked'
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_8'
        templateKey = 's011a-pii-template'
        templateDisplayName = 'S011A PII template'
        sourceFileName = 's011a-pii-blocked.xlsx'
        containsStudentPii = $true
        productionEligible = $false
        maxTotalScore = 100
        fieldMapping = @{
            studentKey = 'student_name'
            totalScore = 'total_score'
            itemScores = @{ Q1 = 'q1_score' }
        }
        itemMaxScores = @{ Q1 = 40 }
        rows = @(
            @{ rowNumber = 2; values = @{ student_name = '真实姓名不应写入'; total_score = '88'; q1_score = '34' } }
        )
    } | ConvertTo-Json -Depth 10

    $blockedHttp = Invoke-WebRequest -Method Post -Uri "$apiUrl/score-imports" -ContentType 'application/json' -Body $blockedBody -TimeoutSec 10 -SkipHttpErrorCheck
    Assert-True ([int]$blockedHttp.StatusCode -eq 400) 'S011A PII request should return HTTP 400'
    $blocked = $blockedHttp.Content | ConvertFrom-Json
    Assert-True ([string]$blocked.status -eq 'blocked') 'S011A PII request should be blocked'
    Assert-True ([bool]$blocked.containsStudentPii) 'S011A blocked response should echo PII flag'
    Assert-True ([string]::IsNullOrWhiteSpace([string]$blocked.batchId)) 'S011A blocked response must not include batch id'
    $blockedCodes = @($blocked.errors | ForEach-Object { $_.code })
    Assert-True ($blockedCodes -contains 'pii_not_allowed') 'S011A PII block code missing'
    $blockedBatchCount = [int](Invoke-ScalarSql "select count(*) from score_import_batches where source_file_name='s011a-pii-blocked.xlsx';")
    Assert-True ($blockedBatchCount -eq 0) 'S011A PII blocked request must not write a batch'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'S011A'
        checkedAt = (Get-Date).ToString('s')
        endpoint = '/score-imports'
        assessmentId = $import.assessmentId
        templateId = $import.templateId
        batchId = $import.batchId
        rowCount = $import.rowCount
        importedCount = $import.importedCount
        errorCount = $import.errorCount
        errorCodes = $errorCodes
        dbCounts = [ordered]@{
            batch = $batchCount
            scoreRecords = $recordCount
            itemScores = $itemScoreCount
            piiRecords = $piiRecordCount
            blockedPiiBatches = $blockedBatchCount
        }
        blockedPiiStatusCode = [int]$blockedHttp.StatusCode
        auditTrail = $import.auditTrail
        teacherMessage = $import.teacherMessage
        conclusion = 'score import API writes draft/test synthetic batches, centralizes abnormal rows, blocks PII before database write, and has no AI runtime dependency'
        rollback = 'revert the S011A service/API/gate changes and remove docs/evidence/20260508-s011a-score-import-api-smoke-report.json; no migration is required'
    }
    $full = Join-Path $repoRoot $ReportPath
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $full -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    if ($null -ne $process) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    if ($pushedLocation) { Pop-Location }
}
