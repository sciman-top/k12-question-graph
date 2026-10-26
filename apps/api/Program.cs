using K12QuestionGraph.Api.Ai;
using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Application.Workflows.Contracts;
using K12QuestionGraph.Api.Configuration;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.Endpoints;
using K12QuestionGraph.Api.FileStore;
using K12QuestionGraph.Api.Infrastructure.Health;
using K12QuestionGraph.Api.Infrastructure.Json;
using K12QuestionGraph.Api.Infrastructure.Queries;
using K12QuestionGraph.Api.Infrastructure.Storage;
using K12QuestionGraph.Api.Infrastructure.Workers;
using K12QuestionGraph.Api.ImportJobs;
using K12QuestionGraph.Api.Papers;
using K12QuestionGraph.Api.Questions;
using K12QuestionGraph.Api.Scores;
using K12QuestionGraph.Api.Security;
using K12QuestionGraph.Api.Workers;
using static K12QuestionGraph.Api.Questions.QuestionHelpers;
using static K12QuestionGraph.Api.FileStore.FormHelpers;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Hosting.WindowsServices;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);
builder.Host.UseWindowsService();

// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();
builder.Services.AddProblemDetails();
builder.Services.AddDataProtection();
builder.Services
    .AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(options =>
    {
        options.Cookie.Name = "KQG.AdminSession";
        options.Cookie.HttpOnly = true;
        options.Cookie.SameSite = SameSiteMode.Strict;
        options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
        options.ExpireTimeSpan = TimeSpan.FromHours(8);
        options.SlidingExpiration = true;
        options.Events.OnRedirectToLogin = context =>
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return Task.CompletedTask;
        };
        options.Events.OnRedirectToAccessDenied = context =>
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            return Task.CompletedTask;
        };
    });
builder.Services.AddAuthorization();
builder.Services.Configure<KqgPathsOptions>(builder.Configuration.GetSection("KqgPaths"));
builder.Services.Configure<PythonWorkerOptions>(builder.Configuration.GetSection("PythonWorker"));
builder.Services.Configure<AiRoutingOptions>(builder.Configuration.GetSection("AiRouting"));
builder.Services.AddDbContext<KqgDbContext>(options =>
    options
        .UseNpgsql(builder.Configuration.GetKqgConnectionString())
        .UseSnakeCaseNamingConvention());
builder.Services.AddScoped<LocalFileStore>();
builder.Services.AddScoped<DocumentWorkerClient>();
builder.Services.AddSingleton<IImportJobLeaseStore, ImportJobLeaseStore>();
builder.Services.AddScoped<CutCandidateGenerationService>();
builder.Services.AddScoped<PaperWorkflowService>();
builder.Services.AddSingleton<IPaperBlueprintConfirmClaimStore, PaperBlueprintConfirmClaimStore>();
builder.Services.AddScoped<ScoreAnalysisWorkflowService>();
builder.Services.AddScoped<ScoreSpreadsheetImportAdapter>();
builder.Services.AddScoped<PaperArtifactService>();
builder.Services.AddScoped<KnowledgeEvidenceWorkflowService>();
builder.Services.AddSingleton<AiPresetAvailabilityCoordinator>();
builder.Services.AddSingleton<AiModelRouter>();
builder.Services.AddSingleton<AiProviderInvocationGate>();
builder.Services.AddSingleton<StubAiProvider>();
builder.Services.AddSingleton<FileAiProviderSettingsStore>();
builder.Services.AddHttpClient<OpenAiCompatibleSmokeTestService>();
builder.Services.AddHostedService<AiPresetRecoveryProbeService>();

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler();
}

app.UseDefaultFiles();
app.UseStaticFiles();
app.UseAuthentication();
app.UseAdminInternalEndpointGuard();
app.UseAuthorization();

app.MapAdminSessionEndpoints();
app.MapKnowledgeEvidenceEndpoints();
app.MapReviewQueueEndpoints();
app.MapSourceDocumentEndpoints();
app.MapQuestionEndpoints();
app.MapPaperBasketEndpoints();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.MapGet("/health", () =>
    Results.Ok(new HealthResponse(
        Status: "ok",
        Service: "K12QuestionGraph.Api")))
.AllowAnonymous()
.WithName("Health");

app.MapGet("/health/details", (IWebHostEnvironment environment, IConfiguration configuration) =>
{
    var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
    var contentRoot = Path.GetFullPath(environment.ContentRootPath);
    var dataRoot = Path.GetFullPath(paths.DataRoot);

    return Results.Ok(new HealthDetailsResponse
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
.WithName("HealthDetails");

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

app.MapAdminAiEndpoints();

app.MapPost("/internal/ai/model-route", (AiRouteRequest request, AiModelRouter router) =>
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





























app.MapScoreEndpoints();







app.MapPost("/knowledge-version-explanations/resolve", (KnowledgeVersionExplanationRequest request, PaperWorkflowService workflowService) =>
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



app.MapFallbackToFile("index.html").AllowAnonymous();

app.Run();

// 业务审计的 reviewedBy 统一取认证 actor 身份;请求体 ReviewedBy 仅兼容保留,
// 不再作为身份来源(2026-08-23 审计 M1 定案)。







public partial class Program;
