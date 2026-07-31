using System.Text.Json;
using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Application.Workflows.Contracts;
using K12QuestionGraph.Api.Domain;

namespace K12QuestionGraph.Api.Tests;

public sealed class CurriculumEvidenceReviewTests
{
    [Fact]
    public void OrderReviewItems_PrioritizesImpactThenLowConfidence()
    {
        var items = new[]
        {
            Item("low-impact", "low", 0.95m),
            Item("high-confidence", "high", 0.90m),
            Item("high-low-confidence", "high", 0.61m),
            Item("medium-impact", "medium", 0.40m),
        };

        var ordered = KnowledgeEvidenceWorkflowService.OrderReviewItems(items);

        Assert.Equal(
            new[] { "high-low-confidence", "high-confidence", "medium-impact", "low-impact" },
            ordered.Select(item => item.StableKey));
    }

    [Theory]
    [InlineData("equivalent", "low", 0.90, true)]
    [InlineData("broader", "low", 0.90, false)]
    [InlineData("equivalent", "high", 0.90, false)]
    [InlineData("equivalent", "low", 0.84, false)]
    public void IsBatchApprovalEligible_RequiresHighConfidenceLowRiskOneToOne(
        string mappingType,
        string impactLevel,
        decimal confidence,
        bool expected)
    {
        var item = Item("candidate", impactLevel, confidence) with
        {
            MappingType = mappingType,
            Reversible = true,
        };

        Assert.Equal(expected, KnowledgeEvidenceWorkflowService.IsBatchApprovalEligible(item));
    }

    [Fact]
    public void BuildDecisionAuditPayload_RecordsBeforeAfterEvidenceAndUndo()
    {
        var before = JsonDocument.Parse("{\"reviewStatus\":\"pending_review\",\"productionEligible\":false}").RootElement.Clone();
        var after = JsonDocument.Parse("{\"reviewStatus\":\"approved\",\"productionEligible\":false}").RootElement.Clone();
        var evidence = JsonDocument.Parse("{\"sourceRegionId\":\"region-1\"}").RootElement.Clone();
        var reviewedAt = DateTimeOffset.Parse("2026-07-30T12:00:00Z");

        var payload = KnowledgeEvidenceWorkflowService.BuildDecisionAuditPayload(
            new CurriculumEvidenceDecisionAuditInput(
                "target",
                Guid.Parse("10000000-0000-0000-0000-000000000001"),
                "approve",
                "teacher-1",
                "Evidence is sufficient.",
                "teacher",
                before,
                after,
                evidence,
                reviewedAt));

        using var document = JsonDocument.Parse(payload);
        var root = document.RootElement;
        Assert.Equal("teacher-1", root.GetProperty("reviewer").GetString());
        Assert.Equal("approve", root.GetProperty("decision").GetString());
        Assert.Equal("pending_review", root.GetProperty("before").GetProperty("reviewStatus").GetString());
        Assert.Equal("approved", root.GetProperty("after").GetProperty("reviewStatus").GetString());
        Assert.Equal("region-1", root.GetProperty("evidence").GetProperty("sourceRegionId").GetString());
        Assert.True(root.GetProperty("undo").GetProperty("allowed").GetBoolean());
        Assert.False(root.GetProperty("activeApply").GetBoolean());
    }

    [Fact]
    public void BuildUndoAuditPayload_PreservesOriginalDecisionAndRestorationSnapshot()
    {
        var decisionPayload = "{\"decision\":\"approve\",\"before\":{\"reviewStatus\":\"pending_review\"},\"after\":{\"reviewStatus\":\"approved\"},\"undo\":{\"allowed\":true}}";
        var undoneAt = DateTimeOffset.Parse("2026-07-30T12:05:00Z");

        var payload = KnowledgeEvidenceWorkflowService.BuildUndoAuditPayload(
            decisionPayload,
            "admin-1",
            "Approval used the wrong evidence.",
            undoneAt);

        using var document = JsonDocument.Parse(payload);
        var root = document.RootElement;
        Assert.Equal("approve", root.GetProperty("decision").GetString());
        Assert.False(root.GetProperty("undo").GetProperty("allowed").GetBoolean());
        Assert.Equal("admin-1", root.GetProperty("undo").GetProperty("reviewer").GetString());
        Assert.Equal("pending_review", root.GetProperty("undo").GetProperty("restored").GetProperty("reviewStatus").GetString());
        Assert.Equal("approved", root.GetProperty("undo").GetProperty("replaced").GetProperty("reviewStatus").GetString());
    }

