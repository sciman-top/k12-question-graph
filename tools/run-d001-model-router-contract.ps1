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
    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','-c','Release','--no-build','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

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
        if ($knowledge.modelRole -ne 'bulk_structuring' -or $knowledge.modelName -ne 'gpt-5.6-terra' -or $knowledge.reasoningEffort -ne 'high') {
            throw "knowledge route default tier mismatch"
        }
        if ($knowledge.escalateToRole -ne 'general_semantics' -or $knowledge.escalateToModel -ne 'gpt-5.6-sol' -or $knowledge.escalateReasoningEffort -ne 'medium') {
            throw "knowledge route semantic escalation mismatch"
        }
        if (-not $knowledge.escalated -or $knowledge.effectiveModelName -ne 'gpt-5.6-sol' -or $knowledge.effectiveReasoningEffort -ne 'medium') {
            throw "balanced low-confidence knowledge route must use its effective escalation"
        }
        if ($knowledge.escalationReasons -notcontains 'low_confidence') { throw "knowledge route escalation reason mismatch" }
        foreach ($blocker in @('real_model_calls_disabled','formal_active_domain_asset_required')) {
            if ($knowledge.blockers -notcontains $blocker) { throw "missing D001 blocker: $blocker" }
        }

        $cropBody = [ordered]@{
            taskType = 'crop_candidate_generation'
            mode = 'high_accuracy'
            assetStatus = 'draft'
            expectedConfidence = 0.95
        } | ConvertTo-Json
        $crop = Invoke-RestMethod -Method Post -Uri "$apiUrl/internal/ai/model-route" -ContentType 'application/json' -Body $cropBody
        if ($crop.stage -ne 'cutting') { throw "crop route must be in cutting stage" }
        if ($crop.modelRole -ne 'visual_document') { throw "crop route must use visual_document role" }
        if ($crop.modelName -ne 'gpt-5.6-terra') { throw "crop route model mismatch" }
        if ($crop.reasoningEffort -ne 'xhigh') { throw "crop route reasoning mismatch" }
        if (-not $crop.schemaExists) { throw "crop route schema missing" }
        if ($crop.escalateToModel -ne 'gpt-5.6-sol' -or $crop.escalateReasoningEffort -ne 'xhigh') {
            throw "crop route semantic escalation mismatch"
        }
        if ($crop.escalated) { throw "strong crop route must not escalate without an allowed risk signal" }

        $cropRiskBody = [ordered]@{
            taskType = 'crop_candidate_generation'
            mode = 'balanced'
            assetStatus = 'draft'
            expectedConfidence = 0.95
            riskSignals = [ordered]@{ semanticConflict = $true }
        } | ConvertTo-Json -Depth 4
        $cropRisk = Invoke-RestMethod -Method Post -Uri "$apiUrl/internal/ai/model-route" -ContentType 'application/json' -Body $cropRiskBody
        if (-not $cropRisk.escalated -or $cropRisk.effectiveModelName -ne 'gpt-5.6-sol' -or $cropRisk.escalationReasons -notcontains 'semantic_conflict') {
            throw "crop semantic conflict must select the effective Sol escalation"
        }

        $paperBody = [ordered]@{
            taskType = 'paper_composition'
            mode = 'high_accuracy'
            assetStatus = 'draft'
            expectedConfidence = 0.9
        } | ConvertTo-Json
        $paper = Invoke-RestMethod -Method Post -Uri "$apiUrl/internal/ai/model-route" -ContentType 'application/json' -Body $paperBody
        if ($paper.stage -ne 'assembly') { throw "paper route must be in assembly stage" }
        if ($paper.modelRole -ne 'semantic_decision') { throw "paper route must use semantic_decision role" }
        if ($paper.modelName -ne 'gpt-5.6-sol') { throw "paper route model mismatch" }
        if ($paper.reasoningEffort -ne 'xhigh') { throw "paper route reasoning mismatch" }
        if (-not $paper.schemaExists) { throw "paper route schema missing" }

        $dedupBody = [ordered]@{
            taskType = 'file_dedup'
            mode = 'low_cost'
            assetStatus = 'active'
            expectedConfidence = 1.0
        } | ConvertTo-Json
        $dedup = Invoke-RestMethod -Method Post -Uri "$apiUrl/internal/ai/model-route" -ContentType 'application/json' -Body $dedupBody
        if ($dedup.modelRole -ne 'local_deterministic' -or $dedup.modelName -ne 'none' -or $dedup.reasoningEffort -ne 'none') {
            throw "deterministic ingest route must not use an external model"
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
            businessRoutes = [ordered]@{
                knowledge = "$($knowledge.modelName)/$($knowledge.reasoningEffort)"
                knowledgeEffective = "$($knowledge.effectiveModelName)/$($knowledge.effectiveReasoningEffort)"
                crop = "$($crop.modelName)/$($crop.reasoningEffort)"
                cropRiskEffective = "$($cropRisk.effectiveModelName)/$($cropRisk.effectiveReasoningEffort)"
                paper = "$($paper.modelName)/$($paper.reasoningEffort)"
                deterministic = "$($dedup.modelName)/$($dedup.reasoningEffort)"
            }
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
