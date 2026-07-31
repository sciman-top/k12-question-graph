param(
    [string] $ReportPath = 'docs\evidence\cek028-question-evidence-search-api.json',
    [int] $ApiPort = 0,
    [string] $Configuration = 'Cek028',
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
$ownsApi = $false

. (Join-Path $PSScriptRoot 'dotenv.ps1')
. (Join-Path $PSScriptRoot 'database-env.ps1')
Import-KqgDotEnv -RepoRoot $repoRoot
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try {
        return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
}

function Get-DatabaseFingerprint {
    $psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'
    Assert-Condition (Test-Path -LiteralPath $psql) "psql is missing: $psql"
    $query = @'
select md5(coalesce(string_agg(scope || ':' || row_id || ':' || payload, E'\n' order by scope,row_id),''))
from (
  select 'asset' as scope,id::text as row_id,to_jsonb(t)::text as payload from domain_asset_versions t where status='active' or source_evidence->>'importKey' in ('cek009_curriculum_requirements_2022_2025_v1','cek023_regional_exam_profile_candidate_v1')
  union all select 'target',id::text,to_jsonb(t)::text from assessment_targets t where metadata->>'importKey'='cek016_guangzhou_assessment_targets_v1'
  union all select 'alignment',id::text,to_jsonb(t)::text from curriculum_alignments t where evidence->>'importKey'='cek016_guangzhou_assessment_targets_v1'
  union all select 'observed',id::text,to_jsonb(t)::text from observed_performance_evidence t
  union all select 'question',id::text,to_jsonb(t)::text from question_items t
) rows;
'@
    $value = $query | & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -v ON_ERROR_STOP=1 -At
    if ($LASTEXITCODE -ne 0) {
        throw "CEK-28 database fingerprint failed with exit code $LASTEXITCODE"
    }
    return ([string]$value).Trim()
}

function Assert-BadRequest([string] $Uri, [string] $ExpectedError) {
    try {
        Invoke-WebRequest -Uri $Uri -TimeoutSec 30 -ErrorAction Stop | Out-Null
        throw "request unexpectedly succeeded: $Uri"
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -ne 400) {
            throw
        }
        $payload = $_.ErrorDetails.Message | ConvertFrom-Json
        Assert-Condition ($payload.error -eq $ExpectedError) "unexpected error for ${Uri}: $($payload.error)"
    }
}

$fingerprintBefore = Get-DatabaseFingerprint
if ($ApiPort -le 0) {
    $ApiPort = Get-FreeTcpPort
    Push-Location $repoRoot
    try {
        dotnet build apps/api/K12QuestionGraph.Api.csproj -c $Configuration --no-restore | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "CEK-28 API build failed with exit code $LASTEXITCODE"
        }
        & (Join-Path $PSScriptRoot 'start-local-api.ps1') -Port $ApiPort -Configuration $Configuration
        $ownsApi = $true
    }
    finally {
        Pop-Location
    }
}

