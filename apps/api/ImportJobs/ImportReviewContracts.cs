using System.Text.Json;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.FileStore;
using K12QuestionGraph.Api.Infrastructure.Json;

namespace K12QuestionGraph.Api.ImportJobs;

public sealed record SourceRegionCreateRequest(
    int PageNumber,
    decimal X,
    decimal Y,
    decimal Width,
    decimal Height,
    string CoordinateUnit,
    string? ScreenshotRelativePath,
    string? RegionType);

public sealed record SourceRegionUpdateRequest(
    int? PageNumber,
    decimal? X,
    decimal? Y,
    decimal? Width,
    decimal? Height,
    string? CoordinateUnit,
    string? ScreenshotRelativePath,
    bool? ClearScreenshot,
    string? RegionType,
    string ReviewedBy,
    string Reason);

public sealed record SourceRegionUpdateResponse(SourceRegionResponse Region, Guid AuditId);

public sealed record SourceRegionResponse(
    Guid Id,
    Guid SourceDocumentId,
    int PageNumber,
    decimal X,
    decimal Y,
    decimal Width,
    decimal Height,
    string CoordinateUnit,
    string? ScreenshotRelativePath,
    string? ScreenshotUrl,
    string PageScreenshotUrl,
    string RegionType)
{
    public static SourceRegionResponse From(SourceRegion region)
    {
        var screenshotUrl = string.IsNullOrWhiteSpace(region.ScreenshotRelativePath)
            ? null
            : $"/source-regions/{region.Id}/screenshot";
        return new SourceRegionResponse(
            region.Id,
            region.SourceDocumentId,
            region.PageNumber,
            region.X,
            region.Y,
            region.Width,
            region.Height,
            region.CoordinateUnit,
            region.ScreenshotRelativePath,
            screenshotUrl,
            $"/source-regions/{region.Id}/page-screenshot",
            region.RegionType);
    }
}

public sealed record SourcePreviewPageResponse(int PageNumber, IReadOnlyList<SourceRegionResponse> Regions);

public sealed record SourceDocumentPreviewResponse(Guid SourceDocumentId, IReadOnlyList<SourcePreviewPageResponse> Pages);

public sealed record SourceDocumentQualityReportResponse(
    Guid SourceDocumentId,
    string SourceTitle,
    string SourceType,
    string Region,
    int? Year,
    string MaterialBatchKey,
    string ClosureStatus,
    bool FullClosureAllowed,
    SourceDocumentQualityMetricsResponse Metrics,
    IReadOnlyList<int> QuestionNumbers,
    IReadOnlyList<int> MissingQuestionNumbers,
    IReadOnlyList<Guid> MissingLinkedSourceRegionIds,
    IReadOnlyList<string> PendingReviewTypes,
    IReadOnlyList<string> Gaps,
    string ExternalAiPolicy,
    string RollbackSql,
    string SummaryChinese);

public sealed record SourceDocumentQualityMetricsResponse(
    int QuestionCount,
    int QuestionNumberCount,
    int AnswerCoveredCount,
    int SolutionCoveredCount,
    int SourceRegionCount,
    int LinkedSourceRegionCount,
    int LinkedSourceScreenshotCount,
    int MissingLinkedSourceScreenshotCount,
    int ImageAssetCount,
    int ImageMatchedQuestionCount,
    int TableBlockCount,
    int FormulaBlockCount,
    int PendingManualItemCount,
    int NoiseRetainedBlockCount,
    int ExternalAiCallCount);

public sealed record SourceMaterialListResponse(
    string Mode,
    IReadOnlyList<SourceMaterialResponse> Items);

public sealed record SourceDocumentAuthorizationUpdateRequest(
    string? LicenseOrPermission,
    bool? SharingAllowed,
    bool? ContainsStudentPii,
    string? AnonymizationStatus,
    bool? ExternalAiAllowed,
    bool? MayUseForKnowledgeExtraction,
    bool? MayUseForExamPointExtraction,
    bool? MayUseForTrendAnalysis,
    string ReviewedBy,
    string Reason);

public sealed record SourceDocumentAuthorizationUpdateResponse(
    SourceMaterialResponse SourceDocument,
    Guid AuditId);

