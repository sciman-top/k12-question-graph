namespace K12QuestionGraph.Api.Endpoints;

using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.Infrastructure.Json;
using K12QuestionGraph.Api.Papers;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using static K12QuestionGraph.Api.FileStore.FormHelpers;

public static class PaperBasketEndpoints
{
    public static void MapPaperBasketEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapPost("/paper-baskets", async (
            PaperBasketCreateRequest request,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            if (request.Items.Count == 0)
            {
                return Results.BadRequest(new { error = "paper_basket_items_required" });
            }

            var questionIds = request.Items.Select(x => x.QuestionItemId).Distinct().ToArray();
            var questions = await dbContext.QuestionItems
                .AsNoTracking()
                .Where(x => questionIds.Contains(x.Id))
                .ToDictionaryAsync(x => x.Id, cancellationToken);
            if (questions.Count != questionIds.Length)
            {
                return Results.Conflict(new { error = "paper_basket_question_missing" });
            }

            var now = DateTimeOffset.UtcNow;
            var normalizedKnowledgeStatus = string.IsNullOrWhiteSpace(request.KnowledgeVersionStatus)
                ? KnowledgeStatuses.Active
                : NormalizeToken(request.KnowledgeVersionStatus, KnowledgeStatuses.Active);
            var knowledgeVersion = request.KnowledgeVersion ?? 1;
            var orderedItems = request.Items
                .Select((item, index) => new { Item = item, SortOrder = item.SortOrder ?? index })
                .OrderBy(x => x.SortOrder)
                .ToArray();

            var basket = new PaperBasket
            {
                Title = string.IsNullOrWhiteSpace(request.Title) ? "未命名试卷" : request.Title.Trim(),
                Subject = NormalizeToken(request.Subject, "physics"),
                Stage = NormalizeToken(request.Stage, "junior_middle_school"),
                Grade = string.IsNullOrWhiteSpace(request.Grade) ? null : request.Grade.Trim(),
                Status = "draft",
                KnowledgeVersionStatus = normalizedKnowledgeStatus,
                KnowledgeVersion = knowledgeVersion,
                Structure = SerializeJson(new
                {
                    itemCount = orderedItems.Length,
                    totalScore = orderedItems.Sum(x => x.Item.Score),
                    sections = orderedItems.GroupBy(x => x.Item.SectionNo).Select(group => new
                    {
                        sectionNo = group.Key,
                        questionCount = group.Count(),
                        score = group.Sum(x => x.Item.Score)
                    }),
                    knowledgeVersionStatus = normalizedKnowledgeStatus,
                    knowledgeVersion
                }),
                CreatedAt = now,
                UpdatedAt = now
            };
            // 篮子与条目必须同事务落库,第二步失败时不再留下空篮子孤儿记录。
            await using var transaction = await dbContext.Database.BeginTransactionAsync(cancellationToken);
            dbContext.PaperBaskets.Add(basket);
            await dbContext.SaveChangesAsync(cancellationToken);

            var basketItems = orderedItems.Select(row =>
            {
                var question = questions[row.Item.QuestionItemId];
                return new PaperBasketItem
                {
                    PaperBasketId = basket.Id,
                    QuestionItemId = question.Id,
                    SectionNo = row.Item.SectionNo,
                    QuestionNo = row.Item.QuestionNo,
                    SubQuestionNo = string.IsNullOrWhiteSpace(row.Item.SubQuestionNo) ? null : row.Item.SubQuestionNo.Trim(),
                    Score = row.Item.Score,
                    SortOrder = row.SortOrder,
                    KnowledgeVersionStatus = normalizedKnowledgeStatus,
                    KnowledgeVersion = knowledgeVersion,
                    Snapshot = SerializeJson(new
                    {
                        question.Subject,
                        question.Stage,
                        question.Grade,
                        question.QuestionType,
                        question.DifficultyEstimated,
                        question.PrimaryKnowledgeId,
                        question.UpdatedAt
                    }),
                    CreatedAt = now
                };
            }).ToArray();
            dbContext.PaperBasketItems.AddRange(basketItems);
            await dbContext.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);

            return Results.Created($"/paper-baskets/{basket.Id}", PaperBasketResponse.From(basket, basketItems));
        })
        .WithName("CreatePaperBasket");
        app.MapGet("/paper-baskets/{id:guid}", async (
            Guid id,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            var basket = await dbContext.PaperBaskets.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (basket is null)
            {
                return Results.NotFound();
            }

            var items = await dbContext.PaperBasketItems
                .AsNoTracking()
                .Where(x => x.PaperBasketId == id)
                .OrderBy(x => x.SortOrder)
                .ToListAsync(cancellationToken);

            return Results.Ok(PaperBasketResponse.From(basket, items));
        })
        .WithName("GetPaperBasket");
        app.MapPost("/paper-baskets/{id:guid}/export-preflight", async (
            Guid id,
            PaperExportPreflightRequest request,
            PaperWorkflowService workflowService,
            CancellationToken cancellationToken) =>
        {
            var result = await workflowService.RunExportPreflightAsync(
                id,
                request.ExportFormat,
                cancellationToken);
            if (result is null)
            {
                return Results.NotFound();
            }

            return Results.Ok(PaperExportPreflightResponse.From(result));
        })
        .WithName("RunPaperExportPreflight");
        app.MapGet("/paper-baskets/{id:guid}/export", async (
            Guid id,
            string? format,
            string? variant,
            PaperArtifactService artifactService,
            CancellationToken cancellationToken) =>
        {
            var result = await artifactService.GenerateAsync(id, format ?? "docx", variant ?? "teacher", cancellationToken);
            if (result is null)
            {
                return Results.NotFound();
            }

            if (result.Status == "blocked")
            {
                return Results.Conflict(new
                {
                    status = result.Status,
                    format = result.Format,
                    errorCode = result.ErrorCode,
                    teacherMessage = result.TeacherMessage,
                    auditTrail = result.AuditTrail
                });
            }

            return Results.File(result.Bytes!, result.Format == "pdf"
                ? "application/pdf"
                : "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                result.FileName,
                enableRangeProcessing: false);
        })
        .WithName("ExportPaperArtifact");
        app.MapPost("/paper-requests/parse", (PaperRequestParseRequest request, PaperWorkflowService workflowService) =>
        {
            if (string.IsNullOrWhiteSpace(request.TeacherRequest))
            {
                return Results.BadRequest(new { error = "teacher_request_required" });
            }

            var result = workflowService.ParsePaperRequest(request.TeacherRequest, request.TextbookVersion);
            return Results.Ok(new PaperRequestParseResponse(
                Mode: result.Mode,
                ProductionEligible: result.ProductionEligible,
                AllowRealModelCalls: result.AllowRealModelCalls,
                SchemaVersion: result.SchemaVersion,
                PromptVersion: result.PromptVersion,
                SystemUnderstanding: result.SystemUnderstanding,
                PaperType: result.PaperType,
                Subject: result.Subject,
                Grade: result.Grade,
                TextbookVersion: result.TextbookVersion,
                Scope: result.Scope,
                TotalScore: result.TotalScore,
                DifficultyTarget: result.DifficultyTarget,
                QuestionTypePlan: result.QuestionTypePlan.Select(x => new PaperQuestionTypePlan(x.QuestionType, x.Count, x.Score)).ToArray(),
                Blueprint: result.Blueprint.Select(x => new PaperBlueprintRow(x.QuestionType, x.Count, x.Score, x.Scope, x.AssetStatus, x.ReviewStatus)).ToArray(),
                Constraints: new PaperRequestConstraints(result.Constraints.KnowledgeStatus, result.Constraints.SourceTypes, result.Constraints.ReviewRequired, result.Constraints.BlocksProductionPaper),
                ReviewQuestions: result.ReviewQuestions));
        })
        .WithName("ParsePaperRequest");
        app.MapPost("/paper-blueprints", async (
            PaperBlueprintReviewCreateRequest request,
            PaperWorkflowService workflowService,
            CancellationToken cancellationToken) =>
        {
            if (string.IsNullOrWhiteSpace(request.TeacherRequest))
            {
                return Results.BadRequest(new { error = "teacher_request_required" });
            }

            try
            {
                var evidence = request.EvidenceConstraints;
                var result = await workflowService.CreateBlueprintReviewAsync(
                    request.TeacherRequest,
                    request.TextbookVersion,
                    evidence is null
                        ? null
                        : new PaperEvidenceConstraintServiceRequest(
                            evidence.EvidenceMode,
                            evidence.PreviewMode,
                            evidence.KnowledgeStableIds ?? [],
                            evidence.RequirementIds ?? [],
                            evidence.AbilityDimensions ?? [],
                            evidence.CognitiveDemands ?? [],
                            evidence.MethodOrExperimentIds ?? [],
                            evidence.ContextTypes ?? [],
                            evidence.ProfileIds ?? []),
                    cancellationToken);

                return Results.Created($"/paper-blueprints/{result.Id}", PaperBlueprintReviewResponse.From(result));
            }
            catch (ArgumentException exception) when (
                exception.Message.Contains("invalid_evidence_mode", StringComparison.Ordinal)
                || exception.Message.Contains("preview_mode_required", StringComparison.Ordinal))
            {
                return Results.BadRequest(new
                {
                    error = exception.Message.Contains("preview_mode_required", StringComparison.Ordinal)
                        ? "preview_mode_required"
                        : "invalid_evidence_mode"
                });
            }
        })
        .WithName("CreatePaperBlueprintReview");
        app.MapPost("/paper-blueprints/{id:guid}/confirm", async (
            Guid id,
            PaperBlueprintConfirmRequest request,
            PaperWorkflowService workflowService,
            CancellationToken cancellationToken) =>
        {
            if (string.IsNullOrWhiteSpace(request.TeacherConfirmedBy))
            {
                return Results.BadRequest(new { error = "teacher_confirmed_by_required" });
            }

            var result = await workflowService.ConfirmBlueprintReviewAsync(
                id,
                request.TeacherConfirmedBy,
                cancellationToken);
            if (result is null)
            {
                return Results.NotFound();
            }

            if (!result.Confirmed)
            {
                return Results.Conflict(new
                {
                    error = result.ErrorCode,
                    result.Status,
                    result.SelectedQuestionCount,
                    result.TeacherMessage,
                    result.AuditTrail,
                    result.VersionReferences,
                    result.ConstraintExplanation,
                    result.ConstraintShortages
                });
            }

            return Results.Ok(PaperBlueprintConfirmResponse.From(result));
        })
        .WithName("ConfirmPaperBlueprintReview");
        app.MapPost("/paper-requests/replace-question", (PaperQuestionReplacementRequest request, PaperWorkflowService workflowService) =>
        {
            if (request.CurrentQuestion is null)
            {
                return Results.BadRequest(new { error = "current_question_required" });
            }

            var serviceRequest = new PaperReplaceRequest(new PaperDraftQuestionServiceItem(
                request.CurrentQuestion.Id,
                request.CurrentQuestion.StemPreview,
                request.CurrentQuestion.QuestionType,
                request.CurrentQuestion.Score,
                request.CurrentQuestion.DifficultyEstimated,
                request.CurrentQuestion.PrimaryKnowledgeId,
                request.CurrentQuestion.PrimaryKnowledgeTitle,
                request.CurrentQuestion.SourceType,
                request.CurrentQuestion.RecentUseStatus));
            var result = workflowService.ReplaceQuestion(serviceRequest);

            var replacement = new PaperDraftQuestion(
                result.Replacement.Id,
                result.Replacement.StemPreview,
                result.Replacement.QuestionType,
                result.Replacement.Score,
                result.Replacement.DifficultyEstimated,
                result.Replacement.PrimaryKnowledgeId,
                result.Replacement.PrimaryKnowledgeTitle,
                result.Replacement.SourceType,
                result.Replacement.RecentUseStatus);
            var before = new PaperDraftQuestion(
                result.Undo.BeforeQuestion.Id,
                result.Undo.BeforeQuestion.StemPreview,
                result.Undo.BeforeQuestion.QuestionType,
                result.Undo.BeforeQuestion.Score,
                result.Undo.BeforeQuestion.DifficultyEstimated,
                result.Undo.BeforeQuestion.PrimaryKnowledgeId,
                result.Undo.BeforeQuestion.PrimaryKnowledgeTitle,
                result.Undo.BeforeQuestion.SourceType,
                result.Undo.BeforeQuestion.RecentUseStatus);
            var undo = new PaperQuestionUndoSnapshot(result.Undo.UndoToken, before, replacement, result.Undo.RevertAction);

            return Results.Ok(new PaperQuestionReplacementResponse(
                result.Mode,
                result.ProductionEligible,
                result.AllowRealModelCalls,
                result.Action,
                result.Reason,
                new PaperQuestionReplacementConstraints(
                    result.Constraints.SameKnowledge,
                    result.Constraints.SameQuestionType,
                    result.Constraints.SimilarDifficulty,
                    result.Constraints.SameScore,
                    result.Constraints.ExcludeCurrentPaperDuplicates,
                    result.Constraints.ExcludeRecentlyUsed,
                    result.Constraints.KnowledgeStatus,
                    result.Constraints.BlocksProductionPaper),
                replacement,
                undo,
                result.AuditTrail));
        })
        .WithName("ReplacePaperQuestion");
    }
}
