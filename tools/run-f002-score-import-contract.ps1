param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $OutputRoot = 'tmp\f002-score-import',
    [string] $Report = 'docs\evidence\f002-score-import-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw "DatabasePassword or PGPASSWORD is required for F002 score import contract"
}

Push-Location $repoRoot
try {
    python tools\f002_score_import_fixture.py --output-root $OutputRoot --report $Report | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "F002 synthetic fixture generation failed" }

    $reportObject = Get-Content -LiteralPath $Report -Raw | ConvertFrom-Json
    if ($reportObject.status -ne 'pass') { throw "F002 fixture report status is not pass" }
    if ($reportObject.mode -ne 'draft_test') { throw "F002 must stay draft_test" }
    if ($reportObject.productionEligible) { throw "F002 must not be production eligible" }
    if ($reportObject.realStudentDataUsed) { throw "F002 must not use real student data" }
    if ($reportObject.importedCount -ne 2) { throw "F002 imported count mismatch" }
    if ($reportObject.errorCount -ne 1) { throw "F002 error count mismatch" }
    if (-not (Test-Path -LiteralPath $reportObject.workbookPath)) { throw "F002 workbook missing" }
    if (-not (Test-Path -LiteralPath $reportObject.mappingPath)) { throw "F002 mapping file missing" }

    $previousConnectionString = $env:KQG_CONNECTION_STRING
    $previousPgPassword = $env:PGPASSWORD
    $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
    $env:PGPASSWORD = $DatabasePassword

    try {
        dotnet ef database update --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "dotnet ef database update failed" }

        $psql = Join-Path $PgBin 'psql.exe'
        $missingTables = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "select count(*) from (values ('score_import_templates'),('score_import_batches'),('score_records'),('item_scores')) as expected(table_name) where not exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = expected.table_name);"
        if ($LASTEXITCODE -ne 0) { throw "F002 table query failed" }
        if ([int](($missingTables | Select-Object -First 1).Trim()) -ne 0) { throw "F002 score import tables are missing" }

        $constraintCount = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "select count(*) from pg_constraint where conname in ('ck_score_import_templates_production_guard','ck_score_import_batches_pii_guard','ck_score_import_batches_counts','ck_score_records_pii_guard','ck_score_records_scores','ck_item_scores_scores');"
        if ($LASTEXITCODE -ne 0) { throw "F002 constraint query failed" }
        if ([int](($constraintCount | Select-Object -First 1).Trim()) -ne 6) { throw "F002 required constraints are missing" }

        $errorSummaryJson = ($reportObject.errors | ConvertTo-Json -Depth 8 -Compress).Replace("'", "''")
        $rawRow1 = ($reportObject.importedRows[0].raw | ConvertTo-Json -Depth 8 -Compress).Replace("'", "''")
        $rawRow2 = ($reportObject.importedRows[1].raw | ConvertTo-Json -Depth 8 -Compress).Replace("'", "''")
        $mappingJson = (Get-Content -LiteralPath $reportObject.mappingPath -Raw).Replace("'", "''")

        $sql = @"