    [Fact]
    public void BuildDecisionResponse_UndoneDomainAssetWithoutTopLevelReviewStatusFailsClosed()
    {
        var audit = new ReviewQueueItem
        {
            Id = Guid.Parse("10000000-0000-0000-0000-000000000001"),
            ReviewType = "curriculum_evidence_decision",
            Status = ReviewStatuses.Dismissed,
            Payload = """
                {
                  "candidateType":"requirement",
                  "candidateId":"20000000-0000-0000-0000-000000000002",
                  "decision":"keep_pending",
                  "before":{"entityKind":"domain_asset_version","status":"candidate","metadata":{"candidateOnly":true}},
                  "after":{"entityKind":"domain_asset_version","status":"candidate","metadata":{"candidateOnly":true}},
                  "undo":{"allowed":false,"restored":{"entityKind":"domain_asset_version","status":"candidate","metadata":{"candidateOnly":true}}},
                  "activeApply":false,
                  "productionEligible":false
                }
                """,
            CreatedAt = DateTimeOffset.Parse("2026-07-31T10:38:28Z"),
            ResolvedAt = DateTimeOffset.Parse("2026-07-31T10:38:29Z"),
        };

        var response = KnowledgeEvidenceWorkflowService.BuildDecisionResponse(audit);

        Assert.Equal(DomainAssetReviewStatuses.PendingReview, response.ReviewStatus);
        Assert.False(response.ActiveApply);
        Assert.False(response.ProductionEligible);
    }

    [Fact]
    public void IsAssetReviewEligible_RejectsActiveAndForeignProfileAssets()
    {
        var eligible = Asset("candidate", "cek023_regional_exam_profile_candidate_v1");
        var active = Asset("active", "cek023_regional_exam_profile_candidate_v1");
        var foreign = Asset("candidate", "legacy_exam_point_import");

        Assert.True(KnowledgeEvidenceWorkflowService.IsAssetReviewEligible(eligible, "profile"));
        Assert.False(KnowledgeEvidenceWorkflowService.IsAssetReviewEligible(active, "profile"));
        Assert.False(KnowledgeEvidenceWorkflowService.IsAssetReviewEligible(foreign, "profile"));
    }

    [Fact]
    public void IsAssetReviewEligible_RequirementRequiresCek09Candidate()
    {
        var eligible = RequirementAsset("candidate", "cek009_curriculum_requirements_2022_2025_v1");
        var active = RequirementAsset("active", "cek009_curriculum_requirements_2022_2025_v1");
        var foreign = RequirementAsset("candidate", "legacy_curriculum_import");

        Assert.True(KnowledgeEvidenceWorkflowService.IsAssetReviewEligible(eligible, "requirement"));
        Assert.False(KnowledgeEvidenceWorkflowService.IsAssetReviewEligible(active, "requirement"));
        Assert.False(KnowledgeEvidenceWorkflowService.IsAssetReviewEligible(foreign, "requirement"));
    }

    [Fact]
    public void IsMappingReviewEligible_RequiresCek09ReviewableNonAppliedMapping()
    {
        var eligible = Mapping("cek009_curriculum_requirements_2022_2025_v1", "pending_review", autoApplied: false);
        var foreign = Mapping("legacy_curriculum_import", "pending_review", autoApplied: false);
        var applied = Mapping("cek009_curriculum_requirements_2022_2025_v1", "approved", autoApplied: true);
        var invalidStatus = Mapping("cek009_curriculum_requirements_2022_2025_v1", "active", autoApplied: false);

        Assert.True(KnowledgeEvidenceWorkflowService.IsMappingReviewEligible(eligible));
        Assert.False(KnowledgeEvidenceWorkflowService.IsMappingReviewEligible(foreign));
        Assert.False(KnowledgeEvidenceWorkflowService.IsMappingReviewEligible(applied));
        Assert.False(KnowledgeEvidenceWorkflowService.IsMappingReviewEligible(invalidStatus));
    }

