param(
    [string] $InputRoot = 'c002-k12-question-graph-candidate-csvs\cleaned',
    [string] $MaterialBatchKey = 'guangzhou_physics_2016_2025',
    [string] $ReportPath = 'docs\evidence\c002-candidate-import-report.json',
    [string] $BackupManifest = '',
    [switch] $Apply,
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $ConnectionString = $env:KQG_CONNECTION_STRING
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'import_c002_candidate_assets.py'
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
        throw 'KQG_CONNECTION_STRING or PGPASSWORD/DatabasePassword is required.'
    }

    $ConnectionString = "host=$DatabaseHost port=$DatabasePort dbname=$DatabaseName user=$DatabaseUser password=$DatabasePassword"
}
else {
    $ConnectionString = ConvertTo-PsycopgConnectionString $ConnectionString
}

$args = @(
    $scriptPath,
    '--input-root', $InputRoot,
    '--material-batch-key', $MaterialBatchKey,
    '--report-path', $ReportPath,
    '--connection-string', $ConnectionString
)

if ($Apply) {
    $args += '--apply'
}

if (-not [string]::IsNullOrWhiteSpace($BackupManifest)) {
    $args += @('--backup-manifest', $BackupManifest)
}

Push-Location $repoRoot
try {
    python @args
    if ($LASTEXITCODE -ne 0) {
        throw "candidate import failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
