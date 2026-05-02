var builder = WebApplication.CreateBuilder(args);

// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();
builder.Services.Configure<KqgPathsOptions>(builder.Configuration.GetSection("KqgPaths"));

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

app.Run();

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