    [Fact]
    public void IsMappingReplacementEligible_StaysInsideCurrentActiveKnowledgeImport()
    {
        var current = KnowledgePoint("active", "active_c002_v1");
        var sameActiveImport = KnowledgePoint("active", "active_c002_v1");
        var foreignActiveImport = KnowledgePoint("active", "foreign_knowledge_v1");
        var candidate = KnowledgePoint("candidate", "active_c002_v1");
        var wrongType = KnowledgePoint("active", "active_c002_v1", "exam_point");

        Assert.True(KnowledgeEvidenceWorkflowService.IsMappingReplacementEligible(current, sameActiveImport));
        Assert.False(KnowledgeEvidenceWorkflowService.IsMappingReplacementEligible(current, foreignActiveImport));
        Assert.False(KnowledgeEvidenceWorkflowService.IsMappingReplacementEligible(current, candidate));
        Assert.False(KnowledgeEvidenceWorkflowService.IsMappingReplacementEligible(current, wrongType));
    }

    [Fact]
    public void ValidateDecisionRequest_RestrictsReplacementToAlignmentMappingChanges()
    {
        var replacementId = Guid.Parse("30000000-0000-0000-0000-000000000003");
        var targetChange = DecisionRequest("target", "change_mapping", replacementId);
        var approveWithReplacement = DecisionRequest("alignment", "approve", replacementId);
        var validChange = DecisionRequest("alignment", "change_mapping", replacementId);

        Assert.Throws<ArgumentException>(() => KnowledgeEvidenceWorkflowService.ValidateDecisionRequest(targetChange));
        Assert.Throws<ArgumentException>(() => KnowledgeEvidenceWorkflowService.ValidateDecisionRequest(approveWithReplacement));
        KnowledgeEvidenceWorkflowService.ValidateDecisionRequest(validChange);
    }

    [Fact]
    public void SnapshotsMatch_DetectsStateChangedAfterDecision()
    {
        var expected = JsonDocument.Parse("{\"status\":\"reviewed\",\"reviewStatus\":\"approved\"}").RootElement.Clone();
        var same = JsonDocument.Parse("{\"reviewStatus\":\"approved\",\"status\":\"reviewed\"}").RootElement.Clone();
        var changed = JsonDocument.Parse("{\"status\":\"candidate\",\"reviewStatus\":\"pending_review\"}").RootElement.Clone();

        Assert.True(KnowledgeEvidenceWorkflowService.SnapshotsMatch(expected, same));
        Assert.False(KnowledgeEvidenceWorkflowService.SnapshotsMatch(expected, changed));
    }

    [Fact]
    public void SnapshotsMatch_IgnoresReviewedAtPrecisionButKeepsMappingStateStrict()
    {
        var expected = JsonDocument.Parse("""
            {
              "entityKind":"domain_asset_mapping",
              "reviewStatus":"approved",
              "targetAssetVersionId":"10000000-0000-0000-0000-000000000001",
              "reviewedAt":"2026-07-30T15:41:13.0075218+00:00",
              "autoApplied":false
            }
            """).RootElement.Clone();
        var databaseRoundTrip = JsonDocument.Parse("""
            {
              "entityKind":"domain_asset_mapping",
              "reviewStatus":"approved",
              "targetAssetVersionId":"10000000-0000-0000-0000-000000000001",
              "reviewedAt":"2026-07-30T23:41:13.007521+08:00",
              "autoApplied":false
            }
            """).RootElement.Clone();
        var changedStatus = JsonDocument.Parse("""
            {
              "entityKind":"domain_asset_mapping",
              "reviewStatus":"rejected",
              "targetAssetVersionId":"10000000-0000-0000-0000-000000000001",
              "reviewedAt":"2026-07-30T23:41:13.007521+08:00",
              "autoApplied":false
            }
            """).RootElement.Clone();
        var changedTarget = JsonDocument.Parse("""
            {
              "entityKind":"domain_asset_mapping",
              "reviewStatus":"approved",
              "targetAssetVersionId":"20000000-0000-0000-0000-000000000002",
              "reviewedAt":"2026-07-30T23:41:13.007521+08:00",
              "autoApplied":false
            }
            """).RootElement.Clone();

        Assert.True(KnowledgeEvidenceWorkflowService.SnapshotsMatch(expected, databaseRoundTrip));
        Assert.False(KnowledgeEvidenceWorkflowService.SnapshotsMatch(expected, changedStatus));
        Assert.False(KnowledgeEvidenceWorkflowService.SnapshotsMatch(expected, changedTarget));
    }

