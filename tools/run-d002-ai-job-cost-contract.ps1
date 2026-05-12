param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw "DatabasePassword or PGPASSWORD is required for D002 AI job cost contract"
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
        dotnet ef database update --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj --configuration Release --no-build | Write-Host
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet ef database update failed"
        }

        $port = Get-FreeTcpPort
        $apiUrl = "http://127.0.0.1:$port"
        $logOut = Join-Path $repoRoot 'docs\evidence\d002-gate-api.out.log'
        $logErr = Join-Path $repoRoot 'docs\evidence\d002-gate-api.err.log'
        $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','-c','Release','--no-build','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

        try {
            Wait-ApiReady -Process $process -ApiUrl $apiUrl -LogErr $logErr

            $input = [ordered]@{
                questionId = "d002-contract"
                text = "请判断该题的知识点候选。"
                source = "synthetic"
            } | ConvertTo-Json
            $idempotencyKey = "d002-contract-$([Guid]::NewGuid())"
            $body = [ordered]@{
                taskType = 'knowledge_tagging'
                mode = 'balanced'
                assetStatus = 'draft'
                expectedConfidence = 0.76
                inputJson = $input
                idempotencyKey = $idempotencyKey
            } | ConvertTo-Json

            $created = Invoke-RestMethod -Method Post -Uri "$apiUrl/internal/ai/jobs/stub" -ContentType 'application/json' -Body $body
            $duplicate = Invoke-RestMethod -Method Post -Uri "$apiUrl/internal/ai/jobs/stub" -ContentType 'application/json' -Body $body

            if ($created.id -ne $duplicate.id) { throw "AI job idempotency failed" }
            if ($created.status -ne 'succeeded') { throw "AI job did not succeed" }
            if ($created.modelProvider -ne 'stub_llm') { throw "AI job must use stub_llm" }
            if ($created.modelName -ne 'stub') { throw "AI job must record modelName" }
            if ([string]::IsNullOrWhiteSpace($created.routingVersion)) { throw "AI job missing routingVersion" }
            if ([string]::IsNullOrWhiteSpace($created.promptVersion)) { throw "AI job missing promptVersion" }
            if ([string]::IsNullOrWhiteSpace($created.schemaVersion)) { throw "AI job missing schemaVersion" }
            if ([string]::IsNullOrWhiteSpace($created.inputHash)) { throw "AI job missing inputHash" }
            if ($created.actualCost -ne 0) { throw "stub AI job must have zero actual cost" }
            if ($created.confidence -lt 0 -or $created.confidence -gt 1) { throw "confidence out of range" }
            if ($created.inputTokens -lt 1 -or $created.outputTokens -lt 1) { throw "token counts were not recorded" }
            if ($created.cachedTokens -ne 0) { throw "stub cachedTokens must be zero" }
            if ($created.latencyMs -lt 0) { throw "latencyMs must be non-negative" }
            if ($created.reviewStatus -ne 'pending_review') { throw "stub LLM result must stay pending_review" }
            if ($created.teacherModified) { throw "new stub AI job should not be teacherModified" }

            $psql = Join-Path $PgBin 'psql.exe'
            $row = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -F '|' -v ON_ERROR_STOP=1 -c "select model_provider, model_name, routing_version, prompt_version, schema_version, input_hash, input_tokens, output_tokens, cached_tokens, actual_cost, review_status from ai_jobs where id = '$($created.id)';"
            if ($LASTEXITCODE -ne 0) { throw "AI job DB query failed" }
            $parts = (($row | Select-Object -First 1) -split '\|')
            if ($parts.Count -lt 11) { throw "AI job DB row was incomplete" }
            if ($parts[0] -ne 'stub_llm') { throw "AI job DB provider mismatch" }
            if ($parts[10] -ne 'pending_review') { throw "AI job DB review status mismatch" }

            [ordered]@{
                status = 'pass'
                jobId = [string]$created.id
                idempotency = 'pass'
                modelProvider = [string]$created.modelProvider
                modelName = [string]$created.modelName
                promptVersion = [string]$created.promptVersion
                schemaVersion = [string]$created.schemaVersion
                inputTokens = [int]$created.inputTokens
                outputTokens = [int]$created.outputTokens
                cachedTokens = [int]$created.cachedTokens
                actualCost = [decimal]$created.actualCost
                confidence = [decimal]$created.confidence
                reviewStatus = [string]$created.reviewStatus
            } | ConvertTo-Json
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
