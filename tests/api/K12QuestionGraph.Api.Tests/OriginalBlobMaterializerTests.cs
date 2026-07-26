using System.Security.Cryptography;
using K12QuestionGraph.Api.FileStore;

namespace K12QuestionGraph.Api.Tests;

public class OriginalBlobMaterializerTests
{
    [Fact]
    public void Reconcile_MaterializesMissingBlobFromVerifiedUpload()
    {
        using var fixture = new BlobFixture("physics-source");

        OriginalBlobMaterializer.Reconcile(
            fixture.Root,
            fixture.RelativePath,
            fixture.Upload,
            fixture.Sha256,
            fixture.SizeBytes);

        Assert.False(File.Exists(fixture.Upload));
        Assert.Equal("physics-source", File.ReadAllText(fixture.Target));
    }

    [Fact]
    public void Reconcile_DeletesUploadWhenExistingBlobIsValid()
    {
        using var fixture = new BlobFixture("same-content");
        Directory.CreateDirectory(Path.GetDirectoryName(fixture.Target)!);
        File.Copy(fixture.Upload, fixture.Target);

        OriginalBlobMaterializer.Reconcile(
            fixture.Root,
            fixture.RelativePath,
            fixture.Upload,
            fixture.Sha256,
            fixture.SizeBytes);

        Assert.False(File.Exists(fixture.Upload));
        Assert.Equal("same-content", File.ReadAllText(fixture.Target));
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
