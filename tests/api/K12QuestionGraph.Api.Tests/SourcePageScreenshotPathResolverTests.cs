using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.FileStore;

namespace K12QuestionGraph.Api.Tests;

public sealed class SourcePageScreenshotPathResolverTests : IDisposable
{
    private readonly string root = Path.Combine(Path.GetTempPath(), $"kqg-source-pages-{Guid.NewGuid():N}");

    [Fact]
    public void PrefersMaterialBatchSourcePageAndFallsBackToLegacyPath()
    {
        var document = new SourceDocument
        {
            Id = Guid.Parse("7b567ac3-1a37-42aa-a8de-b49fbdf564a8"),
            Year = 2018,
            MaterialBatchKey = "guangzhou_physics_2015_2025_20260726_v2",
        };
        var modern = "generated/guangzhou-physics-2015-2025-20260726-v2/source-pages/2018/7b567ac3-1a37-42aa-a8de-b49fbdf564a8/page-001.png";
        var legacy = "generated/guangzhou-2015/pages/7b567ac3-1a37-42aa-a8de-b49fbdf564a8-page-001.png";

        WriteFixture(legacy);
        Assert.Equal(legacy, SourcePageScreenshotPathResolver.ResolveExistingRelativePath(root, document, 1));

        WriteFixture(modern);
        Assert.Equal(modern, SourcePageScreenshotPathResolver.ResolveExistingRelativePath(root, document, 1));
        Assert.Equal(new[] { modern, legacy }, SourcePageScreenshotPathResolver.GetCandidateRelativePaths(document, 1));
    }

    [Fact]
    public void RejectsInvalidPageAndUnsafeMaterialBatchKey()
    {
        var document = new SourceDocument
        {
            Id = Guid.NewGuid(),
            Year = 2025,
            MaterialBatchKey = "../outside",
        };

        Assert.Throws<ArgumentOutOfRangeException>(() =>
            SourcePageScreenshotPathResolver.GetCandidateRelativePaths(document, 0));
        Assert.Single(SourcePageScreenshotPathResolver.GetCandidateRelativePaths(document, 1));
    }

    public void Dispose()
    {
        if (Directory.Exists(root))
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private void WriteFixture(string relativePath)
    {
        var path = Path.Combine(root, relativePath.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "fixture");
    }
}
