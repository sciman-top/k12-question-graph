namespace K12QuestionGraph.Api.Endpoints;

using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.ImportJobs;
using K12QuestionGraph.Api.Infrastructure.Json;
using static K12QuestionGraph.Api.FileStore.FormHelpers;
using static K12QuestionGraph.Api.Questions.QuestionHelpers;
using K12QuestionGraph.Api.Infrastructure.Workers;
using K12QuestionGraph.Api.Questions;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;

public static class ReviewQueueEndpoints
{
    public static void MapReviewQueueEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/review-queue", async (
            string? status,
            string? reviewType,
            string? sortBy,
            string? order,
            int? limit,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            var normalizedStatus = string.IsNullOrWhiteSpace(status) ? ReviewStatuses.Open : NormalizeToken(status, ReviewStatuses.Open);
            var normalizedSortBy = string.IsNullOrWhiteSpace(sortBy) ? "created_at" : NormalizeToken(sortBy, "created_at");
            var descending = !string.Equals(order, "asc", StringComparison.OrdinalIgnoreCase);
            var takeCount = Math.Clamp(limit ?? 100, 1, 500);

            var query = dbContext.ReviewQueueItems.AsNoTracking().Where(x => x.Status == normalizedStatus);
            if (!string.IsNullOrWhiteSpace(reviewType))
            {
                var normalizedReviewType = NormalizeToken(reviewType, string.Empty);
                query = query.Where(x => x.ReviewType == normalizedReviewType);
            }

            // question_no/year/risk 排序键派生自 JSON payload,无法下推 SQL,只能全量
            // 载入后内存排序。曾尝试只扫最近 2000 行,但 order=asc 时更早的记录将永远
            // 不可达,破坏全匹配集排序契约(真题跨年审核走 year_question_no asc),
            // 已按独立评审回退。正确的性能修复需要把年/题号/风险投影为可索引列并
            // 引入真实分页/游标,属带 schema 的后续切片;当前校本题量下全量加载可承受。
            var rows = await query.ToListAsync(cancellationToken);
            var mapped = rows.Select(ReviewQueueItemResponse.From).ToList();
            mapped = normalizedSortBy switch
            {
                "question_no" => descending
                    ? mapped.OrderByDescending(x => ReviewQueuePayloadHelpers.ResolveQuestionNo(x.Payload) ?? int.MinValue).ThenByDescending(x => x.CreatedAt).ToList()
                    : mapped.OrderBy(x => ReviewQueuePayloadHelpers.ResolveQuestionNo(x.Payload) ?? int.MaxValue).ThenBy(x => x.CreatedAt).ToList(),
                "year_question_no" => descending
                    ? mapped.OrderByDescending(x => ReviewQueuePayloadHelpers.ResolveYear(x.Payload) ?? int.MinValue)
                        .ThenByDescending(x => ReviewQueuePayloadHelpers.ResolveQuestionNo(x.Payload) ?? int.MinValue)
                        .ThenByDescending(x => x.CreatedAt).ToList()
                    : mapped.OrderBy(x => ReviewQueuePayloadHelpers.ResolveYear(x.Payload) ?? int.MaxValue)
                        .ThenBy(x => ReviewQueuePayloadHelpers.ResolveQuestionNo(x.Payload) ?? int.MaxValue)
                        .ThenBy(x => x.CreatedAt).ToList(),
                "risk" => descending
                    ? mapped.OrderByDescending(x => x.RiskLevel).ThenByDescending(x => x.CreatedAt).ToList()
                    : mapped.OrderBy(x => x.RiskLevel).ThenBy(x => x.CreatedAt).ToList(),
                _ => descending
                    ? mapped.OrderByDescending(x => x.CreatedAt).ToList()
                    : mapped.OrderBy(x => x.CreatedAt).ToList(),
            };

