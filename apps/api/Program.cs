using K12QuestionGraph.Api.Ai;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.FileStore;
using K12QuestionGraph.Api.ImportJobs;
using K12QuestionGraph.Api.Workers;
using Microsoft.EntityFrameworkCore;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

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
builder.Services.AddSingleton<IAiModelRouter, AiModelRouter>();
builder.Services.AddSingleton<IAiProvider, StubAiProvider>();

var app = builder.Build();

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
    var repoRoot = Path.GetFullPath(Path.Combine(environment.ContentRootPath, "..", ".."));
    var workerScript = Path.GetFullPath(Path.Combine(repoRoot, workerOptions.DocumentWorkerScript));
    checks.Add(new ReadinessCheck("document_worker_script", File.Exists(workerScript), workerScript));

    var ready = checks.All(x => x.Ok);
    var response = new ReadinessResponse(ready ? "ok" : "unhealthy", checks);

    return ready ? Results.Ok(response) : Results.Json(response, statusCode: StatusCodes.Status503ServiceUnavailable);
})
.WithName("ReadinessHealth");

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
    var total = await query.CountAsync(cancellationToken);
    var items = await query
        .OrderByDescending(x => x.UpdatedAt)
        .ThenByDescending(x => x.CreatedAt)
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
            sourceSummary ?? new SourceSummaryResponse([], []));
    }).ToArray();

    return Results.Ok(new QuestionSearchResponse(
        Mode: "draft_test",
        ProductionEligible: false,
        Total: total,
        Limit: pageSize,
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
        OwnerScope = FormValue(form, "ownerScope", defaults.OwnerScope),
        LicenseOrPermission = FormValue(form, "licenseOrPermission", defaults.LicenseOrPermission),
        SharingAllowed = FormBool(form, "sharingAllowed", defaults.SharingAllowed),
        ContainsStudentPii = FormBool(form, "containsStudentPii", defaults.ContainsStudentPii),
        AnonymizationStatus = FormValue(form, "anonymizationStatus", defaults.AnonymizationStatus)
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

public sealed record KqgPathsOptions
{
    public string DataRoot { get; init; } = @"D:\KQG_Data";

    public string FileStoreRoot { get; init; } = @"D:\KQG_Data\file_store";

    public string BackupRoot { get; init; } = @"D:\KQG_Backups";

    public string LogsRoot { get; init; } = @"D:\KQG_Data\logs";
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
    int Limit,
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
    SourceSummaryResponse Sources);

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

public static class JsonHelpers
{
    public static JsonElement ParseJsonElement(string value)
    {
        using var document = JsonDocument.Parse(value);
        return document.RootElement.Clone();
    }
}
