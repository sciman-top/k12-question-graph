using System.Text.Json;

namespace K12QuestionGraph.Api.Application.Workflows.Contracts;

public sealed record KnowledgeEvidenceListRequest(string ReviewStatus = "pending_review", int Take = 100);

public sealed record KnowledgeEvidenceAlignmentDto(
    Guid Id,
    string StableKey,
    string AlignmentType,
    string StandardVersion,
    decimal Confidence,
    bool OriginalBasis,
    string Status,
    string ReviewStatus,
    bool ProductionEligible,
    string Evidence);

public sealed record KnowledgeEvidenceTargetDto(
    Guid Id,
    string StableKey,
    Guid QuestionItemId,
    Guid? QuestionBlockId,
    string ScopeType,
    string TargetStatement,
    decimal Confidence,
    string Status,
    string ReviewStatus,
    bool ProductionEligible,
    Guid? PrimaryKnowledgeAssetVersionId,
    string Metadata,
    IReadOnlyList<KnowledgeEvidenceAlignmentDto> CurriculumAlignments);

public sealed record KnowledgeEvidenceListResponse(
    IReadOnlyList<KnowledgeEvidenceTargetDto> Items,
    int Returned,
    string ReviewStatus,
    bool ProductionEligible,
    string CompletionBoundary);

public sealed record ObservedEvidenceListRequest(
    string ReviewStatus = "pending_review",
    Guid? AssessmentTargetId = null,
    int Take = 100);

public sealed record ObservedPerformanceEvidenceDto(
    Guid Id,
    Guid AssessmentTargetId,
    Guid SourceRegionId,
    decimal? MaximumScore,
    decimal? AverageScore,
    decimal? ScoreRate,
    decimal? DifficultyObserved,
    decimal? Discrimination,
    string DifficultyDirection,
    string SampleScope,
    int? SampleSize,
    string OptionDistribution,
    string RawStatistics,
    decimal Confidence,
    string Status,
    string ReviewStatus,
    bool ProductionEligible,
    string Evidence);

public sealed record ObservedErrorEvidenceDto(
    Guid Id,
    Guid AssessmentTargetId,
    Guid SourceRegionId,
    string RecordKind,
    string Content,
    string GenerationMethod,
    decimal Confidence,
    string Status,
    string ReviewStatus,
    bool ProductionEligible,
    string Evidence);

public sealed record TeachingRecommendationDto(
    Guid Id,
    Guid AssessmentTargetId,
    Guid SourceRegionId,
    string Content,
    string AuthorKind,
    string GenerationMethod,
    decimal Confidence,
    string Status,
    string ReviewStatus,
    bool ProductionEligible,
    string Evidence);

public sealed record ObservedEvidenceListResponse(
    IReadOnlyList<ObservedPerformanceEvidenceDto> Performance,
    IReadOnlyList<ObservedErrorEvidenceDto> Errors,
    IReadOnlyList<TeachingRecommendationDto> TeachingRecommendations,
    int PerformanceReturned,
    int ErrorsReturned,
    int TeachingRecommendationsReturned,
    string ReviewStatus,
    Guid? AssessmentTargetId,
    bool ProductionEligible,
    string CompletionBoundary);

public sealed record RegionalExamProfileDetailResponse(
    Guid Id,
    string StableId,
    int Version,
    string DisplayName,
    string Status,
    string ReviewStatus,
    bool ProductionEligible,
    JsonElement Profile,
    JsonElement Diagnostics,
    IReadOnlyList<Guid> EvidenceTargetIds,
    string ImportKey,
    string CompletionBoundary);

public sealed record QuestionEvidenceSearchRequest(
    string EvidenceMode = "active",
    bool PreviewMode = false,
    string? RequirementId = null,
    string? FacetId = null,
    string? Ability = null,
    string? CognitiveDemand = null,
    string? MethodOrExperiment = null,
    string? Context = null,
    string? Representation = null,
    string? ProfileId = null,
    decimal? ObservedDifficultyMin = null,
    decimal? ObservedDifficultyMax = null,
    double? EstimatedDifficultyMin = null,
    double? EstimatedDifficultyMax = null,
    string? SourceType = null,
    int Page = 1,
    int PageSize = 20);

public sealed record QuestionEvidenceKnowledgeDto(
    string StableId,
    string DisplayName,
    string Role,
    decimal Confidence,
    string Status,
    string ReviewStatus);

public sealed record QuestionEvidenceRequirementDto(
    string StableId,
    string DisplayName,
    string AlignmentType,
    bool OriginalBasis,
    string Provenance,
    Guid SourceDocumentId,
    Guid? SourceRegionId,
    decimal Confidence,
    Guid? CurriculumSourceDocumentId = null,
    Guid? CurriculumSourceRegionId = null,
    int? CurriculumSourcePageNumber = null);

public sealed record QuestionObservedDifficultyDto(
    decimal Value,
    string Direction,
    string SampleScope,
    Guid SourceRegionId,
    string Status,
    string ReviewStatus);

