namespace K12QuestionGraph.Api.Application.Workflows.Contracts;

public static class WorkflowTypes
{
    public const string Import = "import";
    public const string Review = "review";
    public const string Tagging = "tagging";
    public const string Paper = "paper";
    public const string Export = "export";
    public const string Score = "score";
    public const string Analysis = "analysis";
}

public static class WorkflowStatuses
{
    public const string Queued = "queued";
    public const string Running = "running";
    public const string PendingReview = "pending_review";
    public const string Succeeded = "succeeded";
    public const string Failed = "failed";
    public const string Cancelled = "cancelled";
    public const string RollbackReady = "rollback_ready";
    public const string RolledBack = "rolled_back";
}

public static class WorkflowErrorCodes
{
    public const string ValidationFailed = "validation_failed";
    public const string SourceNotFound = "source_not_found";
    public const string SourceRegionMissing = "source_region_missing";
    public const string ImportJobNotFound = "import_job_not_found";
    public const string InvalidStatusTransition = "invalid_status_transition";
    public const string PermissionDenied = "permission_denied";
    public const string ExternalDependencyFailed = "external_dependency_failed";
    public const string RollbackSnapshotMissing = "rollback_snapshot_missing";
    public const string InternalError = "internal_error";
}

public sealed record WorkflowRollbackReference(
    string SnapshotId,
    string SnapshotType,
    string? ManifestPath,
    DateTimeOffset CreatedAt,
    string CreatedBy,
    string? RestoreCommand);

public sealed record WorkflowError(
    string Code,
    string Message,
    bool Retryable,
    string? EvidencePath);

public sealed record WorkflowStatusEnvelope(
    string WorkflowType,
    string Status,
    string CorrelationId,
    DateTimeOffset UpdatedAt,
    WorkflowRollbackReference? Rollback,
    WorkflowError? Error);

public sealed record ImportWorkflowDto(
    Guid ImportJobId,
    Guid InputFileAssetId,
    string SourceType,
    string SourceTitle,
    WorkflowStatusEnvelope State);

public sealed record ReviewWorkflowDto(
    Guid SourceDocumentId,
    int PendingQuestionCount,
    int PendingRegionCount,
    WorkflowStatusEnvelope State);

public sealed record TaggingWorkflowDto(
    Guid QuestionId,
    Guid? PrimaryKnowledgeId,
    int SuggestedTagCount,
    WorkflowStatusEnvelope State);

public sealed record PaperWorkflowDto(
    string RequestText,
    string BlueprintVersion,
    int QuestionCount,
    int TotalScore,
    WorkflowStatusEnvelope State);

public sealed record ExportWorkflowDto(
    Guid PaperId,
    string ExportFormat,
    string ArtifactPath,
    WorkflowStatusEnvelope State);

public sealed record ScoreWorkflowDto(
    Guid AssessmentId,
    string TemplateVersion,
    int ImportedRowCount,
    int ExceptionRowCount,
    WorkflowStatusEnvelope State);

public sealed record AnalysisWorkflowDto(
    Guid AssessmentId,
    string AnalysisVersion,
    int WeakKnowledgePointCount,
    WorkflowStatusEnvelope State);
