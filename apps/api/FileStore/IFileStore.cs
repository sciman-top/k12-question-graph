namespace K12QuestionGraph.Api.FileStore;

public interface IFileStore
{
    Task<FileAssetResponse> StoreOriginalAsync(
        Stream content,
        string originalFileName,
        string? contentType,
        long sizeBytes,
        SourceDocumentMetadata sourceMetadata,
        CancellationToken cancellationToken);
}
