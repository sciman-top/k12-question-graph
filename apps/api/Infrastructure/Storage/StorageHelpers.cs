namespace K12QuestionGraph.Api.Infrastructure.Storage;

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
