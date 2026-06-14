using K12QuestionGraph.Api.Ai;
using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.FileStore;
using K12QuestionGraph.Api.ImportJobs;
using K12QuestionGraph.Api.Workers;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Hosting.WindowsServices;
using System.Globalization;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.NamingConventions;

var builder = WebApplication.CreateBuilder(args);
builder.Host.UseWindowsService();

// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();
builder.Services.AddDataProtection();
builder.Services.Configure<KqgPathsOptions>(builder.Configuration.GetSection("KqgPaths"));
builder.Services.Configure<PythonWorkerOptions>(builder.Configuration.GetSection("PythonWorker"));
builder.Services.Configure<AiRoutingOptions>(builder.Configuration.GetSection("AiRouting"));
builder.Services.AddDbContext<KqgDbContext>(options =>
    options
        .UseNpgsql(builder.Configuration.GetKqgConnectionString())
        .UseSnakeCaseNamingConvention());
builder.Services.AddScoped<IFileStore, LocalFileStore>();
builder.Services.AddScoped<IDocumentWorkerClient, DocumentWorkerClient>();
builder.Services.AddScoped<IImportReviewWorkflowService, ImportReviewWorkflowService>();
builder.Services.AddScoped<ICutCandidateGenerationService, CutCandidateGenerationService>();
builder.Services.AddScoped<IPaperWorkflowService, PaperWorkflowService>();
builder.Services.AddScoped<IScoreAnalysisWorkflowService, ScoreAnalysisWorkflowService>();
builder.Services.AddSingleton<IAiModelRouter, AiModelRouter>();
builder.Services.AddSingleton<IAiProvider, StubAiProvider>();
builder.Services.AddSingleton<IAiProviderSettingsStore, FileAiProviderSettingsStore>();
builder.Services.AddHttpClient<IAiProviderSmokeTestService, OpenAiCompatibleSmokeTestService>();

var app = builder.Build();

app.UseAdminInternalEndpointGuard();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.MapGet("/health", (IWebHostEnvironment environment, IConfiguration configuration) =>
{
    var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
    var contentRoot = Path.GetFullPath(environment.ContentRootPath);
    var dataRoot = Path.GetFullPath(paths.DataRoot);

    return Results.Ok(new HealthResponse
    (
        Status: "ok",
        Service: "K12QuestionGraph.Api",
        ContentRoot: contentRoot,
        DataRoot: dataRoot,
        FileStoreRoot: Path.GetFullPath(paths.FileStoreRoot),
        BackupRoot: Path.GetFullPath(paths.BackupRoot),
        LogsRoot: Path.GetFullPath(paths.LogsRoot),
        ProgramDataSeparated: !string.Equals(contentRoot, dataRoot, StringComparison.OrdinalIgnoreCase)
    ));
})
.WithName("Health");

app.MapGet("/health/db", async (KqgDbContext dbContext, CancellationToken cancellationToken) =>
{
    var canConnect = await dbContext.Database.CanConnectAsync(cancellationToken);

    return Results.Ok(new DatabaseHealthResponse
    (
        Status: canConnect ? "ok" : "unavailable",
        Provider: "PostgreSQL",
        CanConnect: canConnect
    ));
})
.WithName("DatabaseHealth");

app.MapGet("/health/ready", async (
    IWebHostEnvironment environment,
    IConfiguration configuration,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    var checks = new List<ReadinessCheck>
    {
        new("api", true, "API process is running")
    };

    checks.Add(await HealthCheckHelpers.CheckDatabaseAsync(dbContext, cancellationToken));

    var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
    checks.Add(HealthCheckHelpers.CheckWritableDirectory("file_store", paths.FileStoreRoot));
    checks.Add(HealthCheckHelpers.CheckWritableDirectory("logs", paths.LogsRoot));

    var workerOptions = configuration.GetSection("PythonWorker").Get<PythonWorkerOptions>() ?? new PythonWorkerOptions();
    var workerScript = WorkerPathHelpers.ResolveWorkerScriptPath(environment.ContentRootPath, workerOptions.DocumentWorkerScript);
    checks.Add(new ReadinessCheck("document_worker_script", File.Exists(workerScript), workerScript));

    var ready = checks.All(x => x.Ok);
    var response = new ReadinessResponse(ready ? "ok" : "unhealthy", checks);

    return ready ? Results.Ok(response) : Results.Json(response, statusCode: StatusCodes.Status503ServiceUnavailable);
})
.WithName("ReadinessHealth");

app.MapGet("/api/admin/storage/summary", (IConfiguration configuration) =>
{
    var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
    var areas = new[]
    {
        StorageHelpers.SummarizeArea("data_root", paths.DataRoot, cleanupAllowed: false),
        StorageHelpers.SummarizeArea("file_store", paths.FileStoreRoot, cleanupAllowed: false),
        StorageHelpers.SummarizeArea("backup", paths.BackupRoot, cleanupAllowed: false),
        StorageHelpers.SummarizeArea("logs", paths.LogsRoot, cleanupAllowed: false),
        StorageHelpers.SummarizeArea("cache", paths.CacheRoot, cleanupAllowed: true)
    };

    return Results.Ok(new StorageSummaryResponse(
        Status: "ok",
        Mode: "draft_test",
        ProductionEligible: false,
        CacheCleanupRoot: Path.GetFullPath(paths.CacheRoot),
        Areas: areas));
})
.WithName("AdminStorageSummary");

app.MapPost("/api/admin/cache/cleanup", (CacheCleanupRequest request, IConfiguration configuration) =>
{
    var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
    var result = StorageHelpers.CleanConfiguredCache(paths.CacheRoot, request);

    return Results.Ok(result);
})
.WithName("AdminCacheCleanup");

app.MapGet("/api/admin/ai/provider-settings", async (
    IAiProviderSettingsStore settingsStore,
    CancellationToken cancellationToken) =>
{
    var settings = await settingsStore.GetAsync(cancellationToken);
    return Results.Ok(settings);
})
.WithName("GetAdminAiProviderSettings");

app.MapPost("/api/admin/ai/provider-settings", async (
    AdminAiProviderSettingsSaveRequest request,
    IAiProviderSettingsStore settingsStore,
    CancellationToken cancellationToken) =>
{
    var result = await settingsStore.SaveAsync(request, cancellationToken);
    return Results.Ok(result);
})
.WithName("SaveAdminAiProviderSettings");

app.MapPost("/api/admin/ai/provider-settings/test", async (
    AdminAiProviderSettingsTestRequest request,
    IAiProviderSettingsStore settingsStore,
    IAiProviderSmokeTestService smokeTestService,
    CancellationToken cancellationToken) =>
{
    var settings = await settingsStore.GetAsync(cancellationToken);
    var result = await smokeTestService.RunAsync(settings, request, cancellationToken);
    return Results.Ok(result);
})
.WithName("TestAdminAiProviderSettings");

app.MapPost("/internal/ai/model-route", (AiRouteRequest request, IAiModelRouter router) =>
{
    try
    {
        return Results.Ok(router.Route(request));
    }
    catch (AiRouteException exception)
    {
        return Results.BadRequest(new { error = exception.Message });
    }
})
.WithName("RouteAiModel");

app.MapGet("/internal/ai/providers", (IEnumerable<IAiProvider> providers) =>
{
    return Results.Ok(providers.Select(x => new AiProviderInfo(x.ProviderId, x.SupportsRealModelCalls)));
})
.WithName("ListAiProviders");

app.MapPost("/internal/ai/jobs/stub", async (
    AiJobCreateRequest request,
    IAiModelRouter router,
    IEnumerable<IAiProvider> providers,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request.InputJson))
    {
        return Results.BadRequest(new { error = "missing_input_json" });
    }

    AiRouteDecision route;
    try
    {
        route = router.Route(new AiRouteRequest(request.TaskType, request.Mode, request.AssetStatus, request.ExpectedConfidence));
    }
    catch (AiRouteException exception)
    {
        return Results.BadRequest(new { error = exception.Message });
    }

    if (route.AllowRealModelCalls)
    {
        return Results.Conflict(new { error = "real_model_calls_not_allowed_in_draft_test" });
    }

    var provider = providers.FirstOrDefault(x => x.ProviderId == route.Provider);
    if (provider is null)
    {
        return Results.BadRequest(new { error = "ai_provider_not_registered", provider = route.Provider });
    }

    if (provider.SupportsRealModelCalls)
    {
        return Results.Conflict(new { error = "real_model_provider_not_allowed_in_draft_test" });
    }

    var inputHash = Sha256Hex(request.InputJson);
    var idempotencyKey = string.IsNullOrWhiteSpace(request.IdempotencyKey)
        ? $"ai:{route.TaskType}:{route.RoutingVersion}:{route.PromptVersion}:{route.SchemaVersion}:{inputHash}"
        : request.IdempotencyKey.Trim();

    var existing = await dbContext.AIJobs
        .AsNoTracking()
        .FirstOrDefaultAsync(x => x.IdempotencyKey == idempotencyKey, cancellationToken);
    if (existing is not null)
    {
        return Results.Ok(ToAiJobResponse(existing));
    }

    var providerResult = await provider.CompleteStructuredAsync(
        new AiProviderRequest(route.TaskType, route.PromptVersion, route.SchemaVersion, inputHash, request.InputJson),
        cancellationToken);

    var job = new AIJob
    {
        JobType = route.TaskType,
        Status = JobStatuses.Succeeded,
        IdempotencyKey = idempotencyKey,
        ModelRoute = route.Handler,
        ModelProvider = providerResult.ProviderId,
        ModelName = providerResult.ModelName,
        RoutingVersion = route.RoutingVersion,
        PromptVersion = providerResult.PromptVersion,
        SchemaVersion = providerResult.SchemaVersion,
        InputHash = inputHash,
        EstimatedCost = 0,
        ActualCost = providerResult.Cost,
        Confidence = (double)providerResult.Confidence,
        InputTokens = providerResult.InputTokens,
        OutputTokens = providerResult.OutputTokens,
        CachedTokens = providerResult.CachedTokens,
        LatencyMs = providerResult.LatencyMs,
        ReviewStatus = providerResult.ReviewStatus,
        TeacherModified = false,
        Input = request.InputJson,
        Result = providerResult.OutputJson,
        FinishedAt = DateTimeOffset.UtcNow
    };

    dbContext.AIJobs.Add(job);
    await dbContext.SaveChangesAsync(cancellationToken);

    return Results.Created($"/internal/ai/jobs/{job.Id}", ToAiJobResponse(job));
})
.WithName("CreateStubAiJob");

app.MapPost("/ai-suggestions/enqueue", async (
    AiSuggestionEnqueueRequest request,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request.SuggestionType))
    {
        return Results.BadRequest(new { error = "suggestion_type_required" });
    }

    if (request.SourceDocumentId == Guid.Empty)
    {
        return Results.BadRequest(new { error = "source_document_id_required" });
    }

    var sourceExists = await dbContext.SourceDocuments
        .AsNoTracking()
        .AnyAsync(x => x.Id == request.SourceDocumentId, cancellationToken);
    if (!sourceExists)
    {
        return Results.NotFound(new { error = "source_document_not_found" });
    }

    var payloadJson = request.Payload?.GetRawText() ?? "{}";
    var inputJson = JsonSerializer.Serialize(new
    {
        request.SuggestionType,
        request.SourceDocumentId,
        request.SourceRegionIds,
        payload = payloadJson,
        request.ModelRoute,
        request.PromptVersion,
        request.Cost,
        request.Cache
    });
    var inputHash = Sha256Hex(inputJson);
    var idempotencyKey = string.IsNullOrWhiteSpace(request.IdempotencyKey)
        ? $"s007b:{NormalizeToken(request.SuggestionType, "suggestion")}:{request.SourceDocumentId}:{inputHash}"
        : request.IdempotencyKey.Trim();

    var existing = await dbContext.AIJobs
        .AsNoTracking()
        .FirstOrDefaultAsync(x => x.IdempotencyKey == idempotencyKey, cancellationToken);
    if (existing is not null)
    {
        return Results.Ok(new AiSuggestionEnqueueResponse(
            existing.Id,
            Guid.Empty,
            existing.ReviewStatus,
            existing.TeacherModified,
            existing.CreatedAt));
    }

    var now = DateTimeOffset.UtcNow;
    var job = new AIJob
    {
        JobType = NormalizeToken(request.SuggestionType, "suggestion"),
        Status = JobStatuses.Succeeded,
        IdempotencyKey = idempotencyKey,
        ModelRoute = string.IsNullOrWhiteSpace(request.ModelRoute) ? "draft_test_stub" : request.ModelRoute.Trim(),
        ModelProvider = "stub",
        ModelName = "suggestion_stub",
        RoutingVersion = "s007b.v1",
        PromptVersion = string.IsNullOrWhiteSpace(request.PromptVersion) ? "s007b.prompt.v1" : request.PromptVersion.Trim(),
        SchemaVersion = "ai_suggestion_envelope.schema.v1",
        InputHash = inputHash,
        EstimatedCost = request.Cost?.EstimatedUsd,
        ActualCost = request.Cost?.EstimatedUsd,
        Confidence = request.Confidence?.Score,
        InputTokens = request.Cost?.InputTokens,
        OutputTokens = request.Cost?.OutputTokens,
        CachedTokens = request.Cache?.CacheHit == true ? request.Cost?.InputTokens : 0,
        LatencyMs = 0,
        ReviewStatus = ReviewStatuses.Open,
        TeacherModified = false,
        Input = inputJson,
        Result = payloadJson,
        FinishedAt = now
    };

    dbContext.AIJobs.Add(job);

    var queuePayload = SerializeJson(new
    {
        suggestionType = NormalizeToken(request.SuggestionType, "suggestion"),
        sourceDocumentId = request.SourceDocumentId,
        sourceRegionIds = request.SourceRegionIds,
        confidence = request.Confidence?.Score,
        confidenceThreshold = request.Confidence?.Threshold,
        riskLevel = "medium",
        requiredAction = "teacher_review",
        reason = "ai_suggestion_pending_review",
        cost = request.Cost,
        cache = request.Cache,
        aiJobId = job.Id
    });
    var queueItem = new ReviewQueueItem
    {
        ReviewType = "ai_suggestion",
        Status = ReviewStatuses.Open,
        Payload = queuePayload,
        CreatedAt = now
    };
    dbContext.ReviewQueueItems.Add(queueItem);
    await dbContext.SaveChangesAsync(cancellationToken);

    return Results.Created(
        $"/ai-suggestions/enqueue/{job.Id}",
        new AiSuggestionEnqueueResponse(job.Id, queueItem.Id, job.ReviewStatus, job.TeacherModified, now));
})
.WithName("EnqueueAiSuggestion");

app.MapPost("/ai-suggestions/{id:guid}/feedback", async (
    Guid id,
    AiSuggestionFeedbackRequest request,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    var job = await dbContext.AIJobs.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (job is null)
    {
        return Results.NotFound(new { error = "ai_suggestion_not_found" });
    }

    if (string.IsNullOrWhiteSpace(request.Decision))
    {
        return Results.BadRequest(new { error = "decision_required" });
    }

    var now = DateTimeOffset.UtcNow;
    var decision = NormalizeToken(request.Decision, "approve");
    var nextReviewStatus = decision is "approve" or "approved" ? ReviewStatuses.Resolved : ReviewStatuses.Dismissed;
    var beforeValue = job.Result;

    job.TeacherModified = request.TeacherModified;
    job.ReviewStatus = nextReviewStatus;
    job.FinishedAt = now;

    var relatedQueueItems = await dbContext.ReviewQueueItems
        .Where(x => x.ReviewType == "ai_suggestion" && x.Status == ReviewStatuses.Open)
        .OrderByDescending(x => x.CreatedAt)
        .ToListAsync(cancellationToken);
    var resolvedQueueItemIds = new List<Guid>();
    foreach (var item in relatedQueueItems)
    {
        var payload = JsonHelpers.ParseJsonElement(item.Payload);
        if (!payload.TryGetProperty("aiJobId", out var aiJobIdElement) || aiJobIdElement.ValueKind != JsonValueKind.String)
        {
            continue;
        }

        if (!Guid.TryParse(aiJobIdElement.GetString(), out var aiJobId) || aiJobId != id)
        {
            continue;
        }

        item.Status = nextReviewStatus;
        item.ResolvedAt = now;
        item.Payload = ReviewQueuePayloadHelpers.WithReviewAudit(item.Payload, request.ReviewedBy, decision, request.Reason, now);
        resolvedQueueItemIds.Add(item.Id);
    }

    if (request.TeacherModified)
    {
        dbContext.FeedbackEvents.Add(new FeedbackEvent
        {
            AIJobId = job.Id,
            TaskType = job.JobType,
            EntityType = "ai_suggestion",
            EntityId = job.Id,
            FieldKey = "teacher_feedback",
            BeforeValue = string.IsNullOrWhiteSpace(beforeValue) ? "{}" : beforeValue,
            AfterValue = SerializeJson(new
            {
                decision,
                request.TeacherModified,
                reviewedBy = request.ReviewedBy,
                reason = request.Reason,
                reviewStatus = nextReviewStatus
            }),
            AiConfidence = job.Confidence,
            ReasonTag = NormalizeToken(request.Reason, "teacher_modified"),
            TeacherId = string.IsNullOrWhiteSpace(request.ReviewedBy) ? "teacher" : request.ReviewedBy.Trim(),
            PromptVersion = job.PromptVersion,
            SchemaVersion = job.SchemaVersion,
            Model = string.IsNullOrWhiteSpace(job.ModelName) ? job.ModelProvider : $"{job.ModelProvider}/{job.ModelName}",
            AcceptedForEval = true,
            Metadata = SerializeJson(new
            {
                source = "ai_suggestion_feedback",
                decision,
                resolvedQueueItemIds,
                productionPromptMutation = false,
                activeAssetMutation = false
            }),
            CreatedAt = now
        });
    }

    await dbContext.SaveChangesAsync(cancellationToken);
    return Results.Ok(new AiSuggestionFeedbackResponse(
        job.Id,
        decision,
        job.ReviewStatus,
        job.TeacherModified,
        resolvedQueueItemIds,
        now));
})
.WithName("FeedbackAiSuggestion");

app.MapGet("/feedback-events/eval-samples", async (
    int? limit,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    var take = Math.Clamp(limit ?? 20, 1, 100);
    var rows = await dbContext.FeedbackEvents
        .AsNoTracking()
        .Where(x => x.AcceptedForEval)
        .OrderByDescending(x => x.CreatedAt)
        .Take(take)
        .ToListAsync(cancellationToken);

    return Results.Ok(new
    {
        items = rows.Select(x => new
        {
            x.Id,
            x.TaskType,
            x.EntityType,
            x.EntityId,
            x.FieldKey,
            beforeValue = JsonHelpers.ParseJsonElement(x.BeforeValue),
            afterValue = JsonHelpers.ParseJsonElement(x.AfterValue),
            x.AiConfidence,
            x.ReasonTag,
            x.TeacherId,
            x.PromptVersion,
            x.SchemaVersion,
            x.Model,
            x.AcceptedForEval,
            metadata = JsonHelpers.ParseJsonElement(x.Metadata),
            x.CreatedAt
        }).ToArray(),
        totalCount = rows.Count,
        productionPromptMutation = false,
        activeAssetMutation = false
    });
})
.WithName("ListFeedbackEventEvalSamples");

app.MapPost("/ai-suggestions/{id:guid}/confirm", async (
    Guid id,
    AiSuggestionConfirmRequest request,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    var job = await dbContext.AIJobs.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (job is null)
    {
        return Results.NotFound(new { error = "ai_suggestion_not_found" });
    }

    if (job.ReviewStatus != ReviewStatuses.Resolved && job.ReviewStatus != ReviewStatuses.Open)
    {
        return Results.Conflict(new { error = "ai_suggestion_not_reviewable" });
    }

    var knowledgeNodeId = request.KnowledgeNodeId;
    if (knowledgeNodeId is null)
    {
        knowledgeNodeId = await dbContext.KnowledgeNodes
            .AsNoTracking()
            .OrderBy(x => x.CreatedAt)
            .Select(x => (Guid?)x.Id)
            .FirstOrDefaultAsync(cancellationToken);
    }
    if (knowledgeNodeId is null)
    {
        return Results.Conflict(new { error = "knowledge_node_required_for_confirm" });
    }

    var knowledgeExists = await dbContext.KnowledgeNodes
        .AsNoTracking()
        .AnyAsync(x => x.Id == knowledgeNodeId.Value, cancellationToken);
    if (!knowledgeExists)
    {
        return Results.BadRequest(new { error = "knowledge_node_not_found" });
    }

    var now = DateTimeOffset.UtcNow;
    var question = new QuestionItem
    {
        Id = Guid.NewGuid(),
        Subject = string.IsNullOrWhiteSpace(request.Subject) ? "physics" : request.Subject.Trim(),
        Stage = string.IsNullOrWhiteSpace(request.Stage) ? "junior_middle_school" : request.Stage.Trim(),
        Grade = string.IsNullOrWhiteSpace(request.Grade) ? "grade_8" : request.Grade.Trim(),
        QuestionType = string.IsNullOrWhiteSpace(request.QuestionType) ? "single_choice" : request.QuestionType.Trim(),
        DifficultyEstimated = request.DifficultyEstimated,
        DefaultScore = request.DefaultScore,
        Status = QuestionStatuses.Draft,
        Blocks = "[]",
        QualitySignals = SerializeJson(new
        {
            source = "ai_suggestion_teacher_confirmed",
            aiJobId = job.Id,
            reviewedBy = request.ReviewedBy,
            reviewedAt = now.ToString("O")
        }),
        CreatedAt = now,
        UpdatedAt = now
    };
    dbContext.QuestionItems.Add(question);

    var mapping = new KnowledgeMapping
    {
        Id = Guid.NewGuid(),
        QuestionItemId = question.Id,
        KnowledgeNodeId = knowledgeNodeId.Value,
        MappingSource = KnowledgeMappingSources.Manual,
        IsPrimary = true,
        Confidence = request.MappingConfidence,
        Version = 1,
        Evidence = SerializeJson(new
        {
            source = "ai_suggestion_teacher_confirmed",
            aiJobId = job.Id,
            reviewedBy = request.ReviewedBy,
            reason = request.Reason
        }),
        CreatedAt = now
    };
    dbContext.KnowledgeMappings.Add(mapping);

    job.TeacherModified = true;
    job.ReviewStatus = ReviewStatuses.Resolved;
    job.Result = ReviewWorkbenchMutationHelpers.WithPatch(
        job.Result,
        new Dictionary<string, object?>
        {
            ["confirmedQuestionId"] = question.Id,
            ["confirmedKnowledgeMappingId"] = mapping?.Id,
            ["confirmReason"] = request.Reason,
            ["confirmReviewedBy"] = request.ReviewedBy,
            ["confirmAt"] = now.ToString("O")
        });

    await dbContext.SaveChangesAsync(cancellationToken);
    return Results.Ok(new AiSuggestionConfirmResponse(
        job.Id,
        question.Id,
        mapping?.Id,
        "confirmed",
        now));
})
.WithName("ConfirmAiSuggestionToQuestion");

app.MapPost("/ai-suggestions/{id:guid}/undo-confirm", async (
    Guid id,
    AiSuggestionUndoRequest request,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    var job = await dbContext.AIJobs.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (job is null)
    {
        return Results.NotFound(new { error = "ai_suggestion_not_found" });
    }

    var payload = JsonHelpers.ParseJsonElement(job.Result);
    if (!payload.TryGetProperty("confirmedQuestionId", out var questionIdElement) ||
        questionIdElement.ValueKind != JsonValueKind.String ||
        !Guid.TryParse(questionIdElement.GetString(), out var questionId))
    {
        return Results.Conflict(new { error = "ai_suggestion_not_confirmed" });
    }

    var question = await dbContext.QuestionItems.FirstOrDefaultAsync(x => x.Id == questionId, cancellationToken);
    if (question is null)
    {
        return Results.NotFound(new { error = "confirmed_question_not_found" });
    }

    var mappings = await dbContext.KnowledgeMappings
        .Where(x => x.QuestionItemId == questionId)
        .ToListAsync(cancellationToken);
    dbContext.KnowledgeMappings.RemoveRange(mappings);
    dbContext.QuestionItems.Remove(question);

    var now = DateTimeOffset.UtcNow;
    job.Result = ReviewWorkbenchMutationHelpers.WithPatch(
        job.Result,
        new Dictionary<string, object?>
        {
            ["undoReason"] = request.Reason,
            ["undoReviewedBy"] = request.ReviewedBy,
            ["undoAt"] = now.ToString("O"),
            ["confirmedQuestionId"] = null,
            ["confirmedKnowledgeMappingId"] = null
        });

    await dbContext.SaveChangesAsync(cancellationToken);
    return Results.Ok(new AiSuggestionUndoResponse(job.Id, questionId, mappings.Count, "undone", now));
})
.WithName("UndoConfirmAiSuggestionToQuestion");

app.MapPost("/files", async (HttpRequest request, IFileStore fileStore, CancellationToken cancellationToken) =>
{
    var form = await request.ReadFormAsync(cancellationToken);
    var file = form.Files.GetFile("file");
    if (file is null)
    {
        return Results.BadRequest(new { error = "missing_file" });
    }

    if (file.Length <= 0)
    {
        return Results.BadRequest(new { error = "empty_file" });
    }

    await using var stream = file.OpenReadStream();
    var stored = await fileStore.StoreOriginalAsync(
        stream,
        file.FileName,
        file.ContentType,
        file.Length,
        SourceMetadataFromForm(form, file.FileName),
        cancellationToken);

    return Results.Created($"/files/{stored.Id}", stored);
})
.DisableAntiforgery()
.WithName("UploadFile");

app.MapGet("/source-documents", async (
    string? sourceType,
    string? materialBatchKey,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    var query =
        from document in dbContext.SourceDocuments.AsNoTracking()
        join file in dbContext.FileAssets.AsNoTracking() on document.FileAssetId equals file.Id
        select new { document, file };

    if (!string.IsNullOrWhiteSpace(sourceType))
    {
        var value = NormalizeToken(sourceType, "unknown");
        query = query.Where(x => x.document.SourceType == value);
    }

    if (!string.IsNullOrWhiteSpace(materialBatchKey))
    {
        var value = NormalizeToken(materialBatchKey, string.Empty);
        query = query.Where(x => x.document.MaterialBatchKey == value);
    }

    var rows = await query
        .OrderByDescending(x => x.document.CreatedAt)
        .Take(100)
        .ToListAsync(cancellationToken);

    return Results.Ok(new SourceMaterialListResponse(
        Mode: "source_material_workbench_mvp",
        Items: rows.Select(x => SourceMaterialResponse.From(x.document, x.file)).ToArray()));
})
.WithName("ListSourceDocuments");

