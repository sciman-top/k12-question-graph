param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $ConnectionString = $env:KQG_CONNECTION_STRING,
    [string] $ReportPath = 'docs\evidence\k001-active-c002-production-query-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$ConnectionString = Resolve-KqgConnectionString -ConnectionString $ConnectionString
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

function ConvertTo-PsycopgConnectionString([string] $Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or -not $Value.Contains(';')) {
        return $Value
    }

    $map = @{}
    foreach ($part in $Value.Split(';')) {
        if ([string]::IsNullOrWhiteSpace($part) -or -not $part.Contains('=')) {
            continue
        }

        $pieces = $part.Split('=', 2)
        $map[$pieces[0].Trim().ToLowerInvariant()] = $pieces[1].Trim()
    }

    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($pair in @(
        @('host', 'host'),
        @('port', 'port'),
        @('database', 'dbname'),
        @('username', 'user'),
        @('password', 'password')
    )) {
        if ($map.ContainsKey($pair[0]) -and -not [string]::IsNullOrWhiteSpace($map[$pair[0]])) {
            $escaped = $map[$pair[0]].Replace('\', '\\').Replace("'", "\'")
            $tokens.Add("$($pair[1])='$escaped'")
        }
    }

    return ($tokens -join ' ')
}

if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
    if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
        throw 'KQG_CONNECTION_STRING or PGPASSWORD/DatabasePassword is required for K001.'
    }

    $ConnectionString = "host=$DatabaseHost port=$DatabasePort dbname=$DatabaseName user=$DatabaseUser password=$DatabasePassword"
}
else {
    $ConnectionString = ConvertTo-PsycopgConnectionString $ConnectionString
}

Push-Location $repoRoot
try {
    python tools\k001_active_c002_production_query.py --connection-string $ConnectionString --report-path $ReportPath | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "K001 active C002 production query contract failed" }

    $report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass') { throw "K001 report status is not pass" }
    if ($report.mode -ne 'production_query_contract') { throw "K001 mode mismatch" }
    if (-not $report.productionEligible) { throw "K001 production query contract must be production eligible" }
    if ($report.externalAiCalls -ne 0) { throw "K001 must not call external AI" }
    if ($report.realStudentDataUsed) { throw "K001 must not use real student data" }
    if ($report.activeKnowledgeVersion -ne 'junior-physics-guangzhou-source-derived-v1') { throw "K001 active version reference mismatch" }
    if ($report.counts.activeAssets -lt 1) { throw "K001 active asset count missing" }
    if ($report.counts.activeAssets -ne $report.counts.totalAssets) { throw "K001 default batch must be fully active" }
    if ($report.counts.candidateAssets -ne 0) { throw "K001 default batch still has candidate assets" }
    if ($report.counts.pendingMappings -ne 0) { throw "K001 default batch still has pending mappings" }
    if ($report.counts.appliedMigrations -lt 1) { throw "K001 applied migration missing" }
    if ($report.counts.sourceDocuments -ne 33) { throw "K001 source document count mismatch" }
    if (@($report.sampleActiveAssets).Count -lt 1) { throw "K001 active sample assets missing" }
    foreach ($surfaceName in @('questionSearch','paperAssemblyConstraints','knowledgeMasteryAnalysis')) {
        $surface = $report.querySurfaces.$surfaceName
        if ($surface.defaultKnowledgeSource -ne 'active_c002_v1') { throw "K001 $surfaceName default knowledge source mismatch" }
        if ($surface.versionReference.activeKnowledgeVersion -ne $report.activeKnowledgeVersion) { throw "K001 $surfaceName version reference mismatch" }
    }
    if (-not $report.compatibility.doesNotMutateActiveAssets) { throw "K001 must not mutate active assets" }

    [ordered]@{
        status = 'pass'
        task = 'K001'
        activeKnowledgeVersion = [string]$report.activeKnowledgeVersion
        activeAssets = [int]$report.counts.activeAssets
        approvedMappings = [int]$report.counts.approvedMappings
        appliedMigrations = [int]$report.counts.appliedMigrations
        sourceDocuments = [int]$report.counts.sourceDocuments
        querySurfaces = @('questionSearch','paperAssemblyConstraints','knowledgeMasteryAnalysis')
    } | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}
