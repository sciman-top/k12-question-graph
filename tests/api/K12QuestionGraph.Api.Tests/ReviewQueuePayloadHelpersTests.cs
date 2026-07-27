using K12QuestionGraph.Api.Infrastructure.Json;

namespace K12QuestionGraph.Api.Tests;

public class ReviewQueuePayloadHelpersTests
{
    [Fact]
    public void ResolveRequiredActions_SupportsV2ArrayAndLegacyScalar()
    {
        var v2 = ReviewQueuePayloadHelpers.ResolveRequiredActions(
            JsonHelpers.ParseJsonElement("""{"requiredActions":["review_question_crop","review_tags"]}"""));
        var legacy = ReviewQueuePayloadHelpers.ResolveRequiredActions(
            JsonHelpers.ParseJsonElement("""{"requiredAction":"manual_review"}"""));

        Assert.Equal(["review_question_crop", "review_tags"], v2);
        Assert.Equal(["manual_review"], legacy);
    }

    [Fact]
    public void ResolveYear_ReadsNumberAndStringValues()
    {
        Assert.Equal(2020, ReviewQueuePayloadHelpers.ResolveYear(JsonHelpers.ParseJsonElement("""{"year":2020}""")));
        Assert.Equal(2021, ReviewQueuePayloadHelpers.ResolveYear(JsonHelpers.ParseJsonElement("""{"year":"2021"}""")));
        Assert.Null(ReviewQueuePayloadHelpers.ResolveYear(JsonHelpers.ParseJsonElement("{}")));
        Assert.Equal(12, ReviewQueuePayloadHelpers.ResolveQuestionNo(JsonHelpers.ParseJsonElement("""{"questionNo":"12"}""")));
    }

    [Fact]
    public void WithReviewAudit_AppendsHistoryInsteadOfOverwritingIt()
    {
        var first = ReviewQueuePayloadHelpers.WithReviewAudit(
            "{}",
            "reviewer-a",
            "resolved",
            "first",
            DateTimeOffset.Parse("2026-07-27T10:00:00Z"));
        var second = ReviewQueuePayloadHelpers.WithReviewAudit(
            first,
            "reviewer-b",
            "reopened",
            "undo",
            DateTimeOffset.Parse("2026-07-27T10:01:00Z"));

        var payload = JsonHelpers.ParseJsonElement(second);
        var history = payload.GetProperty("reviewAuditHistory");
        Assert.Equal(2, history.GetArrayLength());
        Assert.Equal("resolved", history[0].GetProperty("decision").GetString());
        Assert.Equal("reopened", history[1].GetProperty("decision").GetString());
        Assert.Equal("reopened", payload.GetProperty("reviewAudit").GetProperty("decision").GetString());
    }
}