public sealed record QuestionEvidenceProfileDto(
    string StableId,
    string DisplayName,
    string Status,
    string? TrendStatus);

public sealed record QuestionAssessmentTargetEvidenceDto(
    Guid Id,
    string StableKey,
    string ScopeType,
    string TargetStatement,
    bool IsPrimaryTarget,
    decimal Confidence,
    string Status,
    string ReviewStatus,
    bool ProductionEligible,
    IReadOnlyList<string> AbilityDimensions,
    IReadOnlyList<string> CognitiveDemands,
    IReadOnlyList<string> MethodOrExperimentIds,
    string? ContextType,
    IReadOnlyList<string> RepresentationTypes,
    IReadOnlyList<QuestionEvidenceKnowledgeDto> Knowledge,
    IReadOnlyList<QuestionEvidenceRequirementDto> Requirements,
    IReadOnlyList<QuestionObservedDifficultyDto> ObservedDifficulty,
    IReadOnlyList<QuestionEvidenceProfileDto> Profiles);

public sealed record QuestionEvidenceCardDto(
    Guid QuestionId,
    int? QuestionNo,
    string Subject,
    string Stage,
    string? Grade,
    string? QuestionType,
    string Status,
    double? EstimatedDifficulty,
    string EstimatedDifficultySource,
    IReadOnlyList<QuestionAssessmentTargetEvidenceDto> AssessmentTargets,
    bool ProductionEligible);

public sealed record QuestionEvidenceSearchResponse(
    string EvidenceMode,
    bool PreviewMode,
    bool ProductionEligible,
    int Total,
    int Page,
    int PageSize,
    IReadOnlyList<QuestionEvidenceCardDto> Items,
    string Sort,
    string CompletionBoundary);

public sealed record CurriculumEvidenceReviewListRequest(
    string? GroupId = null,
    int Page = 1,
    int PageSize = 50);

public sealed record CurriculumEvidenceReviewItemDto(
    string CandidateType,
    Guid CandidateId,
    string StableKey,
    string GroupId,
    string ReviewStatus,
    decimal Confidence,
    string ImpactLevel,
    string? MappingType,
    string? AlignmentType,
    bool OriginalBasis,
    bool ProductionEligible,
    bool Reversible,
    bool BatchApprovalEligible,
    JsonElement Summary,
    JsonElement Evidence);

public sealed record CurriculumEvidenceReviewListResponse(
    IReadOnlyList<CurriculumEvidenceReviewItemDto> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages,
    string Sort,
    bool ProductionEligible,
    string CompletionBoundary);

public sealed record CurriculumEvidenceReplacementOptionDto(
    Guid AssetVersionId,
    string StableKey,
    string DisplayName);

public sealed record CurriculumEvidenceReplacementOptionsResponse(
    IReadOnlyList<CurriculumEvidenceReplacementOptionDto> Items,
    bool ProductionEligible,
    string CompletionBoundary);

public sealed record CurriculumEvidenceCandidateReference(
    string CandidateType,
    Guid CandidateId);

public sealed record CurriculumEvidenceDecisionRequest(
    string CandidateType,
    Guid CandidateId,
    string Decision,
    string Reviewer,
    string Reason,
    string ActorRole = "teacher",
    Guid? ReplacementAssetVersionId = null);

public sealed record CurriculumEvidenceBatchDecisionRequest(
    IReadOnlyList<CurriculumEvidenceCandidateReference> Items,
    string Reviewer,
    string Reason,
    string ActorRole = "teacher");

public sealed record CurriculumEvidenceUndoRequest(
    string Reviewer,
    string Reason,
    string ActorRole = "teacher");

public sealed record CurriculumEvidenceDecisionResponse(
    Guid DecisionId,
    string CandidateType,
    Guid CandidateId,
    string Decision,
    string ReviewStatus,
    bool ProductionEligible,
    bool ActiveApply,
    JsonElement Audit);

public sealed record CurriculumEvidenceBatchDecisionResponse(
    IReadOnlyList<CurriculumEvidenceDecisionResponse> Decisions,
    int ApprovedCount,
    bool ActiveApply);

public sealed record CurriculumEvidenceReviewGroupSummary(
    string GroupId,
    string Status,
    int PendingCount,
    int ApprovedCount,
    int RejectedCount,
    int TotalCount,
    string Reason);

public sealed record CurriculumEvidenceReadinessSummary(
    IReadOnlyList<CurriculumEvidenceReviewGroupSummary> Groups,
    int PendingCount,
    int ApprovedCount,
    int RejectedCount,
    bool ReviewComplete,
    bool ActiveApplyAllowed,
    bool ProductionEligible,
    string ErrorPatternStatus,
    string CompletionBoundary);

internal sealed record CurriculumEvidenceDecisionAuditInput(
    string CandidateType,
    Guid CandidateId,
    string Decision,
    string Reviewer,
    string Reason,
    string ActorRole,
    JsonElement Before,
    JsonElement After,
    JsonElement Evidence,
    DateTimeOffset ReviewedAt);
