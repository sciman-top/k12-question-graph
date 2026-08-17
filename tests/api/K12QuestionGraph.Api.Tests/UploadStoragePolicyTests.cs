using System.IO.Compression;
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
    [InlineData("paper.DOCX", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", ".docx")]
    [InlineData("paper.pdf", "application/pdf; charset=binary", ".pdf")]
    [InlineData("scan.JPG", "image/jpeg", ".jpg")]
    [InlineData("scan.tiff", "image/tiff", ".tiff")]
    public void Normalize_AcceptsOnlySupportedExtensionAndMimePairs(
        string fileName,
        string contentType,
        string expectedExtension)
    {
        var result = UploadStoragePolicy.Normalize(fileName, contentType);

        Assert.Equal(fileName, result.OriginalFileName);
        Assert.Equal(expectedExtension, result.StorageExtension);
        Assert.False(string.IsNullOrWhiteSpace(result.ContentType));
    }

    [Theory]
    [InlineData("payload.exe", "application/octet-stream", "unsupported_upload_extension")]
    [InlineData("paper.pdf.exe", "application/pdf", "unsupported_upload_extension")]
    [InlineData("paper.pdf", "text/plain", "upload_content_type_mismatch")]
    [InlineData("paper.docx", "application/zip", "upload_content_type_mismatch")]
    [InlineData("", "application/pdf", "upload_file_name_required")]
    public void Normalize_RejectsUnsupportedOrMismatchedDeclarations(
        string fileName,
        string contentType,
        string expectedCode)
    {
        var exception = Assert.Throws<UnsupportedUploadTypeException>(
            () => UploadStoragePolicy.Normalize(fileName, contentType));

        Assert.Equal(expectedCode, exception.Code);
    }

    [Fact]
    public void Normalize_BoundsDatabaseFieldsWithoutSplittingSurrogatePairs()
    {
        var longName = new string('a', 259) + "😀.pdf";
        var result = UploadStoragePolicy.Normalize(longName, "application/pdf");

        Assert.True(result.OriginalFileName.Length <= 260);
        Assert.False(char.IsHighSurrogate(result.OriginalFileName[^1]));
        Assert.Equal(".pdf", result.StorageExtension);
    }

    [Fact]
    public void ValidateContent_AcceptsMatchingPdfSignature()
    {
        WithTemporaryFile("%PDF-1.7\n%%EOF"u8.ToArray(), path =>
            UploadStoragePolicy.ValidateContent(
                path,
                UploadStoragePolicy.Normalize("paper.pdf", "application/pdf")));
    }

    [Fact]
    public void ValidateContent_RejectsPdfWithExecutablePayloadSignature()
    {
        WithTemporaryFile("MZ-not-a-pdf"u8.ToArray(), path =>
        {
            var exception = Assert.Throws<UnsupportedUploadTypeException>(() =>
                UploadStoragePolicy.ValidateContent(
                    path,
                    UploadStoragePolicy.Normalize("paper.pdf", "application/pdf")));
            Assert.Equal("upload_signature_mismatch", exception.Code);
        });
    }

    [Fact]
    public void ValidateContent_AcceptsDocxWithRequiredOpenXmlParts()
    {
        var path = Path.Combine(Path.GetTempPath(), $"kqg-upload-{Guid.NewGuid():N}.docx");
        try
        {
            using (var archive = ZipFile.Open(path, ZipArchiveMode.Create))
            {
                archive.CreateEntry("[Content_Types].xml");
                archive.CreateEntry("_rels/.rels");
                archive.CreateEntry("word/document.xml");
            }

            UploadStoragePolicy.ValidateContent(
                path,
                UploadStoragePolicy.Normalize(
                    "paper.docx",
                    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ValidateContent_RejectsGenericZipDisguisedAsDocx()
    {
        var path = Path.Combine(Path.GetTempPath(), $"kqg-upload-{Guid.NewGuid():N}.docx");
        try
        {
            using (var archive = ZipFile.Open(path, ZipArchiveMode.Create))
            {
                archive.CreateEntry("payload.txt");
            }

            var exception = Assert.Throws<UnsupportedUploadTypeException>(() =>
                UploadStoragePolicy.ValidateContent(
                    path,
                    UploadStoragePolicy.Normalize(
                        "paper.docx",
                        "application/vnd.openxmlformats-officedocument.wordprocessingml.document")));
            Assert.Equal("docx_structure_invalid", exception.Code);
        }
        finally
        {
            File.Delete(path);
        }
    }

    private static void WithTemporaryFile(byte[] content, Action<string> assertion)
    {
        var path = Path.Combine(Path.GetTempPath(), $"kqg-upload-{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllBytes(path, content);
            assertion(path);
        }
        finally
        {
            File.Delete(path);
        }
    }
}
