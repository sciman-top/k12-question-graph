using K12QuestionGraph.Api.FileStore;

namespace K12QuestionGraph.Api.Tests;

public class UploadStoragePolicyTests
{
    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(UploadStoragePolicy.MaxUploadBytes + 1)]
    public void ValidateDeclaredLength_RejectsEmptyInvalidOrOversizedUploads(long sizeBytes)
    {
        Assert.Throws<InvalidDataException>(() => UploadStoragePolicy.ValidateDeclaredLength(sizeBytes));
    }

    [Fact]
    public void ValidateDeclaredLength_AcceptsTheConfiguredLimit()
    {
        UploadStoragePolicy.ValidateDeclaredLength(UploadStoragePolicy.MaxUploadBytes);
    }

    [Theory]
    [InlineData("paper.DOCX", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "paper.DOCX", ".docx")]
    [InlineData("paper.bad:stream", "text/plain", "paper.bad:stream", ".bin")]
    [InlineData("paper." + "x", "text/plain", "paper.x", ".x")]
    [InlineData("", "", "upload.bin", ".bin")]
    public void Normalize_ProducesSafeStorageIdentity(
        string fileName,
        string contentType,
        string expectedDisplayName,
        string expectedExtension)
    {
        var result = UploadStoragePolicy.Normalize(fileName, contentType);

        Assert.Equal(expectedDisplayName, result.OriginalFileName);
        Assert.Equal(expectedExtension, result.StorageExtension);
        Assert.False(string.IsNullOrWhiteSpace(result.ContentType));
    }

    [Fact]
    public void Normalize_BoundsDatabaseFieldsWithoutSplittingSurrogatePairs()
    {
        var longName = new string('a', 259) + "😀.pdf";
        var result = UploadStoragePolicy.Normalize(longName, new string('x', 129));

        Assert.True(result.OriginalFileName.Length <= 260);
        Assert.False(char.IsHighSurrogate(result.OriginalFileName[^1]));
        Assert.Equal("application/octet-stream", result.ContentType);
        Assert.Equal(".pdf", result.StorageExtension);
    }
}
