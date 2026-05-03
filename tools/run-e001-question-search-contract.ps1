param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw "DatabasePassword or PGPASSWORD is required for E001 question search contract"
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 0)
    try {
        $listener.Start()
        return $listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

function Wait-ApiReady([System.Diagnostics.Process] $Process, [string] $ApiUrl, [string] $LogErr) {
    for ($i = 0; $i -lt 30; $i++) {
        if ($Process.HasExited) {
            throw "API exited before ready on $ApiUrl; see $LogErr"
        }

        try {
            $health = Invoke-RestMethod -Uri "$ApiUrl/health/ready" -TimeoutSec 2
            if ($health.status -eq 'ok') {
                return
            }
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    throw "API did not become ready on $ApiUrl"
}

Push-Location $repoRoot
try {
    $previousConnectionString = $env:KQG_CONNECTION_STRING
    $previousPgPassword = $env:PGPASSWORD
    $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
    $env:PGPASSWORD = $DatabasePassword

    try {
        dotnet ef database update --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj | Write-Host
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet ef database update failed"
        }

        .\tools\seed-knowledge.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host

        $psql = Join-Path $PgBin 'psql.exe'
        $knowledgeId = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "select id from knowledge_nodes where code = 'PHY-JH-MECH-FORCE-NEWTON1' and version = 1;"
        if ($LASTEXITCODE -ne 0) { throw "knowledge node query failed" }
        $knowledgeId = ($knowledgeId | Select-Object -First 1).Trim()
        if ([string]::IsNullOrWhiteSpace($knowledgeId)) { throw "E001 knowledge node fixture missing" }

        $port = Get-FreeTcpPort
        $apiUrl = "http://127.0.0.1:$port"
        $logOut = Join-Path $repoRoot 'docs\evidence\e001-gate-api.out.log'
        $logErr = Join-Path $repoRoot 'docs\evidence\e001-gate-api.err.log'
        $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

        try {
            Wait-ApiReady -Process $process -ApiUrl $apiUrl -LogErr $logErr

            $sample = Join-Path $env:TEMP 'kqg-e001-search-source.txt'
            Set-Content -LiteralPath $sample -Value "E001 question search synthetic source $([Guid]::NewGuid())" -Encoding UTF8
            $upload = curl.exe -s -F "file=@$sample;filename=e001-search-source.txt" -F "sourceType=synthetic" -F "sourceTitle=E001 Search Synthetic Source" -F "ownerScope=school" -F "licenseOrPermission=synthetic_fixture" -F "sharingAllowed=true" -F "containsStudentPii=false" -F "anonymizationStatus=synthetic" "$apiUrl/files" | ConvertFrom-Json

            $regionBody = [ordered]@{
                pageNumber = 1
                x = 12
                y = 16
                width = 60
                height = 20
                coordinateUnit = 'percent'
                screenshotRelativePath = $null
                regionType = 'question'
            } | ConvertTo-Json
            $region = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$($upload.sourceDocument.id)/regions" -ContentType 'application/json' -Body $regionBody

            $questionBody = [ordered]@{
                subject = 'physics'
                stage = 'junior_middle_school'
                grade = 'grade_8'
                questionType = 'single_choice'
                defaultScore = 3
                difficultyEstimated = 0.62
                status = 'draft'
                primaryKnowledgeId = $knowledgeId
                blocks = @(
                    [ordered]@{ blockType = 'text'; sortOrder = 0; content = [ordered]@{ text = '关于惯性的说法，下列哪项正确？' }; sourceRegionId = $region.id },
                    [ordered]@{ blockType = 'option'; sortOrder = 1; content = [ordered]@{ key = 'A'; text = '惯性只和速度有关' }; sourceRegionId = $region.id },
                    [ordered]@{ blockType = 'answer'; sortOrder = 2; content = [ordered]@{ answer = 'B' }; sourceRegionId = $region.id }
                )
                assets = @()
                answer = [ordered]@{ value = 'B' }
                solution = [ordered]@{ text = '惯性是物体保持原有运动状态的性质。' }
            } | ConvertTo-Json -Depth 8
            $created = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionBody

            $searchUri = "$apiUrl/questions?subject=physics&stage=junior_middle_school&grade=grade_8&questionType=single_choice&status=draft&primaryKnowledgeId=$knowledgeId&difficultyMin=0.4&difficultyMax=0.7&sourceType=synthetic&limit=10"
            $search = Invoke-RestMethod -Method Get -Uri $searchUri
            if ($search.mode -ne 'draft_test') { throw "E001 search must stay draft_test while formal C002 is pending" }
            if ($search.productionEligible) { throw "E001 search must not be production eligible while formal C002 is pending" }

            $card = @($search.items | Where-Object { $_.id -eq $created.id }) | Select-Object -First 1
            if ($null -eq $card) { throw "E001 search did not return created question" }
            if ($card.primaryKnowledge.id -ne $knowledgeId) { throw "E001 question card missing primary knowledge" }
            if ($card.primaryKnowledge.status -ne 'draft') { throw "E001 draft knowledge boundary missing" }
            if ($card.questionType -ne 'single_choice') { throw "E001 question type filter failed" }
            if ($card.difficultyEstimated -lt 0.4 -or $card.difficultyEstimated -gt 0.7) { throw "E001 difficulty filter failed" }
            if (@($card.sources.types) -notcontains 'synthetic') { throw "E001 source type summary missing" }
            if ([string]::IsNullOrWhiteSpace($card.preview)) { throw "E001 question card preview missing" }

            $miss = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&grade=grade_8&questionType=single_choice&status=draft&primaryKnowledgeId=$knowledgeId&difficultyMin=0.9&difficultyMax=1.0&sourceType=synthetic&limit=10"
            $missedCard = @($miss.items | Where-Object { $_.id -eq $created.id }) | Select-Object -First 1
            if ($null -ne $missedCard) { throw "E001 difficulty miss filter returned created question" }

            [ordered]@{
                status = 'pass'
                mode = [string]$search.mode
                productionEligible = [bool]$search.productionEligible
                questionId = [string]$created.id
                primaryKnowledgeId = [string]$card.primaryKnowledge.id
                primaryKnowledgeStatus = [string]$card.primaryKnowledge.status
                sourceTypes = @($card.sources.types)
                preview = [string]$card.preview
            } | ConvertTo-Json -Depth 6
        }
        finally {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    finally {
        $env:KQG_CONNECTION_STRING = $previousConnectionString
        $env:PGPASSWORD = $previousPgPassword
    }
}
finally {
    Pop-Location
}
