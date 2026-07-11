using System.Text.Json;
using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Application.Workflows.Contracts;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.Infrastructure.Json;

namespace K12QuestionGraph.Api.Papers;

public sealed record PaperBasketCreateRequest(
    string Title,
    string Subject,
    string Stage,
    string? Grade,
    string? KnowledgeVersionStatus,
    int? KnowledgeVersion,
    IReadOnlyList<PaperBasketCreateItem> Items);

public sealed record PaperBasketCreateItem(
    Guid QuestionItemId,
    int SectionNo,
    int QuestionNo,
    string? SubQuestionNo,
    decimal Score,
    int? SortOrder);

public sealed record PaperBasketResponse(
    Guid Id,
    string Title,
    string Subject,
    string Stage,
    string? Grade,
    string Status,
    string KnowledgeVersionStatus,
    int KnowledgeVersion,
    JsonElement Structure,
    IReadOnlyList<PaperBasketItemResponse> Items,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt)
{
    public static PaperBasketResponse From(PaperBasket basket, IReadOnlyList<PaperBasketItem> items)
    {
        return new PaperBasketResponse(
            basket.Id,
            basket.Title,
            basket.Subject,
            basket.Stage,
            basket.Grade,
            basket.Status,
            basket.KnowledgeVersionStatus,
            basket.KnowledgeVersion,
            JsonHelpers.ParseJsonElement(basket.Structure),
            items.Select(PaperBasketItemResponse.From).ToArray(),
            basket.CreatedAt,
            basket.UpdatedAt);
    }
}

public sealed record PaperBasketItemResponse(
    Guid Id,
    Guid QuestionItemId,
    int SectionNo,
    int QuestionNo,
    string? SubQuestionNo,
    decimal Score,
    int SortOrder,
    string KnowledgeVersionStatus,
    int KnowledgeVersion,
    JsonElement Snapshot)
{
    public static PaperBasketItemResponse From(PaperBasketItem item)
    {
        return new PaperBasketItemResponse(
            item.Id,
            item.QuestionItemId,
            item.SectionNo,
            item.QuestionNo,
            item.SubQuestionNo,
            item.Score,
            item.SortOrder,
            item.KnowledgeVersionStatus,
            item.KnowledgeVersion,
            JsonHelpers.ParseJsonElement(item.Snapshot));
    }
}

public sealed record PaperExportPreflightRequest(string ExportFormat);

public sealed record PaperExportPreflightResponse(
    Guid PaperBasketId,
    string Title,
    string ExportFormat,
    string Status,
    bool ProductionEligible,
    int ItemCount,
    IReadOnlyList<PaperExportPreflightItemResponse> Items,
    IReadOnlyDictionary<string, int> IssueCounts,
    PaperExportPreflightSummaryResponse Summary,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail)
{
    public static PaperExportPreflightResponse From(PaperExportPreflightServiceResult result)
    {
        return new PaperExportPreflightResponse(
            result.PaperBasketId,
            result.Title,
            result.ExportFormat,
            result.Status,
            result.ProductionEligible,
            result.ItemCount,
            result.Items.Select(PaperExportPreflightItemResponse.From).ToArray(),
            result.IssueCounts,
            PaperExportPreflightSummaryResponse.From(result.Summary),
            result.TeacherMessage,
            result.AuditTrail);
    }
}

public sealed record PaperExportPreflightSummaryResponse(
    int ImageReadyCount,
    int FormulaReadyCount,
    int TableReadyCount,
    int AnswerReadyCount,
    int SolutionReadyCount,
    int AuthorizedSourceCount,
    int ActiveKnowledgeVersionCount)
{
    public static PaperExportPreflightSummaryResponse From(PaperExportPreflightSummary summary)
    {
        return new PaperExportPreflightSummaryResponse(
            summary.ImageReadyCount,
            summary.FormulaReadyCount,
            summary.TableReadyCount,
            summary.AnswerReadyCount,
            summary.SolutionReadyCount,
            summary.AuthorizedSourceCount,
            summary.ActiveKnowledgeVersionCount);
    }
}

