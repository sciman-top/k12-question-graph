using K12QuestionGraph.Api.Ai;
using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.FileStore;
using K12QuestionGraph.Api.ImportJobs;
using K12QuestionGraph.Api.Workers;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Hosting.WindowsServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);
builder.Host.UseWindowsService();

// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();
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
        now);
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
                            text = $"候选片段 {x.SequenceNo}",
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
    string? knowledgeStatus,
    int? knowledgeVersion,
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

    var pageSize = Math.Clamp(limit ?? 20, 1, 50);
    var pageIndex = Math.Max(1, page ?? 1);
    var offset = (pageIndex - 1) * pageSize;
    var total = await query.CountAsync(cancellationToken);
    var items = await query
        .OrderByDescending(x => x.UpdatedAt)
        .ThenByDescending(x => x.CreatedAt)
        .Skip(offset)
        .Take(pageSize)
        .ToListAsync(cancellationToken);

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
        select new { block.QuestionItemId, document.SourceTitle, document.SourceType }
    ).Concat(
        from asset in dbContext.QuestionAssets.AsNoTracking()
        where questionIds.Contains(asset.QuestionItemId) && asset.SourceRegionId != null
        join region in dbContext.SourceRegions.AsNoTracking() on asset.SourceRegionId!.Value equals region.Id
        join document in dbContext.SourceDocuments.AsNoTracking() on region.SourceDocumentId equals document.Id
        select new { asset.QuestionItemId, document.SourceTitle, document.SourceType }
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
                x.Select(row => row.SourceType).Where(value => !string.IsNullOrWhiteSpace(value)).Distinct().ToArray()));

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
            primaryKnowledge,
            GetQuestionPreview(itemBlocks ?? []),
            itemBlocks?.Length ?? 0,
            assetCount,
            sourceSummary ?? new SourceSummaryResponse([], []),
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

    if (!ImportJobTransitions.IsAllowed(job.Status, JobStatuses.Running))
    {
        return Results.Conflict(new { error = "invalid_status_transition", from = job.Status, to = JobStatuses.Running });
    }

    var now = DateTimeOffset.UtcNow;
    job.Status = JobStatuses.Running;
    job.StartedAt ??= now;
    job.FinishedAt = null;
    job.AttemptCount += 1;
    job.LockedBy = "document-worker-smoke";
    job.LockedUntil = now.AddMinutes(5);
    await dbContext.SaveChangesAsync(cancellationToken);

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
    await dbContext.SaveChangesAsync(cancellationToken);

    return Results.Ok(new
    {
        job.Id,
        job.Status,
        result.ExitCode,
        result.StandardOutput,
        result.StandardError
    });
})
.WithName("RunDocumentWorkerSmoke");

app.Run();

static SourceDocumentMetadata SourceMetadataFromForm(IFormCollection form, string originalFileName)
{
    var defaults = SourceDocumentMetadata.Defaults(Path.GetFileName(originalFileName));

    return defaults with
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

    var allowedBlockTypes = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "text",
        "option",
        "sub_question",
        "answer",
        "solution",
        "formula",
        "image",
        "table",
        "chart",
        "group_ref"
    };
    foreach (var block in request.Blocks)
    {
        if (!allowedBlockTypes.Contains(NormalizeToken(block.BlockType, "text")))
        {
            return "invalid_block_type";
        }
    }

    return null;
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

public sealed record SourceRegionCreateRequest(
    int PageNumber,
    decimal X,
    decimal Y,
    decimal Width,
    decimal Height,
    string CoordinateUnit,
    string? ScreenshotRelativePath,
    string? RegionType);

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
    string RegionType)
{
    public static SourceRegionResponse From(SourceRegion region)
    {
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
            region.RegionType);
    }
}

public sealed record SourcePreviewPageResponse(int PageNumber, IReadOnlyList<SourceRegionResponse> Regions);

public sealed record SourceDocumentPreviewResponse(Guid SourceDocumentId, IReadOnlyList<SourcePreviewPageResponse> Pages);

public sealed record SourceMaterialListResponse(
    string Mode,
    IReadOnlyList<SourceMaterialResponse> Items);

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
    string Reason);

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

public sealed record QuestionAssetCreateRequest(
    Guid? FileAssetId,
    Guid? SourceRegionId,
    string AssetType,
    string? Purpose,
    JsonElement Metadata);

public sealed record QuestionResponse(
    Guid Id,
    string Subject,
    string Stage,
    string? Grade,
    string? QuestionType,
    decimal? DefaultScore,
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
            item.Status,
            blocks.Select(QuestionBlockResponse.From).ToArray(),
            assets.Select(QuestionAssetResponse.From).ToArray(),
            JsonHelpers.ParseJsonElement(item.CustomFields));
    }
}

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
    string AssetType,
    string Purpose,
    JsonElement Metadata)
{
    public static QuestionAssetResponse From(QuestionAsset asset)
    {
        return new QuestionAssetResponse(
            asset.Id,
            asset.QuestionItemId,
            asset.FileAssetId,
            asset.SourceRegionId,
            asset.AssetType,
            asset.Purpose,
            JsonHelpers.ParseJsonElement(asset.Metadata));
    }
}

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

public sealed record SourceSummaryResponse(IReadOnlyList<string> Titles, IReadOnlyList<string> Types);

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
    string RegionType)
{
    public static QuestionSourceRegionResponse From(SourceRegion region, SourceDocument? document)
    {
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

    public static string WithReviewAudit(
        string payloadJson,
        string reviewedBy,
        string decision,
        string reason,
        DateTimeOffset reviewedAt)
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

        payload["reviewAudit"] = new
        {
            reviewedBy,
            decision,
            reason,
            reviewedAt = reviewedAt.ToString("O")
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
