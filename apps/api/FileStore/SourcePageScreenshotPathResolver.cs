using K12QuestionGraph.Api.Domain;

namespace K12QuestionGraph.Api.FileStore;

public static class SourcePageScreenshotPathResolver
{
    public static IReadOnlyList<string> GetCandidateRelativePaths(SourceDocument document, int pageNumber)
    {
        ArgumentNullException.ThrowIfNull(document);
        ArgumentOutOfRangeException.ThrowIfLessThan(pageNumber, 1);

        var candidates = new List<string>();
        if (document.Year.HasValue && IsSafeMaterialBatchKey(document.MaterialBatchKey))
        {
            var normalizedBatchKey = document.MaterialBatchKey.Replace('_', '-');
            candidates.Add(
                $"generated/{normalizedBatchKey}/source-pages/{document.Year.Value}/{document.Id}/page-{pageNumber:000}.png");
        }

        candidates.Add($"generated/guangzhou-2015/pages/{document.Id}-page-{pageNumber:000}.png");
        return candidates;
    }

    public static string? ResolveExistingRelativePath(
        string fileStoreRoot,
        SourceDocument document,
        int pageNumber)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(fileStoreRoot);
        var root = Path.GetFullPath(fileStoreRoot);
        foreach (var relativePath in GetCandidateRelativePaths(document, pageNumber))
        {
            var fullPath = Path.GetFullPath(Path.Combine(root, relativePath.Replace('/', Path.DirectorySeparatorChar)));
            if (fullPath.StartsWith(root, StringComparison.OrdinalIgnoreCase) && File.Exists(fullPath))
            {
                return relativePath;
            }
        }

        return null;
    }

    private static bool IsSafeMaterialBatchKey(string value) =>
        !string.IsNullOrWhiteSpace(value)
        && value.All(character => char.IsAsciiLetterOrDigit(character) || character is '_' or '-');
}
