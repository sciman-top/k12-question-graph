param(
    [string] $ReportPath = 'docs/evidence/20260528-ns102-migration-baseline.json',
    [string] $Project = 'apps/api/K12QuestionGraph.Api.csproj',
    [string] $StartupProject = 'apps/api/K12QuestionGraph.Api.csproj',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-Capture([string] $FilePath, [string[]] $Arguments) {
    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) { $exitCode = 0 }
    return [ordered]@{
        exitCode = [int]$exitCode
        output = (($output | Select-Object -First 240) -join "`n").Trim()
    }
}

function ConvertFrom-PrefixedJson([string] $Text) {
    $jsonText = (($Text -split "`r?`n") | ForEach-Object { $_ -replace '^data:\s?', '' }) -join "`n"
    return $jsonText | ConvertFrom-Json
}

function Invoke-Psql([string] $Sql) {
    $psqlPath = Join-Path $PgBin 'psql.exe'
    if (-not (Test-Path -LiteralPath $psqlPath)) {
        $command = Get-Command 'psql' -ErrorAction SilentlyContinue
        Assert-Condition ($null -ne $command) 'psql not found in PgBin or PATH'
        $psqlPath = [string]$command.Source
    }

    return Invoke-Capture $psqlPath @(
        '-h', $DatabaseHost,
        '-p', [string]$DatabasePort,
        '-U', $DatabaseUser,
        '-d', $DatabaseName,
        '-At',
        '-F', '|',
        '-c', $Sql
    )
}

Push-Location $repoRoot
try {
    $migrationFiles = @(Get-ChildItem -LiteralPath 'apps/api/Data/Migrations' -Filter '*.cs' |
        Where-Object { $_.Name -notlike '*.Designer.cs' -and $_.Name -ne 'KqgDbContextModelSnapshot.cs' } |
        Sort-Object Name |
        ForEach-Object { $_.BaseName })

    $buildResult = Invoke-Capture 'dotnet' @('build', $Project)
    Assert-Condition ($buildResult.exitCode -eq 0) 'dotnet build failed before migration baseline'

    $efList = Invoke-Capture 'dotnet' @(
        'ef', 'migrations', 'list',
        '--project', $Project,
        '--startup-project', $StartupProject,
        '--configuration', 'Debug',
        '--no-build',
        '--no-connect',
        '--json',
        '--prefix-output'
    )
    Assert-Condition ($efList.exitCode -eq 0) 'dotnet ef migrations list --no-connect failed'
    $availableMigrations = @(ConvertFrom-PrefixedJson $efList.output)
    $availableIds = @($availableMigrations | ForEach-Object { [string]$_.id })

    $appliedResult = Invoke-Psql 'select migration_id from "__EFMigrationsHistory" order by migration_id;'
    Assert-Condition ($appliedResult.exitCode -eq 0) 'failed to query __EFMigrationsHistory'
    $appliedIds = @(($appliedResult.output -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $missingInDatabase = @($availableIds | Where-Object { $appliedIds -notcontains $_ })
    $unknownInDatabase = @($appliedIds | Where-Object { $availableIds -notcontains $_ })
    Assert-Condition ($missingInDatabase.Count -eq 0) "database missing migrations: $($missingInDatabase -join ', ')"
    Assert-Condition ($unknownInDatabase.Count -eq 0) "database has unknown migrations: $($unknownInDatabase -join ', ')"

    $studentPrivacySql = @"
select 'students', count(*), count(*) filter (where contains_student_pii), count(*) filter (where anonymization_status <> 'synthetic') from students
union all select 'class_groups', count(*), count(*) filter (where contains_student_pii), count(*) filter (where anonymization_status <> 'synthetic') from class_groups
union all select 'assessments', count(*), count(*) filter (where contains_student_pii), count(*) filter (where anonymization_status <> 'synthetic') from assessments
union all select 'score_import_batches', count(*), count(*) filter (where contains_student_pii), count(*) filter (where production_eligible) from score_import_batches
union all select 'score_records', count(*), count(*) filter (where contains_student_pii), count(*) filter (where synthetic_fixture = false) from score_records;
"@
    $privacyResult = Invoke-Psql $studentPrivacySql
    Assert-Condition ($privacyResult.exitCode -eq 0) 'student privacy fixture query failed'

    $privacyRows = @()
    foreach ($line in (($privacyResult.output -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $parts = $line -split '\|'
        $privacyRows += [ordered]@{
            table = [string]$parts[0]
            rowCount = [int]$parts[1]
            containsStudentPiiCount = [int]$parts[2]
            nonSyntheticOrProductionCount = [int]$parts[3]
        }
    }

    $piiRows = @($privacyRows | Where-Object { $_.containsStudentPiiCount -gt 0 })
    $nonSyntheticRows = @($privacyRows | Where-Object { $_.nonSyntheticOrProductionCount -gt 0 })
    Assert-Condition ($piiRows.Count -eq 0) 'student privacy baseline found rows with contains_student_pii=true'
    Assert-Condition ($nonSyntheticRows.Count -eq 0) 'student privacy baseline found non-synthetic or production score rows'

    $latestMigration = if ($availableIds.Count -gt 0) { $availableIds[-1] } else { '' }
    $report = [ordered]@{
        status = 'pass'
        task = 'NS102 migration baseline'
        checkedAt = (Get-Date).ToString('s')
        mode = 'read_only'
        project = $Project
        startupProject = $StartupProject
        database = [ordered]@{
            host = $DatabaseHost
            port = $DatabasePort
            name = $DatabaseName
            user = $DatabaseUser
            passwordPrinted = $false
        }
        guardrail = [ordered]@{
            noMigrationApplied = $true
            noSchemaWrite = $true
            noRealStudentDataProcessed = $true
            noExternalAiUsed = $true
        }
        migrationFiles = $migrationFiles
        availableMigrations = $availableIds
        appliedMigrations = $appliedIds
        availableMigrationCount = $availableIds.Count
        appliedMigrationCount = $appliedIds.Count
        latestMigration = $latestMigration
        missingInDatabase = $missingInDatabase
        unknownInDatabase = $unknownInDatabase
        studentPrivacyFixtureCheck = $privacyRows
        buildOutput = $buildResult.output
        efListOutput = $efList.output
        teacherEfficiencyCheck = 'database and migration baseline is current before teacher-facing import, paper, export, and score workflows are advanced'
        rollback = 'git restore tools/run-ns102-migration-baseline.ps1 tasks/non-site-implementation-plan.csv; git clean -f -- docs/evidence/20260528-ns102-migration-baseline.json'
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent (Join-Path $repoRoot $ReportPath)) -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $repoRoot $ReportPath) -Encoding UTF8

    [ordered]@{
        status = $report.status
        task = $report.task
        report = $ReportPath
        availableMigrationCount = $report.availableMigrationCount
        appliedMigrationCount = $report.appliedMigrationCount
        latestMigration = $report.latestMigration
        missingInDatabase = $report.missingInDatabase
        unknownInDatabase = $report.unknownInDatabase
        studentPrivacyFixtureCheck = $report.studentPrivacyFixtureCheck
    } | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

