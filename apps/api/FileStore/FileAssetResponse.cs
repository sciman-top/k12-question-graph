namespace K12QuestionGraph.Api.FileStore;

public sealed record FileAssetResponse(
    Guid Id,
    string OriginalFileName,
    string RelativePath,
    string StorageScope,
    string ContentType,
    string Sha256,
    long SizeBytes);
