using K12QuestionGraph.Api.Application.Workflows.Contracts;
using K12QuestionGraph.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace K12QuestionGraph.Api.Application.Workflows;

public interface IPaperWorkflowService
{
    Task<PaperWorkflowDto> BuildDraftAsync(string requestText, CancellationToken cancellationToken);
    PaperRequestParseServiceResult ParsePaperRequest(string teacherRequest, string? textbookVersion);
    PaperReplaceServiceResult ReplaceQuestion(PaperReplaceRequest request);
    KnowledgeVersionExplanationServiceResult ResolveKnowledgeVersionExplanation(KnowledgeVersionExplanationServiceRequest request);
}

public sealed class PaperWorkflowService(KqgDbContext dbContext) : IPaperWorkflowService
{
    public async Task<PaperWorkflowDto> BuildDraftAsync(string requestText, CancellationToken cancellationToken)
    {
        var normalized = string.IsNullOrWhiteSpace(requestText) ? "默认组卷请求" : requestText.Trim();

        var questionCount = await dbContext.QuestionItems.AsNoTracking().CountAsync(cancellationToken);
        var useCount = Math.Max(1, Math.Min(questionCount, 10));

        return new PaperWorkflowDto(
            normalized,
            "paper-blueprint-v1",
            useCount,
            useCount * 3,
            new WorkflowStatusEnvelope(
                WorkflowTypes.Paper,
                WorkflowStatuses.PendingReview,
                $"paper:{DateTimeOffset.UtcNow:yyyyMMddHHmmss}",
                DateTimeOffset.UtcNow,
                Rollback: null,
                Error: null));
    }

    public PaperRequestParseServiceResult ParsePaperRequest(string teacherRequest, string? textbookVersion)
    {
        var normalized = teacherRequest.Trim();
        var scope = InferPaperRequestScope(normalized);
        var questionTypePlan = new[]
        {
            new PaperQuestionTypePlanServiceItem("single_choice", 5, 15m),
            new PaperQuestionTypePlanServiceItem("calculation", 2, 10m),
            new PaperQuestionTypePlanServiceItem("experiment", 1, 5m)
        };
        var blueprint = questionTypePlan.Select(item => new PaperBlueprintServiceItem(
            item.QuestionType,
            item.Count,
            item.Score,
            scope,
            "draft_dynamic_asset",
            "pending_review")).ToArray();

        return new PaperRequestParseServiceResult(
            "draft_test",
            false,
            false,
            "schemas/ai/natural_language_paper_request.schema.json",
            "prompt.e002.draft-test.v1",
            $"按初中物理 draft 动态资产生成组卷理解：{normalized}",
            normalized.Contains("复习", StringComparison.OrdinalIgnoreCase) ? "review_practice" : "unit_practice",
            "physics",
            normalized.Contains("九") ? "grade_9" : "grade_8",
            textbookVersion,
            scope,
            30,
            normalized.Contains("偏难") ? "medium_hard" : "medium",
            questionTypePlan,
            blueprint,
            new PaperRequestConstraintsServiceItem("draft", ["synthetic"], true, true),
            [
                "是否需要限定教材版本或章节范围？",
                "是否需要排除最近已练过的题目？",
                "是否确认使用 draft_test 细目表继续生成试卷草稿？"
            ]);
    }

    public PaperReplaceServiceResult ReplaceQuestion(PaperReplaceRequest request)
    {
        var current = request.CurrentQuestion;
        var constraints = new PaperQuestionReplacementConstraintsServiceItem(
            true, true, true, true, true, true, "draft", true);
        var replacement = new PaperDraftQuestionServiceItem(
            "draft-replacement-" + current.Id,
            BuildReplacementPreview(current.StemPreview),
            current.QuestionType,
            current.Score,
            ClampDifficulty((current.DifficultyEstimated ?? 0.6) + 0.03),
            current.PrimaryKnowledgeId,
            current.PrimaryKnowledgeTitle,
            "synthetic",
            "not_recently_used");
        var undo = new PaperQuestionUndoSnapshotServiceItem(
            "undo-" + Guid.NewGuid().ToString("N"),
            current,
            replacement,
            "restore_before_question");

        return new PaperReplaceServiceResult(
            "draft_test",
            false,
            false,
            "replace_question",
            "same_knowledge_type_difficulty_score",
            constraints,
            replacement,
            undo,
            [
                "kept primary knowledge constraint",
                "kept question type constraint",
                "kept score constraint",
                "kept draft_test non-production boundary"
            ]);
    }

