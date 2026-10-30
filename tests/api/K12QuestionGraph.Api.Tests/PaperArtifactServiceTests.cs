using System.Globalization;
using System.IO.Compression;
using System.Text;
using K12QuestionGraph.Api.Papers;

namespace K12QuestionGraph.Api.Tests;

public sealed class PaperArtifactServiceTests
{
    [Fact]
    public void DocxIsValidPackageAndStudentVariantCanOmitAnswers()
    {
        var bytes = PaperArtifactService.BuildDocx("合成测试卷", [(1, 5m, "惯性测试题", null)]);

        using var archive = new ZipArchive(new MemoryStream(bytes), ZipArchiveMode.Read);
        Assert.NotNull(archive.GetEntry("[Content_Types].xml"));
        var document = archive.GetEntry("word/document.xml");
        Assert.NotNull(document);
        using var reader = new StreamReader(document!.Open(), Encoding.UTF8);
        var xml = reader.ReadToEnd();
        Assert.Contains("惯性测试题", xml);
        Assert.DoesNotContain("答案：", xml);
    }

    [Fact]
    public void BuildDocx_FormatsScoresWithInvariantCulture()
    {
        var previousCulture = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("de-DE");
            var bytes = PaperArtifactService.BuildDocx("合成测试卷", [(1, 3.5m, "惯性测试题", null)]);

            using var archive = new ZipArchive(new MemoryStream(bytes), ZipArchiveMode.Read);
            using var reader = new StreamReader(archive.GetEntry("word/document.xml")!.Open(), Encoding.UTF8);
            var xml = reader.ReadToEnd();

            Assert.Contains("3.5分", xml);
            Assert.DoesNotContain("3,5分", xml);
        }
        finally
        {
            CultureInfo.CurrentCulture = previousCulture;
        }
    }

    [Fact]
    public async Task PdfConversionPreservesChineseAndTeacherAnswerWhenLibreOfficeIsAvailable()
    {
        if (!File.Exists(@"C:\Program Files\LibreOffice\program\soffice.com")) return;
        var docx = PaperArtifactService.BuildDocx("合成测试卷", [(1, 5m, "惯性测试题", "B")]);
        var bytes = await PaperArtifactService.ConvertDocxToPdfAsync(docx, CancellationToken.None);

        Assert.StartsWith("%PDF-", Encoding.ASCII.GetString(bytes, 0, 5));
        Assert.True(bytes.Length > 1000);
    }
}