public sealed record PaperExportPreflightItemResponse(
    Guid QuestionItemId,
    int QuestionNo,
    string? SubQuestionNo,
    decimal Score,
    string KnowledgeVersionStatus,
    int KnowledgeVersion,
    bool HasImage,
    bool HasFormula,
    bool HasTable,
    bool HasAnswer,
    bool HasSolution,
    string SourceAuthorizationStatus,
    bool HasKnowledgeVersionReference,
    IReadOnlyList<PaperExportPreflightIssueResponse> Issues)
{
    public static PaperExportPreflightItemResponse From(PaperExportPreflightItemServiceResult item)
    {
        return new PaperExportPreflightItemResponse(
            item.QuestionItemId,
            item.QuestionNo,
            item.SubQuestionNo,
            item.Score,
            item.KnowledgeVersionStatus,
            item.KnowledgeVersion,
            item.HasImage,
            item.HasFormula,
            item.HasTable,
            item.HasAnswer,
            item.HasSolution,
            item.SourceAuthorizationStatus,
            item.HasKnowledgeVersionReference,
            item.Issues.Select(PaperExportPreflightIssueResponse.From).ToArray());
    }
}

public sealed record PaperExportPreflightIssueResponse(
    string Code,
    string Severity,
    string Message)
{
    public static PaperExportPreflightIssueResponse From(PaperExportPreflightIssueServiceItem issue)
    {
        return new PaperExportPreflightIssueResponse(issue.Code, issue.Severity, issue.Message);
    }
}

public sealed record PaperRequestParseRequest(
    string TeacherRequest,
    string? TextbookVersion);

public sealed record PaperRequestParseResponse(
    string Mode,
    bool ProductionEligible,
    bool AllowRealModelCalls,
    string SchemaVersion,
    string PromptVersion,
    string SystemUnderstanding,
    string PaperType,
    string Subject,
    string Grade,
    string? TextbookVersion,
    IReadOnlyList<string> Scope,
    int TotalScore,
    string DifficultyTarget,
    IReadOnlyList<PaperQuestionTypePlan> QuestionTypePlan,
    IReadOnlyList<PaperBlueprintRow> Blueprint,
    PaperRequestConstraints Constraints,
    IReadOnlyList<string> ReviewQuestions);

public sealed record PaperQuestionTypePlan(
    string QuestionType,
    int Count,
    decimal Score);

public sealed record PaperBlueprintRow(
    string QuestionType,
    int Count,
    decimal Score,
    IReadOnlyList<string> Scope,
    string AssetStatus,
    string ReviewStatus);

public sealed record PaperRequestConstraints(
    string KnowledgeStatus,
    IReadOnlyList<string> SourceTypes,
    bool ReviewRequired,
    bool BlocksProductionPaper);

public sealed record PaperBlueprintReviewCreateRequest(
    string TeacherRequest,
    string? TextbookVersion);

public sealed record PaperBlueprintReviewResponse(
    Guid Id,
    string Status,
    string Mode,
    bool ProductionEligible,
    bool AllowRealModelCalls,
    string RequestText,
    string Subject,
    string Grade,
    string? TextbookVersion,
    IReadOnlyList<string> Scope,
    int TotalScore,
    string DifficultyTarget,
    IReadOnlyList<PaperBlueprintRow> Blueprint,
    PaperRequestConstraints Constraints,
    IReadOnlyList<string> ReviewQuestions,
    bool MustConfirmBeforeTakingQuestions,
    bool OpaqueGenerationAllowed,
    Guid? ConfirmedPaperBasketId,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt)
{
    public static PaperBlueprintReviewResponse From(PaperBlueprintReviewServiceResult result)
    {
        return new PaperBlueprintReviewResponse(
            result.Id,
            result.Status,
            result.Mode,
            result.ProductionEligible,
            result.AllowRealModelCalls,
            result.RequestText,
            result.Subject,
            result.Grade,
            result.TextbookVersion,
            result.Scope,
            result.TotalScore,
            result.DifficultyTarget,
            result.Blueprint.Select(x => new PaperBlueprintRow(x.QuestionType, x.Count, x.Score, x.Scope, x.AssetStatus, x.ReviewStatus)).ToArray(),
            new PaperRequestConstraints(
                result.Constraints.KnowledgeStatus,
                result.Constraints.SourceTypes,
                result.Constraints.ReviewRequired,
                result.Constraints.BlocksProductionPaper),
            result.ReviewQuestions,
            result.MustConfirmBeforeTakingQuestions,
            result.OpaqueGenerationAllowed,
            result.ConfirmedPaperBasketId,
            result.CreatedAt,
            result.UpdatedAt);
    }
}