app.MapPatch("/source-documents/{id:guid}/authorization", async (
    Guid id,
    SourceDocumentAuthorizationUpdateRequest request,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request.ReviewedBy))
    {
        return Results.BadRequest(new { error = "reviewed_by_required" });
    }

    if (string.IsNullOrWhiteSpace(request.Reason))
    {
        return Results.BadRequest(new { error = "reason_required" });
    }

    var sourceDocument = await dbContext.SourceDocuments
        .FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (sourceDocument is null)
    {
        return Results.NotFound(new { error = "source_document_not_found" });
    }
    var file = await dbContext.FileAssets
        .AsNoTracking()
        .FirstOrDefaultAsync(x => x.Id == sourceDocument.FileAssetId, cancellationToken);
    if (file is null)
    {
        return Results.Conflict(new { error = "source_file_missing", fileAssetId = sourceDocument.FileAssetId });
    }

    var before = SourceMaterialResponse.From(sourceDocument, file);
    if (!string.IsNullOrWhiteSpace(request.LicenseOrPermission))
    {
        sourceDocument.LicenseOrPermission = NormalizeToken(request.LicenseOrPermission, "unknown");
    }
    if (request.SharingAllowed.HasValue)
    {
        sourceDocument.SharingAllowed = request.SharingAllowed.Value;
    }
    if (request.ContainsStudentPii.HasValue)
    {
        sourceDocument.ContainsStudentPii = request.ContainsStudentPii.Value;
    }
    if (!string.IsNullOrWhiteSpace(request.AnonymizationStatus))
    {
        sourceDocument.AnonymizationStatus = NormalizeToken(request.AnonymizationStatus, "not_applicable");
    }
    if (request.ExternalAiAllowed.HasValue)
    {
        sourceDocument.ExternalAiAllowed = request.ExternalAiAllowed.Value;
    }
    if (request.MayUseForKnowledgeExtraction.HasValue)
    {
        sourceDocument.MayUseForKnowledgeExtraction = request.MayUseForKnowledgeExtraction.Value;
    }
    if (request.MayUseForExamPointExtraction.HasValue)
    {
        sourceDocument.MayUseForExamPointExtraction = request.MayUseForExamPointExtraction.Value;
    }
    if (request.MayUseForTrendAnalysis.HasValue)
    {
        sourceDocument.MayUseForTrendAnalysis = request.MayUseForTrendAnalysis.Value;
    }

    var now = DateTimeOffset.UtcNow;
    var after = SourceMaterialResponse.From(sourceDocument, file);
    var audit = new ReviewQueueItem
    {
        ReviewType = "source_document_authorization",
        Status = ReviewStatuses.Resolved,
        CreatedAt = now,
        ResolvedAt = now,
        Payload = JsonSerializer.Serialize(new
        {
            sourceDocumentId = id,
            before,
            after,
            reviewAudit = new
            {
                reviewedBy = request.ReviewedBy.Trim(),
                decision = "source_document_authorization_updated",
                reason = request.Reason.Trim(),
                reviewedAt = now.ToString("O")
            }
        })
    };
    dbContext.ReviewQueueItems.Add(audit);
    await dbContext.SaveChangesAsync(cancellationToken);

    return Results.Ok(new SourceDocumentAuthorizationUpdateResponse(after, audit.Id));
})
.WithName("UpdateSourceDocumentAuthorization");

app.MapPost("/imports", async (HttpRequest request, IFileStore fileStore, KqgDbContext dbContext, CancellationToken cancellationToken) =>
{
    var form = await request.ReadFormAsync(cancellationToken);
    var file = form.Files.GetFile("file");
    if (file is null)
    {
        return Results.BadRequest(new { error = "missing_file" });
    }

    if (file.Length <= 0)
    {
        return Results.BadRequest(new { error = "empty_file" });
    }

    await using var stream = file.OpenReadStream();
    var stored = await fileStore.StoreOriginalAsync(
        stream,
        file.FileName,
        file.ContentType,
        file.Length,
        SourceMetadataFromForm(form, file.FileName),
        cancellationToken);

    var idempotencyKey = $"import:original:{stored.Sha256}";
    var existing = await dbContext.ImportJobs
        .FirstOrDefaultAsync(x => x.IdempotencyKey == idempotencyKey, cancellationToken);

    if (existing is not null)
    {
        return Results.Ok(ImportJobResponse.From(existing, stored));
    }

    var job = new ImportJob
    {
        InputFileAssetId = stored.Id,
        Status = JobStatuses.Queued,
        IdempotencyKey = idempotencyKey,
        Input = $$"""
        {"fileAssetId":"{{stored.Id}}","relativePath":"{{stored.RelativePath}}","sha256":"{{stored.Sha256}}"}
        """
    };

    dbContext.ImportJobs.Add(job);
    await dbContext.SaveChangesAsync(cancellationToken);

    return Results.Created($"/imports/{job.Id}", ImportJobResponse.From(job, stored));
})
.DisableAntiforgery()
.WithName("CreateImportJob");

app.MapGet("/imports/{id:guid}", async (Guid id, KqgDbContext dbContext, CancellationToken cancellationToken) =>
{
    var job = await dbContext.ImportJobs
        .AsNoTracking()
        .FirstOrDefaultAsync(x => x.Id == id, cancellationToken);

    return job is null ? Results.NotFound() : Results.Ok(ImportJobResponse.From(job));
})
.WithName("GetImportJob");

app.MapPost("/source-documents/{id:guid}/regions", async (
    Guid id,
    SourceRegionCreateRequest request,
    KqgDbContext dbContext,
    IConfiguration configuration,
    CancellationToken cancellationToken) =>
{
    var sourceDocument = await dbContext.SourceDocuments.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (sourceDocument is null)
    {
        return Results.NotFound(new { error = "source_document_not_found" });
    }

    var validationError = ValidateSourceRegionRequest(request);
    if (validationError is not null)
    {
        return Results.BadRequest(new { error = validationError });
    }

    if (!string.IsNullOrWhiteSpace(request.ScreenshotRelativePath))
    {
        var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
        if (!TryResolveFileStorePath(paths.FileStoreRoot, request.ScreenshotRelativePath, out var screenshotPath))
        {
            return Results.BadRequest(new { error = "invalid_screenshot_relative_path" });
        }

        if (!File.Exists(screenshotPath))
        {
            return Results.Conflict(new { error = "source_region_screenshot_missing", screenshotRelativePath = request.ScreenshotRelativePath });
        }
    }

    var region = new SourceRegion
    {
        SourceDocumentId = id,
        PageNumber = request.PageNumber,
        X = request.X,
        Y = request.Y,
        Width = request.Width,
        Height = request.Height,
        CoordinateUnit = NormalizeToken(request.CoordinateUnit, "percent"),
        ScreenshotRelativePath = string.IsNullOrWhiteSpace(request.ScreenshotRelativePath) ? null : request.ScreenshotRelativePath.Trim().Replace('\\', '/'),
        RegionType = string.IsNullOrWhiteSpace(request.RegionType) ? "preview" : NormalizeToken(request.RegionType, "preview")
    };

    dbContext.SourceRegions.Add(region);
    await dbContext.SaveChangesAsync(cancellationToken);

    return Results.Created($"/source-regions/{region.Id}", SourceRegionResponse.From(region));
})
.WithName("CreateSourceRegion");

app.MapPatch("/source-regions/{id:guid}", async (
    Guid id,
    SourceRegionUpdateRequest request,
    KqgDbContext dbContext,
    IConfiguration configuration,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request.ReviewedBy))
    {
        return Results.BadRequest(new { error = "reviewed_by_required" });
    }

    if (string.IsNullOrWhiteSpace(request.Reason))
    {
        return Results.BadRequest(new { error = "reason_required" });
    }

    var region = await dbContext.SourceRegions.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (region is null)
    {
        return Results.NotFound(new { error = "source_region_not_found" });
    }

    var next = new SourceRegionCreateRequest(
        request.PageNumber ?? region.PageNumber,
        request.X ?? region.X,
        request.Y ?? region.Y,
        request.Width ?? region.Width,
        request.Height ?? region.Height,
        request.CoordinateUnit ?? region.CoordinateUnit,
        request.ScreenshotRelativePath ?? region.ScreenshotRelativePath,
        request.RegionType ?? region.RegionType);
    var validationError = ValidateSourceRegionRequest(next);
    if (validationError is not null)
    {
        return Results.BadRequest(new { error = validationError });
    }

    var normalizedScreenshotPath = string.IsNullOrWhiteSpace(next.ScreenshotRelativePath)
        ? null
        : next.ScreenshotRelativePath.Trim().Replace('\\', '/');
    if (!string.IsNullOrWhiteSpace(normalizedScreenshotPath))
    {
        var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
        if (!TryResolveFileStorePath(paths.FileStoreRoot, normalizedScreenshotPath, out var screenshotPath))
        {
            return Results.BadRequest(new { error = "invalid_screenshot_relative_path" });
        }

        if (!File.Exists(screenshotPath))
        {
            return Results.Conflict(new { error = "source_region_screenshot_missing", screenshotRelativePath = normalizedScreenshotPath });
        }
    }

    var before = SourceRegionResponse.From(region);
    region.PageNumber = next.PageNumber;
    region.X = next.X;
    region.Y = next.Y;
    region.Width = next.Width;
    region.Height = next.Height;
    region.CoordinateUnit = NormalizeToken(next.CoordinateUnit, "percent");
    region.ScreenshotRelativePath = normalizedScreenshotPath;
    region.RegionType = string.IsNullOrWhiteSpace(next.RegionType) ? "preview" : NormalizeToken(next.RegionType, "preview");

    var now = DateTimeOffset.UtcNow;
    var audit = new ReviewQueueItem
    {
        ReviewType = "source_region_revision",
        Status = ReviewStatuses.Resolved,
        ResolvedAt = now,
        CreatedAt = now,
        Payload = JsonSerializer.Serialize(new
        {
            sourceRegionId = region.Id,
            sourceDocumentId = region.SourceDocumentId,
            before,
            after = SourceRegionResponse.From(region),
            reviewAudit = new
            {
                reviewedBy = request.ReviewedBy.Trim(),
                decision = "source_region_updated",
                reason = request.Reason.Trim(),
                reviewedAt = now.ToString("O")
            }
        })
    };
    dbContext.ReviewQueueItems.Add(audit);
    await dbContext.SaveChangesAsync(cancellationToken);

    return Results.Ok(new SourceRegionUpdateResponse(SourceRegionResponse.From(region), audit.Id));
})
.WithName("UpdateSourceRegion");

app.MapGet("/source-documents/{id:guid}/preview", async (
    Guid id,
    KqgDbContext dbContext,
    IConfiguration configuration,
    CancellationToken cancellationToken) =>
{
    var sourceDocument = await dbContext.SourceDocuments.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (sourceDocument is null)
    {
        return Results.NotFound(new { error = "source_document_not_found" });
    }

    var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
    var regions = await dbContext.SourceRegions
        .AsNoTracking()
        .Where(x => x.SourceDocumentId == id)
        .OrderBy(x => x.PageNumber)
        .ThenBy(x => x.CreatedAt)
        .ToListAsync(cancellationToken);

    var missingScreenshot = regions.FirstOrDefault(x =>
        !string.IsNullOrWhiteSpace(x.ScreenshotRelativePath) &&
        (!TryResolveFileStorePath(paths.FileStoreRoot, x.ScreenshotRelativePath, out var screenshotPath) || !File.Exists(screenshotPath)));
    if (missingScreenshot is not null)
    {
        return Results.Conflict(new { error = "source_region_screenshot_missing", regionId = missingScreenshot.Id, missingScreenshot.ScreenshotRelativePath });
    }

    var pages = regions
        .GroupBy(x => x.PageNumber)
        .Select(x => new SourcePreviewPageResponse(
            x.Key,
            x.Select(SourceRegionResponse.From).ToArray()))
        .ToArray();

    return Results.Ok(new SourceDocumentPreviewResponse(id, pages));
})
.WithName("GetSourceDocumentPreview");

app.MapGet("/source-documents/{id:guid}/quality-report", async (
    Guid id,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    var sourceDocument = await dbContext.SourceDocuments
        .AsNoTracking()
        .FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (sourceDocument is null)
    {
        return Results.NotFound(new { error = "source_document_not_found" });
    }

    var blockQuestionIds =
        from block in dbContext.QuestionBlocks.AsNoTracking()
        where block.SourceRegionId != null
        join region in dbContext.SourceRegions.AsNoTracking() on block.SourceRegionId!.Value equals region.Id
        where region.SourceDocumentId == id
        select block.QuestionItemId;
    var assetQuestionIds =
        from asset in dbContext.QuestionAssets.AsNoTracking()
        where asset.SourceRegionId != null
        join region in dbContext.SourceRegions.AsNoTracking() on asset.SourceRegionId!.Value equals region.Id
        where region.SourceDocumentId == id
        select asset.QuestionItemId;
    var questionIds = await blockQuestionIds
        .Concat(assetQuestionIds)
        .Distinct()
        .ToListAsync(cancellationToken);

    var questions = await dbContext.QuestionItems
        .AsNoTracking()
        .Where(x => questionIds.Contains(x.Id))
        .ToListAsync(cancellationToken);
    var blocks = await dbContext.QuestionBlocks
        .AsNoTracking()
        .Where(x => questionIds.Contains(x.QuestionItemId))
        .ToListAsync(cancellationToken);
    var assets = await dbContext.QuestionAssets
        .AsNoTracking()
        .Where(x => questionIds.Contains(x.QuestionItemId))
        .ToListAsync(cancellationToken);
    var regions = await dbContext.SourceRegions
        .AsNoTracking()
        .Where(x => x.SourceDocumentId == id)
        .ToListAsync(cancellationToken);

    var questionIdSet = questionIds.ToHashSet();
    var openReviewItems = await dbContext.ReviewQueueItems
        .AsNoTracking()
        .Where(x => x.Status == ReviewStatuses.Open)
        .ToListAsync(cancellationToken);
    var relatedOpenReviewItems = openReviewItems
        .Where(x => ReviewQueuePayloadReferences(x.Payload, id, questionIdSet))
        .ToArray();

    var questionNumbers = questions
        .Select(x => TryGetIntCustomField(x.CustomFields, "questionNo"))
        .Where(x => x.HasValue)
        .Select(x => x!.Value)
        .Distinct()
        .OrderBy(x => x)
        .ToArray();
    var missingQuestionNumbers = questionNumbers.Length == 0
        ? Array.Empty<int>()
        : Enumerable.Range(questionNumbers.Min(), questionNumbers.Max() - questionNumbers.Min() + 1)
            .Except(questionNumbers)
            .ToArray();
    var linkedRegionIds = blocks
        .Select(x => x.SourceRegionId)
        .Concat(assets.Select(x => x.SourceRegionId))
        .Where(x => x.HasValue)
        .Select(x => x!.Value)
        .Distinct()
        .ToHashSet();
    var linkedRegions = regions.Where(x => linkedRegionIds.Contains(x.Id)).ToArray();
    var missingLinkedScreenshots = linkedRegions
        .Where(x => string.IsNullOrWhiteSpace(x.ScreenshotRelativePath))
        .Select(x => x.Id)
        .ToArray();

    var answerCoveredCount = questions.Count(x => QuestionCustomFieldHasValue(x.CustomFields, "answer"));
    var solutionCoveredCount = questions.Count(x => QuestionCustomFieldHasValue(x.CustomFields, "solution"));
    var tableCount = blocks.Count(x => string.Equals(x.BlockType, "table", StringComparison.OrdinalIgnoreCase));
    var formulaCount = blocks.Count(x => string.Equals(x.BlockType, "formula", StringComparison.OrdinalIgnoreCase));
    var imageAssets = assets.Where(x => string.Equals(x.AssetType, "image", StringComparison.OrdinalIgnoreCase)).ToArray();
    var imageMatchedQuestionCount = imageAssets.Select(x => x.QuestionItemId).Distinct().Count();
    var externalAiCalls = questions.Sum(x => TryGetIntCustomField(x.QualitySignals, "externalAiCalls") ?? 0);
    var noiseRetainedBlockCount = blocks.Count(QuestionBlockLooksLikeRetainedNoise);

    var gaps = new List<string>();
    if (questions.Count == 0)
    {
        gaps.Add("question_items_missing");
    }
    if (questionNumbers.Length != questions.Count || missingQuestionNumbers.Length > 0)
    {
        gaps.Add("question_number_incomplete");
    }
    if (answerCoveredCount != questions.Count)
    {
        gaps.Add("answer_coverage_incomplete");
    }
    if (missingLinkedScreenshots.Length > 0)
    {
        gaps.Add("linked_source_screenshot_missing");
    }
    if (relatedOpenReviewItems.Length > 0)
    {
        gaps.Add("manual_review_pending");
    }
    if (noiseRetainedBlockCount > 0)
    {
        gaps.Add("possible_layout_noise_retained");
    }

    var metrics = new SourceDocumentQualityMetricsResponse(
        QuestionCount: questions.Count,
        QuestionNumberCount: questionNumbers.Length,
        AnswerCoveredCount: answerCoveredCount,
        SolutionCoveredCount: solutionCoveredCount,
        SourceRegionCount: regions.Count,
        LinkedSourceRegionCount: linkedRegions.Length,
        LinkedSourceScreenshotCount: linkedRegions.Count(x => !string.IsNullOrWhiteSpace(x.ScreenshotRelativePath)),
        MissingLinkedSourceScreenshotCount: missingLinkedScreenshots.Length,
        ImageAssetCount: imageAssets.Length,
        ImageMatchedQuestionCount: imageMatchedQuestionCount,
        TableBlockCount: tableCount,
        FormulaBlockCount: formulaCount,
        PendingManualItemCount: relatedOpenReviewItems.Length,
        NoiseRetainedBlockCount: noiseRetainedBlockCount,
        ExternalAiCallCount: externalAiCalls);

    var closureStatus = gaps.Count == 0 ? "paper_quality_pass" : "not_closed";
    return Results.Ok(new SourceDocumentQualityReportResponse(
        SourceDocumentId: sourceDocument.Id,
        SourceTitle: sourceDocument.SourceTitle,
        SourceType: sourceDocument.SourceType,
        Region: sourceDocument.Region,
        Year: sourceDocument.Year,
        MaterialBatchKey: sourceDocument.MaterialBatchKey,
        ClosureStatus: closureStatus,
        FullClosureAllowed: false,
        Metrics: metrics,
        QuestionNumbers: questionNumbers,
        MissingQuestionNumbers: missingQuestionNumbers,
        MissingLinkedSourceRegionIds: missingLinkedScreenshots,
        PendingReviewTypes: relatedOpenReviewItems
            .Select(x => x.ReviewType)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(x => x)
            .ToArray(),
        Gaps: gaps,
        ExternalAiPolicy: externalAiCalls == 0 ? "no_external_ai_calls" : "external_ai_calls_require_review",
        RollbackSql: BuildSourceDocumentRollbackSql(sourceDocument.Id),
        SummaryChinese: gaps.Count == 0
            ? "本份试卷题号、答案、来源截图和结构化质量指标通过；全量 REAL005 仍需逐年逐题证据。"
            : $"本份试卷仍有 {gaps.Count} 类缺口：{string.Join("、", gaps)}。"));
})
.WithName("GetSourceDocumentQualityReport");

app.MapGet("/source-regions/{id:guid}/screenshot", async (
    Guid id,
    KqgDbContext dbContext,
    IConfiguration configuration,
    CancellationToken cancellationToken) =>
{
    var region = await dbContext.SourceRegions
        .AsNoTracking()
        .FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (region is null)
    {
        return Results.NotFound(new { error = "source_region_not_found" });
    }

    if (string.IsNullOrWhiteSpace(region.ScreenshotRelativePath))
    {
        return Results.Conflict(new { error = "source_region_screenshot_not_available", regionId = id });
    }

    var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
    if (!TryResolveFileStorePath(paths.FileStoreRoot, region.ScreenshotRelativePath, out var screenshotPath))
    {
        return Results.BadRequest(new { error = "invalid_screenshot_relative_path", regionId = id });
    }

    if (!File.Exists(screenshotPath))
    {
        return Results.Conflict(new { error = "source_region_screenshot_missing", regionId = id, region.ScreenshotRelativePath });
    }

    return Results.File(screenshotPath, InferContentType(screenshotPath), enableRangeProcessing: true);
})
.WithName("GetSourceRegionScreenshot");

app.MapGet("/source-regions/{id:guid}/page-screenshot", async (
    Guid id,
    KqgDbContext dbContext,
    IConfiguration configuration,
    CancellationToken cancellationToken) =>
{
    var region = await dbContext.SourceRegions
        .AsNoTracking()
        .FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (region is null)
    {
        return Results.NotFound(new { error = "source_region_not_found" });
    }

    var relative = BuildSourcePageScreenshotRelativePath(region.SourceDocumentId, region.PageNumber);
    var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
    if (!TryResolveFileStorePath(paths.FileStoreRoot, relative, out var screenshotPath))
    {
        return Results.BadRequest(new { error = "invalid_page_screenshot_relative_path", regionId = id });
    }

    if (!File.Exists(screenshotPath))
    {
        return Results.Conflict(new
        {
            error = "source_region_page_screenshot_missing",
            regionId = id,
            pageNumber = region.PageNumber,
            screenshotRelativePath = relative
        });
    }

    return Results.File(screenshotPath, InferContentType(screenshotPath), enableRangeProcessing: true);
})
.WithName("GetSourceRegionPageScreenshot");

app.MapPost("/source-documents/{id:guid}/cut-candidates/generate", async (
    Guid id,
    ICutCandidateGenerationService service,
    CancellationToken cancellationToken) =>
{
    try
    {
        var result = await service.GenerateAsync(id, cancellationToken);
        return Results.Ok(new CutCandidateGenerationResponse(
            result.SourceDocumentId,
            result.GeneratedCount,
            result.LowConfidenceReviewQueueCount,
            result.LowConfidenceThreshold));
    }
    catch (InvalidOperationException ex) when (ex.Message == "source_document_not_found")
    {
        return Results.NotFound(new { error = "source_document_not_found" });
    }
})
.WithName("GenerateCutCandidates");

app.MapGet("/source-documents/{id:guid}/cut-candidates", async (
    Guid id,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    var sourceExists = await dbContext.SourceDocuments
        .AsNoTracking()
        .AnyAsync(x => x.Id == id, cancellationToken);
    if (!sourceExists)
    {
        return Results.NotFound(new { error = "source_document_not_found" });
    }

    var rows = await dbContext.CutCandidates
        .AsNoTracking()
        .Where(x => x.SourceDocumentId == id)
        .OrderBy(x => x.SequenceNo)
        .ThenBy(x => x.CreatedAt)
        .ToListAsync(cancellationToken);

    return Results.Ok(new CutCandidateListResponse(
        id,
        rows.Select(CutCandidateResponse.From).ToArray()));
})
.WithName("ListCutCandidates");

app.MapGet("/review-queue", async (
    string? status,
    string? reviewType,
    string? sortBy,
    string? order,
    int? limit,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    var normalizedStatus = string.IsNullOrWhiteSpace(status) ? ReviewStatuses.Open : NormalizeToken(status, ReviewStatuses.Open);
    var normalizedSortBy = string.IsNullOrWhiteSpace(sortBy) ? "created_at" : NormalizeToken(sortBy, "created_at");
    var descending = !string.Equals(order, "asc", StringComparison.OrdinalIgnoreCase);
    var takeCount = Math.Clamp(limit ?? 100, 1, 200);

    var query = dbContext.ReviewQueueItems.AsNoTracking().Where(x => x.Status == normalizedStatus);
    if (!string.IsNullOrWhiteSpace(reviewType))
    {
        var normalizedReviewType = NormalizeToken(reviewType, string.Empty);
        query = query.Where(x => x.ReviewType == normalizedReviewType);
    }

    var rows = await query.ToListAsync(cancellationToken);
    var mapped = rows.Select(ReviewQueueItemResponse.From).ToList();
    mapped = normalizedSortBy switch
    {
        "question_no" => descending
            ? mapped.OrderByDescending(x => ReviewQueuePayloadHelpers.ResolveQuestionNo(x.Payload) ?? int.MinValue).ThenByDescending(x => x.CreatedAt).ToList()
            : mapped.OrderBy(x => ReviewQueuePayloadHelpers.ResolveQuestionNo(x.Payload) ?? int.MaxValue).ThenBy(x => x.CreatedAt).ToList(),
        "risk" => descending
            ? mapped.OrderByDescending(x => x.RiskLevel).ThenByDescending(x => x.CreatedAt).ToList()
            : mapped.OrderBy(x => x.RiskLevel).ThenBy(x => x.CreatedAt).ToList(),
        _ => descending
            ? mapped.OrderByDescending(x => x.CreatedAt).ToList()
            : mapped.OrderBy(x => x.CreatedAt).ToList(),
    };

    return Results.Ok(new ReviewQueueListResponse(mapped.Take(takeCount).ToArray(), mapped.Count));
})
.WithName("ListReviewQueueItems");

app.MapPost("/review-queue/batch-resolve", async (
    ReviewQueueBatchResolveRequest request,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    if (request.ItemIds.Count == 0)
    {
        return Results.BadRequest(new { error = "item_ids_required" });
    }

    if (string.IsNullOrWhiteSpace(request.ReviewedBy))
    {
        return Results.BadRequest(new { error = "reviewed_by_required" });
    }

    if (string.IsNullOrWhiteSpace(request.Reason))
    {
        return Results.BadRequest(new { error = "reason_required" });
    }

    var itemIds = request.ItemIds.Distinct().ToArray();
    var rows = await dbContext.ReviewQueueItems
        .Where(x => itemIds.Contains(x.Id))
        .ToListAsync(cancellationToken);

    var skippedHighRisk = new List<Guid>();
    var resolvedIds = new List<Guid>();
    var now = DateTimeOffset.UtcNow;
    foreach (var row in rows)
    {
        if (!string.Equals(row.Status, ReviewStatuses.Open, StringComparison.OrdinalIgnoreCase))
        {
            continue;
        }

        var riskLevel = ReviewQueuePayloadHelpers.ResolveRiskLevel(row.Payload);
        if (riskLevel == "high")
        {
            skippedHighRisk.Add(row.Id);
            continue;
        }

        row.Status = request.Decision == "dismissed" ? ReviewStatuses.Dismissed : ReviewStatuses.Resolved;
        row.ResolvedAt = now;
        row.Payload = ReviewQueuePayloadHelpers.WithReviewAudit(
            row.Payload,
            request.ReviewedBy.Trim(),
            request.Decision,
            request.Reason.Trim(),
            now);
        resolvedIds.Add(row.Id);
    }

    await dbContext.SaveChangesAsync(cancellationToken);
    return Results.Ok(new ReviewQueueBatchResolveResponse(resolvedIds, skippedHighRisk));
})
.WithName("BatchResolveReviewQueueItems");

app.MapPost("/review-queue/{id:guid}/resolve", async (
    Guid id,
    ReviewQueueResolveRequest request,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request.ReviewedBy))
    {
        return Results.BadRequest(new { error = "reviewed_by_required" });
    }

    if (string.IsNullOrWhiteSpace(request.Reason))
    {
        return Results.BadRequest(new { error = "reason_required" });
    }

    var row = await dbContext.ReviewQueueItems.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (row is null)
    {
        return Results.NotFound(new { error = "review_queue_item_not_found" });
    }

    if (!string.Equals(row.Status, ReviewStatuses.Open, StringComparison.OrdinalIgnoreCase))
    {
        return Results.Conflict(new { error = "review_queue_item_not_open", status = row.Status });
    }

    var now = DateTimeOffset.UtcNow;
    row.Status = request.Decision == "dismissed" ? ReviewStatuses.Dismissed : ReviewStatuses.Resolved;
    row.ResolvedAt = now;
    row.Payload = ReviewQueuePayloadHelpers.WithReviewAudit(
        row.Payload,
        request.ReviewedBy.Trim(),
        request.Decision,
        request.Reason.Trim(),
        now,
        request.Revision);
    await dbContext.SaveChangesAsync(cancellationToken);

    return Results.Ok(ReviewQueueItemResponse.From(row));
})
.WithName("ResolveReviewQueueItem");

