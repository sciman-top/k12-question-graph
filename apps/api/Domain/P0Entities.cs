namespace K12QuestionGraph.Api.Domain;

public static class JobStatuses
{
    public const string Queued = "queued";
    public const string Running = "running";
    public const string Succeeded = "succeeded";
    public const string Failed = "failed";
    public const string Cancelled = "cancelled";
    public const string RetryWaiting = "retry_waiting";
}

public static class ReviewStatuses
{
    public const string Open = "open";
    public const string Resolved = "resolved";
    public const string Dismissed = "dismissed";
}

public static class BackupStatuses
{
    public const string Queued = "queued";
    public const string Running = "running";
    public const string Succeeded = "succeeded";
    public const string Failed = "failed";
}

public static class QuestionStatuses
{
    public const string Draft = "draft";
    public const string PendingReview = "pending_review";
    public const string Usable = "usable";
    public const string Recommended = "recommended";
    public const string NeedsImprovement = "needs_improvement";
    public const string Paused = "paused";
    public const string Retired = "retired";
}

public static class KnowledgeStatuses
{
    public const string Draft = "draft";
    public const string Candidate = "candidate";
    public const string Reviewed = "reviewed";
    public const string Active = "active";
    public const string Deprecated = "deprecated";
    public const string Merged = "merged";
    public const string Superseded = "superseded";
}

public static class KnowledgeEdgeTypes
{
    public const string ParentChild = "parent_child";
    public const string Prerequisite = "prerequisite";
    public const string Related = "related";
}

public static class KnowledgeMappingSources
{
    public const string Manual = "manual";
    public const string Import = "import";
    public const string AiSuggested = "ai_suggested";
}

public static class DomainAssetStatuses
{
    public const string Draft = "draft";
    public const string Candidate = "candidate";
    public const string Reviewed = "reviewed";
    public const string Active = "active";
    public const string Deprecated = "deprecated";
    public const string Merged = "merged";
    public const string Superseded = "superseded";
}

public static class DomainAssetAuthorities
{
    public const string Bootstrap = "bootstrap";
    public const string SourceDerived = "source_derived";
    public const string SchoolApproved = "school_approved";
    public const string Policy = "policy";
}

public static class DomainAssetMappingTypes
{
    public const string Equivalent = "equivalent";
    public const string Split = "split";
    public const string Merge = "merge";
    public const string Broader = "broader";
    public const string Narrower = "narrower";
    public const string Renamed = "renamed";
    public const string Deprecated = "deprecated";
}

public static class DomainAssetReviewStatuses
{
    public const string AutoApplied = "auto_applied";
    public const string PendingReview = "pending_review";
    public const string Approved = "approved";
    public const string Rejected = "rejected";
}

public static class DomainAssetMigrationStatuses
{
    public const string Draft = "draft";
    public const string DryRun = "dry_run";
    public const string PendingReview = "pending_review";
    public const string Applied = "applied";
    public const string RolledBack = "rolled_back";
    public const string Rejected = "rejected";
}

public static class AssessmentStatuses
{
    public const string Draft = "draft";
    public const string PendingReview = "pending_review";
    public const string Ready = "ready";
    public const string Archived = "archived";
}

public static class ScoreImportStatuses
{
    public const string Draft = "draft";
    public const string Imported = "imported";
    public const string Failed = "failed";
    public const string Archived = "archived";
}

public static class CutCandidateStatuses
{
    public const string PendingReview = "pending_review";
    public const string NeedsSplit = "needs_split";
    public const string NeedsMerge = "needs_merge";
    public const string Accepted = "accepted";
    public const string Rejected = "rejected";
    public const string RetryRequired = "retry_required";
}

public sealed class TeacherPreference
{
    public Guid Id { get; set; }

    public string TeacherKey { get; set; } = string.Empty;

    public string PreferenceKey { get; set; } = string.Empty;

