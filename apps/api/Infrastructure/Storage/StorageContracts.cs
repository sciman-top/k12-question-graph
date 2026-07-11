namespace K12QuestionGraph.Api.Infrastructure.Storage;

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
