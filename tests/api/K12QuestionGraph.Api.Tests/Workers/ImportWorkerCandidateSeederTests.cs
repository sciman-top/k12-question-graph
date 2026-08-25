using System.Text.Json;
using K12QuestionGraph.Api.Configuration;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.ImportJobs;
using K12QuestionGraph.Api.Workers;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Xunit;

namespace K12QuestionGraph.Api.Tests;

public class ImportWorkerCandidateSeederTests : IDisposable
{
    private readonly string _fileStoreRoot = WorkerTestHarness.CreateTempDirectory();

    public void Dispose()
    {
        WorkerTestHarness.DeleteDirectoryBestEffort(_fileStoreRoot);
    }

    private static KqgDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<KqgDbContext>()
            .UseInMemoryDatabase($"seeder-tests-{Guid.NewGuid():N}")
            .Options;
        return new KqgDbContext(options);
    }

    private async Task<DocumentWorkerResult> RunRealWorkerOnDocxAsync(string relativePath)
    {
        var client = new DocumentWorkerClient(
            Options.Create(new PythonWorkerOptions
            {
                PythonExecutable = WorkerTestHarness.PythonExecutable.Value,
                DocumentWorkerScript = WorkerTestHarness.WorkerScript.Value,
                TimeoutSeconds = 60,
            }),
            Options.Create(new KqgPathsOptions { FileStoreRoot = _fileStoreRoot }),
            new FakeHostEnvironment());
        return await client.RunSmokeAsync(Guid.NewGuid(), relativePath, simulateFailure: false, CancellationToken.None);
    }

    [Fact]
    public async Task SeedAsync_MaterializesRealWorkerDocxOutputIntoCandidates()
    {
        Directory.CreateDirectory(Path.Combine(_fileStoreRoot, "original"));
        var docxPath = Path.Combine(_fileStoreRoot, "original", "physics.docx");
        WorkerTestHarness.WriteMinimalDocx(
            docxPath,
            "1. 下列关于声现象的说法正确的是",
            "A. 声音由物体振动产生",
            "答案:B");

        var workerResult = await RunRealWorkerOnDocxAsync("original/physics.docx");
        Assert.Equal(0, workerResult.ExitCode);

        using var dbContext = CreateContext();
        var sourceDocument = new SourceDocument { Id = Guid.NewGuid(), FileAssetId = Guid.NewGuid() };

        var summary = await ImportWorkerCandidateSeeder.SeedAsync(
            dbContext,
            sourceDocument,
            workerResult.StandardOutput,
            "test-generation",
            CancellationToken.None);
        await dbContext.SaveChangesAsync();

        // docx 段落分类:题干(question_stem)、选项(option)、答案(answer)各一块。
        Assert.Equal("openxml_docx_adapter", summary.AdapterName);
        Assert.Equal(3, summary.SourceRegionCount);
        Assert.Equal(3, summary.CutCandidateCount);
        // 题干回退置信度 0.88 不触发接管;选项/答案 0.78 低于 0.85 触发人工接管队列。
        Assert.Equal(2, summary.LowConfidenceReviewQueueCount);

        var candidates = await dbContext.CutCandidates
            .Where(candidate => candidate.SourceDocumentId == sourceDocument.Id)
            .OrderBy(candidate => candidate.SequenceNo)
            .ToListAsync();
        Assert.Equal(3, candidates.Count);
        Assert.All(candidates, candidate => Assert.Equal(CutCandidateStatuses.PendingReview, candidate.Status));
        Assert.Equal("question_stem", candidates[0].SegmentType);
        Assert.Equal("option", candidates[1].SegmentType);
        Assert.Equal("answer", candidates[2].SegmentType);
        Assert.All(candidates, candidate => Assert.Contains("document_worker_local", candidate.Metadata));
        Assert.All(candidates, candidate => Assert.Contains("test-generation", candidate.Metadata));

        var queueItems = await dbContext.ReviewQueueItems.ToListAsync();
        Assert.Equal(2, queueItems.Count);
        Assert.All(queueItems, item => Assert.Equal(ReviewStatuses.Open, item.Status));
    }

    [Fact]
    public async Task SeedAsync_CapsMaterializedCandidatesAtBoundary()
    {
        var blocks = new List<string>();
        for (var index = 1; index <= 200; index++)
        {
            blocks.Add($"{{\"blockType\":\"question_stem\",\"textPreview\":\"合成题干 {index}\"}}");
        }

        var workerOutput = JsonSerializer.Serialize(new
        {
            status = "ok",
            documentModel = new
            {
                schemaVersion = "document-model.v0.1",
                pages = new[]
                {
                    new { pageNumber = 1, layoutBlocks = JsonSerializer.Deserialize<JsonElement>($"[{string.Join(",", blocks)}]") },
                },
            },
            adapterDiagnostics = new[] { new { adapterName = "synthetic_adapter" } },
        });

        using var dbContext = CreateContext();
        var sourceDocument = new SourceDocument { Id = Guid.NewGuid(), FileAssetId = Guid.NewGuid() };

        var summary = await ImportWorkerCandidateSeeder.SeedAsync(
            dbContext,
            sourceDocument,
            workerOutput,
            "cap-generation",
            CancellationToken.None);
        await dbContext.SaveChangesAsync();

        Assert.Equal(120, summary.CutCandidateCount);
        Assert.Equal(120, await dbContext.CutCandidates.CountAsync());
    }

    [Fact]
    public async Task SeedAsync_ReturnsEmptySummaryWhenDocumentModelMissing()
    {
        using var dbContext = CreateContext();
        var sourceDocument = new SourceDocument { Id = Guid.NewGuid(), FileAssetId = Guid.NewGuid() };

        var summary = await ImportWorkerCandidateSeeder.SeedAsync(
            dbContext,
            sourceDocument,
            JsonSerializer.Serialize(new { status = "ok", jobId = "abc" }),
            "empty-generation",
            CancellationToken.None);

        Assert.Equal(string.Empty, summary.AdapterName);
        Assert.Equal(0, summary.SourceRegionCount);
        Assert.Equal(0, summary.CutCandidateCount);
        Assert.Equal(0, summary.LowConfidenceReviewQueueCount);
    }
}
