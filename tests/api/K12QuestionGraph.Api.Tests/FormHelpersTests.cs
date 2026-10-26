using K12QuestionGraph.Api.FileStore;

namespace K12QuestionGraph.Api.Tests;

public sealed class FormHelpersTests
{
    [Fact]
    public void TryResolveFileStorePathAcceptsOnlyPathsInsideConfiguredRoot()
    {
        var root = Path.GetFullPath(Path.Combine(Path.GetTempPath(), $"kqg-file-store-{Guid.NewGuid():N}"));

        Assert.True(FormHelpers.TryResolveFileStorePath(root, "generated/page-001.png", out var resolved));
        Assert.StartsWith(
            root.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar,
            resolved,
            OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);

        Assert.False(FormHelpers.TryResolveFileStorePath(root, "", out _));
        Assert.False(FormHelpers.TryResolveFileStorePath(root, "/outside/page.png", out _));
        Assert.False(FormHelpers.TryResolveFileStorePath(root, "../outside/page.png", out _));
        Assert.False(FormHelpers.TryResolveFileStorePath(root, "generated/../../outside/page.png", out _));
    }
}
