using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.FileStore;
using K12QuestionGraph.Api.ImportJobs;
using K12QuestionGraph.Api.Workers;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();
builder.Services.Configure<KqgPathsOptions>(builder.Configuration.GetSection("KqgPaths"));
builder.Services.Configure<PythonWorkerOptions>(builder.Configuration.GetSection("PythonWorker"));
builder.Services.AddDbContext<KqgDbContext>(options =>
    options
        .UseNpgsql(builder.Configuration.GetKqgConnectionString())
        .UseSnakeCaseNamingConvention());
builder.Services.AddScoped<IFileStore, LocalFileStore>();
builder.Services.AddScoped<IDocumentWorkerClient, DocumentWorkerClient>();

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

app.MapPost("/files", async (IFormFile file, IFileStore fileStore, CancellationToken cancellationToken) =>
{
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
        cancellationToken);

    return Results.Created($"/files/{stored.Id}", stored);
})
.DisableAntiforgery()
.WithName("UploadFile");

app.MapPost("/imports", async (IFormFile file, IFileStore fileStore, KqgDbContext dbContext, CancellationToken cancellationToken) =>
{
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
