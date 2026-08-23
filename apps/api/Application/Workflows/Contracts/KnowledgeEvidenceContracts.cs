using System.Text.Json;

namespace K12QuestionGraph.Api.Application.Workflows.Contracts;

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
