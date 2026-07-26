using System.Security.Cryptography;

namespace K12QuestionGraph.Api.FileStore;

internal static class OriginalBlobMaterializer
{
    public static void Reconcile(
        string fileStoreRoot,
        string relativePath,
        string uploadPath,
        string expectedSha256,
        long expectedSizeBytes)
    {
        var root = Path.GetFullPath(fileStoreRoot);
        var target = Path.GetFullPath(Path.Combine(root, relativePath.Replace('/', Path.DirectorySeparatorChar)));
        var rootPrefix = root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        if (!target.StartsWith(rootPrefix, comparison))
        {
            throw new InvalidDataException($"FileStore relative path escapes the configured root: {relativePath}");
        }

        if (File.Exists(target))
        {
            var targetInfo = new FileInfo(target);
            if (targetInfo.Length != expectedSizeBytes || !string.Equals(Sha256File(target), expectedSha256, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException($"Existing FileStore blob does not match its database hash: {relativePath}");
            }

            File.Delete(uploadPath);
            return;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        File.Move(uploadPath, target);
    }

    private static string Sha256File(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }
}
