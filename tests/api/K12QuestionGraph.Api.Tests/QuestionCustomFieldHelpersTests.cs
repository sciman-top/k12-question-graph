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
    public void TryGetStringAndArrayFields_ReadCandidateMetadataWithoutPromotingIt()
    {
        const string json = """{"primaryKnowledgeCandidateId":"KPHY-C003-025","abilityDimensions":["信息提取","科学推理"]}""";

        Assert.Equal(
            "KPHY-C003-025",
            QuestionCustomFieldHelpers.TryGetStringField(json, "primaryKnowledgeCandidateId"));
        Assert.Equal(
            ["信息提取", "科学推理"],
            QuestionCustomFieldHelpers.TryGetStringArrayField(json, "abilityDimensions"));
        Assert.Null(QuestionCustomFieldHelpers.TryGetStringField("not-json", "primaryKnowledgeCandidateId"));
        Assert.Empty(QuestionCustomFieldHelpers.TryGetStringArrayField("not-json", "abilityDimensions"));
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
    public void Merge_UpdatesReviewLabelsWithoutChangingOtherCandidateFields()
    {
        var merged = QuestionCustomFieldHelpers.Merge(
            """{"questionNo":5,"productionEligible":false,"primaryKnowledgeCandidateId":"K-1"}""",
            answer: null,
            solution: null,
            primaryKnowledgeLabel: "光的反射",
            knowledgeTags: ["光学", "光学", " 反射 "]);

        using var mergedDoc = JsonDocument.Parse(merged);
        Assert.Equal("K-1", mergedDoc.RootElement.GetProperty("primaryKnowledgeCandidateId").GetString());
        Assert.False(mergedDoc.RootElement.GetProperty("productionEligible").GetBoolean());
        Assert.Equal("光的反射", mergedDoc.RootElement.GetProperty("primaryKnowledgeLabel").GetString());
        Assert.Equal(["光学", "反射"], mergedDoc.RootElement.GetProperty("knowledgeTags").EnumerateArray().Select(x => x.GetString()));
    }

    [Fact]
    public void HasMeaningfulValue_Rejects_Null_And_EmptyObjects()
    {
        Assert.False(QuestionCustomFieldHelpers.HasMeaningfulValue("""{"answer":null}""", "answer"));
        Assert.False(QuestionCustomFieldHelpers.HasMeaningfulValue("""{"answer":{"text":""}}""", "answer"));
        Assert.False(QuestionCustomFieldHelpers.HasMeaningfulValue("""{"answer":{"value":"","reviewStatus":"pending_review"}}""", "answer"));
        Assert.False(QuestionCustomFieldHelpers.HasMeaningfulValue("""{"solution":{"text":"","source":"answer_pdf","reviewStatus":"pending_review"}}""", "solution"));
        Assert.True(QuestionCustomFieldHelpers.HasMeaningfulValue("""{"answer":{"text":"有效"}}""", "answer"));
        Assert.True(QuestionCustomFieldHelpers.HasMeaningfulValue("""{"solution":{"text":"有效解析","reviewStatus":"pending_review"}}""", "solution"));
    }

    [Fact]
    public void BuildContainmentFilter_UsesNumberForYearAndArrayForCandidateIds()
    {
        Assert.Equal("""{"year":2025}""", QuestionCustomFieldHelpers.BuildContainmentFilter("year", 2025));
        Assert.Equal(
            """{"knowledgeCandidateIds":["KPHY-C003-059"]}""",
            QuestionCustomFieldHelpers.BuildArrayContainmentFilter("knowledgeCandidateIds", "KPHY-C003-059"));
        Assert.Equal(
            """{"examPointCandidateIds":["EPHY-C003-032"]}""",
            QuestionCustomFieldHelpers.BuildArrayContainmentFilter("examPointCandidateIds", "EPHY-C003-032"));
    }
}
