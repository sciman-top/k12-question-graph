using K12QuestionGraph.Api.Application.Workflows.Contracts;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;

namespace K12QuestionGraph.Api.Application.Workflows;

public interface IPaperWorkflowService
{
    Task<PaperWorkflowDto> BuildDraftAsync(string requestText, CancellationToken cancellationToken);
    Task<PaperBlueprintReviewServiceResult> CreateBlueprintReviewAsync(
        string teacherRequest,
        string? textbookVersion,
        CancellationToken cancellationToken);
    Task<PaperBlueprintConfirmServiceResult?> ConfirmBlueprintReviewAsync(
        Guid blueprintReviewId,
        string teacherConfirmedBy,
        CancellationToken cancellationToken);
    Task<PaperExportPreflightServiceResult?> RunExportPreflightAsync(
        Guid paperBasketId,
        string exportFormat,
        CancellationToken cancellationToken);
    PaperRequestParseServiceResult ParsePaperRequest(string teacherRequest, string? textbookVersion);
    PaperReplaceServiceResult ReplaceQuestion(PaperReplaceRequest request);
    KnowledgeVersionExplanationServiceResult ResolveKnowledgeVersionExplanation(KnowledgeVersionExplanationServiceRequest request);
}

public sealed class PaperWorkflowService(KqgDbContext dbContext) : IPaperWorkflowService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

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

    public async Task<PaperBlueprintReviewServiceResult> CreateBlueprintReviewAsync(
        string teacherRequest,
        string? textbookVersion,
        CancellationToken cancellationToken)
    {
        var parsed = ParsePaperRequest(teacherRequest, textbookVersion);
        var now = DateTimeOffset.UtcNow;
        var review = new PaperBlueprintReview
        {
            Id = Guid.NewGuid(),
            RequestText = teacherRequest.Trim(),
            Subject = parsed.Subject,
            Stage = "junior_middle_school",
            Grade = parsed.Grade,
            TextbookVersion = parsed.TextbookVersion,
            Status = WorkflowReviewStatuses.PendingReview,
            Blueprint = SerializeJson(parsed.Blueprint),
            Constraints = SerializeJson(new
            {
                parsed.Constraints.KnowledgeStatus,
                parsed.Constraints.SourceTypes,
                parsed.Constraints.ReviewRequired,
                parsed.Constraints.BlocksProductionPaper,
                mustConfirmBeforeTakingQuestions = true,
                opaqueGenerationAllowed = false,
                allowRealModelCalls = parsed.AllowRealModelCalls
            }),
            ReviewQuestions = SerializeJson(parsed.ReviewQuestions),
            CreatedAt = now,
            UpdatedAt = now
        };

        dbContext.PaperBlueprintReviews.Add(review);
        await dbContext.SaveChangesAsync(cancellationToken);

        return new PaperBlueprintReviewServiceResult(
            review.Id,
            review.Status,
            parsed.Mode,
            parsed.ProductionEligible,
            parsed.AllowRealModelCalls,
            review.RequestText,
            parsed.Subject,
            parsed.Grade,
            parsed.TextbookVersion,
            parsed.Scope,
            parsed.TotalScore,
            parsed.DifficultyTarget,
            parsed.Blueprint,
            parsed.Constraints,
            parsed.ReviewQuestions,
            MustConfirmBeforeTakingQuestions: true,
            OpaqueGenerationAllowed: false,
            ConfirmedPaperBasketId: null,
            CreatedAt: review.CreatedAt,
            UpdatedAt: review.UpdatedAt);
    }

    public async Task<PaperBlueprintConfirmServiceResult?> ConfirmBlueprintReviewAsync(
        Guid blueprintReviewId,
        string teacherConfirmedBy,
        CancellationToken cancellationToken)
    {
        var review = await dbContext.PaperBlueprintReviews
            .FirstOrDefaultAsync(x => x.Id == blueprintReviewId, cancellationToken);
        if (review is null)
        {
            return null;
        }

        if (!string.Equals(review.Status, WorkflowReviewStatuses.PendingReview, StringComparison.OrdinalIgnoreCase))
        {
            return new PaperBlueprintConfirmServiceResult(
                review.Id,
                review.Status,
                false,
                review.ConfirmedPaperBasketId,
                0,
                "blueprint_already_closed",
                "此细目表已经处理过，不能重复确认取题。",
                ["no_duplicate_confirm"]);
        }

        var blueprint = DeserializeBlueprint(review.Blueprint);
        var requiredCount = blueprint.Sum(x => Math.Max(0, x.Count));
        if (requiredCount <= 0)
        {
            return new PaperBlueprintConfirmServiceResult(
                review.Id,
                review.Status,
                false,
                null,
                0,
                "blueprint_empty",
                "细目表没有可取题数量。",
                ["block_empty_blueprint"]);
        }

        var questions = await dbContext.QuestionItems
            .AsNoTracking()
            .Where(x =>
                x.Subject == review.Subject &&
                x.Stage == review.Stage &&
                (x.Status == QuestionStatuses.Draft ||
                 x.Status == QuestionStatuses.Usable ||
                 x.Status == QuestionStatuses.Recommended))
            .OrderBy(x => x.QuestionType)
            .ThenBy(x => x.CreatedAt)
            .Take(requiredCount)
            .ToListAsync(cancellationToken);

        if (questions.Count < requiredCount)
        {
            return new PaperBlueprintConfirmServiceResult(
                review.Id,
                review.Status,
                false,
                null,
                questions.Count,
                "question_pool_insufficient",
                "当前题库不足以按确认后的细目表取题。",
                ["no_opaque_generation", "teacher_can_adjust_blueprint_or_import_more_questions"]);
        }

        var now = DateTimeOffset.UtcNow;
        var basket = new PaperBasket
        {
            Id = Guid.NewGuid(),
            Title = BuildPaperBasketTitle(review.RequestText),
            Subject = review.Subject,
            Stage = review.Stage,
            Grade = review.Grade,
            Status = "draft",
            KnowledgeVersionStatus = KnowledgeStatuses.Active,
            KnowledgeVersion = 1,
            Structure = SerializeJson(new
            {
                blueprintReviewId = review.Id,
                itemCount = questions.Count,
                totalScore = blueprint.Sum(x => x.Score),
                confirmedBy = teacherConfirmedBy.Trim(),
                confirmRequiredBeforeQuestionSelection = true,
                opaqueGenerationAllowed = false,
                source = "confirmed_blueprint_review"
            }),
            CreatedAt = now,
            UpdatedAt = now
        };
        dbContext.PaperBaskets.Add(basket);
        await dbContext.SaveChangesAsync(cancellationToken);

        var basketItems = questions.Select((question, index) => new PaperBasketItem
        {
            Id = Guid.NewGuid(),
            PaperBasketId = basket.Id,
            QuestionItemId = question.Id,
            SectionNo = 1,
            QuestionNo = index + 1,
            Score = question.DefaultScore ?? 3m,
            SortOrder = index,
            KnowledgeVersionStatus = KnowledgeStatuses.Active,
            KnowledgeVersion = 1,
            Snapshot = SerializeJson(new
            {
                question.Subject,
                question.Stage,
                question.Grade,
                question.QuestionType,
                question.DifficultyEstimated,
                question.PrimaryKnowledgeId,
                selectedAfterTeacherConfirmedBlueprint = true,
                question.UpdatedAt
            }),
            CreatedAt = now
        }).ToArray();
        dbContext.PaperBasketItems.AddRange(basketItems);

        review.Status = WorkflowReviewStatuses.Confirmed;
        review.TeacherConfirmedBy = teacherConfirmedBy.Trim();
        review.TeacherConfirmedAt = now;
        review.ConfirmedPaperBasketId = basket.Id;
        review.UpdatedAt = now;
        await dbContext.SaveChangesAsync(cancellationToken);

        return new PaperBlueprintConfirmServiceResult(
            review.Id,
            review.Status,
            true,
            basket.Id,
            basketItems.Length,
            null,
            "教师确认细目表后才创建题篮并取题。",
            ["teacher_confirmed_blueprint", "created_draft_paper_basket", "no_opaque_generation"]);
    }

    public async Task<PaperExportPreflightServiceResult?> RunExportPreflightAsync(
        Guid paperBasketId,
        string exportFormat,
        CancellationToken cancellationToken)
    {
        var basket = await dbContext.PaperBaskets
            .AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == paperBasketId, cancellationToken);
        if (basket is null)
        {
            return null;
        }

        var basketItems = await dbContext.PaperBasketItems
            .AsNoTracking()
            .Where(x => x.PaperBasketId == paperBasketId)
            .OrderBy(x => x.SortOrder)
            .ToListAsync(cancellationToken);

        var questionIds = basketItems.Select(x => x.QuestionItemId).Distinct().ToArray();
        var questions = await dbContext.QuestionItems
            .AsNoTracking()
            .Where(x => questionIds.Contains(x.Id))
            .ToDictionaryAsync(x => x.Id, cancellationToken);
        var blocks = await dbContext.QuestionBlocks
            .AsNoTracking()
            .Where(x => questionIds.Contains(x.QuestionItemId))
            .OrderBy(x => x.SortOrder)
            .ToListAsync(cancellationToken);
        var assets = await dbContext.QuestionAssets
            .AsNoTracking()
            .Where(x => questionIds.Contains(x.QuestionItemId))
            .ToListAsync(cancellationToken);

        var sourceRegionIds = blocks.Select(x => x.SourceRegionId)
            .Concat(assets.Select(x => x.SourceRegionId))
            .Where(x => x.HasValue)
            .Select(x => x!.Value)
            .Distinct()
            .ToArray();
        var regions = await dbContext.SourceRegions
            .AsNoTracking()
            .Where(x => sourceRegionIds.Contains(x.Id))
            .ToDictionaryAsync(x => x.Id, cancellationToken);
        var sourceDocumentIds = regions.Values.Select(x => x.SourceDocumentId).Distinct().ToArray();
        var documents = await dbContext.SourceDocuments
            .AsNoTracking()
            .Where(x => sourceDocumentIds.Contains(x.Id))
            .ToDictionaryAsync(x => x.Id, cancellationToken);

        var blocksByQuestion = blocks.GroupBy(x => x.QuestionItemId).ToDictionary(x => x.Key, x => x.ToArray());
        var assetsByQuestion = assets.GroupBy(x => x.QuestionItemId).ToDictionary(x => x.Key, x => x.ToArray());
        var itemResults = basketItems.Select(item =>
        {
            questions.TryGetValue(item.QuestionItemId, out var question);
            blocksByQuestion.TryGetValue(item.QuestionItemId, out var itemBlocks);
            assetsByQuestion.TryGetValue(item.QuestionItemId, out var itemAssets);
            return BuildExportPreflightItem(item, question, itemBlocks ?? [], itemAssets ?? [], regions, documents);
        }).ToArray();

        var issueCounts = itemResults
            .SelectMany(x => x.Issues)
            .GroupBy(x => x.Code, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(x => x.Key, x => x.Count(), StringComparer.OrdinalIgnoreCase);
        var blocked = itemResults.SelectMany(x => x.Issues).Any(x => string.Equals(x.Severity, "blocker", StringComparison.OrdinalIgnoreCase));

        return new PaperExportPreflightServiceResult(
            basket.Id,
            basket.Title,
            NormalizeToken(exportFormat, "docx"),
            blocked ? "blocked" : "ready_for_review",
            false,
            itemResults.Length,
            itemResults,
            issueCounts,
            new PaperExportPreflightSummary(
                itemResults.Count(x => x.HasImage),
                itemResults.Count(x => x.HasFormula),
                itemResults.Count(x => x.HasTable),
                itemResults.Count(x => x.HasAnswer),
                itemResults.Count(x => x.HasSolution),
                itemResults.Count(x => string.Equals(x.SourceAuthorizationStatus, "authorized", StringComparison.OrdinalIgnoreCase)),
                itemResults.Count(x => x.HasKnowledgeVersionReference)),
            blocked
                ? "导出前仍有答案、解析、来源授权或版本引用问题，请先处理后再生成文件。"
                : "导出前审校通过，可进入 Word/PDF 产物生成。",
            [
                "checked_question_images",
                "checked_formula_table_blocks",
                "checked_answer_solution",
                "checked_source_authorization",
                "checked_knowledge_version_reference"
            ]);
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

    private static string SerializeJson<T>(T value)
    {
        return JsonSerializer.Serialize(value, JsonOptions);
    }

    private static IReadOnlyList<PaperBlueprintServiceItem> DeserializeBlueprint(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return [];
        }

        return JsonSerializer.Deserialize<IReadOnlyList<PaperBlueprintServiceItem>>(value, JsonOptions) ?? [];
    }

    private static string BuildPaperBasketTitle(string requestText)
    {
        var normalized = string.IsNullOrWhiteSpace(requestText) ? "确认后的试卷草稿" : requestText.Trim();
        return normalized.Length <= 48 ? normalized : normalized[..48];
    }

    private static PaperExportPreflightItemServiceResult BuildExportPreflightItem(
        PaperBasketItem item,
        QuestionItem? question,
        IReadOnlyList<QuestionBlock> blocks,
        IReadOnlyList<QuestionAsset> assets,
        IReadOnlyDictionary<Guid, SourceRegion> regions,
        IReadOnlyDictionary<Guid, SourceDocument> documents)
    {
        if (question is null)
        {
            return new PaperExportPreflightItemServiceResult(
                item.QuestionItemId,
                item.QuestionNo,
                item.SubQuestionNo,
                item.Score,
                item.KnowledgeVersionStatus,
                item.KnowledgeVersion,
                false,
                false,
                false,
                false,
                false,
                "missing",
                false,
                [new PaperExportPreflightIssueServiceItem("question_missing", "blocker", "题目不存在，无法导出。")]);
        }

        var issues = new List<PaperExportPreflightIssueServiceItem>();
        var hasImage = assets.Any(x =>
            string.Equals(x.AssetType, "image", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(x.AssetType, "figure", StringComparison.OrdinalIgnoreCase));
        var hasFormula = blocks.Any(x =>
            string.Equals(x.BlockType, "formula", StringComparison.OrdinalIgnoreCase) ||
            ContentContainsAny(x.Content, "latex", "formula"));
        var hasTable = blocks.Any(x =>
            string.Equals(x.BlockType, "table", StringComparison.OrdinalIgnoreCase) ||
            ContentContainsAny(x.Content, "rows", "columns", "table"));
        var hasAnswer = CustomFieldHasValue(question.CustomFields, "answer");
        var hasSolution = CustomFieldHasValue(question.CustomFields, "solution");
        var sourceDocuments = ResolveSourceDocuments(blocks, assets, regions, documents);
        var sourceAuthorizationStatus = GetSourceAuthorizationStatus(sourceDocuments);
        var hasKnowledgeVersionReference =
            string.Equals(item.KnowledgeVersionStatus, KnowledgeStatuses.Active, StringComparison.OrdinalIgnoreCase) &&
            item.KnowledgeVersion >= 1 &&
            question.PrimaryKnowledgeId is not null;

        if (!hasImage)
        {
            issues.Add(new PaperExportPreflightIssueServiceItem("image_not_attached", "warning", "本题没有题图附件；若原题含图，请先补齐。"));
        }
        if (!hasAnswer)
        {
            issues.Add(new PaperExportPreflightIssueServiceItem("answer_missing", "blocker", "缺少答案，不能生成教师版或答案版。"));
        }
        if (!hasSolution)
        {
            issues.Add(new PaperExportPreflightIssueServiceItem("solution_missing", "blocker", "缺少解析，不能进入导出。"));
        }
        if (sourceDocuments.Count == 0)
        {
            issues.Add(new PaperExportPreflightIssueServiceItem("source_missing", "blocker", "缺少来源区域或来源资料，不能确认授权。"));
        }
        else if (!string.Equals(sourceAuthorizationStatus, "authorized", StringComparison.OrdinalIgnoreCase))
        {
            issues.Add(new PaperExportPreflightIssueServiceItem("source_authorization_risk", "blocker", "来源授权或隐私状态不满足导出要求。"));
        }
        if (!hasKnowledgeVersionReference)
        {
            issues.Add(new PaperExportPreflightIssueServiceItem("knowledge_version_reference_missing", "blocker", "缺少可复现的当前知识版本引用。"));
        }

        return new PaperExportPreflightItemServiceResult(
            item.QuestionItemId,
            item.QuestionNo,
            item.SubQuestionNo,
            item.Score,
            item.KnowledgeVersionStatus,
            item.KnowledgeVersion,
            hasImage,
            hasFormula,
            hasTable,
            hasAnswer,
            hasSolution,
            sourceAuthorizationStatus,
            hasKnowledgeVersionReference,
            issues);
    }

    private static IReadOnlyList<SourceDocument> ResolveSourceDocuments(
        IReadOnlyList<QuestionBlock> blocks,
        IReadOnlyList<QuestionAsset> assets,
        IReadOnlyDictionary<Guid, SourceRegion> regions,
        IReadOnlyDictionary<Guid, SourceDocument> documents)
    {
        return blocks.Select(x => x.SourceRegionId)
            .Concat(assets.Select(x => x.SourceRegionId))
            .Where(x => x.HasValue)
            .Select(x => x!.Value)
            .Distinct()
            .Select(regionId => regions.TryGetValue(regionId, out var region) ? region.SourceDocumentId : (Guid?)null)
            .Where(x => x.HasValue)
            .Select(x => x!.Value)
            .Distinct()
            .Select(documentId => documents.TryGetValue(documentId, out var document) ? document : null)
            .Where(x => x is not null)
            .Select(x => x!)
            .ToArray();
    }

    private static string GetSourceAuthorizationStatus(IReadOnlyList<SourceDocument> documents)
    {
        if (documents.Count == 0)
        {
            return "missing";
        }

        var allAuthorized = documents.All(x =>
            x.SharingAllowed &&
            !string.Equals(x.LicenseOrPermission, "unknown", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(x.LicenseOrPermission, "none", StringComparison.OrdinalIgnoreCase) &&
            (!x.ContainsStudentPii ||
             string.Equals(x.AnonymizationStatus, "anonymized", StringComparison.OrdinalIgnoreCase) ||
             string.Equals(x.AnonymizationStatus, "not_applicable", StringComparison.OrdinalIgnoreCase)));
        return allAuthorized ? "authorized" : "risk";
    }

    private static bool CustomFieldHasValue(string customFields, string field)
    {
        try
        {
            using var document = JsonDocument.Parse(customFields);
            if (!document.RootElement.TryGetProperty(field, out var value) ||
                value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
            {
                return false;
            }

            return value.ValueKind != JsonValueKind.Object || value.EnumerateObject().Any();
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static bool ContentContainsAny(string content, params string[] tokens)
    {
        return tokens.Any(token => content.Contains(token, StringComparison.OrdinalIgnoreCase));
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

public sealed record PaperBlueprintReviewServiceResult(
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
    IReadOnlyList<PaperBlueprintServiceItem> Blueprint,
    PaperRequestConstraintsServiceItem Constraints,
    IReadOnlyList<string> ReviewQuestions,
    bool MustConfirmBeforeTakingQuestions,
    bool OpaqueGenerationAllowed,
    Guid? ConfirmedPaperBasketId,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public sealed record PaperBlueprintConfirmServiceResult(
    Guid Id,
    string Status,
    bool Confirmed,
    Guid? PaperBasketId,
    int SelectedQuestionCount,
    string? ErrorCode,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail);

public sealed record PaperExportPreflightServiceResult(
    Guid PaperBasketId,
    string Title,
    string ExportFormat,
    string Status,
    bool ProductionEligible,
    int ItemCount,
    IReadOnlyList<PaperExportPreflightItemServiceResult> Items,
    IReadOnlyDictionary<string, int> IssueCounts,
    PaperExportPreflightSummary Summary,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail);

public sealed record PaperExportPreflightSummary(
    int ImageReadyCount,
    int FormulaReadyCount,
    int TableReadyCount,
    int AnswerReadyCount,
    int SolutionReadyCount,
    int AuthorizedSourceCount,
    int ActiveKnowledgeVersionCount);

public sealed record PaperExportPreflightItemServiceResult(
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
    IReadOnlyList<PaperExportPreflightIssueServiceItem> Issues);

public sealed record PaperExportPreflightIssueServiceItem(
    string Code,
    string Severity,
    string Message);

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