begin;
with
template_fixture as (
    insert into score_import_templates (
        template_key, display_name, version, mode, production_eligible,
        synthetic_fixture, review_status, field_mapping, migration_policy, created_at, updated_at
    )
    values (
        'f002-synthetic-score-template-' || gen_random_uuid(),
        'F002 synthetic Excel score mapping',
        1,
        'draft_test',
        false,
        true,
        'pending_review',
        '$mappingJson'::jsonb,
        '{"dynamicAsset":"excel_score_field_mapping","requiresRollbackSnapshot":true}'::jsonb,
        now(),
        now()
    )
    returning id
),
student_one as (
    insert into students (student_key, display_code, stage, grade, synthetic_fixture, contains_student_pii, anonymization_status, student_portal_enabled, metadata, created_at, updated_at)
    values ('syn-student-001-' || gen_random_uuid(), 'SYN-001', 'junior_middle_school', 'grade_8', true, false, 'synthetic', false, '{"fixture":"F002"}'::jsonb, now(), now())
    returning id, student_key
),
student_two as (
    insert into students (student_key, display_code, stage, grade, synthetic_fixture, contains_student_pii, anonymization_status, student_portal_enabled, metadata, created_at, updated_at)
    values ('syn-student-002-' || gen_random_uuid(), 'SYN-002', 'junior_middle_school', 'grade_8', true, false, 'synthetic', false, '{"fixture":"F002"}'::jsonb, now(), now())
    returning id, student_key
),
class_fixture as (
    insert into class_groups (class_key, display_name, stage, grade, school_year, synthetic_fixture, contains_student_pii, anonymization_status, metadata, created_at, updated_at)
    values ('f002-synthetic-class-' || gen_random_uuid(), '八年级 synthetic 成绩导入班', 'junior_middle_school', 'grade_8', '2026', true, false, 'synthetic', '{"fixture":"F002"}'::jsonb, now(), now())
    returning id
),
assessment_fixture as (
    insert into assessments (assessment_key, title, subject, stage, grade, status, mode, production_eligible, synthetic_fixture, contains_student_pii, anonymization_status, student_portal_enabled, blueprint, metadata, created_at, updated_at)
    values ('f002-synthetic-assessment-' || gen_random_uuid(), 'F002 synthetic score import assessment', 'physics', 'junior_middle_school', 'grade_8', 'draft', 'draft_test', false, true, false, 'synthetic', false, '{"items":[{"questionNo":"q1","score":3},{"questionNo":"q2","score":5}]}'::jsonb, '{"fixture":"F002"}'::jsonb, now(), now())
    returning id
),
batch_fixture as (
    insert into score_import_batches (
        assessment_id, template_id, mode, status, source_file_name, production_eligible,
        synthetic_fixture, contains_student_pii, row_count, imported_count, error_count, error_summary, metadata, created_at
    )
    select assessment_fixture.id, template_fixture.id, 'draft_test', 'imported', 'f002-synthetic-score-template.xlsx', false, true, false, 3, 2, 1, '$errorSummaryJson'::jsonb, '{"fixture":"F002"}'::jsonb, now()
    from assessment_fixture, template_fixture
    returning id, assessment_id
),
record_one as (
    insert into score_records (assessment_id, student_id, import_batch_id, student_key, total_score, max_score, status, synthetic_fixture, contains_student_pii, raw_row, created_at)
    select batch_fixture.assessment_id, student_one.id, batch_fixture.id, student_one.student_key, 8, 8, 'imported', true, false, '$rawRow1'::jsonb, now()
    from batch_fixture, student_one
    returning id
),
record_two as (
    insert into score_records (assessment_id, student_id, import_batch_id, student_key, total_score, max_score, status, synthetic_fixture, contains_student_pii, raw_row, created_at)
    select batch_fixture.assessment_id, student_two.id, batch_fixture.id, student_two.student_key, 6, 8, 'imported', true, false, '$rawRow2'::jsonb, now()
    from batch_fixture, student_two
    returning id
),
item_insert as (
    insert into item_scores (score_record_id, question_no, field_name, score, max_score, metadata, created_at)
    select id, 'q1', 'q1_score', 3, 3, '{"fixture":"F002"}'::jsonb, now() from record_one
    union all select id, 'q2', 'q2_score', 5, 5, '{"fixture":"F002"}'::jsonb, now() from record_one
    union all select id, 'q1', 'q1_score', 2, 3, '{"fixture":"F002"}'::jsonb, now() from record_two
    union all select id, 'q2', 'q2_score', 4, 5, '{"fixture":"F002"}'::jsonb, now() from record_two
    returning id
)
select
    (select count(*) from template_fixture) as templates,
    (select count(*) from batch_fixture) as batches,
    (select count(*) from record_one) + (select count(*) from record_two) as score_records,
    (select count(*) from item_insert) as item_scores,
    (select count(*) from score_import_batches where mode = 'draft_test' and production_eligible) as unsafe_batches,
    (select count(*) from score_records where contains_student_pii) as pii_records;
rollback;
"@

        $row = $sql | & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -F '|' -v ON_ERROR_STOP=1
        if ($LASTEXITCODE -ne 0) { throw "F002 synthetic DB import transaction failed" }
        $parts = (($row | Where-Object { $_ -match '\|' } | Select-Object -Last 1) -split '\|')
        if ($parts.Count -ne 6) { throw "F002 DB fixture output was incomplete" }
        if ($parts[0] -ne '1' -or $parts[1] -ne '1' -or $parts[2] -ne '2' -or $parts[3] -ne '4') {
            throw "F002 DB fixture did not cover template/batch/records/item scores"
        }
        if ($parts[4] -ne '0') { throw "F002 draft score import was production eligible" }
        if ($parts[5] -ne '0') { throw "F002 score records contain PII" }

        $reportObject | Add-Member -NotePropertyName dbContract -NotePropertyValue ([ordered]@{
            tables = @('score_import_templates', 'score_import_batches', 'score_records', 'item_scores')
            requiredConstraintCount = [int](($constraintCount | Select-Object -First 1).Trim())
            templates = [int]$parts[0]
            batches = [int]$parts[1]
            scoreRecords = [int]$parts[2]
            itemScores = [int]$parts[3]
            unsafeBatches = [int]$parts[4]
            piiRecords = [int]$parts[5]
            rollback = 'transaction_rollback'
        })
        $reportObject | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Report -Encoding utf8
        $reportObject | ConvertTo-Json -Depth 12
    }
    finally {
        $env:KQG_CONNECTION_STRING = $previousConnectionString
        $env:PGPASSWORD = $previousPgPassword
    }
}
finally {
    Pop-Location
}
