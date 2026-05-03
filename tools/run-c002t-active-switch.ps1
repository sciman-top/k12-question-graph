param(
    [string] $ImportKey = 'c002_candidate_import_guangzhou_physics_2016_2025_v1',
    [string] $MaterialBatchKey = 'guangzhou_physics_2016_2025',
    [string] $BackupManifest = '',
    [string] $ReportPath = 'docs\evidence\c002t-active-switch-report.json',
    [int] $ExpectedSourceDocumentCount = 33,
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
$scriptPath = Join-Path $PSScriptRoot 'c002t_active_switch.py'
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
    '--connection-string', $ConnectionString,
    '--import-key', $ImportKey,
    '--material-batch-key', $MaterialBatchKey,
    '--report-path', $ReportPath,
    '--expected-source-document-count', $ExpectedSourceDocumentCount
)

if (-not [string]::IsNullOrWhiteSpace($BackupManifest)) {
    $args += @('--backup-manifest', $BackupManifest)
}
if ($Apply) {
    $args += '--apply'
}

Push-Location $repoRoot
try {
    python @args
    if ($LASTEXITCODE -ne 0) {
        throw "C002T active switch failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