    public KnowledgeVersionExplanationServiceResult ResolveKnowledgeVersionExplanation(KnowledgeVersionExplanationServiceRequest request)
    {
        var currentTargets = request.CurrentKnowledgeStableIds
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Select(id => id.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var artifactType = NormalizeToken(request.ArtifactType, "question");
        var mappingType = string.IsNullOrWhiteSpace(request.MappingType)
            ? "equivalent"
            : NormalizeToken(request.MappingType, "equivalent");
        var historicalVersion = request.HistoricalKnowledgeVersion.Trim();
        var currentVersion = request.CurrentKnowledgeVersion.Trim();
        var currentVersionDifferent = !string.Equals(
            historicalVersion,
            currentVersion,
            StringComparison.OrdinalIgnoreCase);
        var explanationText = BuildKnowledgeVersionExplanationText(
            artifactType,
            request.HistoricalKnowledgeStableId.Trim(),
            historicalVersion,
            currentVersion,
            mappingType,
            currentTargets,
            request.AffectsHistoricalAnalysis);

        return new KnowledgeVersionExplanationServiceResult(
            "historical_version_explanation_contract",
            false,
            true,
            false,
            false,
            artifactType,
            request.ArtifactId.Trim(),
            request.HistoricalKnowledgeStableId.Trim(),
            historicalVersion,
            currentVersion,
            mappingType,
            currentTargets,
            true,
            currentVersionDifferent,
            request.AffectsHistoricalAnalysis,
            explanationText,
            currentVersionDifferent
                ? $"此{artifactType}保留生成时的历史知识版本；当前版本已通过 {mappingType} 映射到 {string.Join(", ", currentTargets)}。"
                : $"此{artifactType}使用的知识版本仍是当前版本，可直接按 {string.Join(", ", currentTargets)} 理解。",
            [
                $"preserve_historical_view:{historicalVersion}",
                $"resolve_current_mapping:{currentVersion}:{mappingType}",
                "block_production_history_rewrite"
            ]);
    }

    private static IReadOnlyList<string> InferPaperRequestScope(string teacherRequest)
    {
        var scope = new List<string>();
        if (teacherRequest.Contains("惯性", StringComparison.OrdinalIgnoreCase))
        {
            scope.Add("牛顿第一定律与惯性");
        }
        if (teacherRequest.Contains("速度", StringComparison.OrdinalIgnoreCase))
        {
            scope.Add("速度与平均速度");
        }
        if (teacherRequest.Contains("力", StringComparison.OrdinalIgnoreCase) && scope.Count == 0)
        {
            scope.Add("力学基础");
        }
        if (scope.Count == 0)
        {
            scope.Add("力学基础");
        }
        return scope;
    }

    private static double? ClampDifficulty(double? value)
    {
        if (value is null)
        {
            return null;
        }

        return Math.Clamp(value.Value, 0.05, 0.95);
    }

    private static string BuildReplacementPreview(string currentPreview)
    {
        if (string.IsNullOrWhiteSpace(currentPreview))
        {
            return "替换题草稿：请补充题干。";
        }

        return currentPreview.Contains("惯性", StringComparison.OrdinalIgnoreCase)
            ? currentPreview.Replace("说法", "理解", StringComparison.OrdinalIgnoreCase)
            : $"替换题草稿：{currentPreview}";
    }

    private static string NormalizeToken(string value, string fallback)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return fallback;
        }

