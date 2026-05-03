param(
    [string] $ApiProject = 'apps\api\K12QuestionGraph.Api.csproj'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

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

function Wait-ApiHealth([System.Diagnostics.Process] $Process, [string] $ApiUrl, [string] $LogErr) {
    for ($i = 0; $i -lt 30; $i++) {
        if ($Process.HasExited) {
            throw "API exited before health check on $ApiUrl; see $LogErr"
        }

        try {
            $health = Invoke-RestMethod -Uri "$ApiUrl/health" -TimeoutSec 2
            if ($health.status -eq 'ok') {
                return
            }
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    throw "API did not become healthy on $ApiUrl"
}

Push-Location $repoRoot
try {
    $app = Get-Content -LiteralPath 'apps\web\src\App.tsx' -Raw
    foreach ($pattern in @(
        'data-flow="paper-request-understanding"',
        'data-contract="synthetic-paper-request"',
        'data-contract="paper-understanding"',
        'data-contract="blueprint-draft"',
        'data-contract="paper-review-questions"',
        'productionEligible=false',
        'draft_test'
    )) {
        if (-not $app.Contains($pattern)) {
            throw "missing E002 UI contract marker: $pattern"
        }
    }

    $port = Get-FreeTcpPort
    $apiUrl = "http://127.0.0.1:$port"
    $logOut = Join-Path $repoRoot 'docs\evidence\e002-gate-api.out.log'
    $logErr = Join-Path $repoRoot 'docs\evidence\e002-gate-api.err.log'
    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project',$ApiProject,'--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

    try {
        Wait-ApiHealth -Process $process -ApiUrl $apiUrl -LogErr $logErr

        $body = [ordered]@{
            teacherRequest = '八年级物理，牛顿第一定律与惯性，单选 5 题、计算 2 题、实验 1 题，总分 30 分，难度中等'
            textbookVersion = 'draft_test'
        } | ConvertTo-Json
        $parsed = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-requests/parse" -ContentType 'application/json' -Body $body

        if ($parsed.mode -ne 'draft_test') { throw "E002 parse must stay draft_test" }
        if ($parsed.productionEligible) { throw "E002 parse must not be production eligible" }
        if ($parsed.allowRealModelCalls) { throw "E002 parse must not allow real model calls" }
        if ($parsed.schemaVersion -ne 'schemas/ai/natural_language_paper_request.schema.json') { throw "E002 schema version mismatch" }
        if ([string]::IsNullOrWhiteSpace($parsed.systemUnderstanding)) { throw "E002 system understanding missing" }
        if (@($parsed.blueprint).Count -lt 3) { throw "E002 blueprint draft too small" }
        if (@($parsed.reviewQuestions).Count -lt 1) { throw "E002 review questions missing" }
        if ($parsed.constraints.knowledgeStatus -ne 'draft') { throw "E002 must use draft dynamic assets" }
        if (-not $parsed.constraints.blocksProductionPaper) { throw "E002 must block production paper semantics" }

        [ordered]@{
            status = 'pass'
            mode = [string]$parsed.mode
            productionEligible = [bool]$parsed.productionEligible
            allowRealModelCalls = [bool]$parsed.allowRealModelCalls
            schemaVersion = [string]$parsed.schemaVersion
            totalScore = [int]$parsed.totalScore
            blueprintRows = @($parsed.blueprint).Count
            reviewQuestions = @($parsed.reviewQuestions).Count
            knowledgeStatus = [string]$parsed.constraints.knowledgeStatus
        } | ConvertTo-Json
    }
    finally {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
}
finally {
    Pop-Location
}
