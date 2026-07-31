using K12QuestionGraph.Api.Application.Workflows;

namespace K12QuestionGraph.Api.Tests;

public sealed class KnowledgeEvidenceWorkflowServiceTests
{
    [Theory]
    [InlineData(0, 1)]
    [InlineData(100, 100)]
    [InlineData(1000, 500)]
    public void NormalizeTake_ClampsToSafeReadWindow(int requested, int expected)
    {
        Assert.Equal(expected, KnowledgeEvidenceWorkflowService.NormalizeTake(requested));
    }

    [Theory]
    [InlineData(null, "pending_review")]
    [InlineData(" PENDING_REVIEW ", "pending_review")]
    [InlineData("approved", "approved")]
    public void NormalizeReviewStatus_AcceptsClosedContract(string? requested, string expected)
    {
        Assert.Equal(expected, KnowledgeEvidenceWorkflowService.NormalizeReviewStatus(requested));
    }

    [Fact]
    public void NormalizeReviewStatus_RejectsUnknownValues()
    {
        var error = Assert.Throws<ArgumentException>(() => KnowledgeEvidenceWorkflowService.NormalizeReviewStatus("active"));
        Assert.Contains("invalid_review_status", error.Message, StringComparison.Ordinal);
    }
}
