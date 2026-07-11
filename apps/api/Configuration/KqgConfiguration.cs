namespace K12QuestionGraph.Api.Configuration;

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

public sealed record KqgPathsOptions
{
    public string DataRoot { get; init; } = @"D:\KQG_Data";

    public string FileStoreRoot { get; init; } = @"D:\KQG_Data\file_store";

    public string BackupRoot { get; init; } = @"D:\KQG_Backups";

    public string LogsRoot { get; init; } = @"D:\KQG_Data\logs";

    public string CacheRoot { get; init; } = @"D:\KQG_Data\cache";
}