public sealed record SourceMaterialResponse(
    Guid Id,
    Guid FileAssetId,
    string SourceType,
    string SourceTitle,
    string Region,
    int? Year,
    string GradeOrScope,
    string EditionOrVersion,
    string MaterialBatchKey,
    string LicenseOrPermission,
    bool ContainsStudentPii,
    string AnonymizationStatus,
    bool ExternalAiAllowed,
    bool MayUseForKnowledgeExtraction,
    bool MayUseForExamPointExtraction,
    bool MayUseForTrendAnalysis,
    string OriginalFileName,
    string RelativePath,
    string Sha256,
    long SizeBytes)
{
    public static SourceMaterialResponse From(SourceDocument document, FileAsset file)
    {
        return new SourceMaterialResponse(
            document.Id,
            document.FileAssetId,
            document.SourceType,
            document.SourceTitle,
            document.Region,
            document.Year,
            document.GradeOrScope,
            document.EditionOrVersion,
            document.MaterialBatchKey,
            document.LicenseOrPermission,
            document.ContainsStudentPii,
            document.AnonymizationStatus,
            document.ExternalAiAllowed,
            document.MayUseForKnowledgeExtraction,
            document.MayUseForExamPointExtraction,
            document.MayUseForTrendAnalysis,
            file.OriginalFileName,
            file.RelativePath,
            file.Sha256,
            file.SizeBytes);
    }
}

public sealed record CutCandidateGenerationResponse(
    Guid SourceDocumentId,
    int GeneratedCount,
    int LowConfidenceReviewQueueCount,
    decimal LowConfidenceThreshold);

public sealed record ImportWorkerProcessingSummary(
    string AdapterName,
    int SourceRegionCount,
    int CutCandidateCount,
    int LowConfidenceReviewQueueCount)
{
    public static ImportWorkerProcessingSummary Empty { get; } = new(
        AdapterName: string.Empty,
        SourceRegionCount: 0,
        CutCandidateCount: 0,
        LowConfidenceReviewQueueCount: 0);
}

public sealed record CutCandidateListResponse(
    Guid SourceDocumentId,
    IReadOnlyList<CutCandidateResponse> Items);

public sealed record CutCandidateResponse(
    Guid Id,
    Guid SourceDocumentId,
    Guid? SourceRegionId,
    Guid? SuggestedQuestionItemId,
    string Status,
    decimal Confidence,
    string SegmentType,
    int SequenceNo,
    JsonElement CandidatePayload,
    string FailureReason,
    string TakeoverAction,
    JsonElement Metadata)
{
    public static CutCandidateResponse From(CutCandidate row)
    {
        return new CutCandidateResponse(
            row.Id,
            row.SourceDocumentId,
            row.SourceRegionId,
            row.SuggestedQuestionItemId,
            row.Status,
            row.Confidence,
            row.SegmentType,
            row.SequenceNo,
            JsonHelpers.ParseJsonElement(row.CandidatePayload),
            row.FailureReason,
            row.TakeoverAction,
            JsonHelpers.ParseJsonElement(row.Metadata));
    }
}

public sealed record ReviewQueueListResponse(
    IReadOnlyList<ReviewQueueItemResponse> Items,
    int TotalCount);

public sealed record ReviewQueueItemResponse(
    Guid Id,
    string ReviewType,
    string Status,
    string RiskLevel,
    string RequiredAction,
    IReadOnlyList<string> RequiredActions,
    decimal? Confidence,
    string? Reason,
    JsonElement Payload,
    DateTimeOffset CreatedAt,
    DateTimeOffset? ResolvedAt)
{
    public static ReviewQueueItemResponse From(ReviewQueueItem row)
    {
        var payload = JsonHelpers.ParseJsonElement(row.Payload);
        return new ReviewQueueItemResponse(
            row.Id,
            row.ReviewType,
            row.Status,
            ReviewQueuePayloadHelpers.ResolveRiskLevel(payload),
            ReviewQueuePayloadHelpers.ResolveRequiredAction(payload),
            ReviewQueuePayloadHelpers.ResolveRequiredActions(payload),
            ReviewQueuePayloadHelpers.ResolveConfidence(payload),
            ReviewQueuePayloadHelpers.ResolveReason(payload),
            payload,
            row.CreatedAt,
            row.ResolvedAt);
    }
}

public sealed record ReviewQueueBatchResolveRequest(
    IReadOnlyList<Guid> ItemIds,
    string ReviewedBy,
    string Decision,
    string Reason);

public sealed record ReviewQueueBatchResolveResponse(
    IReadOnlyList<Guid> ResolvedIds,
    IReadOnlyList<Guid> SkippedHighRiskIds);

public sealed record ReviewQueueResolveRequest(
    string ReviewedBy,
    string Decision,
    string Reason,
    ReviewQueueRevisionRequest? Revision);

public sealed record ReviewQueueReopenRequest(
    string ReviewedBy,
    string Reason);

public sealed record ReviewWorkbenchActionRequest(
    string Action,
    Guid SourceDocumentId,
    IReadOnlyList<Guid> CandidateIds,
    string? AssetLabel,
    string? ReviewedBy,
    string? Reason);

public sealed record ReviewWorkbenchActionResponse(
    string Action,
    Guid SourceDocumentId,
    IReadOnlyList<Guid> TouchedIds,
    IReadOnlyList<Guid> CreatedCandidateIds,
    IReadOnlyList<Guid> SkippedIds,
    Guid? CreatedQuestionId);
