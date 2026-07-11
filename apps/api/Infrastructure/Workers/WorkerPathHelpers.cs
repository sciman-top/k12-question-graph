namespace K12QuestionGraph.Api.Infrastructure.Workers;

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