            return Results.Ok(new ReviewQueueListResponse(mapped.Take(takeCount).ToArray(), mapped.Count));
        })
        .WithName("ListReviewQueueItems");
        app.MapPost("/review-queue/batch-resolve", async (
            ReviewQueueBatchResolveRequest request,
            HttpContext httpContext,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            if (request.ItemIds.Count == 0)
            {
                return Results.BadRequest(new { error = "item_ids_required" });
            }

            if (string.IsNullOrWhiteSpace(request.Reason))
            {
                return Results.BadRequest(new { error = "reason_required" });
            }

            var auditedActor = ResolveAuditedActor(httpContext);

            var itemIds = request.ItemIds.Distinct().ToArray();
            var rows = await dbContext.ReviewQueueItems
                .Where(x => itemIds.Contains(x.Id))
                .ToListAsync(cancellationToken);

            var skippedHighRisk = new List<Guid>();
            var resolvedIds = new List<Guid>();
            var now = DateTimeOffset.UtcNow;
            foreach (var row in rows)
            {
                if (!string.Equals(row.Status, ReviewStatuses.Open, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var riskLevel = ReviewQueuePayloadHelpers.ResolveRiskLevel(row.Payload);
                if (riskLevel == "high")
                {
                    skippedHighRisk.Add(row.Id);
                    continue;
                }

                row.Status = request.Decision == "dismissed" ? ReviewStatuses.Dismissed : ReviewStatuses.Resolved;
                row.ResolvedAt = now;
                row.Payload = ReviewQueuePayloadHelpers.WithReviewAudit(
                    row.Payload,
                    auditedActor,
                    request.Decision,
                    request.Reason.Trim(),
                    now);
                resolvedIds.Add(row.Id);
            }

            await dbContext.SaveChangesAsync(cancellationToken);
            return Results.Ok(new ReviewQueueBatchResolveResponse(resolvedIds, skippedHighRisk));
        })
        .WithName("BatchResolveReviewQueueItems");
        app.MapPost("/review-queue/{id:guid}/resolve", async (
            Guid id,
            ReviewQueueResolveRequest request,
            HttpContext httpContext,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            if (string.IsNullOrWhiteSpace(request.Reason))
            {
                return Results.BadRequest(new { error = "reason_required" });
            }

            var auditedActor = ResolveAuditedActor(httpContext);

            var row = await dbContext.ReviewQueueItems.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (row is null)
            {
                return Results.NotFound(new { error = "review_queue_item_not_found" });
            }

            if (!string.Equals(row.Status, ReviewStatuses.Open, StringComparison.OrdinalIgnoreCase))
            {
                return Results.Conflict(new { error = "review_queue_item_not_open", status = row.Status });
            }

            var now = DateTimeOffset.UtcNow;
            row.Status = request.Decision == "dismissed" ? ReviewStatuses.Dismissed : ReviewStatuses.Resolved;
            row.ResolvedAt = now;
            row.Payload = ReviewQueuePayloadHelpers.WithReviewAudit(
                row.Payload,
                auditedActor,
                request.Decision,
                request.Reason.Trim(),
                now,
                request.Revision);
            await dbContext.SaveChangesAsync(cancellationToken);

            return Results.Ok(ReviewQueueItemResponse.From(row));
        })
        .WithName("ResolveReviewQueueItem");
        app.MapPost("/review-queue/{id:guid}/reopen", async (
            Guid id,
            ReviewQueueReopenRequest request,
            HttpContext httpContext,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            if (string.IsNullOrWhiteSpace(request.Reason))
            {
                return Results.BadRequest(new { error = "reason_required" });
            }

            var auditedActor = ResolveAuditedActor(httpContext);

            var row = await dbContext.ReviewQueueItems.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (row is null)
            {
                return Results.NotFound(new { error = "review_queue_item_not_found" });
            }

            if (string.Equals(row.Status, ReviewStatuses.Open, StringComparison.OrdinalIgnoreCase))
            {
                return Results.Conflict(new { error = "review_queue_item_already_open" });
            }

            var now = DateTimeOffset.UtcNow;
            row.Status = ReviewStatuses.Open;
            row.ResolvedAt = null;
            row.Payload = ReviewQueuePayloadHelpers.WithReviewAudit(
                row.Payload,
                auditedActor,
                "reopened",
                request.Reason.Trim(),
                now);
            await dbContext.SaveChangesAsync(cancellationToken);

            return Results.Ok(ReviewQueueItemResponse.From(row));
        })
        .WithName("ReopenReviewQueueItem");
        app.MapPost("/review-workbench/actions", async (
            ReviewWorkbenchActionRequest request,
            HttpContext httpContext,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            if (string.IsNullOrWhiteSpace(request.Action))
            {
                return Results.BadRequest(new { error = "action_required" });
            }

            if (request.CandidateIds.Count == 0)
            {
                return Results.BadRequest(new { error = "candidate_ids_required" });
            }

            var sourceExists = await dbContext.SourceDocuments
                .AsNoTracking()
                .AnyAsync(x => x.Id == request.SourceDocumentId, cancellationToken);
            if (!sourceExists)
            {
                return Results.NotFound(new { error = "source_document_not_found" });
            }

            var normalizedAction = NormalizeToken(request.Action, string.Empty);
            var candidates = await dbContext.CutCandidates
                .Where(x => x.SourceDocumentId == request.SourceDocumentId && request.CandidateIds.Contains(x.Id))
                .OrderBy(x => x.SequenceNo)
                .ToListAsync(cancellationToken);

            if (candidates.Count == 0)
            {
                return Results.NotFound(new { error = "cut_candidates_not_found" });
            }

            var now = DateTimeOffset.UtcNow;
            var touchedIds = new List<Guid>();
            Guid? createdQuestionId = null;
            var createdCandidateIds = new List<Guid>();
            var skippedIds = new List<Guid>();

            switch (normalizedAction)
            {
                case "merge":
                    if (candidates.Count < 2)
                    {
                        return Results.BadRequest(new { error = "merge_requires_at_least_two_candidates" });
                    }

                    {
                        var primary = candidates[0];
                        var mergedIds = candidates.Skip(1).Select(x => x.Id).ToArray();
                        primary.CandidatePayload = ReviewWorkbenchMutationHelpers.WithPatch(primary.CandidatePayload, new Dictionary<string, object?>
                        {
                            ["mergedFromCandidateIds"] = mergedIds,
                            ["mergedAt"] = now.ToString("O")
                        });
                        primary.UpdatedAt = now;
                        touchedIds.Add(primary.Id);

                        foreach (var candidate in candidates.Skip(1))
                        {
                            candidate.Status = CutCandidateStatuses.Rejected;
                            candidate.FailureReason = "merged_into_primary";
                            candidate.TakeoverAction = "manual_review";
                            candidate.UpdatedAt = now;
                            touchedIds.Add(candidate.Id);
                        }
                    }
                    break;

                case "split":
                    if (candidates.Count != 1)
                    {
                        return Results.BadRequest(new { error = "split_requires_exactly_one_candidate" });
                    }

                    {
                        var target = candidates[0];
                        var maxSequence = await dbContext.CutCandidates
                            .Where(x => x.SourceDocumentId == request.SourceDocumentId)
                            .MaxAsync(x => (int?)x.SequenceNo, cancellationToken) ?? 0;

                        var left = ReviewWorkbenchMutationHelpers.CloneCandidate(target, maxSequence + 1, now, "split_part_a");
                        var right = ReviewWorkbenchMutationHelpers.CloneCandidate(target, maxSequence + 2, now, "split_part_b");
                        dbContext.CutCandidates.Add(left);
                        dbContext.CutCandidates.Add(right);
                        createdCandidateIds.Add(left.Id);
                        createdCandidateIds.Add(right.Id);

                        target.Status = CutCandidateStatuses.Rejected;
                        target.FailureReason = "split_into_two_candidates";
                        target.UpdatedAt = now;
                        touchedIds.Add(target.Id);
                    }
                    break;

                case "skip":
                    foreach (var candidate in candidates)
                    {
                        candidate.Status = CutCandidateStatuses.Rejected;
                        candidate.FailureReason = "skipped_by_teacher";
                        candidate.UpdatedAt = now;
                        touchedIds.Add(candidate.Id);
                    }
                    break;

                case "rerun":
                    foreach (var candidate in candidates)
                    {
                        candidate.Status = CutCandidateStatuses.RetryRequired;
                        candidate.FailureReason = "rerun_requested";
                        candidate.TakeoverAction = "rerun";
                        candidate.UpdatedAt = now;
                        touchedIds.Add(candidate.Id);
                    }
                    break;

                case "associate":
                    if (string.IsNullOrWhiteSpace(request.AssetLabel))
                    {
                        return Results.BadRequest(new { error = "asset_label_required_for_associate" });
                    }

                    foreach (var candidate in candidates)
                    {
                        candidate.Metadata = ReviewWorkbenchMutationHelpers.WithPatch(candidate.Metadata, new Dictionary<string, object?>
                        {
                            ["associatedAssetLabel"] = request.AssetLabel.Trim(),
                            ["associatedAt"] = now.ToString("O")
                        });
                        candidate.UpdatedAt = now;
                        touchedIds.Add(candidate.Id);
                    }
                    break;

                case "undo":
                    foreach (var candidate in candidates)
                    {
                        candidate.Status = CutCandidateStatuses.PendingReview;
                        candidate.FailureReason = string.Empty;
                        candidate.TakeoverAction = "manual_review";
                        candidate.SuggestedQuestionItemId = null;
                        candidate.UpdatedAt = now;
                        touchedIds.Add(candidate.Id);
                    }
                    break;

                case "save_question":
                    {
                        var blocks = candidates
                            .Select((x, index) => new QuestionBlock
                            {
                                QuestionItemId = Guid.Empty,
                                BlockType = "text",
                                SortOrder = index,
                                Content = JsonSerializer.Serialize(new
                                {
                                    text = ResolveCandidateText(x),
                                    candidateId = x.Id
                                }),
                                SourceRegionId = x.SourceRegionId,
                                CreatedAt = now
                            })
                            .ToArray();

                        var question = new QuestionItem
                        {
                            Id = Guid.NewGuid(),
                            Subject = "physics",
                            Stage = "junior_middle_school",
                            Status = QuestionStatuses.Draft,
                            QuestionType = "short_answer",
                            Blocks = JsonSerializer.Serialize(blocks.Select(x => new
                            {
                                x.BlockType,
                                x.SortOrder,
                                x.SourceRegionId
                            })),
                            CreatedAt = now,
                            UpdatedAt = now
                        };

                        foreach (var block in blocks)
                        {
                            block.QuestionItemId = question.Id;
                        }

                        dbContext.QuestionItems.Add(question);
                        dbContext.QuestionBlocks.AddRange(blocks);
                        createdQuestionId = question.Id;
                        foreach (var candidate in candidates)
                        {
                            candidate.Status = CutCandidateStatuses.Accepted;
                            candidate.SuggestedQuestionItemId = question.Id;
                            candidate.UpdatedAt = now;
                            touchedIds.Add(candidate.Id);
                        }
                    }
                    break;

                default:
                    return Results.BadRequest(new { error = "unsupported_action" });
            }

            var reviewQueueRows = await dbContext.ReviewQueueItems
                .Where(x => x.ReviewType == "cut_candidate" && x.Status == ReviewStatuses.Open)
                .ToListAsync(cancellationToken);

            var candidateSourceRegionIds = candidates
                .Where(x => x.SourceRegionId.HasValue)
                .Select(x => x.SourceRegionId!.Value)
                .ToHashSet();

            foreach (var row in reviewQueueRows)
            {
                if (!ReviewWorkbenchMutationHelpers.QueueItemMatchesCandidates(row.Payload, candidateSourceRegionIds))
                {
                    continue;
                }

                row.Status = normalizedAction is "skip" ? ReviewStatuses.Dismissed : ReviewStatuses.Resolved;
                row.ResolvedAt = now;
                row.Payload = ReviewQueuePayloadHelpers.WithReviewAudit(
                    row.Payload,
                    ResolveAuditedActor(httpContext),
                    normalizedAction,
                    string.IsNullOrWhiteSpace(request.Reason) ? "workbench_action" : request.Reason.Trim(),
                    now);
                touchedIds.Add(row.Id);
            }

            await dbContext.SaveChangesAsync(cancellationToken);
            return Results.Ok(new ReviewWorkbenchActionResponse(
                normalizedAction,
                request.SourceDocumentId,
                touchedIds.Distinct().ToArray(),
                createdCandidateIds,
                skippedIds,
                createdQuestionId));
        })
        .WithName("ApplyReviewWorkbenchAction");
    }
}
