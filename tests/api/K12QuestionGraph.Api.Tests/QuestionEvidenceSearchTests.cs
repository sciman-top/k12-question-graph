using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Application.Workflows.Contracts;

namespace K12QuestionGraph.Api.Tests;

public sealed class QuestionEvidenceSearchTests
{
    [Theory]
    [InlineData(null, "active")]
    [InlineData("", "active")]
    [InlineData(" ACTIVE ", "active")]
    [InlineData("reviewed", "reviewed")]
    [InlineData("candidate", "candidate")]
    public void NormalizesClosedEvidenceModes(string? value, string expected)
    {
        Assert.Equal(expected, KnowledgeEvidenceWorkflowService.NormalizeEvidenceMode(value));
    }

    [Fact]
    public void RejectsUnknownEvidenceMode()
    {
        var error = Assert.Throws<ArgumentException>(() =>
            KnowledgeEvidenceWorkflowService.NormalizeEvidenceMode("draft"));

        Assert.Contains("invalid_evidence_mode", error.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("candidate")]
    [InlineData("reviewed")]
    public void RequiresExplicitPreviewForNonActiveEvidence(string evidenceMode)
    {
        var request = new QuestionEvidenceSearchRequest(EvidenceMode: evidenceMode, PreviewMode: false);

        var error = Assert.Throws<ArgumentException>(() =>
            KnowledgeEvidenceWorkflowService.ValidateQuestionEvidenceSearchRequest(request));

        Assert.Contains("preview_mode_required", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void AllowsExplicitCandidatePreview()
    {
        var request = new QuestionEvidenceSearchRequest(
            EvidenceMode: "candidate",
            PreviewMode: true,
            Ability: "科学推理",
            ObservedDifficultyMin: 0.4m,
            EstimatedDifficultyMax: 0.8);

        KnowledgeEvidenceWorkflowService.ValidateQuestionEvidenceSearchRequest(request);
    }

    [Fact]
    public void KeepsObservedAndEstimatedDifficultyRangesIndependent()
    {
        var valid = new QuestionEvidenceSearchRequest(
            ObservedDifficultyMin: 0.2m,
            ObservedDifficultyMax: 0.8m,
            EstimatedDifficultyMin: 0.3,
            EstimatedDifficultyMax: 0.9);
        KnowledgeEvidenceWorkflowService.ValidateQuestionEvidenceSearchRequest(valid);

        var invalidObserved = valid with { ObservedDifficultyMin = 0.9m, ObservedDifficultyMax = 0.1m };
        var observedError = Assert.Throws<ArgumentException>(() =>
            KnowledgeEvidenceWorkflowService.ValidateQuestionEvidenceSearchRequest(invalidObserved));
        Assert.Contains("invalid_difficulty_range", observedError.Message, StringComparison.Ordinal);

        var invalidEstimated = valid with { EstimatedDifficultyMin = 0.9, EstimatedDifficultyMax = 0.1 };
        var estimatedError = Assert.Throws<ArgumentException>(() =>
            KnowledgeEvidenceWorkflowService.ValidateQuestionEvidenceSearchRequest(invalidEstimated));
        Assert.Contains("invalid_difficulty_range", estimatedError.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void ReadsCurriculumSourceAnchorFromCandidateSourceEvidence()
    {
        const string sourceEvidence = """
        {
          "evidenceAnchors": [{
            "sourceDocumentId": "ec5db25f-4336-4dc7-9d34-870e76ea0c8a",
            "sourceRegionId": null,
            "pdfPageNumber": 31,
            "textBlockSha256": "e5112a0f83073c4de4b043149ed05b8bd18325923e57af6e8227a7b133eb8baf"
          }]
        }
        """;

        var anchor = CurriculumSourceAnchorParser.ReadFirst(sourceEvidence);

        Assert.NotNull(anchor);
        Assert.Equal(Guid.Parse("ec5db25f-4336-4dc7-9d34-870e76ea0c8a"), anchor.SourceDocumentId);
        Assert.Null(anchor.SourceRegionId);
        Assert.Equal(31, anchor.PageNumber);
        Assert.Equal("e5112a0f83073c4de4b043149ed05b8bd18325923e57af6e8227a7b133eb8baf", anchor.AnchorSha256);
    }
}