        var normalized = value.Trim().ToLowerInvariant();
        return string.IsNullOrWhiteSpace(normalized) ? fallback : normalized;
    }

    private static string BuildKnowledgeVersionExplanationText(
        string artifactType,
        string historicalKnowledgeStableId,
        string historicalKnowledgeVersion,
        string currentKnowledgeVersion,
        string mappingType,
        IReadOnlyList<string> currentKnowledgeStableIds,
        bool affectsHistoricalAnalysis)
    {
        var currentTargets = currentKnowledgeStableIds.Count == 0
            ? "无映射目标"
            : string.Join("、", currentKnowledgeStableIds);
        var analysisNote = affectsHistoricalAnalysis
            ? "历史学情口径保持生成时版本，不回写覆盖。"
            : "历史学情口径未受影响。";
        return $"此{artifactType}生成时使用历史知识版本 {historicalKnowledgeVersion}，知识点为 {historicalKnowledgeStableId}。当前知识版本为 {currentKnowledgeVersion}，通过 {mappingType} 映射到 {currentTargets}。{analysisNote}";
    }
}

public sealed record PaperQuestionTypePlanServiceItem(string QuestionType, int Count, decimal Score);

public sealed record PaperBlueprintServiceItem(
    string QuestionType,
    int Count,
    decimal Score,
    IReadOnlyList<string> Scope,
    string AssetStatus,
    string ReviewStatus);

public sealed record PaperRequestConstraintsServiceItem(
    string KnowledgeStatus,
    IReadOnlyList<string> SourceTypes,
    bool ReviewRequired,
    bool BlocksProductionPaper);

public sealed record PaperRequestParseServiceResult(
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
    IReadOnlyList<PaperQuestionTypePlanServiceItem> QuestionTypePlan,
    IReadOnlyList<PaperBlueprintServiceItem> Blueprint,
    PaperRequestConstraintsServiceItem Constraints,
    IReadOnlyList<string> ReviewQuestions);

public sealed record PaperDraftQuestionServiceItem(
    string Id,
    string StemPreview,
    string QuestionType,
    decimal Score,
    double? DifficultyEstimated,
    string PrimaryKnowledgeId,
    string PrimaryKnowledgeTitle,
    string SourceType,
    string RecentUseStatus);

public sealed record PaperQuestionReplacementConstraintsServiceItem(
    bool SameKnowledge,
    bool SameQuestionType,
    bool SimilarDifficulty,
    bool SameScore,
    bool ExcludeCurrentPaperDuplicates,
    bool ExcludeRecentlyUsed,
    string KnowledgeStatus,
    bool BlocksProductionPaper);

public sealed record PaperQuestionUndoSnapshotServiceItem(
    string UndoToken,
    PaperDraftQuestionServiceItem BeforeQuestion,
    PaperDraftQuestionServiceItem AfterQuestion,
    string RevertAction);

public sealed record PaperReplaceRequest(PaperDraftQuestionServiceItem CurrentQuestion);

public sealed record PaperReplaceServiceResult(
    string Mode,
    bool ProductionEligible,
    bool AllowRealModelCalls,
    string Action,
    string Reason,
    PaperQuestionReplacementConstraintsServiceItem Constraints,
    PaperDraftQuestionServiceItem Replacement,
    PaperQuestionUndoSnapshotServiceItem Undo,
    IReadOnlyList<string> AuditTrail);

public sealed record KnowledgeVersionExplanationServiceRequest(
    string ArtifactType,
    string ArtifactId,
    string HistoricalKnowledgeStableId,
    string HistoricalKnowledgeVersion,
    string CurrentKnowledgeVersion,
    string? MappingType,
    IReadOnlyList<string> CurrentKnowledgeStableIds,
    bool AffectsHistoricalAnalysis);

public sealed record KnowledgeVersionExplanationServiceResult(
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
