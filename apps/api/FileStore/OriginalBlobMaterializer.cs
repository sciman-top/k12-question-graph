using System.Security.Cryptography;

namespace K12QuestionGraph.Api.FileStore;

internal static class OriginalBlobMaterializer
{
    // 仅为测试注入"目标在 Exists 检查与 Move 之间被并发者创建"的竞态窗口;
    // 生产路径恒为 File.Move。
    internal static Action<string, string> MoveFiles { get; set; } = static (source, destination) => File.Move(source, destination);

    public static bool Reconcile(
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
            VerifyExistingBlob(target, relativePath, expectedSha256, expectedSizeBytes);
            File.Delete(uploadPath);
            return false;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        try
        {
            MoveFiles(uploadPath, target);
        }
        catch (IOException) when (File.Exists(target))
        {
            // 跨进程竞态:同 hash 并发上传者在 Exists 检查后先落了同名 blob。
            // 失败方按重复处理:校验赢家 blob 与本方 hash 一致后丢弃本方上传,
            // 而不是让 IOException 冒泡成 500。
            VerifyExistingBlob(target, relativePath, expectedSha256, expectedSizeBytes);
            TryDeleteBestEffort(uploadPath);
            return false;
        }
        return true;
    }

    private static void VerifyExistingBlob(string target, string relativePath, string expectedSha256, long expectedSizeBytes)
    {
        var targetInfo = new FileInfo(target);
        if (targetInfo.Length != expectedSizeBytes || !string.Equals(Sha256File(target), expectedSha256, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException($"Existing FileStore blob does not match its database hash: {relativePath}");
        }
    }

    private static void TryDeleteBestEffort(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (IOException)
        {
            // 上传临时文件的清理失败不影响重复判定;调用方 finally 也会再尝试。
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    public static void DeleteIfMatches(
        string fileStoreRoot,
        string relativePath,
        string expectedSha256,
        long expectedSizeBytes)
    {
        var root = Path.GetFullPath(fileStoreRoot);
        var target = Path.GetFullPath(Path.Combine(root, relativePath.Replace('/', Path.DirectorySeparatorChar)));
        var rootPrefix = root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        if (!target.StartsWith(rootPrefix, comparison) || !File.Exists(target))
        {
            return;
        }

        var targetInfo = new FileInfo(target);
        if (targetInfo.Length == expectedSizeBytes &&
            string.Equals(Sha256File(target), expectedSha256, StringComparison.OrdinalIgnoreCase))
        {
            File.Delete(target);
        }
    }

    private static string Sha256File(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }
}