$baseUrl = "http://127.0.0.1:$ApiPort"
try {
    $active = Invoke-RestMethod -Uri "$baseUrl/knowledge-evidence/questions?pageSize=1" -TimeoutSec 30
    Assert-Condition ($active.evidenceMode -eq 'active') 'CEK-28 default evidence mode must be active.'
    Assert-Condition ($active.previewMode -eq $false) 'CEK-28 active mode must not be marked preview.'
    Assert-Condition ($active.productionEligible -eq $true) 'CEK-28 active query must be production-eligible only.'

    Assert-BadRequest `
        -Uri "$baseUrl/knowledge-evidence/questions?evidenceMode=candidate&pageSize=1" `
        -ExpectedError 'preview_mode_required'
    Assert-BadRequest `
        -Uri "$baseUrl/knowledge-evidence/questions?evidenceMode=reviewed&pageSize=1" `
        -ExpectedError 'preview_mode_required'
    Assert-BadRequest `
        -Uri "$baseUrl/knowledge-evidence/questions?evidenceMode=candidate&previewMode=true&observedDifficultyMin=0.9&observedDifficultyMax=0.1" `
        -ExpectedError 'invalid_difficulty_range'

    $candidate = Invoke-RestMethod -Uri "$baseUrl/knowledge-evidence/questions?evidenceMode=candidate&previewMode=true&pageSize=2" -TimeoutSec 30
    Assert-Condition ($candidate.total -eq 234) "CEK-28 candidate question total drifted: $($candidate.total)"
    Assert-Condition ($candidate.previewMode -eq $true -and $candidate.productionEligible -eq $false) 'candidate preview boundary failed.'
    Assert-Condition (@($candidate.items).Count -eq 2) 'candidate pagination failed.'
    Assert-Condition (@($candidate.items | Where-Object { $_.productionEligible -ne $false }).Count -eq 0) 'candidate card became production eligible.'
    Assert-Condition (@($candidate.items[0].assessmentTargets).Count -gt 0) 'candidate card has no assessment targets.'
    Assert-Condition ($candidate.items[0].estimatedDifficultySource -eq 'question_estimated') 'estimated difficulty source label is missing.'

    $ability = [uri]::EscapeDataString('科学推理')
    $abilityResult = Invoke-RestMethod -Uri "$baseUrl/knowledge-evidence/questions?evidenceMode=candidate&previewMode=true&ability=$ability&pageSize=2" -TimeoutSec 30
    Assert-Condition ($abilityResult.total -gt 0) 'ability filter returned no questions.'

    $context = [uri]::EscapeDataString('experimental')
    $contextResult = Invoke-RestMethod -Uri "$baseUrl/knowledge-evidence/questions?evidenceMode=candidate&previewMode=true&context=$context&pageSize=1" -TimeoutSec 30
    Assert-Condition ($contextResult.total -gt 0) 'context filter returned no questions.'

    $representation = [uri]::EscapeDataString('diagram')
    $representationResult = Invoke-RestMethod -Uri "$baseUrl/knowledge-evidence/questions?evidenceMode=candidate&previewMode=true&representation=$representation&pageSize=1" -TimeoutSec 30
    Assert-Condition ($representationResult.total -gt 0) 'representation filter returned no questions.'

    $observed = Invoke-RestMethod -Uri "$baseUrl/knowledge-evidence/questions?evidenceMode=candidate&previewMode=true&observedDifficultyMin=0.5&observedDifficultyMax=1&pageSize=2" -TimeoutSec 30
    Assert-Condition ($observed.total -gt 0) 'observed difficulty filter returned no questions.'
    $observedRows = @($observed.items | ForEach-Object { $_.assessmentTargets } | ForEach-Object { $_.observedDifficulty })
    Assert-Condition ($observedRows.Count -gt 0) 'observed difficulty projection is empty.'
    Assert-Condition (@($observedRows | Where-Object { $_.direction -ne 'higher_is_easier' }).Count -eq 0) 'observed difficulty direction drifted.'

    $profileId = 'EPHY-GUANGZHOU-074E4C66013F8AE6'
    $profileResult = Invoke-RestMethod -Uri "$baseUrl/knowledge-evidence/questions?evidenceMode=candidate&previewMode=true&profileId=$profileId&pageSize=2" -TimeoutSec 30
    Assert-Condition ($profileResult.total -gt 0) 'profile filter returned no questions.'

    $alignment = $null
    for ($page = 1; $page -le 5 -and $null -eq $alignment; $page++) {
        $pageResult = Invoke-RestMethod -Uri "$baseUrl/knowledge-evidence/questions?evidenceMode=candidate&previewMode=true&page=$page&pageSize=50" -TimeoutSec 30
        foreach ($card in @($pageResult.items)) {
            foreach ($target in @($card.assessmentTargets)) {
                if (@($target.requirements).Count -gt 0) {
                    $alignment = $target.requirements[0]
                    break
                }
            }
            if ($null -ne $alignment) { break }
        }
    }
    Assert-Condition ($null -ne $alignment) 'candidate projection has no curriculum alignment.'
    Assert-Condition ($alignment.provenance -eq $alignment.alignmentType) 'alignment provenance label was lost.'
    Assert-Condition ($alignment.originalBasis -eq $false -and $alignment.provenance -eq 'retrospective_crosswalk') 'retrospective crosswalk disclosure failed.'
    $requirementId = [uri]::EscapeDataString([string]$alignment.stableId)
    $requirementResult = Invoke-RestMethod -Uri "$baseUrl/knowledge-evidence/questions?evidenceMode=candidate&previewMode=true&requirementId=$requirementId&pageSize=2" -TimeoutSec 30
    $facetResult = Invoke-RestMethod -Uri "$baseUrl/knowledge-evidence/questions?evidenceMode=candidate&previewMode=true&facetId=$requirementId&pageSize=2" -TimeoutSec 30
    Assert-Condition ($requirementResult.total -gt 0 -and $facetResult.total -gt 0) 'requirement/facet filter returned no questions.'

    $legacy = Invoke-RestMethod -Uri "$baseUrl/questions?year=2015&limit=1" -TimeoutSec 30
    Assert-Condition ($legacy.total -eq 24 -and @($legacy.items).Count -eq 1) 'legacy /questions query changed.'

    $fingerprintAfter = Get-DatabaseFingerprint
    Assert-Condition ($fingerprintBefore -eq $fingerprintAfter) 'CEK-28 read-only API changed database state.'

    $report = [ordered]@{
        schemaVersion = 'cek028-question-evidence-search-api.v1'
        status = 'pass'
        taskId = 'CEK-28'
        checkedAt = (Get-Date).ToUniversalTime().ToString('o')
        apiPort = $ApiPort
        modes = [ordered]@{
            defaultActiveTotal = $active.total
            activeProductionEligible = $active.productionEligible
            candidateTotal = $candidate.total
            candidatePreview = $candidate.previewMode
            candidateProductionEligible = $candidate.productionEligible
            candidateWithoutPreviewRejected = $true
            reviewedWithoutPreviewRejected = $true
        }
        filters = [ordered]@{
            abilityTotal = $abilityResult.total
            contextTotal = $contextResult.total
            representationTotal = $representationResult.total
            observedDifficultyTotal = $observed.total
            profileTotal = $profileResult.total
            requirementId = $alignment.stableId
            requirementTotal = $requirementResult.total
            facetTotal = $facetResult.total
        }
        provenance = [ordered]@{
            estimatedDifficultySource = $candidate.items[0].estimatedDifficultySource
            observedDifficultyDirection = @($observedRows | Select-Object -ExpandProperty direction -Unique)
            alignmentType = $alignment.alignmentType
            originalBasis = $alignment.originalBasis
            retrospectiveDisclosed = $true
        }
        compatibility = [ordered]@{
            legacyEndpoint = '/questions?year=2015&limit=1'
            legacyTotal = $legacy.total
            legacyReturned = @($legacy.items).Count
            legacyContractUnchanged = $true
        }
        governance = [ordered]@{
            databaseFingerprintBefore = $fingerprintBefore
            databaseFingerprintAfter = $fingerprintAfter
            databaseUnchanged = ($fingerprintBefore -eq $fingerprintAfter)
            activeWrite = $false
            productionEligible = $false
        }
        completionBoundary = 'CEK-28 proves the read-only API, explicit preview gate, evidence filters, provenance projection, and legacy query compatibility. It does not review candidates, switch active assets, add the CEK-29 Web client, or close REAL005.'
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFile) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFile -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    if ($ownsApi) {
        & (Join-Path $PSScriptRoot 'start-local-api.ps1') -Stop -Port $ApiPort -Configuration $Configuration | Out-Host
    }
}
