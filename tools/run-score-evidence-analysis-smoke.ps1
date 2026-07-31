param(
    [int] $ApiPort = 0,
    [string] $Configuration = 'Cek032',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $ReportPath = 'docs\evidence\cek032-score-evidence-analysis-smoke.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$reportFile = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $ReportPath))
$psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'
$ownsApi = $false

. (Join-Path $PSScriptRoot 'dotenv.ps1')
. (Join-Path $PSScriptRoot 'database-env.ps1')
Import-KqgDotEnv -RepoRoot $repoRoot
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
$env:PGPASSWORD = $DatabasePassword

function Invoke-Scalar([string] $Query) {
    $value = $Query | & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -v ON_ERROR_STOP=1 -At
    if ($LASTEXITCODE -ne 0) { throw "CEK-32 database query failed with exit code $LASTEXITCODE" }
    return ([string]$value).Trim()
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Invoke-JsonRequest([string] $Uri, [object] $Body) {
    $response = Invoke-WebRequest -Uri $Uri -Method Post -ContentType 'application/json' `
        -Body ($Body | ConvertTo-Json -Depth 10) -TimeoutSec 30
    return $response.Content | ConvertFrom-Json
}

if (-not (Test-Path -LiteralPath $psql)) { throw "psql is missing: $psql" }
Push-Location $repoRoot
try {
    $assessmentId = Invoke-Scalar @'
select a.id::text
from assessments a
join score_records sr on sr.assessment_id = a.id
where a.contains_student_pii = false and sr.contains_student_pii = false
order by sr.created_at desc
limit 1;
'@
    if ([string]::IsNullOrWhiteSpace($assessmentId)) { throw 'No non-PII draft/test assessment with score records is available.' }

    $fingerprintBefore = Invoke-Scalar @'
select md5(coalesce(string_agg(scope || ':' || row_id || ':' || payload, E'\n' order by scope,row_id),''))
from (
  select 'assessment' as scope,id::text as row_id,to_jsonb(t)::text as payload from assessments t
  union all select 'score_record',id::text,to_jsonb(t)::text from score_records t
  union all select 'item_score',id::text,to_jsonb(t)::text from item_scores t
) rows;
'@
    if ($ApiPort -le 0) { $ApiPort = Get-FreeTcpPort }
    dotnet build apps/api/K12QuestionGraph.Api.csproj -c $Configuration --no-restore | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'CEK-32 API build failed.' }
    & (Join-Path $PSScriptRoot 'start-local-api.ps1') -Port $ApiPort -Configuration $Configuration | Out-Host
    $ownsApi = $true
    $baseUrl = "http://127.0.0.1:$ApiPort"

    $blocked = Invoke-JsonRequest "$baseUrl/assessments/$assessmentId/score-evidence-analysis/preview" @{
        containsStudentPii = $false
        mappings = @(
            @{ questionNo = 'Q1'; questionItemId = $null },
            @{ questionNo = 'Q2'; questionItemId = $null }
        )
    }
    if ($blocked.status -ne 'blocked' -or $blocked.productionEligible -ne $false -or $blocked.writesProductionHistory -ne $false) {
        throw 'Unmapped score evidence did not fail closed.'
    }
    if (@($blocked.blockingIssues).Count -eq 0) { throw 'Blocked analysis did not expose blocking issues.' }

    $pii = Invoke-JsonRequest "$baseUrl/assessments/$assessmentId/score-evidence-analysis/preview" @{
        containsStudentPii = $true
        mappings = @()
    }
    if ($pii.status -ne 'blocked' -or $pii.realStudentDataUsed -ne $true -or $pii.productionEligible -ne $false) {
        throw 'PII score evidence did not fail closed.'
    }
    if (@($pii.blockingIssues | Where-Object { $_.codes -contains 'student_pii_detected' }).Count -eq 0) {
        throw 'PII blocking issue was not exposed.'
    }
}
finally {
    if ($ownsApi -and $ApiPort -gt 0) {
        & (Join-Path $PSScriptRoot 'start-local-api.ps1') -Stop -Port $ApiPort -Configuration $Configuration | Out-Host
    }
    Pop-Location
}

$fingerprintAfter = Invoke-Scalar @'
select md5(coalesce(string_agg(scope || ':' || row_id || ':' || payload, E'\n' order by scope,row_id),''))
from (
  select 'assessment' as scope,id::text as row_id,to_jsonb(t)::text as payload from assessments t
  union all select 'score_record',id::text,to_jsonb(t)::text from score_records t
  union all select 'item_score',id::text,to_jsonb(t)::text from item_scores t
) rows;
'@
if ($fingerprintAfter -ne $fingerprintBefore) { throw 'CEK-32 smoke changed score evidence tables.' }

$report = [ordered]@{
    schemaVersion = 'cek032-score-evidence-analysis-smoke.v1'
    status = 'pass'
    taskId = 'CEK-32'
    checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
    assessmentId = $assessmentId
    unmappedPreview = [ordered]@{
        status = [string]$blocked.status
        blockingIssueCount = @($blocked.blockingIssues).Count
        productionEligible = [bool]$blocked.productionEligible
        writesProductionHistory = [bool]$blocked.writesProductionHistory
    }
    piiPreview = [ordered]@{
        status = [string]$pii.status
        studentPiiDetected = @($pii.blockingIssues | Where-Object { $_.codes -contains 'student_pii_detected' }).Count -gt 0
        realStudentDataUsed = [bool]$pii.realStudentDataUsed
        productionEligible = [bool]$pii.productionEligible
    }
    governance = [ordered]@{
        scoreEvidenceFingerprintBefore = $fingerprintBefore
        scoreEvidenceFingerprintAfter = $fingerprintAfter
        databaseRestored = $true
        activeWrite = $false
        productionEligible = $false
        diagnosisStatus = 'pending_teacher_confirmation'
    }
    referencesReviewed = @(
        [ordered]@{ path = 'official-docs/EntityFramework.Docs/entity-framework/core/performance/efficient-querying.md'; revision = '058a5fc' },
        [ordered]@{ path = 'official-docs/react.dev/src/content/learn/choosing-the-state-structure.md'; revision = '6ec6134' },
        [ordered]@{ path = 'official-docs/tanstack-query/docs/framework/react/guides/queries.md'; revision = '763782a' }
    )
    adoptionDecision = @(
        'adopt EF Core AsNoTracking for every read-only evidence query',
        'adopt React derived rendering for weakest dimensions and counts instead of redundant state',
        'retain the existing explicit score-workflow command client because this read-only POST is user-triggered and no shared server cache is consumed',
        'OpenXML reference is not applicable because CEK-32 changes neither score file parsing nor export artifacts'
    )
    completionBoundary = 'CEK-32 proves read-only score evidence preview and fail-closed PII/unmapped-target behavior. It does not create analysis history, confirm diagnoses, or activate candidate evidence.'
}
$parent = Split-Path -Parent $reportFile
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFile -Encoding utf8
$report | ConvertTo-Json -Depth 8