app.MapPost("/review-workbench/actions", async (
    ReviewWorkbenchActionRequest request,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request.Action))
    {
        return Results.BadRequest(new { error = "action_required" });
    }

    if (request.CandidateIds.Count == 0)
    {
        return Results.BadRequest(new { error = "candidate_ids_required" });
    }

    var sourceExists = await dbContext.SourceDocuments
        .AsNoTracking()
        .AnyAsync(x => x.Id == request.SourceDocumentId, cancellationToken);
    if (!sourceExists)
    {
        return Results.NotFound(new { error = "source_document_not_found" });
    }

    var normalizedAction = NormalizeToken(request.Action, string.Empty);
    var candidates = await dbContext.CutCandidates
        .Where(x => x.SourceDocumentId == request.SourceDocumentId && request.CandidateIds.Contains(x.Id))
        .OrderBy(x => x.SequenceNo)
        .ToListAsync(cancellationToken);

    if (candidates.Count == 0)
    {
        return Results.NotFound(new { error = "cut_candidates_not_found" });
    }

    var now = DateTimeOffset.UtcNow;
    var touchedIds = new List<Guid>();
    Guid? createdQuestionId = null;
    var createdCandidateIds = new List<Guid>();
    var skippedIds = new List<Guid>();

    switch (normalizedAction)
    {
        case "merge":
            if (candidates.Count < 2)
            {
                return Results.BadRequest(new { error = "merge_requires_at_least_two_candidates" });
            }

            {
                var primary = candidates[0];
                var mergedIds = candidates.Skip(1).Select(x => x.Id).ToArray();
                primary.CandidatePayload = ReviewWorkbenchMutationHelpers.WithPatch(primary.CandidatePayload, new Dictionary<string, object?>
                {
                    ["mergedFromCandidateIds"] = mergedIds,
                    ["mergedAt"] = now.ToString("O")
                });
                primary.UpdatedAt = now;
                touchedIds.Add(primary.Id);

                foreach (var candidate in candidates.Skip(1))
                {
                    candidate.Status = CutCandidateStatuses.Rejected;
                    candidate.FailureReason = "merged_into_primary";
                    candidate.TakeoverAction = "manual_review";
                    candidate.UpdatedAt = now;
                    touchedIds.Add(candidate.Id);
                }
            }
            break;

        case "split":
            if (candidates.Count != 1)
            {
                return Results.BadRequest(new { error = "split_requires_exactly_one_candidate" });
            }

            {
                var target = candidates[0];
                var maxSequence = await dbContext.CutCandidates
                    .Where(x => x.SourceDocumentId == request.SourceDocumentId)
                    .MaxAsync(x => (int?)x.SequenceNo, cancellationToken) ?? 0;

                var left = ReviewWorkbenchMutationHelpers.CloneCandidate(target, maxSequence + 1, now, "split_part_a");
                var right = ReviewWorkbenchMutationHelpers.CloneCandidate(target, maxSequence + 2, now, "split_part_b");
                dbContext.CutCandidates.Add(left);
                dbContext.CutCandidates.Add(right);
                createdCandidateIds.Add(left.Id);
                createdCandidateIds.Add(right.Id);

                target.Status = CutCandidateStatuses.Rejected;
                target.FailureReason = "split_into_two_candidates";
                target.UpdatedAt = now;
                touchedIds.Add(target.Id);
            }
            break;

        case "skip":
            foreach (var candidate in candidates)
            {
                candidate.Status = CutCandidateStatuses.Rejected;
                candidate.FailureReason = "skipped_by_teacher";
                candidate.UpdatedAt = now;
                touchedIds.Add(candidate.Id);
            }
            break;

        case "rerun":
            foreach (var candidate in candidates)
            {
                candidate.Status = CutCandidateStatuses.RetryRequired;
                candidate.FailureReason = "rerun_requested";
                candidate.TakeoverAction = "rerun";
                candidate.UpdatedAt = now;
                touchedIds.Add(candidate.Id);
            }
            break;

        case "associate":
            if (string.IsNullOrWhiteSpace(request.AssetLabel))
            {
                return Results.BadRequest(new { error = "asset_label_required_for_associate" });
            }

            foreach (var candidate in candidates)
            {
                candidate.Metadata = ReviewWorkbenchMutationHelpers.WithPatch(candidate.Metadata, new Dictionary<string, object?>
                {
                    ["associatedAssetLabel"] = request.AssetLabel.Trim(),
                    ["associatedAt"] = now.ToString("O")
                });
                candidate.UpdatedAt = now;
                touchedIds.Add(candidate.Id);
            }
            break;

        case "undo":
            foreach (var candidate in candidates)
            {
                candidate.Status = CutCandidateStatuses.PendingReview;
                candidate.FailureReason = string.Empty;
                candidate.TakeoverAction = "manual_review";
                candidate.SuggestedQuestionItemId = null;
                candidate.UpdatedAt = now;
                touchedIds.Add(candidate.Id);
            }
            break;

        case "save_question":
            {
                var blocks = candidates
                    .Select((x, index) => new QuestionBlock
                    {
                        QuestionItemId = Guid.Empty,
                        BlockType = "text",
                        SortOrder = index,
                        Content = JsonSerializer.Serialize(new
                        {
                            text = ResolveCandidateText(x),
                            candidateId = x.Id
                        }),
                        SourceRegionId = x.SourceRegionId,
                        CreatedAt = now
                    })
                    .ToArray();

                var question = new QuestionItem
                {
                    Subject = "physics",
                    Stage = "junior_middle_school",
                    Status = QuestionStatuses.Draft,
                    QuestionType = "short_answer",
                    Blocks = JsonSerializer.Serialize(blocks.Select(x => new
                    {
                        x.BlockType,
                        x.SortOrder,
                        x.SourceRegionId
                    })),
                    CreatedAt = now,
                    UpdatedAt = now
                };

                dbContext.QuestionItems.Add(question);
                await dbContext.SaveChangesAsync(cancellationToken);
                createdQuestionId = question.Id;

                foreach (var block in blocks)
                {
                    block.QuestionItemId = question.Id;
                }

                dbContext.QuestionBlocks.AddRange(blocks);
                foreach (var candidate in candidates)
                {
                    candidate.Status = CutCandidateStatuses.Accepted;
                    candidate.SuggestedQuestionItemId = question.Id;
                    candidate.UpdatedAt = now;
                    touchedIds.Add(candidate.Id);
                }
            }
            break;

        default:
            return Results.BadRequest(new { error = "unsupported_action" });
    }

    var reviewQueueRows = await dbContext.ReviewQueueItems
        .Where(x => x.ReviewType == "cut_candidate" && x.Status == ReviewStatuses.Open)
        .ToListAsync(cancellationToken);

    var candidateSourceRegionIds = candidates
        .Where(x => x.SourceRegionId.HasValue)
        .Select(x => x.SourceRegionId!.Value)
        .ToHashSet();

    foreach (var row in reviewQueueRows)
    {
        if (!ReviewWorkbenchMutationHelpers.QueueItemMatchesCandidates(row.Payload, candidateSourceRegionIds))
        {
            continue;
        }

        row.Status = normalizedAction is "skip" ? ReviewStatuses.Dismissed : ReviewStatuses.Resolved;
        row.ResolvedAt = now;
        row.Payload = ReviewQueuePayloadHelpers.WithReviewAudit(
            row.Payload,
            string.IsNullOrWhiteSpace(request.ReviewedBy) ? "workbench" : request.ReviewedBy.Trim(),
            normalizedAction,
            string.IsNullOrWhiteSpace(request.Reason) ? "workbench_action" : request.Reason.Trim(),
            now);
        touchedIds.Add(row.Id);
    }

    await dbContext.SaveChangesAsync(cancellationToken);
    return Results.Ok(new ReviewWorkbenchActionResponse(
        normalizedAction,
        request.SourceDocumentId,
        touchedIds.Distinct().ToArray(),
        createdCandidateIds,
        skippedIds,
        createdQuestionId));
})
.WithName("ApplyReviewWorkbenchAction");

app.MapPost("/questions", async (
    QuestionCreateRequest request,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    var validationError = ValidateQuestionCreateRequest(request);
    if (validationError is not null)
    {
        return Results.BadRequest(new { error = validationError });
    }

    if (request.DifficultyEstimated is < 0 or > 1)
    {
        return Results.BadRequest(new { error = "invalid_difficulty_estimated" });
    }

    if (request.PrimaryKnowledgeId.HasValue)
    {
        var primaryKnowledgeExists = await dbContext.KnowledgeNodes
            .AsNoTracking()
            .AnyAsync(x => x.Id == request.PrimaryKnowledgeId.Value, cancellationToken);
        if (!primaryKnowledgeExists)
        {
            return Results.Conflict(new { error = "primary_knowledge_missing" });
        }
    }

    var sourceRegionIds = request.Blocks
        .Select(x => x.SourceRegionId)
        .Concat(request.Assets.Select(x => x.SourceRegionId))
        .Where(x => x.HasValue)
        .Select(x => x!.Value)
        .Distinct()
        .ToArray();
    if (sourceRegionIds.Length > 0)
    {
        var found = await dbContext.SourceRegions
            .Where(x => sourceRegionIds.Contains(x.Id))
            .Select(x => x.Id)
            .ToListAsync(cancellationToken);
        if (found.Count != sourceRegionIds.Length)
        {
            return Results.Conflict(new { error = "source_region_missing" });
        }
    }

    var fileAssetIds = request.Assets
        .Select(x => x.FileAssetId)
        .Where(x => x.HasValue)
        .Select(x => x!.Value)
        .Distinct()
        .ToArray();
    if (fileAssetIds.Length > 0)
    {
        var found = await dbContext.FileAssets
            .Where(x => fileAssetIds.Contains(x.Id))
            .Select(x => x.Id)
            .ToListAsync(cancellationToken);
        if (found.Count != fileAssetIds.Length)
        {
            return Results.Conflict(new { error = "file_asset_missing" });
        }
    }

    await using var transaction = await dbContext.Database.BeginTransactionAsync(cancellationToken);
    var now = DateTimeOffset.UtcNow;
    var item = new QuestionItem
    {
        Subject = NormalizeToken(request.Subject, "physics"),
        Stage = NormalizeToken(request.Stage, "junior_middle_school"),
        Grade = string.IsNullOrWhiteSpace(request.Grade) ? null : request.Grade.Trim(),
        QuestionType = string.IsNullOrWhiteSpace(request.QuestionType) ? null : NormalizeToken(request.QuestionType, "unknown"),
        DefaultScore = request.DefaultScore,
        DifficultyEstimated = request.DifficultyEstimated,
        Status = string.IsNullOrWhiteSpace(request.Status) ? QuestionStatuses.Draft : NormalizeToken(request.Status, QuestionStatuses.Draft),
        PrimaryKnowledgeId = request.PrimaryKnowledgeId,
        Blocks = SerializeJson(request.Blocks.Select((block, index) => new
        {
            type = NormalizeToken(block.BlockType, "text"),
            order = block.SortOrder ?? index,
            content = block.Content,
            source_region_id = block.SourceRegionId
        })),
        CustomFields = SerializeJson(new
        {
            answer = request.Answer,
            solution = request.Solution
        }),
        QualitySignals = "{}",
        CreatedAt = now,
        UpdatedAt = now
    };

    dbContext.QuestionItems.Add(item);
    await dbContext.SaveChangesAsync(cancellationToken);

    var blocks = request.Blocks.Select((block, index) => new QuestionBlock
    {
        QuestionItemId = item.Id,
        BlockType = NormalizeToken(block.BlockType, "text"),
        SortOrder = block.SortOrder ?? index,
        Content = SerializeJson(block.Content),
        SourceRegionId = block.SourceRegionId
    }).ToArray();

    var assets = request.Assets.Select(asset => new QuestionAsset
    {
        QuestionItemId = item.Id,
        FileAssetId = asset.FileAssetId,
        SourceRegionId = asset.SourceRegionId,
        AssetType = NormalizeToken(asset.AssetType, "image"),
        Purpose = string.IsNullOrWhiteSpace(asset.Purpose) ? "question_content" : NormalizeToken(asset.Purpose, "question_content"),
        Metadata = SerializeJson(asset.Metadata)
    }).ToArray();

    dbContext.QuestionBlocks.AddRange(blocks);
    dbContext.QuestionAssets.AddRange(assets);
    await dbContext.SaveChangesAsync(cancellationToken);

    var tableReviewItems = blocks
        .Where(RequiresTableBlockReview)
        .Select(block => CreateTableBlockReviewItem(item, block, now))
        .ToArray();
    if (tableReviewItems.Length > 0)
    {
        dbContext.ReviewQueueItems.AddRange(tableReviewItems);
        await dbContext.SaveChangesAsync(cancellationToken);
    }

    var formulaReviewItems = blocks
        .Where(RequiresFormulaBlockReview)
        .Select(block => CreateFormulaBlockReviewItem(item, block, now))
        .ToArray();
    if (formulaReviewItems.Length > 0)
    {
        dbContext.ReviewQueueItems.AddRange(formulaReviewItems);
        await dbContext.SaveChangesAsync(cancellationToken);
    }

    await transaction.CommitAsync(cancellationToken);

    return Results.Created($"/questions/{item.Id}", QuestionResponse.From(item, blocks, assets));
})
.WithName("CreateQuestion");

app.MapGet("/questions", async (
    string? subject,
    string? stage,
    string? grade,
    string? questionType,
    string? status,
    Guid? primaryKnowledgeId,
    double? difficultyMin,
    double? difficultyMax,
    string? sourceType,
    bool? hasFormula,
    bool? hasTable,
    bool? hasImage,
    string? knowledgeStatus,
    int? knowledgeVersion,
    string? sortBy,
    string? order,
    int? page,
    int? limit,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    var query = dbContext.QuestionItems.AsNoTracking().AsQueryable();

    if (!string.IsNullOrWhiteSpace(subject))
    {
        var value = NormalizeToken(subject, "physics");
        query = query.Where(x => x.Subject == value);
    }

    if (!string.IsNullOrWhiteSpace(stage))
    {
        var value = NormalizeToken(stage, "junior_middle_school");
        query = query.Where(x => x.Stage == value);
    }

    if (!string.IsNullOrWhiteSpace(grade))
    {
        var value = grade.Trim();
        query = query.Where(x => x.Grade == value);
    }

    if (!string.IsNullOrWhiteSpace(questionType))
    {
        var value = NormalizeToken(questionType, "unknown");
        query = query.Where(x => x.QuestionType == value);
    }

    if (!string.IsNullOrWhiteSpace(status))
    {
        var value = NormalizeToken(status, QuestionStatuses.Draft);
        query = query.Where(x => x.Status == value);
    }

    if (primaryKnowledgeId.HasValue)
    {
        query = query.Where(x => x.PrimaryKnowledgeId == primaryKnowledgeId.Value);
    }
    else
    {
        var normalizedKnowledgeStatus = string.IsNullOrWhiteSpace(knowledgeStatus)
            ? KnowledgeStatuses.Active
            : NormalizeToken(knowledgeStatus, KnowledgeStatuses.Active);
        var normalizedKnowledgeVersion = knowledgeVersion.GetValueOrDefault(1);
        var knowledgeIds = dbContext.KnowledgeNodes
            .AsNoTracking()
            .Where(x => x.Status == normalizedKnowledgeStatus && x.Version == normalizedKnowledgeVersion)
            .Select(x => x.Id);
        query = query.Where(x => x.PrimaryKnowledgeId.HasValue && knowledgeIds.Contains(x.PrimaryKnowledgeId.Value));
    }

    if (difficultyMin.HasValue)
    {
        query = query.Where(x => x.DifficultyEstimated != null && x.DifficultyEstimated >= difficultyMin.Value);
    }

    if (difficultyMax.HasValue)
    {
        query = query.Where(x => x.DifficultyEstimated != null && x.DifficultyEstimated <= difficultyMax.Value);
    }

    if (!string.IsNullOrWhiteSpace(sourceType))
    {
        var value = NormalizeToken(sourceType, "unknown");
        var blockQuestionIds =
            from block in dbContext.QuestionBlocks.AsNoTracking()
            where block.SourceRegionId != null
            join region in dbContext.SourceRegions.AsNoTracking() on block.SourceRegionId!.Value equals region.Id
            join document in dbContext.SourceDocuments.AsNoTracking() on region.SourceDocumentId equals document.Id
            where document.SourceType == value
            select block.QuestionItemId;
        var assetQuestionIds =
            from asset in dbContext.QuestionAssets.AsNoTracking()
            where asset.SourceRegionId != null
            join region in dbContext.SourceRegions.AsNoTracking() on asset.SourceRegionId!.Value equals region.Id
            join document in dbContext.SourceDocuments.AsNoTracking() on region.SourceDocumentId equals document.Id
            where document.SourceType == value
            select asset.QuestionItemId;
        var sourceQuestionIds = blockQuestionIds.Concat(assetQuestionIds).Distinct();
        query = query.Where(x => sourceQuestionIds.Contains(x.Id));
    }

    if (hasFormula.HasValue)
    {
        var formulaQuestionIds = dbContext.QuestionBlocks
            .AsNoTracking()
            .Where(x => x.BlockType == "formula")
            .Select(x => x.QuestionItemId)
            .Distinct();
        query = hasFormula.Value
            ? query.Where(x => formulaQuestionIds.Contains(x.Id))
            : query.Where(x => !formulaQuestionIds.Contains(x.Id));
    }

    if (hasTable.HasValue)
    {
        var tableQuestionIds = dbContext.QuestionBlocks
            .AsNoTracking()
            .Where(x => x.BlockType == "table")
            .Select(x => x.QuestionItemId)
            .Distinct();
        query = hasTable.Value
            ? query.Where(x => tableQuestionIds.Contains(x.Id))
            : query.Where(x => !tableQuestionIds.Contains(x.Id));
    }

    if (hasImage.HasValue)
    {
        var imageQuestionIds = dbContext.QuestionAssets
            .AsNoTracking()
            .Where(x => x.AssetType == "image")
            .Select(x => x.QuestionItemId)
            .Distinct();
        query = hasImage.Value
            ? query.Where(x => imageQuestionIds.Contains(x.Id))
            : query.Where(x => !imageQuestionIds.Contains(x.Id));
    }

    var pageSize = Math.Clamp(limit ?? 20, 1, 50);
    var pageIndex = Math.Max(1, page ?? 1);
    var offset = (pageIndex - 1) * pageSize;
    var normalizedSortBy = NormalizeToken(sortBy ?? string.Empty, "updated_at");
    var sortDescending = string.Equals(NormalizeToken(order ?? string.Empty, "desc"), "desc", StringComparison.OrdinalIgnoreCase);
    int total;
    List<QuestionItem> items;
    if (normalizedSortBy is "question_no" or "exam_question_no")
    {
        var allItems = await query.ToListAsync(cancellationToken);
        total = allItems.Count;
        var sorted = sortDescending
            ? allItems
                .OrderByDescending(x => TryGetIntCustomField(x.CustomFields, "questionNo") ?? int.MinValue)
                .ThenByDescending(x => x.UpdatedAt)
                .ThenByDescending(x => x.CreatedAt)
            : allItems
                .OrderBy(x => TryGetIntCustomField(x.CustomFields, "questionNo") ?? int.MaxValue)
                .ThenBy(x => x.UpdatedAt)
                .ThenBy(x => x.CreatedAt);
        items = sorted
            .Skip(offset)
            .Take(pageSize)
            .ToList();
    }
    else
    {
        total = await query.CountAsync(cancellationToken);
        items = await query
            .OrderByDescending(x => x.UpdatedAt)
            .ThenByDescending(x => x.CreatedAt)
            .Skip(offset)
            .Take(pageSize)
            .ToListAsync(cancellationToken);
    }

    var questionIds = items.Select(x => x.Id).ToArray();
    var blocks = await dbContext.QuestionBlocks
        .AsNoTracking()
        .Where(x => questionIds.Contains(x.QuestionItemId))
        .OrderBy(x => x.SortOrder)
        .ToListAsync(cancellationToken);
    var assets = await dbContext.QuestionAssets
        .AsNoTracking()
        .Where(x => questionIds.Contains(x.QuestionItemId))
        .ToListAsync(cancellationToken);

    var primaryKnowledgeIds = items
        .Select(x => x.PrimaryKnowledgeId)
        .Where(x => x.HasValue)
        .Select(x => x!.Value)
        .Distinct()
        .ToArray();
    var knowledgeById = await dbContext.KnowledgeNodes
        .AsNoTracking()
        .Where(x => primaryKnowledgeIds.Contains(x.Id))
        .ToDictionaryAsync(x => x.Id, cancellationToken);

    var sourceRows = await (
        from block in dbContext.QuestionBlocks.AsNoTracking()
        where questionIds.Contains(block.QuestionItemId) && block.SourceRegionId != null
        join region in dbContext.SourceRegions.AsNoTracking() on block.SourceRegionId!.Value equals region.Id
        join document in dbContext.SourceDocuments.AsNoTracking() on region.SourceDocumentId equals document.Id
        select new
        {
            block.QuestionItemId,
            document.SourceTitle,
            document.SourceType,
            document.LicenseOrPermission,
            document.SharingAllowed,
            document.ContainsStudentPii,
            document.AnonymizationStatus,
            HasScreenshot = !string.IsNullOrWhiteSpace(region.ScreenshotRelativePath)
        }
    ).Concat(
        from asset in dbContext.QuestionAssets.AsNoTracking()
        where questionIds.Contains(asset.QuestionItemId) && asset.SourceRegionId != null
        join region in dbContext.SourceRegions.AsNoTracking() on asset.SourceRegionId!.Value equals region.Id
        join document in dbContext.SourceDocuments.AsNoTracking() on region.SourceDocumentId equals document.Id
        select new
        {
            asset.QuestionItemId,
            document.SourceTitle,
            document.SourceType,
            document.LicenseOrPermission,
            document.SharingAllowed,
            document.ContainsStudentPii,
            document.AnonymizationStatus,
            HasScreenshot = !string.IsNullOrWhiteSpace(region.ScreenshotRelativePath)
        }
    ).ToListAsync(cancellationToken);

    var blockByQuestionId = blocks.GroupBy(x => x.QuestionItemId).ToDictionary(x => x.Key, x => x.ToArray());
    var assetCountByQuestionId = assets.GroupBy(x => x.QuestionItemId).ToDictionary(x => x.Key, x => x.Count());
    var hasFormulaByQuestionId = blocks
        .Where(x => x.BlockType == "formula")
        .GroupBy(x => x.QuestionItemId)
        .ToDictionary(x => x.Key, _ => true);
    var hasTableByQuestionId = blocks
        .Where(x => x.BlockType == "table")
        .GroupBy(x => x.QuestionItemId)
        .ToDictionary(x => x.Key, _ => true);
    var hasImageByQuestionId = assets
        .Where(x => x.AssetType == "image")
        .GroupBy(x => x.QuestionItemId)
        .ToDictionary(x => x.Key, _ => true);
    var sourceByQuestionId = sourceRows
        .GroupBy(x => x.QuestionItemId)
        .ToDictionary(
            x => x.Key,
            x => new SourceSummaryResponse(
                x.Select(row => row.SourceTitle).Where(value => !string.IsNullOrWhiteSpace(value)).Distinct().ToArray(),
                x.Select(row => row.SourceType).Where(value => !string.IsNullOrWhiteSpace(value)).Distinct().ToArray(),
                x.Select(row => row.LicenseOrPermission).Where(value => !string.IsNullOrWhiteSpace(value)).Distinct().ToArray(),
                x.All(row => row.SharingAllowed),
                x.Any(row => row.ContainsStudentPii),
                x.Select(row => row.AnonymizationStatus).Where(value => !string.IsNullOrWhiteSpace(value)).Distinct().ToArray(),
                x.Count(),
                x.Count(row => row.HasScreenshot)));

    var cards = items.Select(item =>
    {
        blockByQuestionId.TryGetValue(item.Id, out var itemBlocks);
        assetCountByQuestionId.TryGetValue(item.Id, out var assetCount);
        sourceByQuestionId.TryGetValue(item.Id, out var sourceSummary);
        var primaryKnowledge = item.PrimaryKnowledgeId.HasValue && knowledgeById.TryGetValue(item.PrimaryKnowledgeId.Value, out var node)
            ? KnowledgeNodeCardResponse.From(node)
            : null;

        return new QuestionCardResponse(
            item.Id,
            item.Subject,
            item.Stage,
            item.Grade,
            item.QuestionType,
            item.DefaultScore,
            item.DifficultyEstimated,
            item.Status,
            TryGetIntCustomField(item.CustomFields, "questionNo"),
            primaryKnowledge,
            GetQuestionPreview(itemBlocks ?? []),
            itemBlocks?.Length ?? 0,
            assetCount,
            sourceSummary ?? new SourceSummaryResponse([], [], [], false, false, [], 0, 0),
            hasFormulaByQuestionId.ContainsKey(item.Id),
            hasTableByQuestionId.ContainsKey(item.Id),
            hasImageByQuestionId.ContainsKey(item.Id));
    }).ToArray();

    return Results.Ok(new QuestionSearchResponse(
        Mode: "draft_test",
        ProductionEligible: false,
        Total: total,
        Page: pageIndex,
        Limit: pageSize,
        KnowledgeStatus: primaryKnowledgeId.HasValue
            ? "by_primary_knowledge_id"
            : (string.IsNullOrWhiteSpace(knowledgeStatus) ? KnowledgeStatuses.Active : NormalizeToken(knowledgeStatus, KnowledgeStatuses.Active)),
        KnowledgeVersion: primaryKnowledgeId.HasValue
            ? null
            : (knowledgeVersion ?? 1),
        Items: cards));
})
.WithName("SearchQuestionCards");

app.MapGet("/questions/{id:guid}", async (Guid id, KqgDbContext dbContext, CancellationToken cancellationToken) =>
{
    var item = await dbContext.QuestionItems.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (item is null)
    {
        return Results.NotFound();
    }

    var blocks = await dbContext.QuestionBlocks
        .AsNoTracking()
        .Where(x => x.QuestionItemId == id)
        .OrderBy(x => x.SortOrder)
        .ToListAsync(cancellationToken);
    var assets = await dbContext.QuestionAssets
        .AsNoTracking()
        .Where(x => x.QuestionItemId == id)
        .OrderBy(x => x.CreatedAt)
        .ToListAsync(cancellationToken);

    return Results.Ok(QuestionResponse.From(item, blocks, assets));
})
.WithName("GetQuestion");