public sealed record PaperBlueprintConfirmRequest(string TeacherConfirmedBy);

public sealed record PaperBlueprintConfirmResponse(
    Guid Id,
    string Status,
    bool Confirmed,
    Guid? PaperBasketId,
    int SelectedQuestionCount,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail)
{
    public static PaperBlueprintConfirmResponse From(PaperBlueprintConfirmServiceResult result)
    {
        return new PaperBlueprintConfirmResponse(
            result.Id,
            result.Status,
            result.Confirmed,
            result.PaperBasketId,
            result.SelectedQuestionCount,
            result.TeacherMessage,
            result.AuditTrail);
    }
}

public sealed record PaperQuestionReplacementRequest(PaperDraftQuestion CurrentQuestion);

public sealed record PaperDraftQuestion(
    string Id,
    string StemPreview,
    string QuestionType,
    decimal Score,
    double? DifficultyEstimated,
    string PrimaryKnowledgeId,
    string PrimaryKnowledgeTitle,
    string SourceType,
    string RecentUseStatus);

public sealed record PaperQuestionReplacementResponse(
    string Mode,
    bool ProductionEligible,
    bool AllowRealModelCalls,
    string Action,
    string Reason,
    PaperQuestionReplacementConstraints Constraints,
    PaperDraftQuestion Replacement,
    PaperQuestionUndoSnapshot Undo,
    IReadOnlyList<string> AuditTrail);

public sealed record PaperQuestionReplacementConstraints(
    bool SameKnowledge,
    bool SameQuestionType,
    bool SimilarDifficulty,
    bool SameScore,
    bool ExcludeCurrentPaperDuplicates,
    bool ExcludeRecentlyUsed,
    string KnowledgeStatus,
    bool BlocksProductionPaper);

public sealed record PaperQuestionUndoSnapshot(
    string UndoToken,
    PaperDraftQuestion BeforeQuestion,
    PaperDraftQuestion AfterQuestion,
    string RevertAction);

public sealed record KnowledgeVersionExplanationRequest(
    string ArtifactType,
    string ArtifactId,
    string HistoricalKnowledgeStableId,
    string HistoricalKnowledgeVersion,
    string CurrentKnowledgeVersion,
    string? MappingType,
    IReadOnlyList<string> CurrentKnowledgeStableIds,
    bool AffectsHistoricalAnalysis);

public sealed record KnowledgeVersionExplanationResponse(
    string Mode,
    bool ProductionEligible,
    bool ReadOnly,
    bool RealStudentDataUsed,
    bool WritesProductionHistory,
    string ArtifactType,
    string ArtifactId,
    string HistoricalKnowledgeStableId,
    string HistoricalKnowledgeVersion,
    string CurrentKnowledgeVersion,
    string MappingType,
    IReadOnlyList<string> CurrentKnowledgeStableIds,
    bool FrozenHistoricalView,
    bool CurrentVersionDifferent,
    bool AffectsHistoricalAnalysis,
    string ExplanationText,
    string TeacherVisibleSummary,
    IReadOnlyList<string> AuditTrail);
