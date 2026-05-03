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

function Wait-ApiStarted([System.Diagnostics.Process] $Process, [string] $ApiUrl, [string] $LogErr) {
    for ($i = 0; $i -lt 30; $i++) {
        if ($Process.HasExited) {
            throw "API exited before ready on $ApiUrl; see $LogErr"
        }

        try {
            Invoke-RestMethod -Uri "$ApiUrl/health" -TimeoutSec 2 | Out-Null
            return
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    throw "API did not start on $ApiUrl"
}

Push-Location $repoRoot
try {
    $port = Get-FreeTcpPort
    $apiUrl = "http://127.0.0.1:$port"
    $logOut = Join-Path $repoRoot 'docs\evidence\d001-gate-api.out.log'
    $logErr = Join-Path $repoRoot 'docs\evidence\d001-gate-api.err.log'
    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

    try {
        Wait-ApiStarted -Process $process -ApiUrl $apiUrl -LogErr $logErr

        $providers = Invoke-RestMethod -Method Get -Uri "$apiUrl/internal/ai/providers"
        $stubProvider = @($providers | Where-Object { $_.providerId -eq 'stub_llm' }) | Select-Object -First 1
        if ($null -eq $stubProvider) { throw "stub_llm provider is not registered" }
        if ($stubProvider.supportsRealModelCalls) { throw "stub_llm must not support real model calls" }

        $knowledgeBody = [ordered]@{
            taskType = 'knowledge_tagging'
            mode = 'balanced'
            assetStatus = 'draft'
            expectedConfidence = 0.76
        } | ConvertTo-Json
        $knowledge = Invoke-RestMethod -Method Post -Uri "$apiUrl/internal/ai/model-route" -ContentType 'application/json' -Body $knowledgeBody

        if ($knowledge.status -ne 'pass') { throw "knowledge route did not pass" }
        if ($knowledge.provider -ne 'stub_llm') { throw "knowledge route must use stub_llm while real model calls are disabled" }
        if ($knowledge.allowRealModelCalls) { throw "real model calls must stay disabled for D001 draft/test" }
        if ($knowledge.productionEligible) { throw "draft knowledge route must not be production eligible" }
        if (-not $knowledge.requiresHumanReview) { throw "LLM route must require human review in D001 draft/test" }
        if (-not $knowledge.schemaExists) { throw "knowledge mapping schema missing" }
        foreach ($blocker in @('real_model_calls_disabled','formal_active_domain_asset_required')) {
            if ($knowledge.blockers -notcontains $blocker) { throw "missing D001 blocker: $blocker" }
        }

        $ruleBody = [ordered]@{
            taskType = 'file_dedup'
            mode = 'low_cost'
            assetStatus = 'active'
            expectedConfidence = 1.0
        } | ConvertTo-Json
        $rule = Invoke-RestMethod -Method Post -Uri "$apiUrl/internal/ai/model-route" -ContentType 'application/json' -Body $ruleBody

        if ($rule.handler -ne 'rule') { throw "file_dedup must route to rule handler" }
        if ($rule.provider -ne 'rule') { throw "file_dedup provider must remain rule" }
        if ($rule.costTier -ne 'none') { throw "rule route must have no model cost" }
        if (-not $rule.productionEligible) { throw "rule route should be production eligible when active assets are used" }

        $badBody = [ordered]@{
            taskType = 'unknown_ai_task'
            mode = 'balanced'
            assetStatus = 'draft'
        } | ConvertTo-Json
        try {
            Invoke-RestMethod -Method Post -Uri "$apiUrl/internal/ai/model-route" -ContentType 'application/json' -Body $badBody | Out-Null
            throw "unknown task was accepted"
        }
        catch {
            if ($_.Exception.Response.StatusCode.value__ -ne 400) {
                throw
            }
        }

        [ordered]@{
            status = 'pass'
            routingVersion = $knowledge.routingVersion
            allowRealModelCalls = $knowledge.allowRealModelCalls
            providerRegistered = $true
            draftKnowledgeProvider = $knowledge.provider
            draftKnowledgeProductionEligible = $knowledge.productionEligible
            ruleProvider = $rule.provider
            unknownTaskRejected = $true
        } | ConvertTo-Json
    }
    finally {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
}
finally {
    Pop-Location
}
