using System.Text.Json;
using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Domain;

namespace K12QuestionGraph.Api.Tests;

public sealed class RegionalExamProfileQueryTests
{
    [Fact]
    public void ProjectRegionalExamProfile_ReturnsGovernedProfileDetail()
    {
        var asset = CreateAsset();

        var result = KnowledgeEvidenceWorkflowService.ProjectRegionalExamProfile(asset);

        Assert.NotNull(result);
        Assert.Equal("EPHY-GUANGZHOU-FIXTURE", result.StableId);
        Assert.Equal("pending_review", result.ReviewStatus);
        Assert.False(result.ProductionEligible);
        Assert.Equal(4, result.Profile.GetProperty("year_range").GetProperty("comparable_exam_years").GetArrayLength());
        Assert.Equal(360, result.Profile.GetProperty("score_weight").GetProperty("denominator_total_exam_score").GetInt32());
        Assert.Equal("historical", result.Profile.GetProperty("standard_regime").GetProperty("regime_id").GetString());
        Assert.Equal(3, result.Diagnostics.GetProperty("occurrenceYears").GetArrayLength());
        Assert.Equal(Guid.Parse("10000000-0000-0000-0000-000000000001"), Assert.Single(result.EvidenceTargetIds));
    }

    [Fact]
    public void ProjectRegionalExamProfile_RejectsLegacyOrUnsafeExamPointAssets()
    {
        var legacy = CreateAsset(metadata: "{\"review_status\":\"pending_review\"}");
        var active = CreateAsset(status: "active");
        var wrongImport = CreateAsset(sourceEvidence: JsonSerializer.Serialize(new
        {
            importKey = "legacy_exam_point_import",
            evidenceTargetIds = new[] { "10000000-0000-0000-0000-000000000001" }
        }));
        var invalidEvidenceTarget = CreateAsset(sourceEvidence: JsonSerializer.Serialize(new
        {
            importKey = "cek023_regional_exam_profile_candidate_v1",
            evidenceTargetIds = new[] { "not-a-guid" }
        }));
        var invalidMetadataType = CreateAsset(metadata: JsonSerializer.Serialize(new
        {
            semantic_type = 23,
            storage_asset_type = "exam_point",
            review_status = "pending_review",
            production_eligible = false,
            diagnostics = new { }
        }));

        Assert.Null(KnowledgeEvidenceWorkflowService.ProjectRegionalExamProfile(legacy));
        Assert.Null(KnowledgeEvidenceWorkflowService.ProjectRegionalExamProfile(active));
        Assert.Null(KnowledgeEvidenceWorkflowService.ProjectRegionalExamProfile(wrongImport));
        Assert.Null(KnowledgeEvidenceWorkflowService.ProjectRegionalExamProfile(invalidEvidenceTarget));
        Assert.Null(KnowledgeEvidenceWorkflowService.ProjectRegionalExamProfile(invalidMetadataType));
    }

    private static DomainAssetVersion CreateAsset(
        string? metadata = null,
        string status = "candidate",
        string? sourceEvidence = null) => new()
    {
        Id = Guid.Parse("00000000-0000-0000-0000-000000000001"),
        AssetType = "exam_point",
        StableId = "EPHY-GUANGZHOU-FIXTURE",
        Version = 1,
        DisplayName = "Guangzhou fixture profile",
        Status = status,
        Authority = "source_derived",
        Metadata = metadata ?? JsonSerializer.Serialize(new
        {
            semantic_type = "RegionalExamPointProfile",
            storage_asset_type = "exam_point",
            review_status = "pending_review",
            production_eligible = false,
            year_range = new { start_year = 2021, end_year = 2024, comparable_exam_years = new[] { 2021, 2022, 2023, 2024 } },
            standard_regime = new { regime_id = "historical" },
            score_weight = new { denominator_total_exam_score = 360 },
            diagnostics = new { occurrenceYears = new[] { 2022, 2023, 2024 } }
        }),
        SourceEvidence = sourceEvidence ?? JsonSerializer.Serialize(new
        {
            importKey = "cek023_regional_exam_profile_candidate_v1",
            evidenceTargetIds = new[] { "10000000-0000-0000-0000-000000000001" }
        })
    };
}