app.MapPatch("/questions/{id:guid}", async (
    Guid id,
    QuestionUpdateRequest request,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request.ReviewedBy))
    {
        return Results.BadRequest(new { error = "reviewed_by_required" });
    }

    if (string.IsNullOrWhiteSpace(request.Reason))
    {
        return Results.BadRequest(new { error = "reason_required" });
    }

    var item = await dbContext.QuestionItems.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (item is null)
    {
        return Results.NotFound(new { error = "question_not_found" });
    }

    if (request.DifficultyEstimated is < 0 or > 1)
    {
        return Results.BadRequest(new { error = "invalid_difficulty_estimated" });
    }

    if (request.PrimaryKnowledgeId.HasValue)
    {
        var knowledgeExists = await dbContext.KnowledgeNodes
            .AsNoTracking()
            .AnyAsync(x => x.Id == request.PrimaryKnowledgeId.Value, cancellationToken);
        if (!knowledgeExists)
        {
            return Results.Conflict(new { error = "primary_knowledge_missing", primaryKnowledgeId = request.PrimaryKnowledgeId.Value });
        }
    }

    var requestedBlocks = request.Blocks ?? [];
    foreach (var block in requestedBlocks)
    {
        if (!string.IsNullOrWhiteSpace(block.BlockType) && !IsAllowedQuestionBlockType(NormalizeToken(block.BlockType, "text")))
        {
            return Results.BadRequest(new { error = "invalid_block_type" });
        }
    }

    var sourceRegionIds = requestedBlocks
        .Select(x => x.SourceRegionId)
        .Where(x => x.HasValue)
        .Select(x => x!.Value)
        .Distinct()
        .ToArray();
    if (sourceRegionIds.Length > 0)
    {
        var found = await dbContext.SourceRegions
            .AsNoTracking()
            .Where(x => sourceRegionIds.Contains(x.Id))
            .Select(x => x.Id)
            .ToListAsync(cancellationToken);
        if (found.Count != sourceRegionIds.Length)
        {
            return Results.Conflict(new { error = "source_region_missing" });
        }
    }

    var blocks = await dbContext.QuestionBlocks
        .Where(x => x.QuestionItemId == id)
        .OrderBy(x => x.SortOrder)
        .ToListAsync(cancellationToken);
    var assets = await dbContext.QuestionAssets
        .AsNoTracking()
        .Where(x => x.QuestionItemId == id)
        .OrderBy(x => x.CreatedAt)
        .ToListAsync(cancellationToken);
    var before = QuestionResponse.From(item, blocks, assets);

    if (!string.IsNullOrWhiteSpace(request.QuestionType))
    {
        item.QuestionType = NormalizeToken(request.QuestionType, "unknown");
    }
    if (request.DefaultScore.HasValue)
    {
        item.DefaultScore = request.DefaultScore;
    }
    if (request.DifficultyEstimated.HasValue)
    {
        item.DifficultyEstimated = request.DifficultyEstimated;
    }
    if (!string.IsNullOrWhiteSpace(request.Status))
    {
        item.Status = NormalizeToken(request.Status, QuestionStatuses.Draft);
    }
    if (request.PrimaryKnowledgeId.HasValue)
    {
        item.PrimaryKnowledgeId = request.PrimaryKnowledgeId.Value;
        var primaryMappings = await dbContext.KnowledgeMappings
            .Where(x => x.QuestionItemId == id && x.IsPrimary)
            .ToListAsync(cancellationToken);
        foreach (var mapping in primaryMappings)
        {
            mapping.IsPrimary = false;
        }

        var targetMapping = await dbContext.KnowledgeMappings
            .FirstOrDefaultAsync(
                x => x.QuestionItemId == id && x.KnowledgeNodeId == request.PrimaryKnowledgeId.Value,
                cancellationToken);
        if (targetMapping is null)
        {
            dbContext.KnowledgeMappings.Add(new KnowledgeMapping
            {
                QuestionItemId = id,
                KnowledgeNodeId = request.PrimaryKnowledgeId.Value,
                MappingSource = KnowledgeMappingSources.Manual,
                IsPrimary = true,
                Confidence = 1.0m,
                Version = 1,
                Evidence = SerializeJson(new
                {
                    source = "question_update",
                    reviewedBy = request.ReviewedBy.Trim(),
                    reason = request.Reason.Trim()
                }),
                CreatedAt = DateTimeOffset.UtcNow
            });
        }
        else
        {
            targetMapping.MappingSource = KnowledgeMappingSources.Manual;
            targetMapping.IsPrimary = true;
            targetMapping.Confidence = 1.0m;
            targetMapping.Version = 1;
            targetMapping.Evidence = SerializeJson(new
            {
                source = "question_update",
                reviewedBy = request.ReviewedBy.Trim(),
                reason = request.Reason.Trim()
            });
        }
    }

    var blockById = blocks.ToDictionary(x => x.Id);
    var nextSortOrder = blocks.Count == 0 ? 0 : blocks.Max(x => x.SortOrder) + 1;
    foreach (var blockPatch in requestedBlocks)
    {
        QuestionBlock block;
        if (blockPatch.Id.HasValue)
        {
            if (!blockById.TryGetValue(blockPatch.Id.Value, out block!))
            {
                return Results.Conflict(new { error = "question_block_missing", blockId = blockPatch.Id.Value });
            }
        }
        else
        {
            block = new QuestionBlock
            {
                QuestionItemId = id,
                BlockType = "text",
                SortOrder = nextSortOrder++,
                Content = "{}",
                CreatedAt = DateTimeOffset.UtcNow
            };
            dbContext.QuestionBlocks.Add(block);
            blocks.Add(block);
        }

        if (!string.IsNullOrWhiteSpace(blockPatch.BlockType))
        {
            block.BlockType = NormalizeToken(blockPatch.BlockType, "text");
        }
        if (blockPatch.SortOrder.HasValue)
        {
            block.SortOrder = blockPatch.SortOrder.Value;
        }
        if (blockPatch.Content.HasValue)
        {
            block.Content = SerializeJson(blockPatch.Content.Value);
        }
        if (blockPatch.SourceRegionId.HasValue)
        {
            block.SourceRegionId = blockPatch.SourceRegionId;
        }
    }

    var answer = request.Answer.HasValue
        ? request.Answer.Value.Clone()
        : TryGetCustomFieldElement(item.CustomFields, "answer");
    var solution = request.Solution.HasValue
        ? request.Solution.Value.Clone()
        : TryGetCustomFieldElement(item.CustomFields, "solution");
    item.CustomFields = MergeQuestionCustomFields(item.CustomFields, answer, solution);
    item.Blocks = SerializeJson(blocks.OrderBy(x => x.SortOrder).Select(block => new
    {
        type = block.BlockType,
        order = block.SortOrder,
        content = JsonHelpers.ParseJsonElement(block.Content),
        source_region_id = block.SourceRegionId
    }));
    item.UpdatedAt = DateTimeOffset.UtcNow;

    var now = DateTimeOffset.UtcNow;
    var audit = new ReviewQueueItem
    {
        ReviewType = "question_revision",
        Status = ReviewStatuses.Resolved,
        CreatedAt = now,
        ResolvedAt = now,
        Payload = JsonSerializer.Serialize(new
        {
            questionItemId = id,
            before,
            after = QuestionResponse.From(item, blocks.OrderBy(x => x.SortOrder).ToList(), assets),
            reviewAudit = new
            {
                reviewedBy = request.ReviewedBy.Trim(),
                decision = "question_updated",
                reason = request.Reason.Trim(),
                reviewedAt = now.ToString("O")
            }
        })
    };
    dbContext.ReviewQueueItems.Add(audit);

    await dbContext.SaveChangesAsync(cancellationToken);
    var afterBlocks = await dbContext.QuestionBlocks
        .AsNoTracking()
        .Where(x => x.QuestionItemId == id)
        .OrderBy(x => x.SortOrder)
        .ToListAsync(cancellationToken);
    return Results.Ok(new QuestionRevisionResponse(QuestionResponse.From(item, afterBlocks, assets), audit.Id));
})
.WithName("UpdateQuestion");

app.MapPost("/questions/{id:guid}/assets", async (
    Guid id,
    QuestionAssetAssociationRequest request,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request.ReviewedBy))
    {
        return Results.BadRequest(new { error = "reviewed_by_required" });
    }

    if (string.IsNullOrWhiteSpace(request.Reason))
    {
        return Results.BadRequest(new { error = "reason_required" });
    }

    var itemExists = await dbContext.QuestionItems.AsNoTracking().AnyAsync(x => x.Id == id, cancellationToken);
    if (!itemExists)
    {
        return Results.NotFound(new { error = "question_not_found" });
    }

    var sourceRegionExists = await dbContext.SourceRegions
        .AsNoTracking()
        .AnyAsync(x => x.Id == request.SourceRegionId, cancellationToken);
    if (!sourceRegionExists)
    {
        return Results.Conflict(new { error = "source_region_missing" });
    }

    if (request.FileAssetId.HasValue)
    {
        var fileAssetExists = await dbContext.FileAssets
            .AsNoTracking()
            .AnyAsync(x => x.Id == request.FileAssetId.Value, cancellationToken);
        if (!fileAssetExists)
        {
            return Results.Conflict(new { error = "file_asset_missing" });
        }
    }

    var now = DateTimeOffset.UtcNow;
    var asset = new QuestionAsset
    {
        QuestionItemId = id,
        FileAssetId = request.FileAssetId,
        SourceRegionId = request.SourceRegionId,
        AssetType = string.IsNullOrWhiteSpace(request.AssetType) ? "image" : NormalizeToken(request.AssetType, "image"),
        Purpose = string.IsNullOrWhiteSpace(request.Purpose) ? "question_figure" : NormalizeToken(request.Purpose, "question_figure"),
        Metadata = SerializeJson(request.Metadata),
        CreatedAt = now
    };
    dbContext.QuestionAssets.Add(asset);

    var audit = new ReviewQueueItem
    {
        ReviewType = "question_asset_revision",
        Status = ReviewStatuses.Resolved,
        CreatedAt = now,
        ResolvedAt = now,
        Payload = JsonSerializer.Serialize(new
        {
            questionItemId = id,
            questionAssetId = asset.Id,
            sourceRegionId = asset.SourceRegionId,
            fileAssetId = asset.FileAssetId,
            assetType = asset.AssetType,
            purpose = asset.Purpose,
            decision = "question_asset_associated",
            reviewAudit = new
            {
                reviewedBy = request.ReviewedBy.Trim(),
                decision = "question_asset_associated",
                reason = request.Reason.Trim(),
                reviewedAt = now.ToString("O")
            }
        })
    };
    dbContext.ReviewQueueItems.Add(audit);

    await dbContext.SaveChangesAsync(cancellationToken);
    return Results.Created($"/questions/{id}/assets/{asset.Id}", new QuestionAssetRevisionResponse(QuestionAssetResponse.From(asset), audit.Id));
})
.WithName("AssociateQuestionAsset");

app.MapDelete("/questions/{id:guid}/assets/{assetId:guid}", async (
    Guid id,
    Guid assetId,
    string reviewedBy,
    string reason,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(reviewedBy))
    {
        return Results.BadRequest(new { error = "reviewed_by_required" });
    }

    if (string.IsNullOrWhiteSpace(reason))
    {
        return Results.BadRequest(new { error = "reason_required" });
    }

    var asset = await dbContext.QuestionAssets.FirstOrDefaultAsync(x => x.Id == assetId && x.QuestionItemId == id, cancellationToken);
    if (asset is null)
    {
        return Results.NotFound(new { error = "question_asset_not_found" });
    }

    var now = DateTimeOffset.UtcNow;
    var sourceRegionId = asset.SourceRegionId;
    var fileAssetId = asset.FileAssetId;
    var assetType = asset.AssetType;
    var purpose = asset.Purpose;
    dbContext.QuestionAssets.Remove(asset);

    var audit = new ReviewQueueItem
    {
        ReviewType = "question_asset_revision",
        Status = ReviewStatuses.Resolved,
        CreatedAt = now,
        ResolvedAt = now,
        Payload = JsonSerializer.Serialize(new
        {
            questionItemId = id,
            questionAssetId = assetId,
            sourceRegionId,
            fileAssetId,
            assetType,
            purpose,
            decision = "question_asset_unlinked",
            reviewAudit = new
            {
                reviewedBy = reviewedBy.Trim(),
                decision = "question_asset_unlinked",
                reason = reason.Trim(),
                reviewedAt = now.ToString("O")
            }
        })
    };
    dbContext.ReviewQueueItems.Add(audit);

    await dbContext.SaveChangesAsync(cancellationToken);
    return Results.Ok(new QuestionAssetUnlinkResponse(id, assetId, sourceRegionId, audit.Id));
})
.WithName("UnlinkQuestionAsset");

app.MapGet("/questions/{id:guid}/sources", async (
    Guid id,
    KqgDbContext dbContext,
    IConfiguration configuration,
    CancellationToken cancellationToken) =>
{
    var itemExists = await dbContext.QuestionItems.AsNoTracking().AnyAsync(x => x.Id == id, cancellationToken);
    if (!itemExists)
    {
        return Results.NotFound();
    }

    var blockRegionIds = dbContext.QuestionBlocks
        .AsNoTracking()
        .Where(x => x.QuestionItemId == id && x.SourceRegionId != null)
        .Select(x => x.SourceRegionId!.Value);
    var assetRegionIds = dbContext.QuestionAssets
        .AsNoTracking()
        .Where(x => x.QuestionItemId == id && x.SourceRegionId != null)
        .Select(x => x.SourceRegionId!.Value);
    var sourceRegionIds = await blockRegionIds
        .Concat(assetRegionIds)
        .Distinct()
        .ToListAsync(cancellationToken);

    var regions = await dbContext.SourceRegions
        .AsNoTracking()
        .Where(x => sourceRegionIds.Contains(x.Id))
        .OrderBy(x => x.PageNumber)
        .ThenBy(x => x.CreatedAt)
        .ToListAsync(cancellationToken);

    var sourceDocumentIds = regions.Select(x => x.SourceDocumentId).Distinct().ToArray();
    var documents = await dbContext.SourceDocuments
        .AsNoTracking()
        .Where(x => sourceDocumentIds.Contains(x.Id))
        .ToDictionaryAsync(x => x.Id, cancellationToken);

    var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
    var missingScreenshot = regions.FirstOrDefault(x =>
        !string.IsNullOrWhiteSpace(x.ScreenshotRelativePath) &&
        (!TryResolveFileStorePath(paths.FileStoreRoot, x.ScreenshotRelativePath, out var screenshotPath) || !File.Exists(screenshotPath)));
    if (missingScreenshot is not null)
    {
        return Results.Conflict(new { error = "question_source_screenshot_missing", regionId = missingScreenshot.Id, missingScreenshot.ScreenshotRelativePath });
    }

    return Results.Ok(new QuestionSourceReviewResponse(
        id,
        regions.Select(region =>
        {
            documents.TryGetValue(region.SourceDocumentId, out var document);
            return QuestionSourceRegionResponse.From(region, document);
        }).ToArray()));
})
.WithName("GetQuestionSources");

app.MapPost("/paper-baskets", async (
    PaperBasketCreateRequest request,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    if (request.Items.Count == 0)
    {
        return Results.BadRequest(new { error = "paper_basket_items_required" });
    }

    var questionIds = request.Items.Select(x => x.QuestionItemId).Distinct().ToArray();
    var questions = await dbContext.QuestionItems
        .AsNoTracking()
        .Where(x => questionIds.Contains(x.Id))
        .ToDictionaryAsync(x => x.Id, cancellationToken);
    if (questions.Count != questionIds.Length)
    {
        return Results.Conflict(new { error = "paper_basket_question_missing" });
    }

    var now = DateTimeOffset.UtcNow;
    var normalizedKnowledgeStatus = string.IsNullOrWhiteSpace(request.KnowledgeVersionStatus)
        ? KnowledgeStatuses.Active
        : NormalizeToken(request.KnowledgeVersionStatus, KnowledgeStatuses.Active);
    var knowledgeVersion = request.KnowledgeVersion ?? 1;
    var orderedItems = request.Items
        .Select((item, index) => new { Item = item, SortOrder = item.SortOrder ?? index })
        .OrderBy(x => x.SortOrder)
        .ToArray();

    var basket = new PaperBasket
    {
        Title = string.IsNullOrWhiteSpace(request.Title) ? "未命名试卷" : request.Title.Trim(),
        Subject = NormalizeToken(request.Subject, "physics"),
        Stage = NormalizeToken(request.Stage, "junior_middle_school"),
        Grade = string.IsNullOrWhiteSpace(request.Grade) ? null : request.Grade.Trim(),
        Status = "draft",
        KnowledgeVersionStatus = normalizedKnowledgeStatus,
        KnowledgeVersion = knowledgeVersion,
        Structure = SerializeJson(new
        {
            itemCount = orderedItems.Length,
            totalScore = orderedItems.Sum(x => x.Item.Score),
            sections = orderedItems.GroupBy(x => x.Item.SectionNo).Select(group => new
            {
                sectionNo = group.Key,
                questionCount = group.Count(),
                score = group.Sum(x => x.Item.Score)
            }),
            knowledgeVersionStatus = normalizedKnowledgeStatus,
            knowledgeVersion
        }),
        CreatedAt = now,
        UpdatedAt = now
    };
    dbContext.PaperBaskets.Add(basket);
    await dbContext.SaveChangesAsync(cancellationToken);

    var basketItems = orderedItems.Select(row =>
    {
        var question = questions[row.Item.QuestionItemId];
        return new PaperBasketItem
        {
            PaperBasketId = basket.Id,
            QuestionItemId = question.Id,
            SectionNo = row.Item.SectionNo,
            QuestionNo = row.Item.QuestionNo,
            SubQuestionNo = string.IsNullOrWhiteSpace(row.Item.SubQuestionNo) ? null : row.Item.SubQuestionNo.Trim(),
            Score = row.Item.Score,
            SortOrder = row.SortOrder,
            KnowledgeVersionStatus = normalizedKnowledgeStatus,
            KnowledgeVersion = knowledgeVersion,
            Snapshot = SerializeJson(new
            {
                question.Subject,
                question.Stage,
                question.Grade,
                question.QuestionType,
                question.DifficultyEstimated,
                question.PrimaryKnowledgeId,
                question.UpdatedAt
            }),
            CreatedAt = now
        };
    }).ToArray();
    dbContext.PaperBasketItems.AddRange(basketItems);
    await dbContext.SaveChangesAsync(cancellationToken);

    return Results.Created($"/paper-baskets/{basket.Id}", PaperBasketResponse.From(basket, basketItems));
})
.WithName("CreatePaperBasket");

app.MapGet("/paper-baskets/{id:guid}", async (
    Guid id,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    var basket = await dbContext.PaperBaskets.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (basket is null)
    {
        return Results.NotFound();
    }

    var items = await dbContext.PaperBasketItems
        .AsNoTracking()
        .Where(x => x.PaperBasketId == id)
        .OrderBy(x => x.SortOrder)
        .ToListAsync(cancellationToken);

    return Results.Ok(PaperBasketResponse.From(basket, items));
})
.WithName("GetPaperBasket");

app.MapPost("/score-imports", async (
    ScoreImportRequest request,
    IScoreAnalysisWorkflowService workflowService,
    CancellationToken cancellationToken) =>
{
    var fieldMapping = request.FieldMapping ?? new ScoreImportFieldMappingRequest(
        string.Empty,
        string.Empty,
        new Dictionary<string, string>());
    var rows = request.Rows ?? Array.Empty<ScoreImportRowApiRequest>();
    var result = await workflowService.ImportScoresAsync(
        new ScoreImportServiceRequest(
            request.AssessmentKey,
            request.AssessmentTitle,
            request.Subject,
            request.Stage,
            request.Grade,
            request.TemplateKey,
            request.TemplateDisplayName,
            request.SourceFileName,
            request.ContainsStudentPii,
            request.ProductionEligible,
            request.MaxTotalScore,
            new ScoreImportFieldMapping(
                fieldMapping.StudentKey,
                fieldMapping.TotalScore,
                fieldMapping.ItemScores ?? new Dictionary<string, string>()),
            request.ItemMaxScores ?? new Dictionary<string, decimal>(),
            rows.Select(x => new ScoreImportRowRequest(
                x.RowNumber,
                x.Values ?? new Dictionary<string, string>())).ToArray()),
        cancellationToken);

    var response = ScoreImportResponse.From(result);
    return result.Status == "blocked"
        ? Results.BadRequest(response)
        : Results.Created($"/score-imports/{result.BatchId}", response);
})
.WithName("ImportScores");

app.MapPost("/assessments/{assessmentId:guid}/item-score-mappings/preview", async (
    Guid assessmentId,
    ItemScoreMappingPreviewRequest request,
    IScoreAnalysisWorkflowService workflowService,
    CancellationToken cancellationToken) =>
{
    var result = await workflowService.PreviewItemScoreMappingsAsync(
        assessmentId,
        new ItemScoreMappingPreviewServiceRequest(
            (request.Mappings ?? Array.Empty<ItemScoreMappingRequest>())
                .Select(x => new ItemScoreMappingRequestItem(x.QuestionNo, x.QuestionItemId))
                .ToArray()),
        cancellationToken);
    if (result is null)
    {
        return Results.NotFound(new { error = "assessment_not_found" });
    }

    return Results.Ok(ItemScoreMappingPreviewResponse.From(result));
})
.WithName("PreviewItemScoreMappings");

app.MapPost("/assessments/{assessmentId:guid}/commentary-report/export", async (
    Guid assessmentId,
    CommentaryReportExportRequest request,
    IScoreAnalysisWorkflowService workflowService,
    CancellationToken cancellationToken) =>
{
    var result = await workflowService.ExportCommentaryReportAsync(
        assessmentId,
        new CommentaryReportExportServiceRequest(
            request.Format,
            request.AllowAiDraftText,
            (request.Mappings ?? Array.Empty<ItemScoreMappingRequest>())
                .Select(x => new ItemScoreMappingRequestItem(x.QuestionNo, x.QuestionItemId))
                .ToArray()),
        cancellationToken);
    if (result is null)
    {
        return Results.NotFound(new { error = "assessment_not_found" });
    }

    var response = CommentaryReportExportResponse.From(result);
    return result.Status == "blocked"
        ? Results.Conflict(response)
        : Results.Ok(response);
})
.WithName("ExportCommentaryReport");

app.MapPost("/paper-baskets/{id:guid}/export-preflight", async (
    Guid id,
    PaperExportPreflightRequest request,
    IPaperWorkflowService workflowService,
    CancellationToken cancellationToken) =>
{
    var result = await workflowService.RunExportPreflightAsync(
        id,
        request.ExportFormat,
        cancellationToken);
    if (result is null)
    {
        return Results.NotFound();
    }

    return Results.Ok(PaperExportPreflightResponse.From(result));
})
.WithName("RunPaperExportPreflight");

app.MapPost("/paper-requests/parse", (PaperRequestParseRequest request, IPaperWorkflowService workflowService) =>
{
    if (string.IsNullOrWhiteSpace(request.TeacherRequest))
    {
        return Results.BadRequest(new { error = "teacher_request_required" });
    }

    var result = workflowService.ParsePaperRequest(request.TeacherRequest, request.TextbookVersion);
    return Results.Ok(new PaperRequestParseResponse(
        Mode: result.Mode,
        ProductionEligible: result.ProductionEligible,
        AllowRealModelCalls: result.AllowRealModelCalls,
        SchemaVersion: result.SchemaVersion,
        PromptVersion: result.PromptVersion,
        SystemUnderstanding: result.SystemUnderstanding,
        PaperType: result.PaperType,
        Subject: result.Subject,
        Grade: result.Grade,
        TextbookVersion: result.TextbookVersion,
        Scope: result.Scope,
        TotalScore: result.TotalScore,
        DifficultyTarget: result.DifficultyTarget,
        QuestionTypePlan: result.QuestionTypePlan.Select(x => new PaperQuestionTypePlan(x.QuestionType, x.Count, x.Score)).ToArray(),
        Blueprint: result.Blueprint.Select(x => new PaperBlueprintRow(x.QuestionType, x.Count, x.Score, x.Scope, x.AssetStatus, x.ReviewStatus)).ToArray(),
        Constraints: new PaperRequestConstraints(result.Constraints.KnowledgeStatus, result.Constraints.SourceTypes, result.Constraints.ReviewRequired, result.Constraints.BlocksProductionPaper),
        ReviewQuestions: result.ReviewQuestions));
})
.WithName("ParsePaperRequest");

app.MapPost("/paper-blueprints", async (
    PaperBlueprintReviewCreateRequest request,
    IPaperWorkflowService workflowService,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request.TeacherRequest))
    {
        return Results.BadRequest(new { error = "teacher_request_required" });
    }

    var result = await workflowService.CreateBlueprintReviewAsync(
        request.TeacherRequest,
        request.TextbookVersion,
        cancellationToken);

    return Results.Created($"/paper-blueprints/{result.Id}", PaperBlueprintReviewResponse.From(result));
})
.WithName("CreatePaperBlueprintReview");

app.MapPost("/paper-blueprints/{id:guid}/confirm", async (
    Guid id,
    PaperBlueprintConfirmRequest request,
    IPaperWorkflowService workflowService,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request.TeacherConfirmedBy))
    {
        return Results.BadRequest(new { error = "teacher_confirmed_by_required" });
    }

    var result = await workflowService.ConfirmBlueprintReviewAsync(
        id,
        request.TeacherConfirmedBy,
        cancellationToken);
    if (result is null)
    {
        return Results.NotFound();
    }

    if (!result.Confirmed)
    {
        return Results.Conflict(new
        {
            error = result.ErrorCode,
            result.Status,
            result.SelectedQuestionCount,
            result.TeacherMessage,
            result.AuditTrail
        });
    }

    return Results.Ok(PaperBlueprintConfirmResponse.From(result));
})
.WithName("ConfirmPaperBlueprintReview");

app.MapPost("/paper-requests/replace-question", (PaperQuestionReplacementRequest request, IPaperWorkflowService workflowService) =>
{
    if (request.CurrentQuestion is null)
    {
        return Results.BadRequest(new { error = "current_question_required" });
    }

    var serviceRequest = new PaperReplaceRequest(new PaperDraftQuestionServiceItem(
        request.CurrentQuestion.Id,
        request.CurrentQuestion.StemPreview,
        request.CurrentQuestion.QuestionType,
        request.CurrentQuestion.Score,
        request.CurrentQuestion.DifficultyEstimated,
        request.CurrentQuestion.PrimaryKnowledgeId,
        request.CurrentQuestion.PrimaryKnowledgeTitle,
        request.CurrentQuestion.SourceType,
        request.CurrentQuestion.RecentUseStatus));
    var result = workflowService.ReplaceQuestion(serviceRequest);

    var replacement = new PaperDraftQuestion(
        result.Replacement.Id,
        result.Replacement.StemPreview,
        result.Replacement.QuestionType,
        result.Replacement.Score,
        result.Replacement.DifficultyEstimated,
        result.Replacement.PrimaryKnowledgeId,
        result.Replacement.PrimaryKnowledgeTitle,
        result.Replacement.SourceType,
        result.Replacement.RecentUseStatus);
    var before = new PaperDraftQuestion(
        result.Undo.BeforeQuestion.Id,
        result.Undo.BeforeQuestion.StemPreview,
        result.Undo.BeforeQuestion.QuestionType,
        result.Undo.BeforeQuestion.Score,
        result.Undo.BeforeQuestion.DifficultyEstimated,
        result.Undo.BeforeQuestion.PrimaryKnowledgeId,
        result.Undo.BeforeQuestion.PrimaryKnowledgeTitle,
        result.Undo.BeforeQuestion.SourceType,
        result.Undo.BeforeQuestion.RecentUseStatus);
    var undo = new PaperQuestionUndoSnapshot(result.Undo.UndoToken, before, replacement, result.Undo.RevertAction);

    return Results.Ok(new PaperQuestionReplacementResponse(
        result.Mode,
        result.ProductionEligible,
        result.AllowRealModelCalls,
        result.Action,
        result.Reason,
        new PaperQuestionReplacementConstraints(
            result.Constraints.SameKnowledge,
            result.Constraints.SameQuestionType,
            result.Constraints.SimilarDifficulty,
            result.Constraints.SameScore,
            result.Constraints.ExcludeCurrentPaperDuplicates,
            result.Constraints.ExcludeRecentlyUsed,
            result.Constraints.KnowledgeStatus,
            result.Constraints.BlocksProductionPaper),
        replacement,
        undo,
        result.AuditTrail));
})
.WithName("ReplacePaperQuestion");

app.MapPost("/knowledge-version-explanations/resolve", (KnowledgeVersionExplanationRequest request, IPaperWorkflowService workflowService) =>
{
    if (string.IsNullOrWhiteSpace(request.ArtifactType))
    {
        return Results.BadRequest(new { error = "artifact_type_required" });
    }

    if (string.IsNullOrWhiteSpace(request.ArtifactId))
    {
        return Results.BadRequest(new { error = "artifact_id_required" });
    }

    if (string.IsNullOrWhiteSpace(request.HistoricalKnowledgeStableId))
    {
        return Results.BadRequest(new { error = "historical_knowledge_stable_id_required" });
    }

    if (string.IsNullOrWhiteSpace(request.HistoricalKnowledgeVersion))
    {
        return Results.BadRequest(new { error = "historical_knowledge_version_required" });
    }

    if (string.IsNullOrWhiteSpace(request.CurrentKnowledgeVersion))
    {
        return Results.BadRequest(new { error = "current_knowledge_version_required" });
    }

    if (request.CurrentKnowledgeStableIds.Count == 0)
    {
        return Results.BadRequest(new { error = "current_knowledge_stable_ids_required" });
    }

    var serviceResult = workflowService.ResolveKnowledgeVersionExplanation(new KnowledgeVersionExplanationServiceRequest(
        request.ArtifactType,
        request.ArtifactId,
        request.HistoricalKnowledgeStableId,
        request.HistoricalKnowledgeVersion,
        request.CurrentKnowledgeVersion,
        request.MappingType,
        request.CurrentKnowledgeStableIds,
        request.AffectsHistoricalAnalysis));

    var response = new KnowledgeVersionExplanationResponse(
        serviceResult.Mode,
        serviceResult.ProductionEligible,
        serviceResult.ReadOnly,
        serviceResult.RealStudentDataUsed,
        serviceResult.WritesProductionHistory,
        serviceResult.ArtifactType,
        serviceResult.ArtifactId,
        serviceResult.HistoricalKnowledgeStableId,
        serviceResult.HistoricalKnowledgeVersion,
        serviceResult.CurrentKnowledgeVersion,
        serviceResult.MappingType,
        serviceResult.CurrentKnowledgeStableIds,
        serviceResult.FrozenHistoricalView,
        serviceResult.CurrentVersionDifferent,
        serviceResult.AffectsHistoricalAnalysis,
        serviceResult.ExplanationText,
        serviceResult.TeacherVisibleSummary,
        serviceResult.AuditTrail);

    return Results.Ok(response);
})
.WithName("ResolveKnowledgeVersionExplanation");

