using System.Text.Json;
using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Domain;

namespace K12QuestionGraph.Api.Tests;

public sealed class ErrorPatternPromotionTests
{
    private static readonly ErrorPatternTaxonomyEntry ConceptConfusion = new(
        "concept_confusion",
        "概念混淆",
        "conceptual",
        MisconceptionEligible: true);

    private static readonly ErrorPatternTaxonomyEntry UnitConversion = new(
        "unit_conversion",
        "单位换算错误",
        "procedural",
        MisconceptionEligible: false);

    private static readonly ErrorPatternTaxonomyEntry CarelessOmission = new(
        "careless_omission",
        "粗心遗漏",
        "careless",
        MisconceptionEligible: false);

    private static readonly IReadOnlyList<ErrorPatternTaxonomyEntry> Taxonomy =
        [ConceptConfusion, UnitConversion, CarelessOmission];

    [Fact]
    public void BuildErrorPatternCandidates_RejectsSingleEvidence()
    {
        var candidates = Build(Evidence(ConceptConfusion.Code, year: 2024));

        Assert.Empty(candidates);
    }

    [Fact]
    public void BuildErrorPatternCandidates_RejectsRepeatedEvidenceFromOneQuestionAndYear()
    {
        var questionId = Guid.NewGuid();
        var candidates = Build(
            Evidence(ConceptConfusion.Code, year: 2024, questionId: questionId),
            Evidence(ConceptConfusion.Code, year: 2024, questionId: questionId));

        Assert.Empty(candidates);
    }

    [Fact]
    public void BuildErrorPatternCandidates_DoesNotMergeSemanticallyDifferentCodes()
    {
        var candidates = Build(
            Evidence(ConceptConfusion.Code, year: 2024),
            Evidence(UnitConversion.Code, year: 2024));

        Assert.Empty(candidates);
    }

    [Fact]
    public void BuildErrorPatternCandidates_CreatesCandidateForConsistentCrossQuestionEvidence()
    {
        var first = Evidence(ConceptConfusion.Code, year: 2024);
        var second = Evidence(ConceptConfusion.Code, year: 2024);

        var candidate = Assert.Single(Build(first, second));

        Assert.Equal("error_pattern", candidate.Asset.AssetType);
        Assert.Equal("ERR-CONCEPT-CONFUSION", candidate.Asset.StableId);
        Assert.Equal(DomainAssetStatuses.Candidate, candidate.Asset.Status);
        Assert.Equal(DomainAssetAuthorities.SourceDerived, candidate.Asset.Authority);
        Assert.Equal(2, candidate.EvidenceCount);
        Assert.Equal(2, candidate.DistinctQuestionCount);
        Assert.Equal(1, candidate.DistinctExamYearCount);
        Assert.Equal("cross_question", candidate.StabilityBasis);
        Assert.Equal("controlled_taxonomy_exact_code_v1", candidate.NormalizationMethod);
        Assert.Equal(DomainAssetReviewStatuses.PendingReview, candidate.ReviewerStatus);
        Assert.False(candidate.ProductionEligible);
        Assert.Equal([first.AssessmentTargetId, second.AssessmentTargetId], candidate.EvidenceTargetIds);

        using var metadata = JsonDocument.Parse(candidate.Asset.Metadata);
        Assert.Equal(2, metadata.RootElement.GetProperty("distinctQuestionCount").GetInt32());
        Assert.Equal("pending_review", metadata.RootElement.GetProperty("reviewerStatus").GetString());
        Assert.False(metadata.RootElement.GetProperty("productionEligible").GetBoolean());
    }

    [Fact]
    public void BuildErrorPatternCandidates_CreatesCandidateForConsistentCrossYearEvidence()
    {
        var questionId = Guid.NewGuid();
        var candidate = Assert.Single(Build(
            Evidence(UnitConversion.Code, year: 2023, questionId: questionId),
            Evidence(UnitConversion.Code, year: 2024, questionId: questionId)));

        Assert.Equal(1, candidate.DistinctQuestionCount);
        Assert.Equal(2, candidate.DistinctExamYearCount);
        Assert.Equal("cross_year", candidate.StabilityBasis);
    }

    [Fact]
    public void BuildErrorPatternCandidates_KeepsMisconceptionPromotionPendingAndNonApplying()
    {
        var candidate = Assert.Single(Build(
            Evidence(ConceptConfusion.Code, year: 2023),
            Evidence(ConceptConfusion.Code, year: 2024)));

        Assert.Equal("pending_review", candidate.Promotion.Status);
        Assert.Equal("misconception", candidate.Promotion.TargetKnowledgeType);
        Assert.True(candidate.Promotion.RequiresHumanReview);
        Assert.True(candidate.Promotion.RequiresC002RImpactReport);
        Assert.True(candidate.Promotion.RequiresRollbackSnapshot);
        Assert.False(candidate.Promotion.AutoApplyAllowed);
    }

    [Fact]
    public void BuildErrorPatternCandidates_DoesNotPromoteCarelessPatternToMisconception()
    {
        var candidate = Assert.Single(Build(
            Evidence(CarelessOmission.Code, year: 2023),
            Evidence(CarelessOmission.Code, year: 2024)));

        Assert.Equal("not_eligible", candidate.Promotion.Status);
        Assert.Null(candidate.Promotion.TargetKnowledgeType);
        Assert.False(candidate.Promotion.AutoApplyAllowed);
    }

    [Fact]
    public void BuildErrorPatternCandidates_FailsClosedForUnknownTaxonomyCode()
    {
        var candidates = Build(
            Evidence("unsupported_free_text_label", year: 2023),
            Evidence("unsupported_free_text_label", year: 2024));

        Assert.Empty(candidates);
    }

    private static IReadOnlyList<ErrorPatternCandidate> Build(params ErrorPatternEvidenceInput[] evidence) =>
        KnowledgeEvidenceWorkflowService.BuildErrorPatternCandidates(
            evidence,
            Taxonomy,
            "controlled_taxonomy_exact_code_v1");

    private static ErrorPatternEvidenceInput Evidence(string patternCode, int year, Guid? questionId = null) =>
        new(
            Guid.NewGuid(),
            Guid.NewGuid(),
            questionId ?? Guid.NewGuid(),
            year,
            patternCode);
}
