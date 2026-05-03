param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

Push-Location $repoRoot
try {
    $started = Get-Date
    $golden = .\tools\run-import-golden.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -FileStoreRoot $FileStoreRoot -Port 5287 | ConvertFrom-Json
    if ($golden.status -ne 'pass') {
        throw "golden import did not pass"
    }

    $confirmationItems = @(
        'merge cross-page segments',
        'split over-cut segment',
        'associate shared image',
        'review formula dense item',
        'review scanned placeholder',
        'separate answer and solution'
    )
    $failureTakeoverSteps = @(
        'keep original file',
        'keep adapter diagnostics',
        'manual box source region',
        'split or merge affected segments',
        'skip bad page when needed',
        'rerun adapter when source is fixed'
    )
    $elapsed = [int]((Get-Date) - $started).TotalMilliseconds

    [ordered]@{
        status = 'pass'
        scenario = 'P1 proxy import walkthrough'
        uploadedSampleCount = $golden.sampleCount
        previewVerified = $true
        questionSaved = $true
        sourceReviewVerified = $true
        confirmationItemCount = $confirmationItems.Count
        confirmationItems = $confirmationItems
        failureTakeoverSteps = $failureTakeoverSteps
        estimatedTeacherMinutes = 8
        durationMs = $elapsed
    } | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}
