using K12QuestionGraph.Api.Scores;

namespace K12QuestionGraph.Api.Tests;

public sealed class ScoreSpreadsheetImportAdapterTests
{
    [Fact]
    public async Task ParsesRealXlsxIntoDraftImportContract()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Fixtures", "sample-synthetic-score-import.xlsx");
        await using var stream = File.OpenRead(path);

        var request = await new ScoreSpreadsheetImportAdapter().ParseAsync(
            stream,
            Path.GetFileName(path),
            containsStudentPii: false,
            CancellationToken.None);

        Assert.False(request.ContainsStudentPii);
        Assert.False(request.ProductionEligible);
        Assert.Equal("student_code", request.FieldMapping.StudentKey);
        Assert.Equal("total_score", request.FieldMapping.TotalScore);
        Assert.Equal("Q1(5分)", request.FieldMapping.ItemScores["Q1"]);
        Assert.Equal(5m, request.ItemMaxScores["Q2"]);
        Assert.Equal(3, request.Rows.Count);
        Assert.Equal("7", request.Rows[1].Values["total_score"]);
    }

    [Fact]
    public async Task RejectsNonXlsxPayloadWithoutProducingRows()
    {
        await using var stream = new MemoryStream("not an xlsx"u8.ToArray());

        var error = await Assert.ThrowsAsync<ScoreSpreadsheetImportException>(() =>
            new ScoreSpreadsheetImportAdapter().ParseAsync(stream, "scores.xlsx", false, CancellationToken.None));

        Assert.Equal("xlsx_invalid", error.Code);
        Assert.Equal(400, error.StatusCode);
    }
}
