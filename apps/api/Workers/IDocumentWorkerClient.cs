namespace K12QuestionGraph.Api.Workers;

public interface IDocumentWorkerClient
{
    Task<DocumentWorkerResult> RunSmokeAsync(
        Guid jobId,
        string relativePath,
        bool simulateFailure,
        CancellationToken cancellationToken);
}
