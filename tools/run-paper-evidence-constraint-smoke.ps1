param(
    [Parameter(Mandatory)]
    [string] $BackupManifest,
    [string] $ReportPath = 'docs\evidence\cek031-paper-evidence-constraint-smoke.json',
    [int] $ApiPort = 0,
    [string] $Configuration = 'Cek031',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabasePassword = $env:PGPASSWORD
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$reportFile = if ([System.IO.Path]::IsPathRooted($ReportPath)) {
    [System.IO.Path]::GetFullPath($ReportPath)
}
else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $ReportPath))
}
$createdReviewIds = [System.Collections.Generic.List[string]]::new()
$ownsApi = $false

. (Join-Path $PSScriptRoot 'dotenv.ps1')
. (Join-Path $PSScriptRoot 'database-env.ps1')
Import-KqgDotEnv -RepoRoot $repoRoot
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
$env:PGPASSWORD = $DatabasePassword
$psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Invoke-Scalar([string] $Query) {
    $value = $Query | & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -v ON_ERROR_STOP=1 -At
    if ($LASTEXITCODE -ne 0) { throw "CEK-31 database query failed with exit code $LASTEXITCODE" }
    return ([string]$value).Trim()
}

function Get-PaperFingerprint {
    return Invoke-Scalar @'
select md5(coalesce(string_agg(scope || ':' || row_id || ':' || payload, E'\n' order by scope,row_id),''))
from (
  select 'review' as scope,id::text as row_id,to_jsonb(t)::text as payload from paper_blueprint_reviews t
  union all select 'basket',id::text,to_jsonb(t)::text from paper_baskets t
  union all select 'item',id::text,to_jsonb(t)::text from paper_basket_items t
) rows;
'@
}

function Invoke-JsonRequest([string] $Method, [string] $Uri, [object] $Body, [int] $ExpectedStatus) {
    $response = Invoke-WebRequest `
        -Uri $Uri `
        -Method $Method `
        -ContentType 'application/json' `
        -Body ($Body | ConvertTo-Json -Depth 10) `
        -SkipHttpErrorCheck `
        -TimeoutSec 30
    Assert-Condition ($response.StatusCode -eq $ExpectedStatus) "Unexpected HTTP $($response.StatusCode) for $Uri"
    return $response.Content | ConvertFrom-Json
}