    private static CurriculumEvidenceReviewItemDto Item(
        string stableKey,
        string impactLevel,
        decimal confidence) => new(
            "alignment",
            Guid.NewGuid(),
            stableKey,
            "low_confidence_mappings",
            "pending_review",
            confidence,
            impactLevel,
            "equivalent",
            "retrospective_crosswalk",
            OriginalBasis: false,
            ProductionEligible: false,
            Reversible: true,
            BatchApprovalEligible: false,
            JsonDocument.Parse("{}").RootElement.Clone(),
            JsonDocument.Parse("{}").RootElement.Clone());

    private static DomainAssetVersion Asset(string status, string importKey) => new()
    {
        Id = Guid.NewGuid(),
        AssetType = "exam_point",
        StableId = "EPHY-GUANGZHOU-FIXTURE",
        Version = 1,
        DisplayName = "Fixture profile",
        Status = status,
        Metadata = JsonSerializer.Serialize(new
        {
            semantic_type = "RegionalExamPointProfile",
            review_status = "pending_review",
            production_eligible = false,
        }),
        SourceEvidence = JsonSerializer.Serialize(new { importKey }),
    };

    private static DomainAssetVersion RequirementAsset(string status, string importKey) => new()
    {
        Id = Guid.NewGuid(),
        AssetType = "requirement_facet",
        StableId = "REQ-PHY-FIXTURE",
        Version = 1,
        DisplayName = "Fixture requirement",
        Status = status,
        Metadata = JsonSerializer.Serialize(new { confidence = 0.94m, candidateOnly = true }),
        SourceEvidence = JsonSerializer.Serialize(new
        {
            importKey,
            reviewStatus = "pending_review",
            productionEligible = false,
        }),
    };

    private static DomainAssetMapping Mapping(string importKey, string reviewStatus, bool autoApplied) => new()
    {
        Id = Guid.NewGuid(),
        SourceAssetVersionId = Guid.NewGuid(),
        TargetAssetVersionId = Guid.NewGuid(),
        MappingType = DomainAssetMappingTypes.Equivalent,
        Confidence = 0.9m,
        ReviewStatus = reviewStatus,
        AutoApplied = autoApplied,
        Evidence = JsonSerializer.Serialize(new { importKey }),
    };

    private static DomainAssetVersion KnowledgePoint(
        string status,
        string importKey,
        string assetType = "knowledge_point") => new()
    {
        Id = Guid.NewGuid(),
        AssetType = assetType,
        StableId = $"KPHY-{Guid.NewGuid():N}",
        Version = 1,
        DisplayName = "Fixture knowledge point",
        Status = status,
        Metadata = "{}",
        SourceEvidence = JsonSerializer.Serialize(new { importKey }),
    };

    private static CurriculumEvidenceDecisionRequest DecisionRequest(
        string candidateType,
        string decision,
        Guid? replacementId = null) => new(
            candidateType,
            Guid.Parse("40000000-0000-0000-0000-000000000004"),
            decision,
            "teacher-1",
            "Review fixture decision.",
            "teacher",
            replacementId);
}
