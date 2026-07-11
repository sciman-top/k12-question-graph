using K12QuestionGraph.Api.Data;

namespace K12QuestionGraph.Api.Infrastructure.Health;

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