Assert-Condition (Test-Path -LiteralPath $psql) "psql is missing: $psql"
Assert-Condition (Test-Path -LiteralPath $BackupManifest) "Backup manifest is missing: $BackupManifest"
Push-Location $repoRoot
try {
    & (Join-Path $PSScriptRoot 'verify-backup.ps1') -ManifestPath $BackupManifest | Out-Host
    $fingerprintBefore = Get-PaperFingerprint

    if ($ApiPort -le 0) {
        $ApiPort = Get-FreeTcpPort
        dotnet build apps/api/K12QuestionGraph.Api.csproj -c $Configuration --no-restore | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "CEK-31 API build failed with exit code $LASTEXITCODE" }
        & (Join-Path $PSScriptRoot 'start-local-api.ps1') -Port $ApiPort -Configuration $Configuration
        $ownsApi = $true
    }
    $baseUrl = "http://127.0.0.1:$ApiPort"

    $missingPreview = Invoke-JsonRequest -Method Post -Uri "$baseUrl/paper-blueprints" -ExpectedStatus 400 -Body @{
        teacherRequest = '广州物理证据约束组卷'
        textbookVersion = '人教版九年级'
        evidenceConstraints = @{ evidenceMode = 'candidate'; previewMode = $false }
    }
    Assert-Condition ($missingPreview.error -eq 'preview_mode_required') 'candidate blueprint did not require explicit preview.'

    $candidate = Invoke-JsonRequest -Method Post -Uri "$baseUrl/paper-blueprints" -ExpectedStatus 201 -Body @{
        teacherRequest = '广州物理证据约束组卷'
        textbookVersion = '人教版九年级'
        evidenceConstraints = @{
            evidenceMode = 'candidate'
            previewMode = $true
            requirementIds = @('CR-PHY-JM-2022R2025-4.1.4-F01')
            abilityDimensions = @('科学推理')
        }
    }
    [void]$createdReviewIds.Add([string]$candidate.id)
    Assert-Condition ($candidate.evidenceMode -eq 'candidate' -and $candidate.previewMode -eq $true) 'candidate draft preview boundary failed.'
    Assert-Condition ($candidate.productionEligible -eq $false -and $candidate.draftPreview -eq $true) 'candidate blueprint became production eligible.'
    Assert-Condition ([int]$candidate.evidenceMatchedQuestionCount -ge 0) 'candidate matched count is missing.'
    Assert-Condition (@($candidate.constraintExplanation).Count -ge 2) 'candidate constraint explanation is incomplete.'
    Assert-Condition (@($candidate.versionReferences | Where-Object { $_.provenance -like '*not_original_basis*' }).Count -gt 0) 'retrospective alignment disclosure was lost.'

    $candidateConfirm = Invoke-JsonRequest -Method Post -Uri "$baseUrl/paper-blueprints/$($candidate.id)/confirm" -ExpectedStatus 409 -Body @{
        teacherConfirmedBy = 'cek031-smoke'
    }
    Assert-Condition ($candidateConfirm.error -eq 'preview_blueprint_cannot_create_formal_basket') 'candidate preview confirmation was not blocked.'

    $active = Invoke-JsonRequest -Method Post -Uri "$baseUrl/paper-blueprints" -ExpectedStatus 201 -Body @{
        teacherRequest = '广州物理正式证据约束组卷'
        textbookVersion = '人教版九年级'
        evidenceConstraints = @{
            evidenceMode = 'active'
            previewMode = $false
            requirementIds = @('CR-PHY-JM-2022R2025-4.1.4-F01')
        }
    }
    [void]$createdReviewIds.Add([string]$active.id)
    Assert-Condition ($active.evidenceMode -eq 'active' -and $active.previewMode -eq $false) 'active blueprint mode drifted.'
    Assert-Condition (@($active.constraintShortages).Count -gt 0) 'active shortage was not explicit.'

    $activeConfirm = Invoke-JsonRequest -Method Post -Uri "$baseUrl/paper-blueprints/$($active.id)/confirm" -ExpectedStatus 409 -Body @{
        teacherConfirmedBy = 'cek031-smoke'
    }
    Assert-Condition ($activeConfirm.error -eq 'evidence_constraints_insufficient') 'active evidence shortage was relaxed.'
    Assert-Condition (@($activeConfirm.constraintShortages).Count -gt 0) 'active confirm lost shortage details.'

    $basketDelta = [int](Invoke-Scalar "select count(*) from paper_baskets where structure::jsonb->>'evidenceMode' in ('active','candidate','reviewed');")
    Assert-Condition ($basketDelta -eq 0) 'CEK-31 smoke unexpectedly created an evidence-constrained basket.'
}
finally {
    if ($ownsApi -and $ApiPort -gt 0) {
        & (Join-Path $PSScriptRoot 'start-local-api.ps1') -Stop -Port $ApiPort -Configuration $Configuration | Out-Host
    }
    if ($createdReviewIds.Count -gt 0) {
        $quoted = $createdReviewIds | ForEach-Object {
            $parsedGuid = [Guid]::Empty
            Assert-Condition ([Guid]::TryParse($_, [ref]$parsedGuid)) "Invalid review id captured: $_"
            "'$_'"
        }
        $deleteQuery = "delete from paper_blueprint_reviews where id in ($($quoted -join ','));"
        $null = Invoke-Scalar $deleteQuery
    }
    Pop-Location
}

$fingerprintAfter = Get-PaperFingerprint
Assert-Condition ($fingerprintAfter -eq $fingerprintBefore) 'CEK-31 paper tables did not restore fingerprint parity.'
$report = [ordered]@{
    schemaVersion = 'cek031-paper-evidence-constraint-smoke.v1'
    status = 'pass'
    taskId = 'CEK-31'
    checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
    backupManifest = (Resolve-Path -LiteralPath $BackupManifest).Path
    preview = [ordered]@{
        explicitPreviewRequired = $true
        evidenceMode = [string]$candidate.evidenceMode
        matchedQuestionCount = [int]$candidate.evidenceMatchedQuestionCount
        productionEligible = [bool]$candidate.productionEligible
        formalBasketBlocked = $true
        retrospectiveAlignmentDisclosed = $true
    }
    active = [ordered]@{
        evidenceMode = [string]$active.evidenceMode
        matchedQuestionCount = [int]$active.evidenceMatchedQuestionCount
        shortageCount = @($active.constraintShortages).Count
        constraintsRelaxed = $false
        basketCreated = $false
    }
    governance = [ordered]@{
        paperFingerprintBefore = $fingerprintBefore
        paperFingerprintAfter = $fingerprintAfter
        databaseRestored = $true
        activeWrite = $false
        productionEligible = $false
        real005 = 'not_closed'
    }
    completionBoundary = 'CEK-31 proves evidence-constrained blueprint preview, frozen references, retrospective disclosure, shortage reporting, and candidate-to-formal fail-closed behavior. It does not activate evidence, approve candidates, or close REAL005.'
}
$parent = Split-Path -Parent $reportFile
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFile -Encoding utf8
$report | ConvertTo-Json -Depth 8