app.MapPost("/imports/{id:guid}/status", async (
    Guid id,
    ImportJobStatusUpdate request,
    KqgDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    var job = await dbContext.ImportJobs.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (job is null)
    {
        return Results.NotFound();
    }

    if (!ImportJobTransitions.IsAllowed(job.Status, request.Status))
    {
        return Results.Conflict(new
        {
            error = "invalid_status_transition",
            from = job.Status,
            to = request.Status
        });
    }

    job.Status = request.Status;
    job.LockedBy = request.LockedBy;
    job.LockedUntil = request.LockedUntil?.ToUniversalTime();
    job.LastErrorCode = request.LastErrorCode;
    job.LastErrorMessage = request.LastErrorMessage;

    var now = DateTimeOffset.UtcNow;
    if (request.Status == JobStatuses.Running)
    {
        job.StartedAt ??= now;
        job.FinishedAt = null;
        job.AttemptCount += 1;
    }

    if (request.Status is JobStatuses.Succeeded or JobStatuses.Failed or JobStatuses.Cancelled)
    {
        job.FinishedAt = now;
    }

    await dbContext.SaveChangesAsync(cancellationToken);

    return Results.Ok(ImportJobResponse.From(job));
})
.WithName("UpdateImportJobStatus");

app.MapPost("/imports/{id:guid}/worker-smoke", async (
    Guid id,
    bool? simulateFailure,
    KqgDbContext dbContext,
    IDocumentWorkerClient workerClient,
    CancellationToken cancellationToken) =>
{
    var job = await dbContext.ImportJobs.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    if (job is null)
    {
        return Results.NotFound();
    }

    var fileAsset = await dbContext.FileAssets.FirstOrDefaultAsync(x => x.Id == job.InputFileAssetId, cancellationToken);
    if (fileAsset is null)
    {
        return Results.Conflict(new { error = "input_file_asset_missing" });
    }

    var canStartWorker = ImportJobTransitions.IsAllowed(job.Status, JobStatuses.Running);
    var canReplaySucceededJob = job.Status == JobStatuses.Succeeded && simulateFailure != true;
    var canRetryFailedJob = job.Status == JobStatuses.Failed && simulateFailure != true;
    if (!canStartWorker && !canReplaySucceededJob && !canRetryFailedJob)
    {
        return Results.Conflict(new { error = "invalid_status_transition", from = job.Status, to = JobStatuses.Running });
    }

    var now = DateTimeOffset.UtcNow;
    if (canStartWorker || canRetryFailedJob)
    {
        job.Status = JobStatuses.Running;
        job.StartedAt ??= now;
        job.FinishedAt = null;
        job.AttemptCount += 1;
        job.LockedBy = "document-worker-smoke";
        job.LockedUntil = now.AddMinutes(5);
        await dbContext.SaveChangesAsync(cancellationToken);
    }

    var result = await workerClient.RunSmokeAsync(job.Id, fileAsset.RelativePath, simulateFailure == true, cancellationToken);
    if (result.ExitCode == 0)
    {
        job.Status = JobStatuses.Succeeded;
        job.LastErrorCode = null;
        job.LastErrorMessage = null;
    }
    else
    {
        job.Status = JobStatuses.Failed;
        job.LastErrorCode = "worker_failed";
        job.LastErrorMessage = result.StandardError.Length > 0 ? result.StandardError : result.StandardOutput;
    }

    job.LockedBy = null;
    job.LockedUntil = null;
    job.FinishedAt = DateTimeOffset.UtcNow;

    var sourceDocument = await dbContext.SourceDocuments
        .Where(x => x.FileAssetId == fileAsset.Id)
        .OrderByDescending(x => x.CreatedAt)
        .FirstOrDefaultAsync(cancellationToken);
    var processing = result.ExitCode == 0 && sourceDocument is not null
        ? await SeedLocalImportCandidatesAsync(dbContext, sourceDocument, result.StandardOutput, cancellationToken)
        : ImportWorkerProcessingSummary.Empty;

    await dbContext.SaveChangesAsync(cancellationToken);

    return Results.Ok(new
    {
        job.Id,
        job.Status,
        result.ExitCode,
        result.StandardOutput,
        result.StandardError,
        Processing = processing
    });
})
.WithName("RunDocumentWorkerSmoke");

app.Run();

static SourceDocumentMetadata SourceMetadataFromForm(IFormCollection form, string originalFileName)
{
    var defaults = SourceDocumentMetadata.Defaults(Path.GetFileName(originalFileName));

    var metadata = defaults with
    {
        SourceType = FormValue(form, "sourceType", defaults.SourceType),
        SourceTitle = FormValue(form, "sourceTitle", defaults.SourceTitle),
        Region = FormValue(form, "region", defaults.Region),
        Year = FormInt(form, "year", defaults.Year),
        GradeOrScope = FormValue(form, "gradeOrScope", defaults.GradeOrScope),
        EditionOrVersion = FormValue(form, "editionOrVersion", defaults.EditionOrVersion),
        MaterialBatchKey = FormValue(form, "materialBatchKey", defaults.MaterialBatchKey),
        OwnerScope = FormValue(form, "ownerScope", defaults.OwnerScope),
        LicenseOrPermission = FormValue(form, "licenseOrPermission", defaults.LicenseOrPermission),
        SharingAllowed = FormBool(form, "sharingAllowed", defaults.SharingAllowed),
        ContainsStudentPii = FormBool(form, "containsStudentPii", defaults.ContainsStudentPii),
        AnonymizationStatus = FormValue(form, "anonymizationStatus", defaults.AnonymizationStatus),
        MayUseForKnowledgeExtraction = FormBool(form, "mayUseForKnowledgeExtraction", defaults.MayUseForKnowledgeExtraction),
        MayUseForExamPointExtraction = FormBool(form, "mayUseForExamPointExtraction", defaults.MayUseForExamPointExtraction),
        MayUseForTrendAnalysis = FormBool(form, "mayUseForTrendAnalysis", defaults.MayUseForTrendAnalysis)
    };

    return SourceMaterialClassifier.Classify(metadata, originalFileName);
}

static string FormValue(IFormCollection form, string key, string fallback)
{
    return form.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value)
        ? value.ToString()
        : fallback;
}

static bool FormBool(IFormCollection form, string key, bool fallback)
{
    return form.TryGetValue(key, out var value) && bool.TryParse(value.ToString(), out var parsed)
        ? parsed
        : fallback;
}

static async Task<ImportWorkerProcessingSummary> SeedLocalImportCandidatesAsync(
    KqgDbContext dbContext,
    SourceDocument sourceDocument,
    string workerOutput,
    CancellationToken cancellationToken)
{
    if (string.IsNullOrWhiteSpace(workerOutput))
    {
        return ImportWorkerProcessingSummary.Empty;
    }

    using var document = JsonDocument.Parse(workerOutput);
    var root = document.RootElement;
    var adapterName = ReadFirstAdapterName(root);
    if (!root.TryGetProperty("documentModel", out var documentModel) ||
        !documentModel.TryGetProperty("pages", out var pages) ||
        pages.ValueKind != JsonValueKind.Array)
    {
        return ImportWorkerProcessingSummary.Empty with { AdapterName = adapterName };
    }

    var previousCandidates = await dbContext.CutCandidates
        .Where(x => x.SourceDocumentId == sourceDocument.Id)
        .ToListAsync(cancellationToken);
    var previousLocalCandidates = previousCandidates
        .Where(x => x.Metadata.Contains("document_worker_local", StringComparison.OrdinalIgnoreCase))
        .ToArray();
    var previousLocalRegionIds = previousLocalCandidates
        .Where(x => x.SourceRegionId.HasValue)
        .Select(x => x.SourceRegionId!.Value)
        .ToArray();
    if (previousLocalCandidates.Length > 0)
    {
        dbContext.CutCandidates.RemoveRange(previousLocalCandidates);
    }

    if (previousLocalRegionIds.Length > 0)
    {
        var previousRegions = await dbContext.SourceRegions
            .Where(x => previousLocalRegionIds.Contains(x.Id) && x.RegionType == "document_block")
            .ToListAsync(cancellationToken);
        dbContext.SourceRegions.RemoveRange(previousRegions);
    }

    const int maxCandidates = 120;
    var now = DateTimeOffset.UtcNow;
    var sequenceNo = 1;
    var regions = new List<SourceRegion>();
    var candidates = new List<CutCandidate>();
    var queueItems = new List<ReviewQueueItem>();

    foreach (var page in pages.EnumerateArray())
    {
        var pageNumber = ReadInt(page, "pageNumber", 1);
        if (!page.TryGetProperty("layoutBlocks", out var blocks) ||
            blocks.ValueKind != JsonValueKind.Array)
        {
            continue;
        }

        var blockIndex = 0;
        foreach (var block in blocks.EnumerateArray())
        {
            if (candidates.Count >= maxCandidates)
            {
                break;
            }

            var textPreview = ReadString(block, "textPreview", string.Empty).Trim();
            var blockType = NormalizeToken(ReadString(block, "blockType", "document_block"), "document_block");
            if (string.IsNullOrWhiteSpace(textPreview))
            {
                continue;
            }

            var confidence = ReadDecimal(block, "confidence", blockType == "question_stem" ? 0.88m : 0.78m);
            var takeoverRequired = ReadBool(block, "takeoverRequired", confidence < 0.85m);
            var region = new SourceRegion
            {
                Id = Guid.NewGuid(),
                SourceDocumentId = sourceDocument.Id,
                PageNumber = pageNumber,
                X = 0,
                Y = Math.Min(95, blockIndex * 6),
                Width = 100,
                Height = 5,
                CoordinateUnit = "percent",
                RegionType = "document_block",
                CreatedAt = now
            };
            regions.Add(region);

            var candidate = new CutCandidate
            {
                Id = Guid.NewGuid(),
                SourceDocumentId = sourceDocument.Id,
                SourceRegionId = region.Id,
                Status = CutCandidateStatuses.PendingReview,
                Confidence = confidence,
                SegmentType = blockType,
                SequenceNo = sequenceNo++,
                CandidatePayload = JsonSerializer.Serialize(new
                {
                    extractionMode = "document_worker_local",
                    adapterName,
                    pageNumber,
                    blockType,
                    textPreview,
                    takeoverRequired,
                    sourceRegionId = region.Id
                }),
                FailureReason = takeoverRequired ? "requires_manual_review" : string.Empty,
                TakeoverAction = takeoverRequired ? "manual_review" : "skip",
                Metadata = JsonSerializer.Serialize(new
                {
                    generatedBy = "document_worker_local",
                    generatedAt = now,
                    adapterName,
                    source = "ImportJob.worker-smoke"
                }),
                CreatedAt = now,
                UpdatedAt = now
            };
            candidates.Add(candidate);

            if (takeoverRequired)
            {
                queueItems.Add(new ReviewQueueItem
                {
                    ReviewType = "cut_candidate",
                    Status = ReviewStatuses.Open,
                    Payload = JsonSerializer.Serialize(new
                    {
                        sourceDocumentId = sourceDocument.Id,
                        sourceRegionId = region.Id,
                        candidateId = candidate.Id,
                        confidence,
                        requiredAction = "manual_review",
                        reason = "document_worker_low_confidence_or_header",
                        textPreview
                    }),
                    CreatedAt = now
                });
            }

            blockIndex += 1;
        }
    }

    if (regions.Count == 0 || candidates.Count == 0)
    {
        return ImportWorkerProcessingSummary.Empty with { AdapterName = adapterName };
    }

    dbContext.SourceRegions.AddRange(regions);
    dbContext.CutCandidates.AddRange(candidates);
    if (queueItems.Count > 0)
    {
        dbContext.ReviewQueueItems.AddRange(queueItems);
    }

    return new ImportWorkerProcessingSummary(
        AdapterName: adapterName,
        SourceRegionCount: regions.Count,
        CutCandidateCount: candidates.Count,
        LowConfidenceReviewQueueCount: queueItems.Count);
}

static string ReadFirstAdapterName(JsonElement root)
{
    if (root.TryGetProperty("adapterDiagnostics", out var diagnostics) &&
        diagnostics.ValueKind == JsonValueKind.Array &&
        diagnostics.GetArrayLength() > 0)
    {
        return ReadString(diagnostics[0], "adapterName", string.Empty);
    }

    return string.Empty;
}

static string ReadString(JsonElement element, string propertyName, string fallback)
{
    return element.TryGetProperty(propertyName, out var value) && value.ValueKind == JsonValueKind.String
        ? value.GetString() ?? fallback
        : fallback;
}

static int ReadInt(JsonElement element, string propertyName, int fallback)
{
    return element.TryGetProperty(propertyName, out var value) && value.TryGetInt32(out var parsed)
        ? parsed
        : fallback;
}

static decimal ReadDecimal(JsonElement element, string propertyName, decimal fallback)
{
    return element.TryGetProperty(propertyName, out var value) && value.TryGetDecimal(out var parsed)
        ? parsed
        : fallback;
}

static bool ReadBool(JsonElement element, string propertyName, bool fallback)
{
    return element.TryGetProperty(propertyName, out var value) && value.ValueKind is JsonValueKind.True or JsonValueKind.False
        ? value.GetBoolean()
        : fallback;
}

static string ResolveCandidateText(CutCandidate candidate)
{
    try
    {
        using var document = JsonDocument.Parse(candidate.CandidatePayload);
        var root = document.RootElement;
        var textPreview = ReadString(root, "textPreview", string.Empty).Trim();
        if (!string.IsNullOrWhiteSpace(textPreview))
        {
            return textPreview;
        }
    }
    catch (JsonException)
    {
        return $"候选片段 {candidate.SequenceNo}";
    }

    return $"候选片段 {candidate.SequenceNo}";
}

static int? FormInt(IFormCollection form, string key, int? fallback)
{
    return form.TryGetValue(key, out var value) && int.TryParse(value.ToString(), out var parsed)
        ? parsed
        : fallback;
}

static string? ValidateSourceRegionRequest(SourceRegionCreateRequest request)
{
    if (request.PageNumber < 1)
    {
        return "invalid_page_number";
    }

    if (request.X < 0 || request.Y < 0 || request.Width <= 0 || request.Height <= 0)
    {
        return "invalid_bbox";
    }

    var unit = NormalizeToken(request.CoordinateUnit, "percent");
    return unit is "pixel" or "point" or "percent" ? null : "invalid_coordinate_unit";
}

static bool TryResolveFileStorePath(string fileStoreRoot, string relativePath, out string fullPath)
{
    fullPath = string.Empty;
    if (string.IsNullOrWhiteSpace(relativePath) || Path.IsPathRooted(relativePath))
    {
        return false;
    }

    var normalizedRelative = relativePath.Replace('\\', '/');
    if (normalizedRelative.Split('/').Any(x => x is "" or "." or ".."))
    {
        return false;
    }

    var root = Path.GetFullPath(fileStoreRoot);
    var candidate = Path.GetFullPath(Path.Combine(root, normalizedRelative));
    if (!candidate.StartsWith(root, StringComparison.OrdinalIgnoreCase))
    {
        return false;
    }

    fullPath = candidate;
    return true;
}

static string BuildSourcePageScreenshotRelativePath(Guid sourceDocumentId, int pageNumber)
{
    return $"generated/guangzhou-2015/pages/{sourceDocumentId}-page-{pageNumber:000}.png";
}

static string InferContentType(string path)
{
    return Path.GetExtension(path).ToLowerInvariant() switch
    {
        ".png" => "image/png",
        ".jpg" or ".jpeg" => "image/jpeg",
        ".webp" => "image/webp",
        ".gif" => "image/gif",
        ".svg" => "image/svg+xml",
        ".json" => "application/json; charset=utf-8",
        ".txt" => "text/plain; charset=utf-8",
        ".pdf" => "application/pdf",
        _ => "application/octet-stream"
    };
}

static string NormalizeToken(string value, string fallback)
{
    if (string.IsNullOrWhiteSpace(value))
    {
        return fallback;
    }

    return value.Trim().ToLowerInvariant().Replace('-', '_').Replace(' ', '_');
}

static string SerializeJson<T>(T value)
{
    return JsonSerializer.Serialize(value, new JsonSerializerOptions(JsonSerializerDefaults.Web));
}

static string Sha256Hex(string value)
{
    return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
}

static string GetQuestionPreview(IReadOnlyList<QuestionBlock> blocks)
{
    foreach (var block in blocks.OrderBy(x => x.SortOrder))
    {
        var preview = GetBlockPreview(block);
        if (!string.IsNullOrWhiteSpace(preview))
        {
            return preview.Length <= 120 ? preview : string.Concat(preview.AsSpan(0, 120), "...");
        }
    }

    return string.Empty;
}

static string GetBlockPreview(QuestionBlock block)
{
    try
    {
        using var document = JsonDocument.Parse(block.Content);
        var root = document.RootElement;
        if (root.ValueKind == JsonValueKind.Object)
        {
            foreach (var propertyName in new[] { "text", "answer", "latex", "label" })
            {
                if (root.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String)
                {
                    return property.GetString() ?? string.Empty;
                }
            }
        }

        return root.ToString();
    }
    catch (JsonException)
    {
        return block.Content;
    }
}

