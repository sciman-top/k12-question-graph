param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $Report = 'docs\evidence\f001-assessment-model-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw "DatabasePassword or PGPASSWORD is required for F001 assessment model contract"
}

Push-Location $repoRoot
try {
    $previousConnectionString = $env:KQG_CONNECTION_STRING
    $previousPgPassword = $env:PGPASSWORD
    $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
    $env:PGPASSWORD = $DatabasePassword

    try {
        dotnet ef database update --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj --configuration Release --no-build | Write-Host
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet ef database update failed"
        }

        $psql = Join-Path $PgBin 'psql.exe'
        $missingTables = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "select count(*) from (values ('students'),('class_groups'),('assessments'),('assessment_enrollments')) as expected(table_name) where not exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = expected.table_name);"
        if ($LASTEXITCODE -ne 0) { throw "F001 table query failed" }
        if ([int](($missingTables | Select-Object -First 1).Trim()) -ne 0) { throw "F001 tables are missing" }

        $constraintCount = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "select count(*) from pg_constraint where conname in ('ck_students_no_portal_for_synthetic','ck_students_pii_guard','ck_class_groups_pii_guard','ck_assessments_production_guard','ck_assessments_no_portal_for_draft','ck_assessment_enrollments_pii_guard');"
        if ($LASTEXITCODE -ne 0) { throw "F001 constraint query failed" }
        if ([int](($constraintCount | Select-Object -First 1).Trim()) -ne 6) { throw "F001 required privacy/production constraints are missing" }

        $sql = @'
begin;
with
student_fixture as (
    insert into students (
        student_key,
        display_code,
        stage,
        grade,
        synthetic_fixture,
        contains_student_pii,
        anonymization_status,
        student_portal_enabled,
        metadata,
        created_at,
        updated_at
    )
    values (
        'f001-synthetic-student-' || gen_random_uuid(),
        'SYN-001',
        'junior_middle_school',
        'grade_8',
        true,
        false,
        'synthetic',
        false,
        '{"fixture":"F001","realStudentData":false}'::jsonb,
        now(),
        now()
    )
    returning id
),
class_fixture as (
    insert into class_groups (
        class_key,
        display_name,
        stage,
        grade,
        school_year,
        synthetic_fixture,
        contains_student_pii,
        anonymization_status,
        metadata,
        created_at,
        updated_at
    )
    values (
        'f001-synthetic-class-' || gen_random_uuid(),
        '八年级 synthetic 班',
        'junior_middle_school',
        'grade_8',
        '2026',
        true,
        false,
        'synthetic',
        '{"fixture":"F001","realClassData":false}'::jsonb,
        now(),
        now()
    )
    returning id
),
assessment_fixture as (
    insert into assessments (
        assessment_key,
        title,
        subject,
        stage,
        grade,
        status,
        mode,
        production_eligible,
        synthetic_fixture,
        contains_student_pii,
        anonymization_status,
        student_portal_enabled,
        blueprint,
        metadata,
        created_at,
        updated_at
    )
    values (
        'f001-synthetic-assessment-' || gen_random_uuid(),
        'F001 synthetic physics assessment',
        'physics',
        'junior_middle_school',
        'grade_8',
        'draft',
        'draft_test',
        false,
        true,
        false,
        'synthetic',
        false,
        '{"items":[{"questionNo":"1","score":3}]}'::jsonb,
        '{"fixture":"F001","realScoreData":false}'::jsonb,
        now(),
        now()
    )
    returning id
),
enrollment_fixture as (
    insert into assessment_enrollments (
        assessment_id,
        class_group_id,
        student_id,
        seat_no,
        status,
        synthetic_fixture,
        contains_student_pii,
        score_summary,
        created_at
    )
    select assessment_fixture.id, class_fixture.id, student_fixture.id, '01', 'enrolled', true, false, '{"totalScore":0,"source":"synthetic"}'::jsonb, now()
    from assessment_fixture, class_fixture, student_fixture
    returning id
)
select
    (select count(*) from student_fixture) as students,
    (select count(*) from class_fixture) as class_groups,
    (select count(*) from assessment_fixture) as assessments,
    (select count(*) from enrollment_fixture) as enrollments,
    (select count(*) from students where synthetic_fixture and contains_student_pii) as pii_students,
    (select count(*) from assessments where mode = 'draft_test' and (production_eligible or student_portal_enabled)) as unsafe_draft_assessments;
rollback;
'@

        $row = $sql | & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -F '|' -v ON_ERROR_STOP=1
        if ($LASTEXITCODE -ne 0) { throw "F001 synthetic fixture transaction failed" }
        $parts = (($row | Where-Object { $_ -match '\|' } | Select-Object -Last 1) -split '\|')
        if ($parts.Count -ne 6) { throw "F001 fixture output was incomplete" }
        if ($parts[0] -ne '1' -or $parts[1] -ne '1' -or $parts[2] -ne '1' -or $parts[3] -ne '1') {
            throw "F001 synthetic fixture did not cover student/class/assessment/enrollment"
        }
        if ($parts[4] -ne '0') { throw "F001 synthetic fixture contains student PII" }
        if ($parts[5] -ne '0') { throw "F001 draft assessment is production eligible or student portal enabled" }

        $program = Get-Content -LiteralPath 'apps\api\Program.cs' -Raw
        foreach ($forbidden in @('MapGet("/students', 'MapPost("/students', 'MapGet("/student-portal', 'MapPost("/student-portal')) {
            if ($program.Contains($forbidden)) {
                throw "F001 must not expose student-facing endpoint: $forbidden"
            }
        }

        $reportObject = [ordered]@{
            status = 'pass'
            task = 'F001'
            mode = 'draft_test'
            productionEligible = $false
            realStudentDataUsed = $false
            studentPortalExposed = $false
            tables = @('students', 'class_groups', 'assessments', 'assessment_enrollments')
            requiredConstraintCount = [int](($constraintCount | Select-Object -First 1).Trim())
            syntheticFixture = [ordered]@{
                students = [int]$parts[0]
                classGroups = [int]$parts[1]
                assessments = [int]$parts[2]
                enrollments = [int]$parts[3]
                piiStudents = [int]$parts[4]
                unsafeDraftAssessments = [int]$parts[5]
                rollback = 'transaction_rollback'
            }
            summaryChinese = [ordered]@{
                title = 'F001 学生/班级/考试模型合同报告'
                result = '通过'
                boundary = '仅使用 synthetic 学生、班级、考试和报名关系；不使用真实学生数据，不暴露学生端。'
            }
        }
        $reportObject | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Report -Encoding utf8
        $reportObject | ConvertTo-Json -Depth 8
    }
    finally {
        $env:KQG_CONNECTION_STRING = $previousConnectionString
        $env:PGPASSWORD = $previousPgPassword
    }
}
finally {
    Pop-Location
}