    public string PreferenceValue { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class FileAsset
{
    public Guid Id { get; set; }

    public string OriginalFileName { get; set; } = string.Empty;

    public string RelativePath { get; set; } = string.Empty;

    public string StorageScope { get; set; } = "original";

    public string ContentType { get; set; } = "application/octet-stream";

    public string Sha256 { get; set; } = string.Empty;

    public long SizeBytes { get; set; }

    public string SourceMetadata { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class SourceDocument
{
    public Guid Id { get; set; }

    public Guid FileAssetId { get; set; }

    public string SourceType { get; set; } = "unknown";

    public string SourceTitle { get; set; } = string.Empty;

    public string Region { get; set; } = string.Empty;

    public int? Year { get; set; }

    public string GradeOrScope { get; set; } = string.Empty;

    public string EditionOrVersion { get; set; } = string.Empty;

    public string MaterialBatchKey { get; set; } = string.Empty;

    public string OwnerScope { get; set; } = "teacher_private";

    public string LicenseOrPermission { get; set; } = "unknown";

    public bool SharingAllowed { get; set; }

    public bool ContainsStudentPii { get; set; }

    public string AnonymizationStatus { get; set; } = "not_applicable";

    public bool ExternalAiAllowed { get; set; }

    public bool MayUseForKnowledgeExtraction { get; set; }

    public bool MayUseForExamPointExtraction { get; set; }

    public bool MayUseForTrendAnalysis { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class SourceRegion
{
    public Guid Id { get; set; }

    public Guid SourceDocumentId { get; set; }

    public int PageNumber { get; set; } = 1;

    public decimal X { get; set; }

    public decimal Y { get; set; }

    public decimal Width { get; set; }

    public decimal Height { get; set; }

    public string CoordinateUnit { get; set; } = "percent";

    public string? ScreenshotRelativePath { get; set; }

    public string RegionType { get; set; } = "preview";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class Student
{
    public Guid Id { get; set; }

    public string StudentKey { get; set; } = string.Empty;

    public string DisplayCode { get; set; } = string.Empty;

    public string Stage { get; set; } = "junior_middle_school";

    public string Grade { get; set; } = string.Empty;

    public bool SyntheticFixture { get; set; }

    public bool ContainsStudentPii { get; set; }

    public string AnonymizationStatus { get; set; } = "synthetic";

    public bool StudentPortalEnabled { get; set; }

    public string Metadata { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class ClassGroup
{
    public Guid Id { get; set; }

    public string ClassKey { get; set; } = string.Empty;

    public string DisplayName { get; set; } = string.Empty;

    public string Stage { get; set; } = "junior_middle_school";

    public string Grade { get; set; } = string.Empty;

    public string SchoolYear { get; set; } = string.Empty;

    public bool SyntheticFixture { get; set; }

    public bool ContainsStudentPii { get; set; }

    public string AnonymizationStatus { get; set; } = "synthetic";

    public string Metadata { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class Assessment
{
    public Guid Id { get; set; }

    public string AssessmentKey { get; set; } = string.Empty;

    public string Title { get; set; } = string.Empty;

    public string Subject { get; set; } = "physics";

    public string Stage { get; set; } = "junior_middle_school";

    public string Grade { get; set; } = string.Empty;

    public string Status { get; set; } = AssessmentStatuses.Draft;

    public string Mode { get; set; } = "draft_test";

    public bool ProductionEligible { get; set; }

    public bool SyntheticFixture { get; set; }

    public bool ContainsStudentPii { get; set; }

    public string AnonymizationStatus { get; set; } = "synthetic";

    public bool StudentPortalEnabled { get; set; }

    public string Blueprint { get; set; } = "{}";

    public string Metadata { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class AssessmentEnrollment
{
    public Guid Id { get; set; }

    public Guid AssessmentId { get; set; }

    public Guid ClassGroupId { get; set; }

    public Guid StudentId { get; set; }

    public string SeatNo { get; set; } = string.Empty;

    public string Status { get; set; } = "enrolled";

    public bool SyntheticFixture { get; set; }

    public bool ContainsStudentPii { get; set; }

    public string ScoreSummary { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class ScoreImportTemplate
{
    public Guid Id { get; set; }

    public string TemplateKey { get; set; } = string.Empty;

    public string DisplayName { get; set; } = string.Empty;

    public int Version { get; set; } = 1;

    public string Mode { get; set; } = "draft_test";

    public bool ProductionEligible { get; set; }

    public bool SyntheticFixture { get; set; }

    public string ReviewStatus { get; set; } = DomainAssetReviewStatuses.PendingReview;

    public string FieldMapping { get; set; } = "{}";

    public string MigrationPolicy { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class ScoreImportBatch
{
    public Guid Id { get; set; }

    public Guid AssessmentId { get; set; }

    public Guid TemplateId { get; set; }

    public string Mode { get; set; } = "draft_test";

    public string Status { get; set; } = ScoreImportStatuses.Draft;

    public string SourceFileName { get; set; } = string.Empty;

    public bool ProductionEligible { get; set; }

    public bool SyntheticFixture { get; set; }

    public bool ContainsStudentPii { get; set; }

    public int RowCount { get; set; }

    public int ImportedCount { get; set; }

    public int ErrorCount { get; set; }

    public string ErrorSummary { get; set; } = "[]";

    public string Metadata { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class ScoreRecord
{
    public Guid Id { get; set; }

    public Guid AssessmentId { get; set; }

    public Guid StudentId { get; set; }

    public Guid ImportBatchId { get; set; }

    public string StudentKey { get; set; } = string.Empty;

    public decimal? TotalScore { get; set; }

    public decimal? MaxScore { get; set; }

    public string Status { get; set; } = "imported";

    public bool SyntheticFixture { get; set; }

    public bool ContainsStudentPii { get; set; }

    public string RawRow { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class ItemScore
{
    public Guid Id { get; set; }

    public Guid ScoreRecordId { get; set; }

    public string QuestionNo { get; set; } = string.Empty;

    public string FieldName { get; set; } = string.Empty;

    public decimal Score { get; set; }

    public decimal MaxScore { get; set; }

    public string Metadata { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class ImportJob
{
    public Guid Id { get; set; }

    public Guid InputFileAssetId { get; set; }

    public string Status { get; set; } = JobStatuses.Queued;

    public string IdempotencyKey { get; set; } = string.Empty;

    public string? LockedBy { get; set; }

    public DateTimeOffset? LockedUntil { get; set; }

    public int AttemptCount { get; set; }

    public int MaxAttempts { get; set; } = 3;

    public string? LastErrorCode { get; set; }

    public string? LastErrorMessage { get; set; }

    public string Input { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? StartedAt { get; set; }

    public DateTimeOffset? FinishedAt { get; set; }
}

public sealed class AIJob
{
    public Guid Id { get; set; }

    public string JobType { get; set; } = string.Empty;

    public string Status { get; set; } = JobStatuses.Queued;

    public string IdempotencyKey { get; set; } = string.Empty;

    public string? ModelRoute { get; set; }

    public string? ModelProvider { get; set; }

    public string? ModelName { get; set; }

    public string? RoutingVersion { get; set; }

    public string? PromptVersion { get; set; }

    public string? SchemaVersion { get; set; }

    public string? InputHash { get; set; }

    public decimal? EstimatedCost { get; set; }

    public decimal? ActualCost { get; set; }

    public double? Confidence { get; set; }

    public int? InputTokens { get; set; }

    public int? OutputTokens { get; set; }

    public int? CachedTokens { get; set; }

    public int? LatencyMs { get; set; }

    public string ReviewStatus { get; set; } = ReviewStatuses.Open;

    public bool TeacherModified { get; set; }

    public string Input { get; set; } = "{}";

    public string Result { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? FinishedAt { get; set; }
}

public sealed class ReviewQueueItem
{
    public Guid Id { get; set; }

    public string ReviewType { get; set; } = string.Empty;

    public string Status { get; set; } = ReviewStatuses.Open;

    public string Payload { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? ResolvedAt { get; set; }
}

public sealed class BackupJob
{
    public Guid Id { get; set; }

    public string Status { get; set; } = BackupStatuses.Queued;

    public string? ManifestPath { get; set; }

    public string? ManifestSha256 { get; set; }

    public string? ErrorMessage { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? FinishedAt { get; set; }
}

public sealed class QuestionItem
{
    public Guid Id { get; set; }

    public string Subject { get; set; } = "physics";

    public string Stage { get; set; } = "junior_middle_school";

    public string? Grade { get; set; }

    public string? QuestionType { get; set; }

    public decimal? DefaultScore { get; set; }

    public double? DifficultyEstimated { get; set; }

    public double? DifficultyObserved { get; set; }

    public string Status { get; set; } = QuestionStatuses.Draft;

    public Guid? PrimaryKnowledgeId { get; set; }

    public string Blocks { get; set; } = "[]";

    public string CustomFields { get; set; } = "{}";

    public string QualitySignals { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class KnowledgeNode
{
    public Guid Id { get; set; }

    public string Subject { get; set; } = "physics";

    public string Stage { get; set; } = "junior_middle_school";

    public string Code { get; set; } = string.Empty;

    public string Title { get; set; } = string.Empty;

    public string NodeType { get; set; } = "concept";

    public int Level { get; set; } = 1;

    public string Status { get; set; } = KnowledgeStatuses.Draft;

    public int Version { get; set; } = 1;

    public Guid? ParentId { get; set; }

    public string Metadata { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class KnowledgeEdge
{
    public Guid Id { get; set; }

    public Guid SourceNodeId { get; set; }

    public Guid TargetNodeId { get; set; }

    public string EdgeType { get; set; } = KnowledgeEdgeTypes.ParentChild;

    public int Version { get; set; } = 1;

    public string Metadata { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class KnowledgeMapping
{
    public Guid Id { get; set; }

    public Guid QuestionItemId { get; set; }

    public Guid KnowledgeNodeId { get; set; }

    public string MappingSource { get; set; } = KnowledgeMappingSources.Manual;

    public bool IsPrimary { get; set; }

    public decimal? Confidence { get; set; }

    public int Version { get; set; } = 1;

    public string Evidence { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class DomainAssetVersion
{
    public Guid Id { get; set; }

    public string AssetType { get; set; } = string.Empty;

    public string StableId { get; set; } = string.Empty;

    public int Version { get; set; } = 1;

    public string DisplayName { get; set; } = string.Empty;

    public string Status { get; set; } = DomainAssetStatuses.Draft;

    public string Authority { get; set; } = DomainAssetAuthorities.Bootstrap;

    public string EffectiveScope { get; set; } = "{}";

    public string SourceEvidence { get; set; } = "{}";

    public string Metadata { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class DomainAssetMapping
{
    public Guid Id { get; set; }

    public Guid SourceAssetVersionId { get; set; }

    public Guid TargetAssetVersionId { get; set; }

    public string MappingType { get; set; } = DomainAssetMappingTypes.Equivalent;

    public decimal Confidence { get; set; }

    public string ReviewStatus { get; set; } = DomainAssetReviewStatuses.PendingReview;

    public bool AutoApplied { get; set; }

    public string Evidence { get; set; } = "{}";

    public Guid? MigrationId { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? ReviewedAt { get; set; }
}

public sealed class DomainAssetMigration
{
    public Guid Id { get; set; }

    public string MigrationKey { get; set; } = string.Empty;

    public string Status { get; set; } = DomainAssetMigrationStatuses.Draft;

    public Guid? FromAssetVersionId { get; set; }

    public Guid? ToAssetVersionId { get; set; }

    public string ImpactReport { get; set; } = "{}";

    public string RollbackSnapshot { get; set; } = "{}";

    public string CreatedBy { get; set; } = "system";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? AppliedAt { get; set; }

    public DateTimeOffset? RolledBackAt { get; set; }
}

public sealed class QuestionBlock
{
    public Guid Id { get; set; }

    public Guid QuestionItemId { get; set; }

    public string BlockType { get; set; } = "text";

    public int SortOrder { get; set; }

    public string Content { get; set; } = "{}";

    public Guid? SourceRegionId { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class QuestionAsset
{
    public Guid Id { get; set; }

    public Guid QuestionItemId { get; set; }

    public Guid? FileAssetId { get; set; }

    public Guid? SourceRegionId { get; set; }

    public string AssetType { get; set; } = "image";

    public string Purpose { get; set; } = "question_content";

    public string Metadata { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class PaperBasket
{
    public Guid Id { get; set; }

    public string Title { get; set; } = string.Empty;

    public string Subject { get; set; } = "physics";

    public string Stage { get; set; } = "junior_middle_school";

    public string? Grade { get; set; }

    public string Status { get; set; } = "draft";

    public string KnowledgeVersionStatus { get; set; } = KnowledgeStatuses.Active;

    public int KnowledgeVersion { get; set; } = 1;

    public string Structure { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class PaperBasketItem
{
    public Guid Id { get; set; }

    public Guid PaperBasketId { get; set; }

    public Guid QuestionItemId { get; set; }

    public int SectionNo { get; set; } = 1;

    public int QuestionNo { get; set; } = 1;

    public string? SubQuestionNo { get; set; }

    public decimal Score { get; set; }

    public int SortOrder { get; set; }

    public string KnowledgeVersionStatus { get; set; } = KnowledgeStatuses.Active;

    public int KnowledgeVersion { get; set; } = 1;

    public string Snapshot { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class CutCandidate
{
    public Guid Id { get; set; }

    public Guid SourceDocumentId { get; set; }

    public Guid? SourceRegionId { get; set; }

    public Guid? SuggestedQuestionItemId { get; set; }

    public string Status { get; set; } = CutCandidateStatuses.PendingReview;

    public decimal Confidence { get; set; }

    public string SegmentType { get; set; } = "question_stem";

    public int SequenceNo { get; set; }

    public string CandidatePayload { get; set; } = "{}";

    public string FailureReason { get; set; } = string.Empty;

    public string TakeoverAction { get; set; } = "manual_review";

    public string Metadata { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}