static bool RequiresTableBlockReview(QuestionBlock block)
{
    if (!string.Equals(block.BlockType, "table", StringComparison.OrdinalIgnoreCase))
    {
        return false;
    }

    try
    {
        using var document = JsonDocument.Parse(block.Content);
        var root = document.RootElement;
        var reviewStatus = TryGetStringProperty(root, "reviewStatus");
        if (string.Equals(reviewStatus, "pending_review", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        var confidence = TryGetDoubleProperty(root, "confidence");
        return confidence.HasValue && confidence.Value < 0.8;
    }
    catch (JsonException)
    {
        return true;
    }
}

static ReviewQueueItem CreateTableBlockReviewItem(QuestionItem item, QuestionBlock block, DateTimeOffset now)
{
    double? confidence = null;
    string? caption = null;
    string? reviewStatus = null;
    try
    {
        using var document = JsonDocument.Parse(block.Content);
        var root = document.RootElement;
        confidence = TryGetDoubleProperty(root, "confidence");
        caption = TryGetStringProperty(root, "caption");
        reviewStatus = TryGetStringProperty(root, "reviewStatus");
    }
    catch (JsonException)
    {
        reviewStatus = "pending_review";
    }

    return new ReviewQueueItem
    {
        ReviewType = "question_table_block_review",
        Status = ReviewStatuses.Open,
        CreatedAt = now,
        Payload = JsonSerializer.Serialize(new
        {
            questionItemId = item.Id,
            questionBlockId = block.Id,
            sourceRegionId = block.SourceRegionId,
            blockType = block.BlockType,
            caption,
            confidence,
            reviewStatus = string.IsNullOrWhiteSpace(reviewStatus) ? "pending_review" : reviewStatus,
            riskLevel = "medium",
            requiredAction = "review_table_structure",
            reason = "table_block_low_confidence_or_pending_review",
            sourceWorkflowKey = "real009_table_structure"
        })
    };
}

static bool RequiresFormulaBlockReview(QuestionBlock block)
{
    if (!string.Equals(block.BlockType, "formula", StringComparison.OrdinalIgnoreCase))
    {
        return false;
    }

    try
    {
        using var document = JsonDocument.Parse(block.Content);
        var root = document.RootElement;
        var sourceFormat = TryGetStringProperty(root, "sourceFormat");
        var reviewStatus = TryGetStringProperty(root, "reviewStatus");
        var confidence = TryGetDoubleProperty(root, "confidence");
        if (string.Equals(reviewStatus, "pending_review", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (confidence.HasValue && confidence.Value < 0.9)
        {
            return true;
        }

        if (sourceFormat is not null &&
            !string.Equals(sourceFormat, "omml", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(sourceFormat, "latex", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return false;
    }
    catch (JsonException)
    {
        return true;
    }
}

static ReviewQueueItem CreateFormulaBlockReviewItem(QuestionItem item, QuestionBlock block, DateTimeOffset now)
{
    double? confidence = null;
    string? sourceFormat = null;
    string? reviewStatus = null;
    string? fallbackImageUrl = null;
    try
    {
        using var document = JsonDocument.Parse(block.Content);
        var root = document.RootElement;
        confidence = TryGetDoubleProperty(root, "confidence");
        sourceFormat = TryGetStringProperty(root, "sourceFormat");
        reviewStatus = TryGetStringProperty(root, "reviewStatus");
        fallbackImageUrl = TryGetStringProperty(root, "fallbackImageUrl");
    }
    catch (JsonException)
    {
        reviewStatus = "pending_review";
    }

    return new ReviewQueueItem
    {
        ReviewType = "question_formula_block_review",
        Status = ReviewStatuses.Open,
        CreatedAt = now,
        Payload = JsonSerializer.Serialize(new
        {
            questionItemId = item.Id,
            questionBlockId = block.Id,
            sourceRegionId = block.SourceRegionId,
            blockType = block.BlockType,
            sourceFormat = string.IsNullOrWhiteSpace(sourceFormat) ? "unknown" : sourceFormat,
            confidence,
            fallbackImageUrl,
            reviewStatus = string.IsNullOrWhiteSpace(reviewStatus) ? "pending_review" : reviewStatus,
            riskLevel = "medium",
            requiredAction = "review_formula_structure",
            reason = "formula_block_low_confidence_or_non_omml_candidate",
            sourceWorkflowKey = "real010_formula_fidelity"
        })
    };
}

static string? TryGetStringProperty(JsonElement root, string propertyName)
{
    return root.ValueKind == JsonValueKind.Object &&
        root.TryGetProperty(propertyName, out var property) &&
        property.ValueKind == JsonValueKind.String
        ? property.GetString()
        : null;
}

static double? TryGetDoubleProperty(JsonElement root, string propertyName)
{
    if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty(propertyName, out var property))
    {
        return null;
    }

    if (property.ValueKind == JsonValueKind.Number && property.TryGetDouble(out var number))
    {
        return number;
    }

    return property.ValueKind == JsonValueKind.String &&
        double.TryParse(property.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out number)
        ? number
        : null;
}

static JsonElement? TryGetCustomFieldElement(string json, string propertyName)
{
    try
    {
        using var document = JsonDocument.Parse(json);
        return document.RootElement.ValueKind == JsonValueKind.Object &&
            document.RootElement.TryGetProperty(propertyName, out var property)
            ? property.Clone()
            : null;
    }
    catch (JsonException)
    {
        return null;
    }
}

static int? TryGetIntCustomField(string json, string propertyName)
{
    return QuestionJsonMetadata.TryGetIntField(json, propertyName);
}

static string MergeQuestionCustomFields(string json, JsonElement? answer, JsonElement? solution)
{
    var fields = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
    try
    {
        using var document = JsonDocument.Parse(json);
        if (document.RootElement.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in document.RootElement.EnumerateObject())
            {
                fields[property.Name] = property.Value.Clone();
            }
        }
    }
    catch (JsonException)
    {
        fields.Clear();
    }

    if (answer.HasValue)
    {
        fields["answer"] = answer.Value.Clone();
    }

    if (solution.HasValue)
    {
        fields["solution"] = solution.Value.Clone();
    }

    return JsonSerializer.Serialize(fields);
}

static bool QuestionCustomFieldHasValue(string json, string propertyName)
{
    var value = TryGetCustomFieldElement(json, propertyName);
    if (!value.HasValue || value.Value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
    {
        return false;
    }

    return value.Value.ValueKind != JsonValueKind.Object ||
        value.Value.EnumerateObject().Any(x =>
            x.Value.ValueKind is not JsonValueKind.Null and not JsonValueKind.Undefined &&
            !string.IsNullOrWhiteSpace(x.Value.ToString()));
}

static bool ReviewQueuePayloadReferences(string payload, Guid sourceDocumentId, IReadOnlySet<Guid> questionIds)
{
    try
    {
        using var document = JsonDocument.Parse(payload);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        if (JsonPropertyEqualsGuid(root, "sourceDocumentId", sourceDocumentId))
        {
            return true;
        }

        if (root.TryGetProperty("questionItemId", out var questionElement) &&
            questionElement.ValueKind == JsonValueKind.String &&
            Guid.TryParse(questionElement.GetString(), out var questionId) &&
            questionIds.Contains(questionId))
        {
            return true;
        }

        return false;
    }
    catch (JsonException)
    {
        return false;
    }
}

static bool JsonPropertyEqualsGuid(JsonElement root, string propertyName, Guid expected)
{
    return root.TryGetProperty(propertyName, out var element) &&
        element.ValueKind == JsonValueKind.String &&
        Guid.TryParse(element.GetString(), out var actual) &&
        actual == expected;
}

static bool QuestionBlockLooksLikeRetainedNoise(QuestionBlock block)
{
    if (!string.Equals(block.BlockType, "text", StringComparison.OrdinalIgnoreCase))
    {
        return false;
    }

    try
    {
        using var document = JsonDocument.Parse(block.Content);
        if (document.RootElement.ValueKind != JsonValueKind.Object ||
            !document.RootElement.TryGetProperty("text", out var textElement) ||
            textElement.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        var text = textElement.GetString() ?? string.Empty;
        return NoiseMarkers().Any(marker => text.Contains(marker, StringComparison.OrdinalIgnoreCase));
    }
    catch (JsonException)
    {
        return false;
    }
}

static string BuildSourceDocumentRollbackSql(Guid sourceDocumentId)
{
    return string.Join(Environment.NewLine,
        $"-- REAL012 dry-run rollback reference for source_document {sourceDocumentId}",
        "begin;",
        "delete from review_queue_items where payload::text like '%" + sourceDocumentId + "%';",
        "delete from question_assets where source_region_id in (select id from source_regions where source_document_id = '" + sourceDocumentId + "');",
        "delete from question_blocks where source_region_id in (select id from source_regions where source_document_id = '" + sourceDocumentId + "');",
        "delete from source_regions where source_document_id = '" + sourceDocumentId + "';",
        "rollback;");
}

static string[] NoiseMarkers() =>
[
    "姓名",
    "准考证",
    "装订线",
    "密封线",
    "考试注意",
    "注意事项",
    "本试卷",
    "水印",
    "页码"
];

static AiJobResponse ToAiJobResponse(AIJob job)
{
    return new AiJobResponse(
        job.Id,
        job.JobType,
        job.Status,
        job.IdempotencyKey,
        job.ModelRoute,
        job.ModelProvider,
        job.ModelName,
        job.RoutingVersion,
        job.PromptVersion,
        job.SchemaVersion,
        job.InputHash,
        job.EstimatedCost,
        job.ActualCost,
        job.Confidence,
        job.InputTokens,
        job.OutputTokens,
        job.CachedTokens,
        job.LatencyMs,
        job.ReviewStatus,
        job.TeacherModified,
        job.Result,
        job.CreatedAt,
        job.FinishedAt);
}

static string? ValidateQuestionCreateRequest(QuestionCreateRequest request)
{
    if (request.Blocks.Count == 0)
    {
        return "question_blocks_required";
    }

    foreach (var block in request.Blocks)
    {
        if (!IsAllowedQuestionBlockType(NormalizeToken(block.BlockType, "text")))
        {
            return "invalid_block_type";
        }
    }

    return null;
}

static bool IsAllowedQuestionBlockType(string blockType)
{
    return blockType is
        "text" or
        "option" or
        "sub_question" or
        "answer" or
        "solution" or
        "formula" or
        "image" or
        "table" or
        "chart" or
        "group_ref";
}

public static partial class ConfigurationExtensions
{
    public static string GetKqgConnectionString(this IConfiguration configuration)
    {
        var fromEnvironment = Environment.GetEnvironmentVariable("KQG_CONNECTION_STRING");
        if (!string.IsNullOrWhiteSpace(fromEnvironment))
        {
            return fromEnvironment;
        }

        var fromConfiguration = configuration.GetConnectionString("KqgDatabase");
        if (!string.IsNullOrWhiteSpace(fromConfiguration))
        {
            return fromConfiguration;
        }

        return "Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres";
    }
}

public static class HealthCheckHelpers
{
    public static async Task<ReadinessCheck> CheckDatabaseAsync(KqgDbContext dbContext, CancellationToken cancellationToken)
    {
        try
        {
            return new ReadinessCheck("database", await dbContext.Database.CanConnectAsync(cancellationToken), "PostgreSQL");
        }
        catch (Exception ex)
        {
            return new ReadinessCheck("database", false, ex.Message);
        }
    }

    public static ReadinessCheck CheckWritableDirectory(string name, string path)
    {
        try
        {
            var fullPath = Path.GetFullPath(path);
            Directory.CreateDirectory(fullPath);
            var probePath = Path.Combine(fullPath, $".kqg-health-{Guid.NewGuid():N}.tmp");
            File.WriteAllText(probePath, "ok");
            File.Delete(probePath);
            return new ReadinessCheck(name, true, fullPath);
        }
        catch (Exception ex)
        {
            return new ReadinessCheck(name, false, ex.Message);
        }
    }
}

public static class StorageHelpers
{
    public static StorageAreaResponse SummarizeArea(string name, string path, bool cleanupAllowed)
    {
        var fullPath = Path.GetFullPath(path);
        Directory.CreateDirectory(fullPath);

        long bytes = 0;
        var fileCount = 0;
        foreach (var file in Directory.EnumerateFiles(fullPath, "*", SearchOption.AllDirectories))
        {
            try
            {
                var info = new FileInfo(file);
                bytes += info.Length;
                fileCount++;
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }

        return new StorageAreaResponse(name, fullPath, bytes, fileCount, cleanupAllowed);
    }

    public static CacheCleanupResponse CleanConfiguredCache(string cacheRoot, CacheCleanupRequest request)
    {
        var fullRoot = Path.GetFullPath(cacheRoot);
        Directory.CreateDirectory(fullRoot);

        var cutoffUtc = DateTimeOffset.UtcNow.AddDays(-Math.Max(0, request.OlderThanDays));
        var dryRun = request.DryRun ?? true;
        var matched = new List<CacheCleanupCandidate>();
        var deletedCount = 0;
        long deletedBytes = 0;

        foreach (var file in Directory.EnumerateFiles(fullRoot, "*", SearchOption.AllDirectories))
        {
            var fullFile = Path.GetFullPath(file);
            if (!fullFile.StartsWith(fullRoot, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var info = new FileInfo(fullFile);
            if (info.LastWriteTimeUtc > cutoffUtc)
            {
                continue;
            }

            var relativePath = Path.GetRelativePath(fullRoot, fullFile).Replace('\\', '/');
            var sizeBytes = info.Length;
            matched.Add(new CacheCleanupCandidate(relativePath, sizeBytes, info.LastWriteTimeUtc));
            if (!dryRun)
            {
                info.Delete();
                deletedCount++;
                deletedBytes += sizeBytes;
            }
        }

        return new CacheCleanupResponse(
            Status: "ok",
            Mode: "draft_test",
            ProductionEligible: false,
            DryRun: dryRun,
            CacheRoot: fullRoot,
            OlderThanDays: Math.Max(0, request.OlderThanDays),
            MatchedFileCount: matched.Count,
            MatchedBytes: matched.Sum(x => x.SizeBytes),
            DeletedFileCount: deletedCount,
            DeletedBytes: deletedBytes,
            Candidates: matched);
    }
}

public static class WorkerPathHelpers
{
    public static string ResolveWorkerScriptPath(string contentRootPath, string configuredPath)
    {
        if (Path.IsPathRooted(configuredPath))
        {
            return Path.GetFullPath(configuredPath);
        }

        return Path.GetFullPath(Path.Combine(contentRootPath, configuredPath));
    }
}

public sealed record KqgPathsOptions
{
    public string DataRoot { get; init; } = @"D:\KQG_Data";

    public string FileStoreRoot { get; init; } = @"D:\KQG_Data\file_store";

    public string BackupRoot { get; init; } = @"D:\KQG_Backups";

    public string LogsRoot { get; init; } = @"D:\KQG_Data\logs";

    public string CacheRoot { get; init; } = @"D:\KQG_Data\cache";
}

public sealed record HealthResponse(
    string Status,
    string Service,
    string ContentRoot,
    string DataRoot,
    string FileStoreRoot,
    string BackupRoot,
    string LogsRoot,
    bool ProgramDataSeparated);

public sealed record DatabaseHealthResponse(
    string Status,
    string Provider,
    bool CanConnect);

public sealed record ReadinessResponse(string Status, IReadOnlyList<ReadinessCheck> Checks);

public sealed record ReadinessCheck(string Name, bool Ok, string Detail);

public sealed record StorageSummaryResponse(
    string Status,
    string Mode,
    bool ProductionEligible,
    string CacheCleanupRoot,
    IReadOnlyList<StorageAreaResponse> Areas);

public sealed record StorageAreaResponse(
    string Name,
    string Path,
    long Bytes,
    int FileCount,
    bool CleanupAllowed);

public sealed record CacheCleanupRequest(bool? DryRun = true, int OlderThanDays = 7);

public sealed record CacheCleanupResponse(
    string Status,
    string Mode,
    bool ProductionEligible,
    bool DryRun,
    string CacheRoot,
    int OlderThanDays,
    int MatchedFileCount,
    long MatchedBytes,
    int DeletedFileCount,
    long DeletedBytes,
    IReadOnlyList<CacheCleanupCandidate> Candidates);

public sealed record CacheCleanupCandidate(string RelativePath, long SizeBytes, DateTime LastWriteTimeUtc);

public sealed record AdminAiProviderSettingsContract(
    string Status,
    string Mode,
    bool ProductionEligible,
    string ProviderProfileId,
    string ProviderType,
    string BaseUrl,
    string ImageBaseUrl,
    string CredentialMode,
    string MaskedSecret,
    bool SecretConfigured,
    string MaskedImageSecret,
    bool ImageSecretConfigured,
    bool ImageUsesPrimarySecret,
    int MaxConcurrency,
    int MonthlyBudgetCny,
    bool DisabledByDefault,
    bool AllowRealModelCalls,
    string DefaultSmokeTaskType,
    string DefaultSmokeModel,
    string LastUpdatedAt,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail);

public sealed record AdminAiProviderSettingsSaveRequest(
    string ProviderProfileId,
    string? BaseUrl,
    string? ApiKey,
    string? ImageBaseUrl,
    string? ImageApiKey,
    int MaxConcurrency,
    int MonthlyBudgetCny,
    bool DisabledByDefault,
    bool AllowRealModelCalls,
    string? DefaultSmokeTaskType,
    string? DefaultSmokeModel,
    string? OperatorNote);

public sealed record AdminAiProviderSettingsSaveResult(
    string Status,
    string Mode,
    bool ProductionEligible,
    string ProviderProfileId,
    bool SecretConfigured,
    string MaskedSecret,
    bool ImageSecretConfigured,
    string MaskedImageSecret,
    bool ImageUsesPrimarySecret,
    string LastUpdatedAt,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail);

public sealed record AdminAiProviderSettingsTestRequest(
    string TaskType,
    string? InputJson,
    string? Model,
    string? BaseUrlOverride);

public sealed record AdminAiProviderSettingsTestResult(
    string Status,
    string Mode,
    bool ProductionEligible,
    string ProviderProfileId,
    string ProviderType,
    string Model,
    string TaskType,
    string ReviewStatus,
    bool Passed,
    int HttpStatusCode,
    string Message,
    string OutputJson,
    int InputTokens,
    int OutputTokens,
    int CachedTokens,
    decimal Cost,
    int LatencyMs,
    IReadOnlyList<string> Blockers,
    IReadOnlyList<string> AuditTrail);

internal sealed record StoredAdminAiProviderSettings(
    string SchemaVersion,
    string ProviderProfileId,
    string ProviderType,
    string BaseUrl,
    string ImageBaseUrl,
    string CredentialMode,
    string SecretCiphertext,
    string ImageSecretCiphertext,
    int MaxConcurrency,
    int MonthlyBudgetCny,
    bool DisabledByDefault,
    bool AllowRealModelCalls,
    string DefaultSmokeTaskType,
    string DefaultSmokeModel,
    DateTimeOffset UpdatedAtUtc,
    string LastOperatorNote);

public interface IAiProviderSettingsStore
{
    Task<AdminAiProviderSettingsContract> GetAsync(CancellationToken cancellationToken);
    Task<AdminAiProviderSettingsSaveResult> SaveAsync(AdminAiProviderSettingsSaveRequest request, CancellationToken cancellationToken);
    Task<string> GetPlaintextSecretAsync(CancellationToken cancellationToken);
    Task<string> GetPlaintextImageSecretAsync(CancellationToken cancellationToken);
}

public interface IAiProviderSmokeTestService
{
    Task<AdminAiProviderSettingsTestResult> RunAsync(
        AdminAiProviderSettingsContract settings,
        AdminAiProviderSettingsTestRequest request,
        CancellationToken cancellationToken);
}

public sealed class FileAiProviderSettingsStore(
    IConfiguration configuration,
    IDataProtectionProvider dataProtectionProvider,
    IWebHostEnvironment environment)
    : IAiProviderSettingsStore
{
    private const string SchemaVersion = "admin-ai-provider-settings.v0.1";
    private const string DefaultProviderProfileId = "cloud_openai_candidate";
    private const string DefaultProviderType = "openai_compatible";
    private const string DefaultCredentialMode = "dialog_secret_local_machine";
    private const string DefaultSmokeTaskType = "knowledge_tagging";
    private const string DefaultSmokeModel = "gpt-5.4-mini";
    private const string PrimaryEnvSecretName = "KQG_AI_OPENAI_KEY";
    private const string PrimaryEnvBaseUrlName = "KQG_AI_OPENAI_BASE_URL";
    private const string ImageEnvSecretName = "KQG_AI_IMAGE_OPENAI_KEY";
    private const string ImageEnvBaseUrlName = "KQG_AI_IMAGE_OPENAI_BASE_URL";
    private const string LegacyPrimaryEnvSecretName = "TEXT_PROVIDER_API_KEY";
    private const string LegacyPrimaryEnvBaseUrlName = "TEXT_PROVIDER_BASE_URL";
    private const string LegacyPrimaryEnvModelName = "TEXT_PROVIDER_MODEL";
    private const string LegacyImageEnvSecretName = "IMAGE_PROVIDER_API_KEY_1";
    private const string LegacyImageEnvBaseUrlName = "IMAGE_PROVIDER_BASE_URL";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web) { WriteIndented = true };
    private readonly IDataProtector protector = dataProtectionProvider.CreateProtector("k12-question-graph.admin-ai-provider-settings.v0.1");

    public async Task<AdminAiProviderSettingsContract> GetAsync(CancellationToken cancellationToken)
    {
        var settings = await LoadStoredAsync(cancellationToken);
        return ToContract(settings);
    }

    public async Task<AdminAiProviderSettingsSaveResult> SaveAsync(
        AdminAiProviderSettingsSaveRequest request,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var existing = await LoadStoredAsync(cancellationToken);
        var normalizedSecret = request.ApiKey?.Trim();
        var normalizedImageSecret = request.ImageApiKey?.Trim();
        var secretCiphertext = string.IsNullOrWhiteSpace(normalizedSecret)
            ? existing.SecretCiphertext
            : ProtectSecret(normalizedSecret);
        var imageSecretCiphertext = normalizedImageSecret is null
            ? existing.ImageSecretCiphertext
            : string.IsNullOrWhiteSpace(normalizedImageSecret)
                ? string.Empty
                : ProtectSecret(normalizedImageSecret);
        var now = DateTimeOffset.UtcNow;
        var stored = new StoredAdminAiProviderSettings(
            SchemaVersion,
            Normalize(request.ProviderProfileId, DefaultProviderProfileId),
            DefaultProviderType,
            NormalizeBaseUrl(request.BaseUrl),
            NormalizeOptionalBaseUrl(request.ImageBaseUrl),
            DefaultCredentialMode,
            secretCiphertext,
            imageSecretCiphertext,
            NormalizeRange(request.MaxConcurrency, 1, 8, fallback: existing.MaxConcurrency),
            NormalizeRange(request.MonthlyBudgetCny, 0, 100000, fallback: existing.MonthlyBudgetCny),
            request.DisabledByDefault,
            request.AllowRealModelCalls,
            Normalize(request.DefaultSmokeTaskType, existing.DefaultSmokeTaskType),
            Normalize(request.DefaultSmokeModel, existing.DefaultSmokeModel),
            now,
            Normalize(request.OperatorNote, existing.LastOperatorNote));

        Directory.CreateDirectory(Path.GetDirectoryName(GetSettingsFilePath())!);
        await File.WriteAllTextAsync(
            GetSettingsFilePath(),
            JsonSerializer.Serialize(stored, JsonOptions),
            Encoding.UTF8,
            cancellationToken);

        var plaintextPrimarySecret = UnprotectSecret(stored.SecretCiphertext);
        var plaintextImageSecret = ResolveEffectiveImageSecret(plaintextPrimarySecret, stored.ImageSecretCiphertext);
        return new AdminAiProviderSettingsSaveResult(
            Status: "ok",
            Mode: "draft_test",
            ProductionEligible: false,
            ProviderProfileId: stored.ProviderProfileId,
            SecretConfigured: !string.IsNullOrWhiteSpace(plaintextPrimarySecret),
            MaskedSecret: MaskSecret(plaintextPrimarySecret),
            ImageSecretConfigured: !string.IsNullOrWhiteSpace(plaintextImageSecret),
            MaskedImageSecret: MaskSecret(plaintextImageSecret),
            ImageUsesPrimarySecret: string.IsNullOrWhiteSpace(UnprotectSecret(stored.ImageSecretCiphertext)),
            LastUpdatedAt: stored.UpdatedAtUtc.ToString("O"),
            TeacherMessage: "管理员 AI 设置已保存；默认单 key 生效，图片专用 key 留空时会复用主 key；本机仍只保留加密副本，试跑保持 pending_review。",
            AuditTrail: [
                "save_admin_ai_provider_settings",
                $"provider_profile={stored.ProviderProfileId}",
                $"allow_real_model_calls={stored.AllowRealModelCalls.ToString().ToLowerInvariant()}",
                $"secret_configured={(!string.IsNullOrWhiteSpace(plaintextPrimarySecret)).ToString().ToLowerInvariant()}",
                $"image_secret_configured={(!string.IsNullOrWhiteSpace(plaintextImageSecret)).ToString().ToLowerInvariant()}",
                $"image_uses_primary_secret={(string.IsNullOrWhiteSpace(UnprotectSecret(stored.ImageSecretCiphertext))).ToString().ToLowerInvariant()}"
            ]);
    }

    public async Task<string> GetPlaintextSecretAsync(CancellationToken cancellationToken)
    {
        var stored = await LoadStoredAsync(cancellationToken);
        return UnprotectSecret(stored.SecretCiphertext);
    }

    public async Task<string> GetPlaintextImageSecretAsync(CancellationToken cancellationToken)
    {
        var stored = await LoadStoredAsync(cancellationToken);
        var plaintextPrimarySecret = UnprotectSecret(stored.SecretCiphertext);
        return ResolveEffectiveImageSecret(plaintextPrimarySecret, stored.ImageSecretCiphertext);
    }

    private async Task<StoredAdminAiProviderSettings> LoadStoredAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var path = GetSettingsFilePath();
        if (!File.Exists(path))
        {
            return BuildDefault();
        }

        try
        {
            var json = await File.ReadAllTextAsync(path, cancellationToken);
            var loaded = JsonSerializer.Deserialize<StoredAdminAiProviderSettings>(json, JsonOptions);
            return loaded is null ? BuildDefault() : NormalizeLoaded(loaded);
        }
        catch
        {
            return BuildDefault();
        }
    }

    private AdminAiProviderSettingsContract ToContract(StoredAdminAiProviderSettings settings)
    {
        var plaintextSecret = UnprotectSecret(settings.SecretCiphertext);
        var plaintextImageSecret = ResolveEffectiveImageSecret(plaintextSecret, settings.ImageSecretCiphertext);
        var explicitImageSecret = UnprotectSecret(settings.ImageSecretCiphertext);
        return new AdminAiProviderSettingsContract(
            Status: "ok",
            Mode: "draft_test",
            ProductionEligible: false,
            ProviderProfileId: settings.ProviderProfileId,
            ProviderType: settings.ProviderType,
            BaseUrl: settings.BaseUrl,
            ImageBaseUrl: ResolveEffectiveImageBaseUrl(settings.BaseUrl, settings.ImageBaseUrl),
            CredentialMode: settings.CredentialMode,
            MaskedSecret: MaskSecret(plaintextSecret),
            SecretConfigured: !string.IsNullOrWhiteSpace(plaintextSecret),
            MaskedImageSecret: MaskSecret(plaintextImageSecret),
            ImageSecretConfigured: !string.IsNullOrWhiteSpace(plaintextImageSecret),
            ImageUsesPrimarySecret: string.IsNullOrWhiteSpace(explicitImageSecret),
            MaxConcurrency: settings.MaxConcurrency,
            MonthlyBudgetCny: settings.MonthlyBudgetCny,
            DisabledByDefault: settings.DisabledByDefault,
            AllowRealModelCalls: settings.AllowRealModelCalls,
            DefaultSmokeTaskType: settings.DefaultSmokeTaskType,
            DefaultSmokeModel: settings.DefaultSmokeModel,
            LastUpdatedAt: settings.UpdatedAtUtc.ToString("O"),
            TeacherMessage: "当前为管理员级本机 AI 设置；默认单 key，图片专用 key 可选覆盖；普通教师侧仍只看到简化模式。",
            AuditTrail: [
                "load_admin_ai_provider_settings",
                $"provider_profile={settings.ProviderProfileId}",
                $"secret_configured={(!string.IsNullOrWhiteSpace(plaintextSecret)).ToString().ToLowerInvariant()}",
                $"image_secret_configured={(!string.IsNullOrWhiteSpace(plaintextImageSecret)).ToString().ToLowerInvariant()}",
                $"image_uses_primary_secret={(string.IsNullOrWhiteSpace(explicitImageSecret)).ToString().ToLowerInvariant()}",
                $"allow_real_model_calls={settings.AllowRealModelCalls.ToString().ToLowerInvariant()}"
            ]);
    }

    private StoredAdminAiProviderSettings BuildDefault()
    {
        var defaults = LoadDefaultsFromYaml();
        var envPrimarySecret = ReadFirstEnvironmentValue(PrimaryEnvSecretName, LegacyPrimaryEnvSecretName);
        var envImageSecret = ReadFirstEnvironmentValue(ImageEnvSecretName, LegacyImageEnvSecretName);
        var envPrimaryBaseUrl = ReadFirstEnvironmentValue(PrimaryEnvBaseUrlName, LegacyPrimaryEnvBaseUrlName);
        var envImageBaseUrl = ReadFirstEnvironmentValue(ImageEnvBaseUrlName, LegacyImageEnvBaseUrlName);
        var envDefaultSmokeModel = ReadFirstEnvironmentValue(LegacyPrimaryEnvModelName);
        return new StoredAdminAiProviderSettings(
            SchemaVersion,
            DefaultProviderProfileId,
            DefaultProviderType,
            NormalizeBaseUrl(string.IsNullOrWhiteSpace(envPrimaryBaseUrl) ? defaults.baseUrl : envPrimaryBaseUrl),
            NormalizeOptionalBaseUrl(envImageBaseUrl),
            DefaultCredentialMode,
            string.IsNullOrWhiteSpace(envPrimarySecret) ? string.Empty : ProtectSecret(envPrimarySecret),
            string.IsNullOrWhiteSpace(envImageSecret) ? string.Empty : ProtectSecret(envImageSecret),
            defaults.maxConcurrency,
            defaults.monthlyBudgetCny,
            true,
            false,
            DefaultSmokeTaskType,
            Normalize(envDefaultSmokeModel, DefaultSmokeModel),
            DateTimeOffset.MinValue,
            string.Empty);
    }

    private StoredAdminAiProviderSettings NormalizeLoaded(StoredAdminAiProviderSettings loaded)
    {
        var defaults = LoadDefaultsFromYaml();
        return loaded with
        {
            ProviderProfileId = Normalize(loaded.ProviderProfileId, DefaultProviderProfileId),
            ProviderType = Normalize(loaded.ProviderType, DefaultProviderType),
            BaseUrl = NormalizeBaseUrl(string.IsNullOrWhiteSpace(loaded.BaseUrl) ? defaults.baseUrl : loaded.BaseUrl),
            ImageBaseUrl = NormalizeOptionalBaseUrl(loaded.ImageBaseUrl),
            CredentialMode = Normalize(loaded.CredentialMode, DefaultCredentialMode),
            MaxConcurrency = NormalizeRange(loaded.MaxConcurrency, 1, 8, defaults.maxConcurrency),
            MonthlyBudgetCny = NormalizeRange(loaded.MonthlyBudgetCny, 0, 100000, defaults.monthlyBudgetCny),
            DefaultSmokeTaskType = Normalize(loaded.DefaultSmokeTaskType, DefaultSmokeTaskType),
            DefaultSmokeModel = Normalize(loaded.DefaultSmokeModel, DefaultSmokeModel),
        };
    }

    private (string baseUrl, int maxConcurrency, int monthlyBudgetCny) LoadDefaultsFromYaml()
    {
        var repoRoot = Path.GetFullPath(Path.Combine(environment.ContentRootPath, "..", ".."));
        var yamlPath = Path.Combine(repoRoot, "configs", "ai-provider-profiles.defaults.yaml");
        if (!File.Exists(yamlPath))
        {
            return ("https://api.openai.com/v1", 2, 300);
        }

        try
        {
            var deserializer = new DeserializerBuilder()
                .WithNamingConvention(CamelCaseNamingConvention.Instance)
                .IgnoreUnmatchedProperties()
                .Build();
            var yaml = deserializer.Deserialize<AiProviderProfilesDefaultsDocument>(File.ReadAllText(yamlPath, Encoding.UTF8));
            var profile = yaml?.ProviderProfiles?.FirstOrDefault(x => string.Equals(x.Id, DefaultProviderProfileId, StringComparison.OrdinalIgnoreCase));
            return (
                profile?.BaseUrl ?? "https://api.openai.com/v1",
                profile?.MaxConcurrency ?? 2,
                profile?.MonthlyBudgetCny ?? 300);
        }
        catch
        {
            return ("https://api.openai.com/v1", 2, 300);
        }
    }

    private string GetSettingsFilePath()
    {
        var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
        var settingsRoot = Path.Combine(Path.GetFullPath(paths.DataRoot), "config", "admin");
        return Path.Combine(settingsRoot, "ai-provider-settings.local.json");
    }

    private static string Normalize(string? value, string fallback)
    {
        return string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
    }

    private static int NormalizeRange(int value, int min, int max, int fallback)
    {
        if (value < min || value > max)
        {
            return fallback;
        }

        return value;
    }

    private static string NormalizeBaseUrl(string? value)
    {
        var normalized = Normalize(value, "https://api.openai.com/v1");
        return normalized.TrimEnd('/');
    }

    private static string NormalizeOptionalBaseUrl(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? string.Empty : value.Trim().TrimEnd('/');
    }

    private string ProtectSecret(string value)
    {
        return protector.Protect(value);
    }

    private string UnprotectSecret(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        try
        {
            return protector.Unprotect(value);
        }
        catch
        {
            return string.Empty;
        }
    }

    private static string MaskSecret(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "";
        }

        var trimmed = value.Trim();
        if (trimmed.Length <= 8)
        {
            return new string('*', trimmed.Length);
        }

        return $"{trimmed[..4]}****{trimmed[^4..]}";
    }

    private string ResolveEffectiveImageSecret(string primarySecret, string? imageSecretCiphertext)
    {
        var explicitImageSecret = UnprotectSecret(imageSecretCiphertext);
        return string.IsNullOrWhiteSpace(explicitImageSecret) ? primarySecret : explicitImageSecret;
    }

    private static string ResolveEffectiveImageBaseUrl(string primaryBaseUrl, string? imageBaseUrl)
    {
        return string.IsNullOrWhiteSpace(imageBaseUrl) ? primaryBaseUrl : imageBaseUrl.TrimEnd('/');
    }

    private static string ReadFirstEnvironmentValue(params string[] variableNames)
    {
        foreach (var variableName in variableNames)
        {
            var value = Environment.GetEnvironmentVariable(variableName)?.Trim();
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        return string.Empty;
    }
}

public sealed class OpenAiCompatibleSmokeTestService(
    HttpClient httpClient,
    IAiProviderSettingsStore settingsStore,
    IWebHostEnvironment environment)
    : IAiProviderSmokeTestService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<AdminAiProviderSettingsTestResult> RunAsync(
        AdminAiProviderSettingsContract settings,
        AdminAiProviderSettingsTestRequest request,
        CancellationToken cancellationToken)
    {
        var blockers = new List<string>();
        if (!settings.SecretConfigured)
        {
            blockers.Add("provider_secret_not_configured");
        }

        if (settings.DisabledByDefault)
        {
            blockers.Add("provider_profile_disabled_by_default");
        }

        if (!settings.AllowRealModelCalls)
        {
            blockers.Add("allow_real_model_calls_false");
        }

        if (blockers.Count > 0)
        {
            return new AdminAiProviderSettingsTestResult(
                Status: "blocked",
                Mode: "draft_test",
                ProductionEligible: false,
                ProviderProfileId: settings.ProviderProfileId,
                ProviderType: settings.ProviderType,
                Model: string.IsNullOrWhiteSpace(request.Model) ? settings.DefaultSmokeModel : request.Model.Trim(),
                TaskType: NormalizeTaskType(request.TaskType, settings.DefaultSmokeTaskType),
                ReviewStatus: "pending_review",
                Passed: false,
                HttpStatusCode: 0,
                Message: "管理员 AI 设置未满足真实试跑前置条件；请启用 provider、配置密钥并明确允许 draft/test 试跑。",
                OutputJson: "{}",
                InputTokens: 0,
                OutputTokens: 0,
                CachedTokens: 0,
                Cost: 0,
                LatencyMs: 0,
                Blockers: blockers,
                AuditTrail: [
                    "test_admin_ai_provider_settings_blocked",
                    ..blockers
                ]);
        }

        var secret = await settingsStore.GetPlaintextSecretAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(secret))
        {
            return new AdminAiProviderSettingsTestResult(
                Status: "blocked",
                Mode: "draft_test",
                ProductionEligible: false,
                ProviderProfileId: settings.ProviderProfileId,
                ProviderType: settings.ProviderType,
                Model: string.IsNullOrWhiteSpace(request.Model) ? settings.DefaultSmokeModel : request.Model.Trim(),
                TaskType: NormalizeTaskType(request.TaskType, settings.DefaultSmokeTaskType),
                ReviewStatus: "pending_review",
                Passed: false,
                HttpStatusCode: 0,
                Message: "本机密钥解密失败，未执行云试跑。",
                OutputJson: "{}",
                InputTokens: 0,
                OutputTokens: 0,
                CachedTokens: 0,
                Cost: 0,
                LatencyMs: 0,
                Blockers: ["provider_secret_unavailable"],
                AuditTrail: [ "test_admin_ai_provider_settings_secret_unavailable" ]);
        }

        var taskType = NormalizeTaskType(request.TaskType, settings.DefaultSmokeTaskType);
        var schema = LoadSchemaForTaskType(taskType);
        var payload = new
        {
            model = NormalizeModel(request.Model, settings.DefaultSmokeModel),
            store = false,
            input = NormalizeInputJson(request.InputJson, taskType),
            text = new
            {
                format = new
                {
                    type = "json_schema",
                    name = $"{taskType}_smoke_result",
                    strict = true,
                    schema
                }
            }
        };

        using var message = new HttpRequestMessage(HttpMethod.Post, $"{NormalizeBaseUrl(request.BaseUrlOverride, settings.BaseUrl)}/responses");
        message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", secret);
        message.Content = new StringContent(JsonSerializer.Serialize(payload, JsonOptions), Encoding.UTF8, "application/json");

        var startedAt = DateTimeOffset.UtcNow;
        try
        {
            using var response = await httpClient.SendAsync(message, cancellationToken);
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            var latencyMs = (int)Math.Max(1, (DateTimeOffset.UtcNow - startedAt).TotalMilliseconds);
            var parsed = ParseSmokeResponse(body);
            return new AdminAiProviderSettingsTestResult(
                Status: response.IsSuccessStatusCode ? "ok" : "failed",
                Mode: "draft_test",
                ProductionEligible: false,
                ProviderProfileId: settings.ProviderProfileId,
                ProviderType: settings.ProviderType,
                Model: NormalizeModel(request.Model, settings.DefaultSmokeModel),
                TaskType: taskType,
                ReviewStatus: "pending_review",
                Passed: response.IsSuccessStatusCode,
                HttpStatusCode: (int)response.StatusCode,
                Message: response.IsSuccessStatusCode ? "结构化 smoke 试跑完成；结果仅作 pending_review 候选验证。" : $"云试跑失败：HTTP {(int)response.StatusCode}",
                OutputJson: parsed.outputJson,
                InputTokens: parsed.inputTokens,
                OutputTokens: parsed.outputTokens,
                CachedTokens: parsed.cachedTokens,
                Cost: 0,
                LatencyMs: latencyMs,
                Blockers: [],
                AuditTrail: [
                    "test_admin_ai_provider_settings",
                    $"task_type={taskType}",
                    $"http_status={(int)response.StatusCode}",
                    "review_status=pending_review"
                ]);
        }
        catch (Exception ex)
        {
            return new AdminAiProviderSettingsTestResult(
                Status: "failed",
                Mode: "draft_test",
                ProductionEligible: false,
                ProviderProfileId: settings.ProviderProfileId,
                ProviderType: settings.ProviderType,
                Model: NormalizeModel(request.Model, settings.DefaultSmokeModel),
                TaskType: taskType,
                ReviewStatus: "pending_review",
                Passed: false,
                HttpStatusCode: 0,
                Message: $"云试跑异常：{ex.Message}",
                OutputJson: "{}",
                InputTokens: 0,
                OutputTokens: 0,
                CachedTokens: 0,
                Cost: 0,
                LatencyMs: (int)Math.Max(1, (DateTimeOffset.UtcNow - startedAt).TotalMilliseconds),
                Blockers: ["provider_request_failed"],
                AuditTrail: [
                    "test_admin_ai_provider_settings_exception",
                    "provider_request_failed"
                ]);
        }
    }

    private static string NormalizeTaskType(string? value, string fallback) =>
        string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();

    private static string NormalizeModel(string? value, string fallback) =>
        string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();

    private static string NormalizeBaseUrl(string? overrideValue, string fallback)
    {
        var source = string.IsNullOrWhiteSpace(overrideValue) ? fallback : overrideValue.Trim();
        return source.TrimEnd('/');
    }

    private static string NormalizeInputJson(string? value, string taskType)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            return value;
        }

        return taskType switch
        {
            "question_extraction" => "请根据题目图片 OCR 文本，输出结构化题目草稿。",
            "natural_language_paper_request" => "请把这段教师组卷需求解析成结构化蓝图。",
            "answer_verification" => "请独立校验一道物理题答案与解析是否一致。",
            _ => "请给出初中物理知识点映射候选，并保留人工复核边界。"
        };
    }

    private JsonDocument LoadSchemaForTaskType(string taskType)
    {
        var repoRoot = Path.GetFullPath(Path.Combine(environment.ContentRootPath, "..", ".."));
        var schemaRelativePath = taskType switch
        {
            "question_extraction" => Path.Combine("schemas", "ai", "question_extraction.schema.json"),
            "natural_language_paper_request" => Path.Combine("schemas", "ai", "natural_language_paper_request.schema.json"),
            "answer_verification" => Path.Combine("schemas", "ai", "answer_verification.schema.json"),
            _ => Path.Combine("schemas", "ai", "knowledge_mapping.schema.json")
        };
        var schemaText = File.ReadAllText(Path.Combine(repoRoot, schemaRelativePath), Encoding.UTF8);
        return JsonDocument.Parse(schemaText);
    }

    private static (string outputJson, int inputTokens, int outputTokens, int cachedTokens) ParseSmokeResponse(string body)
    {
        try
        {
            using var document = JsonDocument.Parse(body);
            var root = document.RootElement;
            var usage = root.TryGetProperty("usage", out var usageElement) ? usageElement : default;
            var inputTokens = usage.ValueKind == JsonValueKind.Object && usage.TryGetProperty("input_tokens", out var inputTokenElement)
                ? inputTokenElement.GetInt32()
                : 0;
            var outputTokens = usage.ValueKind == JsonValueKind.Object && usage.TryGetProperty("output_tokens", out var outputTokenElement)
                ? outputTokenElement.GetInt32()
                : 0;
            var cachedTokens = usage.ValueKind == JsonValueKind.Object &&
                usage.TryGetProperty("input_tokens_details", out var detailsElement) &&
                detailsElement.TryGetProperty("cached_tokens", out var cachedTokenElement)
                ? cachedTokenElement.GetInt32()
                : 0;
            var outputJson = root.TryGetProperty("output_text", out var outputTextElement)
                ? outputTextElement.GetString() ?? "{}"
                : body;
            return (outputJson, inputTokens, outputTokens, cachedTokens);
        }
        catch
        {
            return (body, 0, 0, 0);
        }
    }
}

internal sealed class AiProviderProfilesDefaultsDocument
{
    public List<AiProviderProfilesDefaultsProfile>? ProviderProfiles { get; init; }
}

internal sealed class AiProviderProfilesDefaultsProfile
{
    public string? Id { get; init; }
    public string? BaseUrl { get; init; }
    public int? MaxConcurrency { get; init; }
    public int? MonthlyBudgetCny { get; init; }
}

public sealed record SourceRegionCreateRequest(
    int PageNumber,
    decimal X,
    decimal Y,
    decimal Width,
    decimal Height,
    string CoordinateUnit,
    string? ScreenshotRelativePath,
    string? RegionType);

public sealed record SourceRegionUpdateRequest(
    int? PageNumber,
    decimal? X,
    decimal? Y,
    decimal? Width,
    decimal? Height,
    string? CoordinateUnit,
    string? ScreenshotRelativePath,
    string? RegionType,
    string ReviewedBy,
    string Reason);

public sealed record SourceRegionUpdateResponse(SourceRegionResponse Region, Guid AuditId);

public sealed record SourceRegionResponse(
    Guid Id,
    Guid SourceDocumentId,
    int PageNumber,
    decimal X,
    decimal Y,
    decimal Width,
    decimal Height,
    string CoordinateUnit,
    string? ScreenshotRelativePath,
    string? ScreenshotUrl,
    string PageScreenshotUrl,
    string RegionType)
{
    public static SourceRegionResponse From(SourceRegion region)
    {
        var screenshotUrl = string.IsNullOrWhiteSpace(region.ScreenshotRelativePath)
            ? null
            : $"/source-regions/{region.Id}/screenshot";
        return new SourceRegionResponse(
            region.Id,
            region.SourceDocumentId,
            region.PageNumber,
            region.X,
            region.Y,
            region.Width,
            region.Height,
            region.CoordinateUnit,
            region.ScreenshotRelativePath,
            screenshotUrl,
            $"/source-regions/{region.Id}/page-screenshot",
            region.RegionType);
    }
}

public sealed record SourcePreviewPageResponse(int PageNumber, IReadOnlyList<SourceRegionResponse> Regions);

public sealed record SourceDocumentPreviewResponse(Guid SourceDocumentId, IReadOnlyList<SourcePreviewPageResponse> Pages);

public sealed record SourceDocumentQualityReportResponse(
    Guid SourceDocumentId,
    string SourceTitle,
    string SourceType,
    string Region,
    int? Year,
    string MaterialBatchKey,
    string ClosureStatus,
    bool FullClosureAllowed,
    SourceDocumentQualityMetricsResponse Metrics,
    IReadOnlyList<int> QuestionNumbers,
    IReadOnlyList<int> MissingQuestionNumbers,
    IReadOnlyList<Guid> MissingLinkedSourceRegionIds,
    IReadOnlyList<string> PendingReviewTypes,
    IReadOnlyList<string> Gaps,
    string ExternalAiPolicy,
    string RollbackSql,
    string SummaryChinese);

public sealed record SourceDocumentQualityMetricsResponse(
    int QuestionCount,
    int QuestionNumberCount,
    int AnswerCoveredCount,
    int SolutionCoveredCount,
    int SourceRegionCount,
    int LinkedSourceRegionCount,
    int LinkedSourceScreenshotCount,
    int MissingLinkedSourceScreenshotCount,
    int ImageAssetCount,
    int ImageMatchedQuestionCount,
    int TableBlockCount,
    int FormulaBlockCount,
    int PendingManualItemCount,
    int NoiseRetainedBlockCount,
    int ExternalAiCallCount);

public sealed record SourceMaterialListResponse(
    string Mode,
    IReadOnlyList<SourceMaterialResponse> Items);

public sealed record SourceDocumentAuthorizationUpdateRequest(
    string? LicenseOrPermission,
    bool? SharingAllowed,
    bool? ContainsStudentPii,
    string? AnonymizationStatus,
    bool? ExternalAiAllowed,
    bool? MayUseForKnowledgeExtraction,
    bool? MayUseForExamPointExtraction,
    bool? MayUseForTrendAnalysis,
    string ReviewedBy,
    string Reason);

public sealed record SourceDocumentAuthorizationUpdateResponse(
    SourceMaterialResponse SourceDocument,
    Guid AuditId);

public sealed record SourceMaterialResponse(
    Guid Id,
    Guid FileAssetId,
    string SourceType,
    string SourceTitle,
    string Region,
    int? Year,
    string GradeOrScope,
    string EditionOrVersion,
    string MaterialBatchKey,
    string LicenseOrPermission,
    bool ContainsStudentPii,
    string AnonymizationStatus,
    bool ExternalAiAllowed,
    bool MayUseForKnowledgeExtraction,
    bool MayUseForExamPointExtraction,
    bool MayUseForTrendAnalysis,
    string OriginalFileName,
    string RelativePath,
    string Sha256,
    long SizeBytes)
{
    public static SourceMaterialResponse From(SourceDocument document, FileAsset file)
    {
        return new SourceMaterialResponse(
            document.Id,
            document.FileAssetId,
            document.SourceType,
            document.SourceTitle,
            document.Region,
            document.Year,
            document.GradeOrScope,
            document.EditionOrVersion,
            document.MaterialBatchKey,
            document.LicenseOrPermission,
            document.ContainsStudentPii,
            document.AnonymizationStatus,
            document.ExternalAiAllowed,
            document.MayUseForKnowledgeExtraction,
            document.MayUseForExamPointExtraction,
            document.MayUseForTrendAnalysis,
            file.OriginalFileName,
            file.RelativePath,
            file.Sha256,
            file.SizeBytes);
    }
}

public sealed record CutCandidateGenerationResponse(
    Guid SourceDocumentId,
    int GeneratedCount,
    int LowConfidenceReviewQueueCount,
    decimal LowConfidenceThreshold);

public sealed record ImportWorkerProcessingSummary(
    string AdapterName,
    int SourceRegionCount,
    int CutCandidateCount,
    int LowConfidenceReviewQueueCount)
{
    public static ImportWorkerProcessingSummary Empty { get; } = new(
        AdapterName: string.Empty,
        SourceRegionCount: 0,
        CutCandidateCount: 0,
        LowConfidenceReviewQueueCount: 0);
}

public sealed record CutCandidateListResponse(
    Guid SourceDocumentId,
    IReadOnlyList<CutCandidateResponse> Items);

public sealed record CutCandidateResponse(
    Guid Id,
    Guid SourceDocumentId,
    Guid? SourceRegionId,
    Guid? SuggestedQuestionItemId,
    string Status,
    decimal Confidence,
    string SegmentType,
    int SequenceNo,
    JsonElement CandidatePayload,
    string FailureReason,
    string TakeoverAction,
    JsonElement Metadata)
{
    public static CutCandidateResponse From(CutCandidate row)
    {
        return new CutCandidateResponse(
            row.Id,
            row.SourceDocumentId,
            row.SourceRegionId,
            row.SuggestedQuestionItemId,
            row.Status,
            row.Confidence,
            row.SegmentType,
            row.SequenceNo,
            JsonHelpers.ParseJsonElement(row.CandidatePayload),
            row.FailureReason,
            row.TakeoverAction,
            JsonHelpers.ParseJsonElement(row.Metadata));
    }
}

public sealed record ReviewQueueListResponse(
    IReadOnlyList<ReviewQueueItemResponse> Items,
    int TotalCount);

public sealed record ReviewQueueItemResponse(
    Guid Id,
    string ReviewType,
    string Status,
    string RiskLevel,
    string RequiredAction,
    decimal? Confidence,
    string? Reason,
    JsonElement Payload,
    DateTimeOffset CreatedAt,
    DateTimeOffset? ResolvedAt)
{
    public static ReviewQueueItemResponse From(ReviewQueueItem row)
    {
        var payload = JsonHelpers.ParseJsonElement(row.Payload);
        return new ReviewQueueItemResponse(
            row.Id,
            row.ReviewType,
            row.Status,
            ReviewQueuePayloadHelpers.ResolveRiskLevel(payload),
            ReviewQueuePayloadHelpers.ResolveRequiredAction(payload),
            ReviewQueuePayloadHelpers.ResolveConfidence(payload),
            ReviewQueuePayloadHelpers.ResolveReason(payload),
            payload,
            row.CreatedAt,
            row.ResolvedAt);
    }
}

public sealed record ReviewQueueBatchResolveRequest(
    IReadOnlyList<Guid> ItemIds,
    string ReviewedBy,
    string Decision,
    string Reason);

public sealed record ReviewQueueBatchResolveResponse(
    IReadOnlyList<Guid> ResolvedIds,
    IReadOnlyList<Guid> SkippedHighRiskIds);

public sealed record ReviewQueueResolveRequest(
    string ReviewedBy,
    string Decision,
    string Reason,
    ReviewQueueRevisionRequest? Revision);

public sealed record ReviewQueueRevisionRequest(
    string? TextPreview,
    string? Answer,
    string? PrimaryKnowledgeLabel,
    IReadOnlyList<string>? KnowledgeTags);

public sealed record ReviewWorkbenchActionRequest(
    string Action,
    Guid SourceDocumentId,
    IReadOnlyList<Guid> CandidateIds,
    string? AssetLabel,
    string? ReviewedBy,
    string? Reason);

public sealed record ReviewWorkbenchActionResponse(
    string Action,
    Guid SourceDocumentId,
    IReadOnlyList<Guid> TouchedIds,
    IReadOnlyList<Guid> CreatedCandidateIds,
    IReadOnlyList<Guid> SkippedIds,
    Guid? CreatedQuestionId);

public sealed record QuestionCreateRequest(
    string Subject,
    string Stage,
    string? Grade,
    string? QuestionType,
    decimal? DefaultScore,
    double? DifficultyEstimated,
    string? Status,
    Guid? PrimaryKnowledgeId,
    IReadOnlyList<QuestionBlockCreateRequest> Blocks,
    IReadOnlyList<QuestionAssetCreateRequest> Assets,
    JsonElement? Answer,
    JsonElement? Solution);

public sealed record QuestionBlockCreateRequest(
    string BlockType,
    int? SortOrder,
    JsonElement Content,
    Guid? SourceRegionId);

public sealed record QuestionUpdateRequest(
    string? QuestionType,
    decimal? DefaultScore,
    double? DifficultyEstimated,
    string? Status,
    Guid? PrimaryKnowledgeId,
    IReadOnlyList<QuestionBlockUpdateRequest>? Blocks,
    JsonElement? Answer,
    JsonElement? Solution,
    string ReviewedBy,
    string Reason);

public sealed record QuestionBlockUpdateRequest(
    Guid? Id,
    string? BlockType,
    int? SortOrder,
    JsonElement? Content,
    Guid? SourceRegionId);

public sealed record QuestionAssetCreateRequest(
    Guid? FileAssetId,
    Guid? SourceRegionId,
    string AssetType,
    string? Purpose,
    JsonElement Metadata);

public sealed record QuestionAssetAssociationRequest(
    Guid? FileAssetId,
    Guid SourceRegionId,
    string? AssetType,
    string? Purpose,
    JsonElement Metadata,
    string ReviewedBy,
    string Reason);

public sealed record QuestionResponse(
    Guid Id,
    string Subject,
    string Stage,
    string? Grade,
    string? QuestionType,
    decimal? DefaultScore,
    double? DifficultyEstimated,
    Guid? PrimaryKnowledgeId,
    int? QuestionNo,
    string Status,
    IReadOnlyList<QuestionBlockResponse> Blocks,
    IReadOnlyList<QuestionAssetResponse> Assets,
    JsonElement CustomFields)
{
    public static QuestionResponse From(QuestionItem item, IReadOnlyList<QuestionBlock> blocks, IReadOnlyList<QuestionAsset> assets)
    {
        return new QuestionResponse(
            item.Id,
            item.Subject,
            item.Stage,
            item.Grade,
            item.QuestionType,
            item.DefaultScore,
            item.DifficultyEstimated,
            item.PrimaryKnowledgeId,
            QuestionJsonMetadata.TryGetIntField(item.CustomFields, "questionNo"),
            item.Status,
            blocks.Select(QuestionBlockResponse.From).ToArray(),
            assets.Select(QuestionAssetResponse.From).ToArray(),
            JsonHelpers.ParseJsonElement(item.CustomFields));
    }
}

public sealed record QuestionRevisionResponse(QuestionResponse Question, Guid AuditId);

public sealed record QuestionBlockResponse(
    Guid Id,
    Guid QuestionItemId,
    string BlockType,
    int SortOrder,
    JsonElement Content,
    Guid? SourceRegionId)
{
    public static QuestionBlockResponse From(QuestionBlock block)
    {
        return new QuestionBlockResponse(
            block.Id,
            block.QuestionItemId,
            block.BlockType,
            block.SortOrder,
            JsonHelpers.ParseJsonElement(block.Content),
            block.SourceRegionId);
    }
}

public sealed record QuestionAssetResponse(
    Guid Id,
    Guid QuestionItemId,
    Guid? FileAssetId,
    Guid? SourceRegionId,
    string? SourceRegionScreenshotUrl,
    string? SourceRegionPageScreenshotUrl,
    string AssetType,
    string Purpose,
    JsonElement Metadata)
{
    public static QuestionAssetResponse From(QuestionAsset asset)
    {
        var sourceRegionScreenshotUrl = asset.SourceRegionId.HasValue
            ? $"/source-regions/{asset.SourceRegionId.Value}/screenshot"
            : null;
        var sourceRegionPageScreenshotUrl = asset.SourceRegionId.HasValue
            ? $"/source-regions/{asset.SourceRegionId.Value}/page-screenshot"
            : null;

        return new QuestionAssetResponse(
            asset.Id,
            asset.QuestionItemId,
            asset.FileAssetId,
            asset.SourceRegionId,
            sourceRegionScreenshotUrl,
            sourceRegionPageScreenshotUrl,
            asset.AssetType,
            asset.Purpose,
            JsonHelpers.ParseJsonElement(asset.Metadata));
    }
}

public sealed record QuestionAssetRevisionResponse(QuestionAssetResponse Asset, Guid AuditId);

public sealed record QuestionAssetUnlinkResponse(Guid QuestionItemId, Guid AssetId, Guid? SourceRegionId, Guid AuditId);

public sealed record QuestionSourceReviewResponse(Guid QuestionItemId, IReadOnlyList<QuestionSourceRegionResponse> SourceRegions);

public sealed record QuestionSearchResponse(
    string Mode,
    bool ProductionEligible,
    int Total,
    int Page,
    int Limit,
    string KnowledgeStatus,
    int? KnowledgeVersion,
    IReadOnlyList<QuestionCardResponse> Items);

public sealed record QuestionCardResponse(
    Guid Id,
    string Subject,
    string Stage,
    string? Grade,
    string? QuestionType,
    decimal? DefaultScore,
    double? DifficultyEstimated,
    string Status,
    int? QuestionNo,
    KnowledgeNodeCardResponse? PrimaryKnowledge,
    string Preview,
    int BlockCount,
    int AssetCount,
    SourceSummaryResponse Sources,
    bool HasFormula,
    bool HasTable,
    bool HasImage);

public sealed record KnowledgeNodeCardResponse(
    Guid Id,
    string Code,
    string Title,
    int Level,
    string Status,
    int Version)
{
    public static KnowledgeNodeCardResponse From(KnowledgeNode node)
    {
        return new KnowledgeNodeCardResponse(
            node.Id,
            node.Code,
            node.Title,
            node.Level,
            node.Status,
            node.Version);
    }
}

public sealed record SourceSummaryResponse(
    IReadOnlyList<string> Titles,
    IReadOnlyList<string> Types,
    IReadOnlyList<string> Permissions,
    bool SharingAllowed,
    bool ContainsStudentPii,
    IReadOnlyList<string> AnonymizationStatuses,
    int RegionCount,
    int ScreenshotCount);

public sealed record QuestionSourceRegionResponse(
    Guid Id,
    Guid SourceDocumentId,
    string? SourceTitle,
    int PageNumber,
    decimal X,
    decimal Y,
    decimal Width,
    decimal Height,
    string CoordinateUnit,
    string? ScreenshotRelativePath,
    string? ScreenshotUrl,
    string PageScreenshotUrl,
    string RegionType)
{
    public static QuestionSourceRegionResponse From(SourceRegion region, SourceDocument? document)
    {
        var screenshotUrl = string.IsNullOrWhiteSpace(region.ScreenshotRelativePath)
            ? null
            : $"/source-regions/{region.Id}/screenshot";
        return new QuestionSourceRegionResponse(
            region.Id,
            region.SourceDocumentId,
            document?.SourceTitle,
            region.PageNumber,
            region.X,
            region.Y,
            region.Width,
            region.Height,
            region.CoordinateUnit,
            region.ScreenshotRelativePath,
            screenshotUrl,
            $"/source-regions/{region.Id}/page-screenshot",
            region.RegionType);
    }
}

public sealed record PaperBasketCreateRequest(
    string Title,
    string Subject,
    string Stage,
    string? Grade,
    string? KnowledgeVersionStatus,
    int? KnowledgeVersion,
    IReadOnlyList<PaperBasketCreateItem> Items);

public sealed record PaperBasketCreateItem(
    Guid QuestionItemId,
    int SectionNo,
    int QuestionNo,
    string? SubQuestionNo,
    decimal Score,
    int? SortOrder);

public sealed record PaperBasketResponse(
    Guid Id,
    string Title,
    string Subject,
    string Stage,
    string? Grade,
    string Status,
    string KnowledgeVersionStatus,
    int KnowledgeVersion,
    JsonElement Structure,
    IReadOnlyList<PaperBasketItemResponse> Items,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt)
{
    public static PaperBasketResponse From(PaperBasket basket, IReadOnlyList<PaperBasketItem> items)
    {
        return new PaperBasketResponse(
            basket.Id,
            basket.Title,
            basket.Subject,
            basket.Stage,
            basket.Grade,
            basket.Status,
            basket.KnowledgeVersionStatus,
            basket.KnowledgeVersion,
            JsonHelpers.ParseJsonElement(basket.Structure),
            items.Select(PaperBasketItemResponse.From).ToArray(),
            basket.CreatedAt,
            basket.UpdatedAt);
    }
}

public sealed record PaperBasketItemResponse(
    Guid Id,
    Guid QuestionItemId,
    int SectionNo,
    int QuestionNo,
    string? SubQuestionNo,
    decimal Score,
    int SortOrder,
    string KnowledgeVersionStatus,
    int KnowledgeVersion,
    JsonElement Snapshot)
{
    public static PaperBasketItemResponse From(PaperBasketItem item)
    {
        return new PaperBasketItemResponse(
            item.Id,
            item.QuestionItemId,
            item.SectionNo,
            item.QuestionNo,
            item.SubQuestionNo,
            item.Score,
            item.SortOrder,
            item.KnowledgeVersionStatus,
            item.KnowledgeVersion,
            JsonHelpers.ParseJsonElement(item.Snapshot));
    }
}

public sealed record PaperExportPreflightRequest(string ExportFormat);

public sealed record PaperExportPreflightResponse(
    Guid PaperBasketId,
    string Title,
    string ExportFormat,
    string Status,
    bool ProductionEligible,
    int ItemCount,
    IReadOnlyList<PaperExportPreflightItemResponse> Items,
    IReadOnlyDictionary<string, int> IssueCounts,
    PaperExportPreflightSummaryResponse Summary,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail)
{
    public static PaperExportPreflightResponse From(PaperExportPreflightServiceResult result)
    {
        return new PaperExportPreflightResponse(
            result.PaperBasketId,
            result.Title,
            result.ExportFormat,
            result.Status,
            result.ProductionEligible,
            result.ItemCount,
            result.Items.Select(PaperExportPreflightItemResponse.From).ToArray(),
            result.IssueCounts,
            PaperExportPreflightSummaryResponse.From(result.Summary),
            result.TeacherMessage,
            result.AuditTrail);
    }
}

public sealed record PaperExportPreflightSummaryResponse(
    int ImageReadyCount,
    int FormulaReadyCount,
    int TableReadyCount,
    int AnswerReadyCount,
    int SolutionReadyCount,
    int AuthorizedSourceCount,
    int ActiveKnowledgeVersionCount)
{
    public static PaperExportPreflightSummaryResponse From(PaperExportPreflightSummary summary)
    {
        return new PaperExportPreflightSummaryResponse(
            summary.ImageReadyCount,
            summary.FormulaReadyCount,
            summary.TableReadyCount,
            summary.AnswerReadyCount,
            summary.SolutionReadyCount,
            summary.AuthorizedSourceCount,
            summary.ActiveKnowledgeVersionCount);
    }
}

public sealed record PaperExportPreflightItemResponse(
    Guid QuestionItemId,
    int QuestionNo,
    string? SubQuestionNo,
    decimal Score,
    string KnowledgeVersionStatus,
    int KnowledgeVersion,
    bool HasImage,
    bool HasFormula,
    bool HasTable,
    bool HasAnswer,
    bool HasSolution,
    string SourceAuthorizationStatus,
    bool HasKnowledgeVersionReference,
    IReadOnlyList<PaperExportPreflightIssueResponse> Issues)
{
    public static PaperExportPreflightItemResponse From(PaperExportPreflightItemServiceResult item)
    {
        return new PaperExportPreflightItemResponse(
            item.QuestionItemId,
            item.QuestionNo,
            item.SubQuestionNo,
            item.Score,
            item.KnowledgeVersionStatus,
            item.KnowledgeVersion,
            item.HasImage,
            item.HasFormula,
            item.HasTable,
            item.HasAnswer,
            item.HasSolution,
            item.SourceAuthorizationStatus,
            item.HasKnowledgeVersionReference,
            item.Issues.Select(PaperExportPreflightIssueResponse.From).ToArray());
    }
}

public sealed record PaperExportPreflightIssueResponse(
    string Code,
    string Severity,
    string Message)
{
    public static PaperExportPreflightIssueResponse From(PaperExportPreflightIssueServiceItem issue)
    {
        return new PaperExportPreflightIssueResponse(issue.Code, issue.Severity, issue.Message);
    }
}

public sealed record ScoreImportRequest(
    string? AssessmentKey,
    string? AssessmentTitle,
    string? Subject,
    string? Stage,
    string? Grade,
    string? TemplateKey,
    string? TemplateDisplayName,
    string? SourceFileName,
    bool ContainsStudentPii,
    bool ProductionEligible,
    decimal MaxTotalScore,
    ScoreImportFieldMappingRequest FieldMapping,
    IReadOnlyDictionary<string, decimal> ItemMaxScores,
    IReadOnlyList<ScoreImportRowApiRequest> Rows);

public sealed record ScoreImportFieldMappingRequest(
    string StudentKey,
    string TotalScore,
    IReadOnlyDictionary<string, string> ItemScores);

public sealed record ScoreImportRowApiRequest(
    int RowNumber,
    IReadOnlyDictionary<string, string> Values);

public sealed record ScoreImportResponse(
    string Status,
    string Mode,
    bool ProductionEligible,
    bool RealStudentDataUsed,
    bool ContainsStudentPii,
    Guid? AssessmentId,
    Guid? TemplateId,
    Guid? BatchId,
    int RowCount,
    int ImportedCount,
    int ErrorCount,
    IReadOnlyList<ScoreImportRowErrorResponse> Errors,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail)
{
    public static ScoreImportResponse From(ScoreImportServiceResult result)
    {
        return new ScoreImportResponse(
            result.Status,
            result.Mode,
            result.ProductionEligible,
            result.RealStudentDataUsed,
            result.ContainsStudentPii,
            result.AssessmentId,
            result.TemplateId,
            result.BatchId,
            result.RowCount,
            result.ImportedCount,
            result.ErrorCount,
            result.Errors.Select(ScoreImportRowErrorResponse.From).ToArray(),
            result.TeacherMessage,
            result.AuditTrail);
    }
}

public sealed record ScoreImportRowErrorResponse(
    int RowNumber,
    string Code,
    string Message,
    IReadOnlyList<string> Fields)
{
    public static ScoreImportRowErrorResponse From(ScoreImportRowError error)
    {
        return new ScoreImportRowErrorResponse(error.RowNumber, error.Code, error.Message, error.Fields);
    }
}

public sealed record ItemScoreMappingPreviewRequest(
    IReadOnlyList<ItemScoreMappingRequest> Mappings);

public sealed record ItemScoreMappingRequest(
    string QuestionNo,
    Guid? QuestionItemId);

public sealed record ItemScoreMappingPreviewResponse(
    string Mode,
    bool ProductionEligible,
    bool RealStudentDataUsed,
    bool WritesProductionHistory,
    Guid AssessmentId,
    string AssessmentTitle,
    int ItemCount,
    int MappedCount,
    int UnclearCount,
    IReadOnlyList<ItemScoreMappingPreviewRowResponse> Rows,
    IReadOnlyList<ItemScoreMappingIssueResponse> Issues,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail)
{
    public static ItemScoreMappingPreviewResponse From(ItemScoreMappingPreviewServiceResult result)
    {
        return new ItemScoreMappingPreviewResponse(
            result.Mode,
            result.ProductionEligible,
            result.RealStudentDataUsed,
            result.WritesProductionHistory,
            result.AssessmentId,
            result.AssessmentTitle,
            result.ItemCount,
            result.MappedCount,
            result.UnclearCount,
            result.Rows.Select(ItemScoreMappingPreviewRowResponse.From).ToArray(),
            result.Issues.Select(ItemScoreMappingIssueResponse.From).ToArray(),
            result.TeacherMessage,
            result.AuditTrail);
    }
}

public sealed record ItemScoreMappingPreviewRowResponse(
    string QuestionNo,
    IReadOnlyList<string> FieldNames,
    int ScoreRecordCount,
    decimal MaxScore,
    decimal AverageScoreRate,
    Guid? QuestionItemId,
    string? QuestionPreview,
    ItemScoreKnowledgePreviewResponse? PrimaryKnowledge,
    string Status,
    IReadOnlyList<string> IssueCodes)
{
    public static ItemScoreMappingPreviewRowResponse From(ItemScoreMappingPreviewRow row)
    {
        return new ItemScoreMappingPreviewRowResponse(
            row.QuestionNo,
            row.FieldNames,
            row.ScoreRecordCount,
            row.MaxScore,
            row.AverageScoreRate,
            row.QuestionItemId,
            row.QuestionPreview,
            row.PrimaryKnowledge is null ? null : ItemScoreKnowledgePreviewResponse.From(row.PrimaryKnowledge),
            row.Status,
            row.IssueCodes);
    }
}

public sealed record ItemScoreKnowledgePreviewResponse(
    Guid KnowledgeNodeId,
    string Title,
    string Status,
    int Version)
{
    public static ItemScoreKnowledgePreviewResponse From(ItemScoreKnowledgePreview knowledge)
    {
        return new ItemScoreKnowledgePreviewResponse(
            knowledge.KnowledgeNodeId,
            knowledge.Title,
            knowledge.Status,
            knowledge.Version);
    }
}

public sealed record ItemScoreMappingIssueResponse(
    string QuestionNo,
    IReadOnlyList<string> Codes)
{
    public static ItemScoreMappingIssueResponse From(ItemScoreMappingIssue issue)
    {
        return new ItemScoreMappingIssueResponse(issue.QuestionNo, issue.Codes);
    }
}

public sealed record CommentaryReportExportRequest(
    string Format,
    bool AllowAiDraftText,
    IReadOnlyList<ItemScoreMappingRequest> Mappings);

public sealed record CommentaryReportExportResponse(
    string Status,
    string Mode,
    bool ProductionEligible,
    bool RealStudentDataUsed,
    bool WritesProductionHistory,
    bool AllowAiDraftText,
    Guid AssessmentId,
    string AssessmentTitle,
    string Format,
    string? ArtifactPath,
    string? ManifestSha256,
    string ReportMarkdown,
    IReadOnlyList<CommentaryReportSectionResponse> Sections,
    IReadOnlyList<CommentaryWeakKnowledgePointResponse> WeakKnowledgePoints,
    IReadOnlyList<CommentaryPracticeSuggestionResponse> PracticeSuggestions,
    IReadOnlyList<CommentaryReportIssueResponse> BlockingIssues,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail)
{
    public static CommentaryReportExportResponse From(CommentaryReportExportServiceResult result)
    {
        return new CommentaryReportExportResponse(
            result.Status,
            result.Mode,
            result.ProductionEligible,
            result.RealStudentDataUsed,
            result.WritesProductionHistory,
            result.AllowAiDraftText,
            result.AssessmentId,
            result.AssessmentTitle,
            result.Format,
            result.ArtifactPath,
            result.ManifestSha256,
            result.ReportMarkdown,
            result.Sections.Select(CommentaryReportSectionResponse.From).ToArray(),
            result.WeakKnowledgePoints.Select(CommentaryWeakKnowledgePointResponse.From).ToArray(),
            result.PracticeSuggestions.Select(CommentaryPracticeSuggestionResponse.From).ToArray(),
            result.BlockingIssues.Select(CommentaryReportIssueResponse.From).ToArray(),
            result.TeacherMessage,
            result.AuditTrail);
    }
}

public sealed record CommentaryReportSectionResponse(
    string SectionId,
    string Title,
    string Summary)
{
    public static CommentaryReportSectionResponse From(CommentaryReportSection section)
    {
        return new CommentaryReportSectionResponse(section.SectionId, section.Title, section.Summary);
    }
}

public sealed record CommentaryWeakKnowledgePointResponse(
    Guid KnowledgeNodeId,
    string Title,
    int Version,
    decimal ScoreRate,
    string QuestionNo)
{
    public static CommentaryWeakKnowledgePointResponse From(CommentaryWeakKnowledgePoint point)
    {
        return new CommentaryWeakKnowledgePointResponse(point.KnowledgeNodeId, point.Title, point.Version, point.ScoreRate, point.QuestionNo);
    }
}

public sealed record CommentaryPracticeSuggestionResponse(
    Guid KnowledgeNodeId,
    string KnowledgeTitle,
    string Suggestion)
{
    public static CommentaryPracticeSuggestionResponse From(CommentaryPracticeSuggestion suggestion)
    {
        return new CommentaryPracticeSuggestionResponse(suggestion.KnowledgeNodeId, suggestion.KnowledgeTitle, suggestion.Suggestion);
    }
}

public sealed record CommentaryReportIssueResponse(
    string QuestionNo,
    IReadOnlyList<string> Codes)
{
    public static CommentaryReportIssueResponse From(CommentaryReportIssue issue)
    {
        return new CommentaryReportIssueResponse(issue.QuestionNo, issue.Codes);
    }
}

public sealed record PaperRequestParseRequest(
    string TeacherRequest,
    string? TextbookVersion);

public sealed record PaperRequestParseResponse(
    string Mode,
    bool ProductionEligible,
    bool AllowRealModelCalls,
    string SchemaVersion,
    string PromptVersion,
    string SystemUnderstanding,
    string PaperType,
    string Subject,
    string Grade,
    string? TextbookVersion,
    IReadOnlyList<string> Scope,
    int TotalScore,
    string DifficultyTarget,
    IReadOnlyList<PaperQuestionTypePlan> QuestionTypePlan,
    IReadOnlyList<PaperBlueprintRow> Blueprint,
    PaperRequestConstraints Constraints,
    IReadOnlyList<string> ReviewQuestions);

public sealed record PaperQuestionTypePlan(
    string QuestionType,
    int Count,
    decimal Score);

public sealed record PaperBlueprintRow(
    string QuestionType,
    int Count,
    decimal Score,
    IReadOnlyList<string> Scope,
    string AssetStatus,
    string ReviewStatus);

public sealed record PaperRequestConstraints(
    string KnowledgeStatus,
    IReadOnlyList<string> SourceTypes,
    bool ReviewRequired,
    bool BlocksProductionPaper);

public sealed record PaperBlueprintReviewCreateRequest(
    string TeacherRequest,
    string? TextbookVersion);

public sealed record PaperBlueprintReviewResponse(
    Guid Id,
    string Status,
    string Mode,
    bool ProductionEligible,
    bool AllowRealModelCalls,
    string RequestText,
    string Subject,
    string Grade,
    string? TextbookVersion,
    IReadOnlyList<string> Scope,
    int TotalScore,
    string DifficultyTarget,
    IReadOnlyList<PaperBlueprintRow> Blueprint,
    PaperRequestConstraints Constraints,
    IReadOnlyList<string> ReviewQuestions,
    bool MustConfirmBeforeTakingQuestions,
    bool OpaqueGenerationAllowed,
    Guid? ConfirmedPaperBasketId,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt)
{
    public static PaperBlueprintReviewResponse From(PaperBlueprintReviewServiceResult result)
    {
        return new PaperBlueprintReviewResponse(
            result.Id,
            result.Status,
            result.Mode,
            result.ProductionEligible,
            result.AllowRealModelCalls,
            result.RequestText,
            result.Subject,
            result.Grade,
            result.TextbookVersion,
            result.Scope,
            result.TotalScore,
            result.DifficultyTarget,
            result.Blueprint.Select(x => new PaperBlueprintRow(x.QuestionType, x.Count, x.Score, x.Scope, x.AssetStatus, x.ReviewStatus)).ToArray(),
            new PaperRequestConstraints(
                result.Constraints.KnowledgeStatus,
                result.Constraints.SourceTypes,
                result.Constraints.ReviewRequired,
                result.Constraints.BlocksProductionPaper),
            result.ReviewQuestions,
            result.MustConfirmBeforeTakingQuestions,
            result.OpaqueGenerationAllowed,
            result.ConfirmedPaperBasketId,
            result.CreatedAt,
            result.UpdatedAt);
    }
}

public sealed record PaperBlueprintConfirmRequest(string TeacherConfirmedBy);

public sealed record PaperBlueprintConfirmResponse(
    Guid Id,
    string Status,
    bool Confirmed,
    Guid? PaperBasketId,
    int SelectedQuestionCount,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail)
{
    public static PaperBlueprintConfirmResponse From(PaperBlueprintConfirmServiceResult result)
    {
        return new PaperBlueprintConfirmResponse(
            result.Id,
            result.Status,
            result.Confirmed,
            result.PaperBasketId,
            result.SelectedQuestionCount,
            result.TeacherMessage,
            result.AuditTrail);
    }
}

public sealed record PaperQuestionReplacementRequest(PaperDraftQuestion CurrentQuestion);

public sealed record PaperDraftQuestion(
    string Id,
    string StemPreview,
    string QuestionType,
    decimal Score,
    double? DifficultyEstimated,
    string PrimaryKnowledgeId,
    string PrimaryKnowledgeTitle,
    string SourceType,
    string RecentUseStatus);

public sealed record PaperQuestionReplacementResponse(
    string Mode,
    bool ProductionEligible,
    bool AllowRealModelCalls,
    string Action,
    string Reason,
    PaperQuestionReplacementConstraints Constraints,
    PaperDraftQuestion Replacement,
    PaperQuestionUndoSnapshot Undo,
    IReadOnlyList<string> AuditTrail);

public sealed record PaperQuestionReplacementConstraints(
    bool SameKnowledge,
    bool SameQuestionType,
    bool SimilarDifficulty,
    bool SameScore,
    bool ExcludeCurrentPaperDuplicates,
    bool ExcludeRecentlyUsed,
    string KnowledgeStatus,
    bool BlocksProductionPaper);

public sealed record PaperQuestionUndoSnapshot(
    string UndoToken,
    PaperDraftQuestion BeforeQuestion,
    PaperDraftQuestion AfterQuestion,
    string RevertAction);

public sealed record KnowledgeVersionExplanationRequest(
    string ArtifactType,
    string ArtifactId,
    string HistoricalKnowledgeStableId,
    string HistoricalKnowledgeVersion,
    string CurrentKnowledgeVersion,
    string? MappingType,
    IReadOnlyList<string> CurrentKnowledgeStableIds,
    bool AffectsHistoricalAnalysis);

public sealed record KnowledgeVersionExplanationResponse(
    string Mode,
    bool ProductionEligible,
    bool ReadOnly,
    bool RealStudentDataUsed,
    bool WritesProductionHistory,
    string ArtifactType,
    string ArtifactId,
    string HistoricalKnowledgeStableId,
    string HistoricalKnowledgeVersion,
    string CurrentKnowledgeVersion,
    string MappingType,
    IReadOnlyList<string> CurrentKnowledgeStableIds,
    bool FrozenHistoricalView,
    bool CurrentVersionDifferent,
    bool AffectsHistoricalAnalysis,
    string ExplanationText,
    string TeacherVisibleSummary,
    IReadOnlyList<string> AuditTrail);

public static class JsonHelpers
{
    public static JsonElement ParseJsonElement(string value)
    {
        using var document = JsonDocument.Parse(value);
        return document.RootElement.Clone();
    }
}

public static class ReviewQueuePayloadHelpers
{
    public static string ResolveRiskLevel(string payloadJson)
    {
        try
        {
            var payload = JsonHelpers.ParseJsonElement(payloadJson);
            return ResolveRiskLevel(payload);
        }
        catch
        {
            return "high";
        }
    }

    public static string ResolveRiskLevel(JsonElement payload)
    {
        if (ResolveConfidence(payload) is { } confidence)
        {
            return confidence < 0.6m ? "high" : confidence < 0.85m ? "medium" : "low";
        }

        return "high";
    }

    public static string ResolveRequiredAction(JsonElement payload)
    {
        if (payload.ValueKind == JsonValueKind.Object &&
            payload.TryGetProperty("requiredAction", out var actionElement) &&
            actionElement.ValueKind == JsonValueKind.String)
        {
            return actionElement.GetString() ?? "manual_review";
        }

        return "manual_review";
    }

    public static decimal? ResolveConfidence(JsonElement payload)
    {
        if (payload.ValueKind == JsonValueKind.Object &&
            payload.TryGetProperty("confidence", out var confidenceElement) &&
            confidenceElement.TryGetDecimal(out var confidence))
        {
            return confidence;
        }

        return null;
    }

    public static string? ResolveReason(JsonElement payload)
    {
        if (payload.ValueKind == JsonValueKind.Object &&
            payload.TryGetProperty("reason", out var reasonElement) &&
            reasonElement.ValueKind == JsonValueKind.String)
        {
            return reasonElement.GetString();
        }

        return null;
    }

    public static int? ResolveQuestionNo(JsonElement payload)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty("questionNo", out var questionNoElement))
        {
            return null;
        }

        if (questionNoElement.TryGetInt32(out var questionNo))
        {
            return questionNo;
        }

        if (questionNoElement.ValueKind == JsonValueKind.String &&
            int.TryParse(questionNoElement.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out questionNo))
        {
            return questionNo;
        }

        return null;
    }

    public static string WithReviewAudit(
        string payloadJson,
        string reviewedBy,
        string decision,
        string reason,
        DateTimeOffset reviewedAt,
        ReviewQueueRevisionRequest? revision = null)
    {
        Dictionary<string, object?> payload;
        try
        {
            payload = JsonSerializer.Deserialize<Dictionary<string, object?>>(payloadJson) ?? new Dictionary<string, object?>();
        }
        catch
        {
            payload = new Dictionary<string, object?>();
        }

        var trimmedTags = revision?.KnowledgeTags?
            .Where(tag => !string.IsNullOrWhiteSpace(tag))
            .Select(tag => tag.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var hasRevision = revision is not null && (
            !string.IsNullOrWhiteSpace(revision.TextPreview) ||
            !string.IsNullOrWhiteSpace(revision.Answer) ||
            !string.IsNullOrWhiteSpace(revision.PrimaryKnowledgeLabel) ||
            (trimmedTags is { Length: > 0 }));

        payload["reviewAudit"] = new
        {
            reviewedBy,
            decision,
            reason,
            reviewedAt = reviewedAt.ToString("O"),
            revision = hasRevision
                ? new
                {
                    textPreview = revision?.TextPreview?.Trim(),
                    answer = revision?.Answer?.Trim(),
                    primaryKnowledgeLabel = revision?.PrimaryKnowledgeLabel?.Trim(),
                    knowledgeTags = trimmedTags ?? Array.Empty<string>()
                }
                : null
        };

        return JsonSerializer.Serialize(payload);
    }
}

public static class ReviewWorkbenchMutationHelpers
{
    public static string WithPatch(string json, Dictionary<string, object?> patch)
    {
        Dictionary<string, object?> payload;
        try
        {
            payload = JsonSerializer.Deserialize<Dictionary<string, object?>>(json) ?? new Dictionary<string, object?>();
        }
        catch
        {
            payload = new Dictionary<string, object?>();
        }

        foreach (var pair in patch)
        {
            payload[pair.Key] = pair.Value;
        }

        return JsonSerializer.Serialize(payload);
    }

    public static CutCandidate CloneCandidate(CutCandidate source, int sequenceNo, DateTimeOffset now, string splitTag)
    {
        return new CutCandidate
        {
            SourceDocumentId = source.SourceDocumentId,
            SourceRegionId = source.SourceRegionId,
            SuggestedQuestionItemId = null,
            Status = CutCandidateStatuses.PendingReview,
            Confidence = Math.Max(0m, source.Confidence - 0.05m),
            SegmentType = source.SegmentType,
            SequenceNo = sequenceNo,
            CandidatePayload = WithPatch(source.CandidatePayload, new Dictionary<string, object?>
            {
                ["splitTag"] = splitTag,
                ["splitFromCandidateId"] = source.Id
            }),
            FailureReason = "requires_manual_review_after_split",
            TakeoverAction = "manual_review",
            Metadata = WithPatch(source.Metadata, new Dictionary<string, object?>
            {
                ["generatedBy"] = "s006b-split",
                ["generatedAt"] = now.ToString("O")
            }),
            CreatedAt = now,
            UpdatedAt = now
        };
    }

    public static bool QueueItemMatchesCandidates(string payloadJson, HashSet<Guid> candidateSourceRegionIds)
    {
        try
        {
            using var document = JsonDocument.Parse(payloadJson);
            var payload = document.RootElement;
            if (payload.ValueKind != JsonValueKind.Object ||
                !payload.TryGetProperty("sourceRegionId", out var sourceRegionElement) ||
                sourceRegionElement.ValueKind != JsonValueKind.String)
            {
                return false;
            }

            var sourceRegionId = sourceRegionElement.GetString();
            if (string.IsNullOrWhiteSpace(sourceRegionId) || !Guid.TryParse(sourceRegionId, out var parsedRegionId))
            {
                return false;
            }

            return candidateSourceRegionIds.Contains(parsedRegionId);
        }
        catch
        {
            return false;
        }
    }
}

internal static class QuestionJsonMetadata
{
    public static int? TryGetIntField(string json, string propertyName)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Object ||
                !document.RootElement.TryGetProperty(propertyName, out var property))
            {
                return null;
            }

            if (property.ValueKind == JsonValueKind.Number && property.TryGetInt32(out var number))
            {
                return number;
            }

            return property.ValueKind == JsonValueKind.String &&
                int.TryParse(property.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out number)
                ? number
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }
}

public sealed class AdminInternalGuardOptions
{
    public string? ApiKey { get; set; }
    public bool AllowUnguardedDraftTest { get; set; }
}

public sealed class AdminInternalRoleAuditOptions
{
    public bool Enabled { get; set; } = true;
    public bool RequireRoleHeader { get; set; } = true;
    public bool RequireOperatorIdHeader { get; set; } = true;
    public bool EnableAuditLog { get; set; } = true;
    public string AuditLogFileName { get; set; } = "admin-internal-audit.jsonl";
}

public static class AdminInternalEndpointGuard
{
    public const string HeaderName = "X-KQG-Admin-Key";
    public const string RoleHeaderName = "X-KQG-Operator-Role";
    public const string OperatorIdHeaderName = "X-KQG-Operator-Id";
    public const string RollbackRefHeaderName = "X-KQG-Rollback-Ref";
    public const string DraftTestHeaderName = "X-KQG-Auth-Boundary";
    public const string DraftTestHeaderValue = "draft-test-unguarded-admin-internal";

    public static WebApplication UseAdminInternalEndpointGuard(this WebApplication app)
    {
        app.Use(async (context, next) =>
        {
            if (!RequiresGuard(context.Request.Path))
            {
                await next();
                return;
            }

            var options = app.Configuration
                .GetSection("AdminInternalGuard")
                .Get<AdminInternalGuardOptions>() ?? new AdminInternalGuardOptions();
            var roleAuditOptions = app.Configuration
                .GetSection("AdminInternalRoleAudit")
                .Get<AdminInternalRoleAuditOptions>() ?? new AdminInternalRoleAuditOptions();
            var paths = app.Configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
            var configuredKey = options.ApiKey?.Trim();
            var draftTestBypassAllowed = app.Environment.IsDevelopment() && options.AllowUnguardedDraftTest;
            var isHighRiskWrite = IsHighRiskWrite(context.Request.Method);
            var operatorRole = context.Request.Headers.TryGetValue(RoleHeaderName, out var roleValues)
                ? NormalizeRole(roleValues.FirstOrDefault())
                : string.Empty;
            var operatorId = context.Request.Headers.TryGetValue(OperatorIdHeaderName, out var operatorValues)
                ? operatorValues.FirstOrDefault()?.Trim() ?? string.Empty
                : string.Empty;
            var rollbackRef = context.Request.Headers.TryGetValue(RollbackRefHeaderName, out var rollbackValues)
                ? rollbackValues.FirstOrDefault()?.Trim() ?? string.Empty
                : string.Empty;

            Task AuditAsync(int statusCode, string decision)
            {
                if (!roleAuditOptions.Enabled || !roleAuditOptions.EnableAuditLog)
                {
                    return Task.CompletedTask;
                }

                try
                {
                    Directory.CreateDirectory(paths.LogsRoot);
                    var logPath = Path.Combine(paths.LogsRoot, roleAuditOptions.AuditLogFileName);
                    var payload = new
                    {
                        timestampUtc = DateTimeOffset.UtcNow.ToString("O"),
                        path = context.Request.Path.Value,
                        method = context.Request.Method,
                        operatorRole = string.IsNullOrWhiteSpace(operatorRole) ? "unknown" : operatorRole,
                        operatorId = string.IsNullOrWhiteSpace(operatorId) ? "unknown" : operatorId,
                        objectRef = context.Request.Path.Value,
                        highRisk = isHighRiskWrite,
                        rollbackRef = string.IsNullOrWhiteSpace(rollbackRef) ? null : rollbackRef,
                        decision,
                        statusCode
                    };
                    var line = JsonSerializer.Serialize(payload) + Environment.NewLine;
                    File.AppendAllText(logPath, line, Encoding.UTF8);
                }
                catch
                {
                    // Fail open for audit write so API availability isn't broken by logging issues.
                }

                return Task.CompletedTask;
            }

            if (string.IsNullOrWhiteSpace(configuredKey))
            {
                if (draftTestBypassAllowed)
                {
                    context.Response.Headers[DraftTestHeaderName] = DraftTestHeaderValue;
                    await AuditAsync(StatusCodes.Status200OK, "allow_draft_test_bypass");
                    await next();
                    return;
                }

                context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
                await context.Response.WriteAsJsonAsync(new
                {
                    error = "admin_internal_guard_not_configured",
                    requiredHeader = HeaderName
                });
                await AuditAsync(StatusCodes.Status503ServiceUnavailable, "deny_guard_not_configured");
                return;
            }

            if (!context.Request.Headers.TryGetValue(HeaderName, out var providedValues))
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsJsonAsync(new { error = "missing_admin_internal_key" });
                await AuditAsync(StatusCodes.Status401Unauthorized, "deny_missing_admin_key");
                return;
            }

            var providedKey = providedValues.FirstOrDefault();
            if (!FixedTimeEquals(providedKey, configuredKey))
            {
                context.Response.StatusCode = StatusCodes.Status403Forbidden;
                await context.Response.WriteAsJsonAsync(new { error = "invalid_admin_internal_key" });
                await AuditAsync(StatusCodes.Status403Forbidden, "deny_invalid_admin_key");
                return;
            }

            if (roleAuditOptions.Enabled && roleAuditOptions.RequireRoleHeader && string.IsNullOrWhiteSpace(operatorRole))
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsJsonAsync(new { error = "missing_operator_role", requiredHeader = RoleHeaderName });
                await AuditAsync(StatusCodes.Status401Unauthorized, "deny_missing_operator_role");
                return;
            }

            if (roleAuditOptions.Enabled && roleAuditOptions.RequireOperatorIdHeader && string.IsNullOrWhiteSpace(operatorId))
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsJsonAsync(new { error = "missing_operator_id", requiredHeader = OperatorIdHeaderName });
                await AuditAsync(StatusCodes.Status401Unauthorized, "deny_missing_operator_id");
                return;
            }

            if (roleAuditOptions.Enabled && !IsRoleAuthorized(context.Request.Path, context.Request.Method, operatorRole))
            {
                context.Response.StatusCode = StatusCodes.Status403Forbidden;
                await context.Response.WriteAsJsonAsync(new { error = "role_not_authorized", role = operatorRole });
                await AuditAsync(StatusCodes.Status403Forbidden, "deny_role_not_authorized");
                return;
            }

            await AuditAsync(StatusCodes.Status200OK, "allow");
            await next();
        });

        return app;
    }

    private static bool RequiresGuard(PathString path) =>
        path.StartsWithSegments("/api/admin", StringComparison.OrdinalIgnoreCase) ||
        path.StartsWithSegments("/internal/ai", StringComparison.OrdinalIgnoreCase);

    private static bool IsRoleAuthorized(PathString path, string method, string role)
    {
        if (string.IsNullOrWhiteSpace(role))
        {
            return false;
        }

        if (path.StartsWithSegments("/internal/ai", StringComparison.OrdinalIgnoreCase))
        {
            return role == "admin";
        }

        if (path.StartsWithSegments("/api/admin", StringComparison.OrdinalIgnoreCase))
        {
            if (HttpMethods.IsGet(method) || HttpMethods.IsHead(method))
            {
                return role is "admin" or "group_lead";
            }

            return role == "admin";
        }

        return false;
    }

    private static bool IsHighRiskWrite(string method) =>
        HttpMethods.IsPost(method) || HttpMethods.IsPut(method) || HttpMethods.IsPatch(method) || HttpMethods.IsDelete(method);

    private static string NormalizeRole(string? role) =>
        string.IsNullOrWhiteSpace(role) ? string.Empty : role.Trim().ToLowerInvariant();

    private static bool FixedTimeEquals(string? providedKey, string configuredKey)
    {
        if (string.IsNullOrEmpty(providedKey))
        {
            return false;
        }

        var providedBytes = Encoding.UTF8.GetBytes(providedKey);
        var configuredBytes = Encoding.UTF8.GetBytes(configuredKey);
        return providedBytes.Length == configuredBytes.Length &&
            CryptographicOperations.FixedTimeEquals(providedBytes, configuredBytes);
    }
}
