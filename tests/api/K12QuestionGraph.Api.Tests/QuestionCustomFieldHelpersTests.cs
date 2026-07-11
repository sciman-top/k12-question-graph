using System.Text.Json;
using K12QuestionGraph.Api.Infrastructure.Json;

namespace K12QuestionGraph.Api.Tests;

public class QuestionCustomFieldHelpersTests
{
    [Fact]
    public void TryGetIntField_Reads_Number_And_String_Values()
    {
        Assert.Equal(12, QuestionCustomFieldHelpers.TryGetIntField("""{"questionNo":12}""", "questionNo"));
        Assert.Equal(34, QuestionCustomFieldHelpers.TryGetIntField("""{"questionNo":"34"}""", "questionNo"));
        Assert.Null(QuestionCustomFieldHelpers.TryGetIntField("""{"questionNo":"abc"}""", "questionNo"));
    }

    [Fact]
    public void Merge_PreservesExistingFields_AndOverwritesAnswerSolution()
    {
        using var answerDoc = JsonDocument.Parse("""{"value":"B"}""");
        using var solutionDoc = JsonDocument.Parse("""{"text":"解析"}""");

        var merged = QuestionCustomFieldHelpers.Merge(
            """{"questionNo":5,"answer":{"value":"A"}}""",
            answerDoc.RootElement,
            solutionDoc.RootElement);

        using var mergedDoc = JsonDocument.Parse(merged);
        Assert.Equal(5, mergedDoc.RootElement.GetProperty("questionNo").GetInt32());
        Assert.Equal("B", mergedDoc.RootElement.GetProperty("answer").GetProperty("value").GetString());
        Assert.Equal("解析", mergedDoc.RootElement.GetProperty("solution").GetProperty("text").GetString());
    }

    [Fact]
    public void HasMeaningfulValue_Rejects_Null_And_EmptyObjects()
    {
        Assert.False(QuestionCustomFieldHelpers.HasMeaningfulValue("""{"answer":null}""", "answer"));
        Assert.False(QuestionCustomFieldHelpers.HasMeaningfulValue("""{"answer":{"text":""}}""", "answer"));
        Assert.True(QuestionCustomFieldHelpers.HasMeaningfulValue("""{"answer":{"text":"有效"}}""", "answer"));
    }
}
