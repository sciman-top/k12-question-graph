using System.Security.Cryptography;
using K12QuestionGraph.Api.FileStore;

namespace K12QuestionGraph.Api.Tests;

public class OriginalBlobMaterializerTests
{
    [Fact]
    public void Reconcile_MaterializesMissingBlobFromVerifiedUpload()
    {
        using var fixture = new BlobFixture("physics-source");

        var created = OriginalBlobMaterializer.Reconcile(
            fixture.Root,
            fixture.RelativePath,
            fixture.Upload,
            fixture.Sha256,
            fixture.SizeBytes);

        Assert.True(created);
        Assert.False(File.Exists(fixture.Upload));
        Assert.Equal("physics-source", File.ReadAllText(fixture.Target));
    }

    [Fact]
    public void Reconcile_DeletesUploadWhenExistingBlobIsValid()
    {
        using var fixture = new BlobFixture("same-content");
        Directory.CreateDirectory(Path.GetDirectoryName(fixture.Target)!);
        File.Copy(fixture.Upload, fixture.Target);

        var created = OriginalBlobMaterializer.Reconcile(
            fixture.Root,
            fixture.RelativePath,
            fixture.Upload,
            fixture.Sha256,
            fixture.SizeBytes);

        Assert.False(created);
        Assert.False(File.Exists(fixture.Upload));
        Assert.Equal("same-content", File.ReadAllText(fixture.Target));
    }

    [Fact]
    public void DeleteIfMatches_RemovesOnlyTheExpectedCompensationBlob()
    {
        using var fixture = new BlobFixture("transaction-failed");
        Directory.CreateDirectory(Path.GetDirectoryName(fixture.Target)!);
        File.Copy(fixture.Upload, fixture.Target);

        OriginalBlobMaterializer.DeleteIfMatches(
            fixture.Root,
            fixture.RelativePath,
            fixture.Sha256,
            fixture.SizeBytes);

        Assert.False(File.Exists(fixture.Target));
    }

    [Fact]
    public void Reconcile_FailsClosedWhenExistingBlobDoesNotMatch()
    {
        using var fixture = new BlobFixture("expected-content");
        Directory.CreateDirectory(Path.GetDirectoryName(fixture.Target)!);
        File.WriteAllText(fixture.Target, "different-content");

        var error = Assert.Throws<InvalidDataException>(() => OriginalBlobMaterializer.Reconcile(
            fixture.Root,
            fixture.RelativePath,
            fixture.Upload,
            fixture.Sha256,
            fixture.SizeBytes));

        Assert.Contains("does not match", error.Message);
        Assert.True(File.Exists(fixture.Upload));
        Assert.Equal("different-content", File.ReadAllText(fixture.Target));
    }

    [Fact]
    public void Reconcile_TreatsMoveRaceAsDuplicateWhenWinnerBlobMatches()
    {
        // 竞态窗口:Exists 检查后、Move 前,同 hash 并发上传者先落了同名 blob。
        // 用 MoveFiles 接缝确定性地模拟:Move 抛 IOException 且赢家 blob 已就位。
        using var fixture = new BlobFixture("race-winner-content");
        Directory.CreateDirectory(Path.GetDirectoryName(fixture.Target)!);
        var originalMove = OriginalBlobMaterializer.MoveFiles;
        OriginalBlobMaterializer.MoveFiles = (source, destination) =>
        {
            File.Copy(fixture.Upload, fixture.Target);
            throw new IOException("simulated concurrent target creation");
        };
        try
        {
            var created = OriginalBlobMaterializer.Reconcile(
                fixture.Root,
                fixture.RelativePath,
                fixture.Upload,
                fixture.Sha256,
                fixture.SizeBytes);

            Assert.False(created);
            Assert.False(File.Exists(fixture.Upload));
            Assert.Equal("race-winner-content", File.ReadAllText(fixture.Target));
        }
        finally
        {
            OriginalBlobMaterializer.MoveFiles = originalMove;
        }
    }

    [Fact]
    public void Reconcile_FailsClosedWhenMoveRaceWinnerBlobDoesNotMatch()
    {
        using var fixture = new BlobFixture("expected-content");
        Directory.CreateDirectory(Path.GetDirectoryName(fixture.Target)!);
        var originalMove = OriginalBlobMaterializer.MoveFiles;
        OriginalBlobMaterializer.MoveFiles = (_, _) => throw new IOException("simulated concurrent target creation");
        try
        {
            // 竞态赢家 blob 缺失:IOException 的 when 过滤不命中,原样冒泡。
            Assert.Throws<IOException>(() => OriginalBlobMaterializer.Reconcile(
                fixture.Root,
                fixture.RelativePath,
                fixture.Upload,
                fixture.Sha256,
                fixture.SizeBytes));
        }
        finally
        {
            OriginalBlobMaterializer.MoveFiles = originalMove;
        }
    }

    private sealed class BlobFixture : IDisposable
    {
        public BlobFixture(string content)
        {
            Root = Path.Combine(Path.GetTempPath(), $"kqg-blob-test-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Root);
            Upload = Path.Combine(Root, "upload.tmp");
            File.WriteAllText(Upload, content);
            SizeBytes = new FileInfo(Upload).Length;
            Sha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Upload))).ToLowerInvariant();
            RelativePath = $"original/{Sha256[..2]}/{Sha256[2..4]}/{Sha256}.pdf";
            Target = Path.Combine(Root, RelativePath);
        }

        public string Root { get; }
        public string Upload { get; }
        public string RelativePath { get; }
        public string Target { get; }
        public string Sha256 { get; }
        public long SizeBytes { get; }

        public void Dispose()
        {
            Directory.Delete(Root, recursive: true);
        }
    }
}
