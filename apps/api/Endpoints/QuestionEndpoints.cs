namespace K12QuestionGraph.Api.Endpoints;

using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.Configuration;
using K12QuestionGraph.Api.Infrastructure.Json;
using K12QuestionGraph.Api.Infrastructure.Queries;
using K12QuestionGraph.Api.Papers;
using K12QuestionGraph.Api.Questions;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using static K12QuestionGraph.Api.FileStore.FormHelpers;
using static K12QuestionGraph.Api.Questions.QuestionHelpers;

public static class QuestionEndpoints
{
    public static void MapQuestionEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapPost("/questions", async (
            QuestionCreateRequest request,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            var validationError = ValidateQuestionCreateRequest(request);
            if (validationError is not null)
            {
                return Results.BadRequest(new { error = validationError });
            }

            if (request.DifficultyEstimated is < 0 or > 1)
            {
                return Results.BadRequest(new { error = "invalid_difficulty_estimated" });
            }

            if (request.PrimaryKnowledgeId.HasValue)
            {
                var primaryKnowledgeExists = await dbContext.KnowledgeNodes
                    .AsNoTracking()
                    .AnyAsync(x => x.Id == request.PrimaryKnowledgeId.Value, cancellationToken);
                if (!primaryKnowledgeExists)
                {
                    return Results.Conflict(new { error = "primary_knowledge_missing" });
                }
            }

            var sourceRegionIds = request.Blocks
                .Select(x => x.SourceRegionId)
                .Concat(request.Assets.Select(x => x.SourceRegionId))
                .Where(x => x.HasValue)
                .Select(x => x!.Value)
                .Distinct()
                .ToArray();
            if (sourceRegionIds.Length > 0)
            {
                var found = await dbContext.SourceRegions
                    .Where(x => sourceRegionIds.Contains(x.Id))
                    .Select(x => x.Id)
                    .ToListAsync(cancellationToken);
                if (found.Count != sourceRegionIds.Length)
                {
                    return Results.Conflict(new { error = "source_region_missing" });
                }
            }

            var fileAssetIds = request.Assets
                .Select(x => x.FileAssetId)
                .Where(x => x.HasValue)
                .Select(x => x!.Value)
                .Distinct()
                .ToArray();
            if (fileAssetIds.Length > 0)
            {
                var found = await dbContext.FileAssets
                    .Where(x => fileAssetIds.Contains(x.Id))
                    .Select(x => x.Id)
                    .ToListAsync(cancellationToken);
                if (found.Count != fileAssetIds.Length)
                {
                    return Results.Conflict(new { error = "file_asset_missing" });
                }
            }

            await using var transaction = await dbContext.Database.BeginTransactionAsync(cancellationToken);
            var now = DateTimeOffset.UtcNow;
            var item = new QuestionItem
            {
                Subject = NormalizeToken(request.Subject, "physics"),
                Stage = NormalizeToken(request.Stage, "junior_middle_school"),
                Grade = string.IsNullOrWhiteSpace(request.Grade) ? null : request.Grade.Trim(),
                QuestionType = string.IsNullOrWhiteSpace(request.QuestionType) ? null : NormalizeToken(request.QuestionType, "unknown"),
                DefaultScore = request.DefaultScore,
                DifficultyEstimated = request.DifficultyEstimated,
                Status = string.IsNullOrWhiteSpace(request.Status) ? QuestionStatuses.Draft : NormalizeToken(request.Status, QuestionStatuses.Draft),
                PrimaryKnowledgeId = request.PrimaryKnowledgeId,
                Blocks = SerializeJson(request.Blocks.Select((block, index) => new
                {
                    type = NormalizeToken(block.BlockType, "text"),
                    order = block.SortOrder ?? index,
                    content = block.Content,
                    source_region_id = block.SourceRegionId
                })),
                CustomFields = SerializeJson(new
                {
                    answer = request.Answer,
                    solution = request.Solution
                }),
                QualitySignals = "{}",
                CreatedAt = now,
                UpdatedAt = now
            };

            dbContext.QuestionItems.Add(item);
            await dbContext.SaveChangesAsync(cancellationToken);

            var blocks = request.Blocks.Select((block, index) => new QuestionBlock
            {
                QuestionItemId = item.Id,
                BlockType = NormalizeToken(block.BlockType, "text"),
                SortOrder = block.SortOrder ?? index,
                Content = SerializeJson(block.Content),
                SourceRegionId = block.SourceRegionId
            }).ToArray();

            var assets = request.Assets.Select(asset => new QuestionAsset
            {
                QuestionItemId = item.Id,
                FileAssetId = asset.FileAssetId,
                SourceRegionId = asset.SourceRegionId,
                AssetType = NormalizeToken(asset.AssetType, "image"),
                Purpose = string.IsNullOrWhiteSpace(asset.Purpose) ? "question_content" : NormalizeToken(asset.Purpose, "question_content"),
                Metadata = SerializeJson(asset.Metadata)
            }).ToArray();

            dbContext.QuestionBlocks.AddRange(blocks);
            dbContext.QuestionAssets.AddRange(assets);
            await dbContext.SaveChangesAsync(cancellationToken);

            var tableReviewItems = blocks
                .Where(RequiresTableBlockReview)
                .Select(block => CreateTableBlockReviewItem(item, block, now))
                .ToArray();
            if (tableReviewItems.Length > 0)
            {
                dbContext.ReviewQueueItems.AddRange(tableReviewItems);
                await dbContext.SaveChangesAsync(cancellationToken);
            }

            var formulaReviewItems = blocks
                .Where(RequiresFormulaBlockReview)
                .Select(block => CreateFormulaBlockReviewItem(item, block, now))
                .ToArray();
            if (formulaReviewItems.Length > 0)
            {
                dbContext.ReviewQueueItems.AddRange(formulaReviewItems);
                await dbContext.SaveChangesAsync(cancellationToken);
            }

            await transaction.CommitAsync(cancellationToken);

            return Results.Created($"/questions/{item.Id}", QuestionResponse.From(item, blocks, assets));
        })
        .WithName("CreateQuestion");
        app.MapGet("/questions", async (
            string? subject,
            string? stage,
            string? grade,
            string? questionType,
            string? status,
            Guid? primaryKnowledgeId,
            int? year,
            string? knowledgeCandidateId,
            string? examPointCandidateId,
            double? difficultyMin,
            double? difficultyMax,
            string? sourceType,
            bool? hasFormula,
            bool? hasTable,
            bool? hasImage,
            string? knowledgeStatus,
            int? knowledgeVersion,
            string? sortBy,
            string? order,
            int? page,
            int? limit,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            var query = dbContext.QuestionItems.AsNoTracking().AsQueryable();
            var usesCandidateFilters =
                year.HasValue ||
                !string.IsNullOrWhiteSpace(knowledgeCandidateId) ||
                !string.IsNullOrWhiteSpace(examPointCandidateId) ||
                string.Equals(status?.Trim(), QuestionStatuses.PendingReview, StringComparison.OrdinalIgnoreCase);

            if (!string.IsNullOrWhiteSpace(subject))
            {
                var value = NormalizeToken(subject, "physics");
                query = query.Where(x => x.Subject == value);
            }

            if (!string.IsNullOrWhiteSpace(stage))
            {
                var value = NormalizeToken(stage, "junior_middle_school");
                query = query.Where(x => x.Stage == value);
            }

            if (!string.IsNullOrWhiteSpace(grade))
            {
                var value = grade.Trim();
                query = query.Where(x => x.Grade == value);
            }

            if (!string.IsNullOrWhiteSpace(questionType))
            {
                var value = NormalizeToken(questionType, "unknown");
                query = query.Where(x => x.QuestionType == value);
            }

            if (!string.IsNullOrWhiteSpace(status))
            {
                var value = NormalizeToken(status, QuestionStatuses.Draft);
                query = query.Where(x => x.Status == value);
            }

            if (primaryKnowledgeId.HasValue)
            {
                query = query.Where(x => x.PrimaryKnowledgeId == primaryKnowledgeId.Value);
            }
            else if (!usesCandidateFilters)
            {
                var normalizedKnowledgeStatus = string.IsNullOrWhiteSpace(knowledgeStatus)
                    ? KnowledgeStatuses.Active
                    : NormalizeToken(knowledgeStatus, KnowledgeStatuses.Active);
                var normalizedKnowledgeVersion = knowledgeVersion.GetValueOrDefault(1);
                var knowledgeIds = dbContext.KnowledgeNodes
                    .AsNoTracking()
                    .Where(x => x.Status == normalizedKnowledgeStatus && x.Version == normalizedKnowledgeVersion)
                    .Select(x => x.Id);
                query = query.Where(x => x.PrimaryKnowledgeId.HasValue && knowledgeIds.Contains(x.PrimaryKnowledgeId.Value));
            }

            if (year.HasValue)
            {
                var yearFilter = QuestionCustomFieldHelpers.BuildContainmentFilter("year", year.Value);
                query = query.Where(x => EF.Functions.JsonContains(x.CustomFields, yearFilter));
            }

            if (!string.IsNullOrWhiteSpace(knowledgeCandidateId))
            {
                var candidateFilter = QuestionCustomFieldHelpers.BuildArrayContainmentFilter(
                    "knowledgeCandidateIds",
                    knowledgeCandidateId.Trim());
                query = query.Where(x => EF.Functions.JsonContains(x.CustomFields, candidateFilter));
            }

            if (!string.IsNullOrWhiteSpace(examPointCandidateId))
            {
                var candidateFilter = QuestionCustomFieldHelpers.BuildArrayContainmentFilter(
                    "examPointCandidateIds",
                    examPointCandidateId.Trim());
                query = query.Where(x => EF.Functions.JsonContains(x.CustomFields, candidateFilter));
            }

            if (difficultyMin.HasValue)
            {
                query = query.Where(x => x.DifficultyEstimated != null && x.DifficultyEstimated >= difficultyMin.Value);
            }

            if (difficultyMax.HasValue)
            {
                query = query.Where(x => x.DifficultyEstimated != null && x.DifficultyEstimated <= difficultyMax.Value);
            }

            if (!string.IsNullOrWhiteSpace(sourceType))
            {
                var value = NormalizeToken(sourceType, "unknown");
                var blockQuestionIds =
                    from block in dbContext.QuestionBlocks.AsNoTracking()
                    where block.SourceRegionId != null
                    join region in dbContext.SourceRegions.AsNoTracking() on block.SourceRegionId!.Value equals region.Id
                    join document in dbContext.SourceDocuments.AsNoTracking() on region.SourceDocumentId equals document.Id
                    where document.SourceType == value
                    select block.QuestionItemId;
                var assetQuestionIds =
                    from asset in dbContext.QuestionAssets.AsNoTracking()
                    where asset.SourceRegionId != null
                    join region in dbContext.SourceRegions.AsNoTracking() on asset.SourceRegionId!.Value equals region.Id
                    join document in dbContext.SourceDocuments.AsNoTracking() on region.SourceDocumentId equals document.Id
                    where document.SourceType == value
                    select asset.QuestionItemId;
                var sourceQuestionIds = blockQuestionIds.Concat(assetQuestionIds).Distinct();
                query = query.Where(x => sourceQuestionIds.Contains(x.Id));
            }

            if (hasFormula.HasValue)
            {
                var formulaQuestionIds = dbContext.QuestionBlocks
                    .AsNoTracking()
                    .Where(x => x.BlockType == "formula")
                    .Select(x => x.QuestionItemId)
                    .Distinct();
                query = hasFormula.Value
                    ? query.Where(x => formulaQuestionIds.Contains(x.Id))
                    : query.Where(x => !formulaQuestionIds.Contains(x.Id));
            }

            if (hasTable.HasValue)
            {
                var tableQuestionIds = dbContext.QuestionBlocks
                    .AsNoTracking()
                    .Where(x => x.BlockType == "table")
                    .Select(x => x.QuestionItemId)
                    .Distinct();
                query = hasTable.Value
                    ? query.Where(x => tableQuestionIds.Contains(x.Id))
                    : query.Where(x => !tableQuestionIds.Contains(x.Id));
            }

            if (hasImage.HasValue)
            {
                var imageQuestionIds = dbContext.QuestionAssets
                    .AsNoTracking()
                    .Where(x => x.AssetType == "image" || x.AssetType == "question_region_image")
                    .Select(x => x.QuestionItemId)
                    .Distinct();
                query = hasImage.Value
                    ? query.Where(x => imageQuestionIds.Contains(x.Id))
                    : query.Where(x => !imageQuestionIds.Contains(x.Id));
            }

            var pagination = PaginationWindow.Create(page, limit, defaultPageSize: 20, maxPageSize: 50);
            var pageSize = pagination.PageSize;
            var pageIndex = pagination.Page;
            var offset = pagination.Offset;
            var normalizedSortBy = NormalizeToken(sortBy ?? string.Empty, "updated_at");
            var sortDescending = string.Equals(NormalizeToken(order ?? string.Empty, "desc"), "desc", StringComparison.OrdinalIgnoreCase);
            int total;
            List<QuestionItem> items;
            if (normalizedSortBy is "question_no" or "exam_question_no")
            {
                total = await query.CountAsync(cancellationToken);
                var sortedQuery = sortDescending
                    ? query
                        .OrderByDescending(x => x.QuestionNo ?? int.MinValue)
                        .ThenByDescending(x => x.UpdatedAt)
                        .ThenByDescending(x => x.CreatedAt)
                    : query
                        .OrderBy(x => x.QuestionNo ?? int.MaxValue)
                        .ThenBy(x => x.UpdatedAt)
                        .ThenBy(x => x.CreatedAt);
                items = await sortedQuery
                    .Skip(offset)
                    .Take(pageSize)
                    .ToListAsync(cancellationToken);
            }
            else
            {
                total = await query.CountAsync(cancellationToken);
                items = await query
                    .OrderByDescending(x => x.UpdatedAt)
                    .ThenByDescending(x => x.CreatedAt)
                    .Skip(offset)
                    .Take(pageSize)
                    .ToListAsync(cancellationToken);
            }

            var questionIds = items.Select(x => x.Id).ToArray();
            var blocks = await dbContext.QuestionBlocks
                .AsNoTracking()
                .Where(x => questionIds.Contains(x.QuestionItemId))
                .OrderBy(x => x.SortOrder)
                .ToListAsync(cancellationToken);
            var assets = await dbContext.QuestionAssets
                .AsNoTracking()
                .Where(x => questionIds.Contains(x.QuestionItemId))
                .ToListAsync(cancellationToken);

            var primaryKnowledgeIds = items
                .Select(x => x.PrimaryKnowledgeId)
                .Where(x => x.HasValue)
                .Select(x => x!.Value)
                .Distinct()
                .ToArray();
            var knowledgeById = await dbContext.KnowledgeNodes
                .AsNoTracking()
                .Where(x => primaryKnowledgeIds.Contains(x.Id))
                .ToDictionaryAsync(x => x.Id, cancellationToken);

            var candidateStableIds = items
                .SelectMany(item => new[]
                {
                    QuestionCustomFieldHelpers.TryGetStringField(item.CustomFields, "primaryKnowledgeCandidateId"),
                    QuestionCustomFieldHelpers.TryGetStringField(item.CustomFields, "primaryExamPointCandidateId")
                })
                .Where(value => !string.IsNullOrWhiteSpace(value))
                .Select(value => value!)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();
            var candidateAssets = await dbContext.DomainAssetVersions
                .AsNoTracking()
                .Where(x => x.Status == "active" && candidateStableIds.Contains(x.StableId))
                .OrderByDescending(x => x.Version)
                .ToListAsync(cancellationToken);
            var candidateAssetByStableId = candidateAssets
                .GroupBy(x => x.StableId, StringComparer.OrdinalIgnoreCase)
                .ToDictionary(x => x.Key, x => x.First(), StringComparer.OrdinalIgnoreCase);

            var sourceRows = await (
                from block in dbContext.QuestionBlocks.AsNoTracking()
                where questionIds.Contains(block.QuestionItemId) && block.SourceRegionId != null
                join region in dbContext.SourceRegions.AsNoTracking() on block.SourceRegionId!.Value equals region.Id
                join document in dbContext.SourceDocuments.AsNoTracking() on region.SourceDocumentId equals document.Id
                select new
                {
                    block.QuestionItemId,
                    document.SourceTitle,
                    document.SourceType,
                    document.LicenseOrPermission,
                    document.SharingAllowed,
                    document.ContainsStudentPii,
                    document.AnonymizationStatus,
                    HasScreenshot = !string.IsNullOrWhiteSpace(region.ScreenshotRelativePath)
                }
            ).Concat(
                from asset in dbContext.QuestionAssets.AsNoTracking()
                where questionIds.Contains(asset.QuestionItemId) && asset.SourceRegionId != null
                join region in dbContext.SourceRegions.AsNoTracking() on asset.SourceRegionId!.Value equals region.Id
                join document in dbContext.SourceDocuments.AsNoTracking() on region.SourceDocumentId equals document.Id
                select new
                {
                    asset.QuestionItemId,
                    document.SourceTitle,
                    document.SourceType,
                    document.LicenseOrPermission,
                    document.SharingAllowed,
                    document.ContainsStudentPii,
                    document.AnonymizationStatus,
                    HasScreenshot = !string.IsNullOrWhiteSpace(region.ScreenshotRelativePath)
                }
            ).ToListAsync(cancellationToken);

            var blockByQuestionId = blocks.GroupBy(x => x.QuestionItemId).ToDictionary(x => x.Key, x => x.ToArray());
            var assetCountByQuestionId = assets.GroupBy(x => x.QuestionItemId).ToDictionary(x => x.Key, x => x.Count());
            var hasFormulaByQuestionId = blocks
                .Where(x => x.BlockType == "formula")
                .GroupBy(x => x.QuestionItemId)
                .ToDictionary(x => x.Key, _ => true);
            var hasTableByQuestionId = blocks
                .Where(x => x.BlockType == "table")
                .GroupBy(x => x.QuestionItemId)
                .ToDictionary(x => x.Key, _ => true);
            var hasImageByQuestionId = assets
                .Where(x => x.AssetType == "image" || x.AssetType == "question_region_image")
                .GroupBy(x => x.QuestionItemId)
                .ToDictionary(x => x.Key, _ => true);
            var sourceByQuestionId = sourceRows
                .GroupBy(x => x.QuestionItemId)
                .ToDictionary(
                    x => x.Key,
                    x => new SourceSummaryResponse(
                        x.Select(row => row.SourceTitle).Where(value => !string.IsNullOrWhiteSpace(value)).Distinct().ToArray(),
                        x.Select(row => row.SourceType).Where(value => !string.IsNullOrWhiteSpace(value)).Distinct().ToArray(),
                        x.Select(row => row.LicenseOrPermission).Where(value => !string.IsNullOrWhiteSpace(value)).Distinct().ToArray(),
                        x.All(row => row.SharingAllowed),
                        x.Any(row => row.ContainsStudentPii),
                        x.Select(row => row.AnonymizationStatus).Where(value => !string.IsNullOrWhiteSpace(value)).Distinct().ToArray(),
                        x.Count(),
                        x.Count(row => row.HasScreenshot)));

            var cards = items.Select(item =>
            {
                blockByQuestionId.TryGetValue(item.Id, out var itemBlocks);
                assetCountByQuestionId.TryGetValue(item.Id, out var assetCount);
                sourceByQuestionId.TryGetValue(item.Id, out var sourceSummary);
                var primaryKnowledge = item.PrimaryKnowledgeId.HasValue && knowledgeById.TryGetValue(item.PrimaryKnowledgeId.Value, out var node)
                    ? KnowledgeNodeCardResponse.From(node)
                    : null;
                var primaryKnowledgeCandidateId = QuestionCustomFieldHelpers.TryGetStringField(
                    item.CustomFields,
                    "primaryKnowledgeCandidateId");
                var primaryExamPointCandidateId = QuestionCustomFieldHelpers.TryGetStringField(
                    item.CustomFields,
                    "primaryExamPointCandidateId");
                CandidateAssetReferenceResponse? CandidateReference(string? stableId)
                {
                    return !string.IsNullOrWhiteSpace(stableId) &&
                           candidateAssetByStableId.TryGetValue(stableId, out var asset)
                        ? new CandidateAssetReferenceResponse(asset.StableId, asset.DisplayName)
                        : null;
                }
                var candidateTags = primaryKnowledgeCandidateId is not null || primaryExamPointCandidateId is not null
                    ? new QuestionCandidateTagsResponse(
                        CandidateReference(primaryKnowledgeCandidateId),
                        CandidateReference(primaryExamPointCandidateId),
                        QuestionCustomFieldHelpers.TryGetStringArrayField(item.CustomFields, "abilityDimensions"),
                        QuestionCustomFieldHelpers.TryGetStringField(item.CustomFields, "taggingStatus") ?? "pending_review",
                        QuestionCustomFieldHelpers.TryGetBoolField(item.CustomFields, "productionEligible") ?? false)
                    : null;

                return new QuestionCardResponse(
                    item.Id,
                    item.Subject,
                    item.Stage,
                    item.Grade,
                    item.QuestionType,
                    item.DefaultScore,
                    item.DifficultyEstimated,
                    item.Status,
                    QuestionCustomFieldHelpers.TryGetIntField(item.CustomFields, "questionNo"),
                    primaryKnowledge,
                    candidateTags,
                    GetQuestionPreview(itemBlocks ?? []),
                    itemBlocks?.Length ?? 0,
                    assetCount,
                    sourceSummary ?? new SourceSummaryResponse([], [], [], false, false, [], 0, 0),
                    hasFormulaByQuestionId.ContainsKey(item.Id),
                    hasTableByQuestionId.ContainsKey(item.Id),
                    hasImageByQuestionId.ContainsKey(item.Id));
            }).ToArray();

            return Results.Ok(new QuestionSearchResponse(
                Mode: "draft_test",
                ProductionEligible: false,
                Total: total,
                Page: pageIndex,
                Limit: pageSize,
                KnowledgeStatus: usesCandidateFilters
                    ? "candidate_filters"
                    : primaryKnowledgeId.HasValue
                    ? "by_primary_knowledge_id"
                    : (string.IsNullOrWhiteSpace(knowledgeStatus) ? KnowledgeStatuses.Active : NormalizeToken(knowledgeStatus, KnowledgeStatuses.Active)),
                KnowledgeVersion: usesCandidateFilters || primaryKnowledgeId.HasValue
                    ? null
                    : (knowledgeVersion ?? 1),
                Items: cards));
        })
        .WithName("SearchQuestionCards");
        app.MapGet("/questions/{id:guid}", async (Guid id, KqgDbContext dbContext, CancellationToken cancellationToken) =>
        {
            var item = await dbContext.QuestionItems.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (item is null)
            {
                return Results.NotFound();
            }

            var blocks = await dbContext.QuestionBlocks
                .AsNoTracking()
                .Where(x => x.QuestionItemId == id)
                .OrderBy(x => x.SortOrder)
                .ToListAsync(cancellationToken);
            var assets = await dbContext.QuestionAssets
                .AsNoTracking()
                .Where(x => x.QuestionItemId == id)
                .OrderBy(x => x.CreatedAt)
                .ToListAsync(cancellationToken);

            return Results.Ok(QuestionResponse.From(item, blocks, assets));
        })
        .WithName("GetQuestion");
        app.MapPatch("/questions/{id:guid}", async (
            Guid id,
            QuestionUpdateRequest request,
            HttpContext httpContext,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            if (string.IsNullOrWhiteSpace(request.Reason))
            {
                return Results.BadRequest(new { error = "reason_required" });
            }

            var auditedActor = ResolveAuditedActor(httpContext);

            var item = await dbContext.QuestionItems.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (item is null)
            {
                return Results.NotFound(new { error = "question_not_found" });
            }

            if (request.DifficultyEstimated is < 0 or > 1)
            {
                return Results.BadRequest(new { error = "invalid_difficulty_estimated" });
            }

            if (request.PrimaryKnowledgeId.HasValue && request.ClearPrimaryKnowledge is true)
            {
                return Results.BadRequest(new { error = "primary_knowledge_update_conflict" });
            }

            if (request.PrimaryKnowledgeId.HasValue)
            {
                var knowledgeExists = await dbContext.KnowledgeNodes
                    .AsNoTracking()
                    .AnyAsync(x => x.Id == request.PrimaryKnowledgeId.Value, cancellationToken);
                if (!knowledgeExists)
                {
                    return Results.Conflict(new { error = "primary_knowledge_missing", primaryKnowledgeId = request.PrimaryKnowledgeId.Value });
                }
            }

            var currentPrimaryKnowledgeId = item.PrimaryKnowledgeId;
            var requestedBlocks = request.Blocks ?? [];
            foreach (var block in requestedBlocks)
            {
                if (!string.IsNullOrWhiteSpace(block.BlockType) && !IsAllowedQuestionBlockType(NormalizeToken(block.BlockType, "text")))
                {
                    return Results.BadRequest(new { error = "invalid_block_type" });
                }
            }

            var sourceRegionIds = requestedBlocks
                .Select(x => x.SourceRegionId)
                .Where(x => x.HasValue)
                .Select(x => x!.Value)
                .Distinct()
                .ToArray();
            if (sourceRegionIds.Length > 0)
            {
                var found = await dbContext.SourceRegions
                    .AsNoTracking()
                    .Where(x => sourceRegionIds.Contains(x.Id))
                    .Select(x => x.Id)
                    .ToListAsync(cancellationToken);
                if (found.Count != sourceRegionIds.Length)
                {
                    return Results.Conflict(new { error = "source_region_missing" });
                }
            }

            var blocks = await dbContext.QuestionBlocks
                .Where(x => x.QuestionItemId == id)
                .OrderBy(x => x.SortOrder)
                .ToListAsync(cancellationToken);
            var assets = await dbContext.QuestionAssets
                .AsNoTracking()
                .Where(x => x.QuestionItemId == id)
                .OrderBy(x => x.CreatedAt)
                .ToListAsync(cancellationToken);
            var before = QuestionResponse.From(item, blocks, assets);

            if (!string.IsNullOrWhiteSpace(request.QuestionType))
            {
                item.QuestionType = NormalizeToken(request.QuestionType, "unknown");
            }
            if (request.DefaultScore.HasValue)
            {
                item.DefaultScore = request.DefaultScore;
            }
            if (request.DifficultyEstimated.HasValue)
            {
                item.DifficultyEstimated = request.DifficultyEstimated;
            }
            if (!string.IsNullOrWhiteSpace(request.Status))
            {
                item.Status = NormalizeToken(request.Status, QuestionStatuses.Draft);
            }
            if (request.PrimaryKnowledgeId.HasValue)
            {
                item.PrimaryKnowledgeId = request.PrimaryKnowledgeId.Value;
                var primaryMappings = await dbContext.KnowledgeMappings
                    .Where(x => x.QuestionItemId == id && x.IsPrimary)
                    .ToListAsync(cancellationToken);
                foreach (var mapping in primaryMappings)
                {
                    mapping.IsPrimary = false;
                }

                var targetMapping = await dbContext.KnowledgeMappings
                    .FirstOrDefaultAsync(
                        x => x.QuestionItemId == id && x.KnowledgeNodeId == request.PrimaryKnowledgeId.Value,
                        cancellationToken);
                if (targetMapping is null)
                {
                    dbContext.KnowledgeMappings.Add(new KnowledgeMapping
                    {
                        QuestionItemId = id,
                        KnowledgeNodeId = request.PrimaryKnowledgeId.Value,
                        MappingSource = KnowledgeMappingSources.Manual,
                        IsPrimary = true,
                        Confidence = 1.0m,
                        Version = 1,
                        Evidence = SerializeJson(new
                        {
                            source = "question_update",
                            reviewedBy = auditedActor,
                            reason = request.Reason.Trim()
                        }),
                        CreatedAt = DateTimeOffset.UtcNow
                    });
                }
                else
                {
                    targetMapping.MappingSource = KnowledgeMappingSources.Manual;
                    targetMapping.IsPrimary = true;
                    targetMapping.Confidence = 1.0m;
                    targetMapping.Version = 1;
                    targetMapping.Evidence = SerializeJson(new
                    {
                        source = "question_update",
                        reviewedBy = auditedActor,
                        reason = request.Reason.Trim()
                    });
                }
            }
            else if (request.ClearPrimaryKnowledge is true)
            {
                item.PrimaryKnowledgeId = null;

                var primaryMappings = await dbContext.KnowledgeMappings
                    .Where(x => x.QuestionItemId == id && x.IsPrimary)
                    .ToListAsync(cancellationToken);
                foreach (var mapping in primaryMappings)
                {
                    mapping.IsPrimary = false;
                }

                if (currentPrimaryKnowledgeId.HasValue)
                {
                    var targetMapping = await dbContext.KnowledgeMappings
                        .FirstOrDefaultAsync(
                            x => x.QuestionItemId == id && x.KnowledgeNodeId == currentPrimaryKnowledgeId.Value,
                            cancellationToken);
                    if (targetMapping is not null)
                    {
                        dbContext.KnowledgeMappings.Remove(targetMapping);
                    }
                }
            }

            var blockById = blocks.ToDictionary(x => x.Id);
            var nextSortOrder = blocks.Count == 0 ? 0 : blocks.Max(x => x.SortOrder) + 1;
            foreach (var blockPatch in requestedBlocks)
            {
                if (blockPatch.ClearSourceRegion is true && blockPatch.SourceRegionId.HasValue)
                {
                    return Results.BadRequest(new { error = "question_block_source_region_clear_conflict" });
                }

                QuestionBlock block;
                if (blockPatch.Id.HasValue)
                {
                    if (!blockById.TryGetValue(blockPatch.Id.Value, out block!))
                    {
                        return Results.Conflict(new { error = "question_block_missing", blockId = blockPatch.Id.Value });
                    }
                }
                else
                {
                    block = new QuestionBlock
                    {
                        QuestionItemId = id,
                        BlockType = "text",
                        SortOrder = nextSortOrder++,
                        Content = "{}",
                        CreatedAt = DateTimeOffset.UtcNow
                    };
                    dbContext.QuestionBlocks.Add(block);
                    blocks.Add(block);
                }

                if (!string.IsNullOrWhiteSpace(blockPatch.BlockType))
                {
                    block.BlockType = NormalizeToken(blockPatch.BlockType, "text");
                }
                if (blockPatch.SortOrder.HasValue)
                {
                    block.SortOrder = blockPatch.SortOrder.Value;
                }
                if (blockPatch.Content.HasValue)
                {
                    block.Content = SerializeJson(blockPatch.Content.Value);
                }
                if (blockPatch.ClearSourceRegion is true)
                {
                    block.SourceRegionId = null;
                }
                else if (blockPatch.SourceRegionId.HasValue)
                {
                    block.SourceRegionId = blockPatch.SourceRegionId;
                }
            }

            var answer = request.Answer.HasValue
                ? request.Answer.Value.Clone()
                : QuestionCustomFieldHelpers.TryGetElement(item.CustomFields, "answer");
            var solution = request.Solution.HasValue
                ? request.Solution.Value.Clone()
                : QuestionCustomFieldHelpers.TryGetElement(item.CustomFields, "solution");
            item.CustomFields = QuestionCustomFieldHelpers.Merge(
                item.CustomFields,
                answer,
                solution,
                request.PrimaryKnowledgeLabel,
                request.KnowledgeTags);
            item.Blocks = SerializeJson(blocks.OrderBy(x => x.SortOrder).Select(block => new
            {
                type = block.BlockType,
                order = block.SortOrder,
                content = JsonHelpers.ParseJsonElement(block.Content),
                source_region_id = block.SourceRegionId
            }));
            item.UpdatedAt = DateTimeOffset.UtcNow;

            var now = DateTimeOffset.UtcNow;
            var audit = new ReviewQueueItem
            {
                ReviewType = "question_revision",
                Status = ReviewStatuses.Resolved,
                CreatedAt = now,
                ResolvedAt = now,
                Payload = JsonSerializer.Serialize(new
                {
                    questionItemId = id,
                    before,
                    after = QuestionResponse.From(item, blocks.OrderBy(x => x.SortOrder).ToList(), assets),
                    reviewAudit = new
                    {
                        reviewedBy = auditedActor,
                        decision = "question_updated",
                        reason = request.Reason.Trim(),
                        reviewedAt = now.ToString("O")
                    }
                })
            };
            dbContext.ReviewQueueItems.Add(audit);

            await dbContext.SaveChangesAsync(cancellationToken);
            var afterBlocks = await dbContext.QuestionBlocks
                .AsNoTracking()
                .Where(x => x.QuestionItemId == id)
                .OrderBy(x => x.SortOrder)
                .ToListAsync(cancellationToken);
            return Results.Ok(new QuestionRevisionResponse(QuestionResponse.From(item, afterBlocks, assets), audit.Id));
        })
        .WithName("UpdateQuestion");
        app.MapPost("/questions/{id:guid}/assets", async (
            Guid id,
            QuestionAssetAssociationRequest request,
            HttpContext httpContext,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            if (string.IsNullOrWhiteSpace(request.Reason))
            {
                return Results.BadRequest(new { error = "reason_required" });
            }

            var auditedActor = ResolveAuditedActor(httpContext);

            var itemExists = await dbContext.QuestionItems.AsNoTracking().AnyAsync(x => x.Id == id, cancellationToken);
            if (!itemExists)
            {
                return Results.NotFound(new { error = "question_not_found" });
            }

            var sourceRegionExists = await dbContext.SourceRegions
                .AsNoTracking()
                .AnyAsync(x => x.Id == request.SourceRegionId, cancellationToken);
            if (!sourceRegionExists)
            {
                return Results.Conflict(new { error = "source_region_missing" });
            }

            if (request.FileAssetId.HasValue)
            {
                var fileAssetExists = await dbContext.FileAssets
                    .AsNoTracking()
                    .AnyAsync(x => x.Id == request.FileAssetId.Value, cancellationToken);
                if (!fileAssetExists)
                {
                    return Results.Conflict(new { error = "file_asset_missing" });
                }
            }

            var now = DateTimeOffset.UtcNow;
            var asset = new QuestionAsset
            {
                QuestionItemId = id,
                FileAssetId = request.FileAssetId,
                SourceRegionId = request.SourceRegionId,
                AssetType = string.IsNullOrWhiteSpace(request.AssetType) ? "image" : NormalizeToken(request.AssetType, "image"),
                Purpose = string.IsNullOrWhiteSpace(request.Purpose) ? "question_figure" : NormalizeToken(request.Purpose, "question_figure"),
                Metadata = SerializeJson(request.Metadata),
                CreatedAt = now
            };
            dbContext.QuestionAssets.Add(asset);

            var audit = new ReviewQueueItem
            {
                ReviewType = "question_asset_revision",
                Status = ReviewStatuses.Resolved,
                CreatedAt = now,
                ResolvedAt = now,
                Payload = JsonSerializer.Serialize(new
                {
                    questionItemId = id,
                    questionAssetId = asset.Id,
                    sourceRegionId = asset.SourceRegionId,
                    fileAssetId = asset.FileAssetId,
                    assetType = asset.AssetType,
                    purpose = asset.Purpose,
                    decision = "question_asset_associated",
                    reviewAudit = new
                    {
                        reviewedBy = auditedActor,
                        decision = "question_asset_associated",
                        reason = request.Reason.Trim(),
                        reviewedAt = now.ToString("O")
                    }
                })
            };
            dbContext.ReviewQueueItems.Add(audit);

            await dbContext.SaveChangesAsync(cancellationToken);
            return Results.Created($"/questions/{id}/assets/{asset.Id}", new QuestionAssetRevisionResponse(QuestionAssetResponse.From(asset), audit.Id));
        })
        .WithName("AssociateQuestionAsset");
        app.MapDelete("/questions/{id:guid}/assets/{assetId:guid}", async (
            Guid id,
            Guid assetId,
            string? reviewedBy,
            string reason,
            HttpContext httpContext,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            if (string.IsNullOrWhiteSpace(reason))
            {
                return Results.BadRequest(new { error = "reason_required" });
            }

            var auditedActor = ResolveAuditedActor(httpContext);

            var asset = await dbContext.QuestionAssets.FirstOrDefaultAsync(x => x.Id == assetId && x.QuestionItemId == id, cancellationToken);
            if (asset is null)
            {
                return Results.NotFound(new { error = "question_asset_not_found" });
            }

            var now = DateTimeOffset.UtcNow;
            var sourceRegionId = asset.SourceRegionId;
            var fileAssetId = asset.FileAssetId;
            var assetType = asset.AssetType;
            var purpose = asset.Purpose;
            dbContext.QuestionAssets.Remove(asset);

            var audit = new ReviewQueueItem
            {
                ReviewType = "question_asset_revision",
                Status = ReviewStatuses.Resolved,
                CreatedAt = now,
                ResolvedAt = now,
                Payload = JsonSerializer.Serialize(new
                {
                    questionItemId = id,
                    questionAssetId = assetId,
                    sourceRegionId,
                    fileAssetId,
                    assetType,
                    purpose,
                    decision = "question_asset_unlinked",
                    reviewAudit = new
                    {
                        reviewedBy = auditedActor,
                        decision = "question_asset_unlinked",
                        reason = reason.Trim(),
                        reviewedAt = now.ToString("O")
                    }
                })
            };
            dbContext.ReviewQueueItems.Add(audit);

            await dbContext.SaveChangesAsync(cancellationToken);
            return Results.Ok(new QuestionAssetUnlinkResponse(id, assetId, sourceRegionId, audit.Id));
        })
        .WithName("UnlinkQuestionAsset");
        app.MapGet("/questions/{id:guid}/sources", async (
            Guid id,
            KqgDbContext dbContext,
            IConfiguration configuration,
            CancellationToken cancellationToken) =>
        {
            var itemExists = await dbContext.QuestionItems.AsNoTracking().AnyAsync(x => x.Id == id, cancellationToken);
            if (!itemExists)
            {
                return Results.NotFound();
            }

            var blockRegionIds = dbContext.QuestionBlocks
                .AsNoTracking()
                .Where(x => x.QuestionItemId == id && x.SourceRegionId != null)
                .Select(x => x.SourceRegionId!.Value);
            var assetRegionIds = dbContext.QuestionAssets
                .AsNoTracking()
                .Where(x => x.QuestionItemId == id && x.SourceRegionId != null)
                .Select(x => x.SourceRegionId!.Value);
            var sourceRegionIds = await blockRegionIds
                .Concat(assetRegionIds)
                .Distinct()
                .ToListAsync(cancellationToken);

            var regions = await dbContext.SourceRegions
                .AsNoTracking()
                .Where(x => sourceRegionIds.Contains(x.Id))
                .OrderBy(x => x.PageNumber)
                .ThenBy(x => x.CreatedAt)
                .ToListAsync(cancellationToken);

            var sourceDocumentIds = regions.Select(x => x.SourceDocumentId).Distinct().ToArray();
            var documents = await dbContext.SourceDocuments
                .AsNoTracking()
                .Where(x => sourceDocumentIds.Contains(x.Id))
                .ToDictionaryAsync(x => x.Id, cancellationToken);

            var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
            var missingScreenshot = regions.FirstOrDefault(x =>
                !string.IsNullOrWhiteSpace(x.ScreenshotRelativePath) &&
                (!TryResolveFileStorePath(paths.FileStoreRoot, x.ScreenshotRelativePath, out var screenshotPath) || !File.Exists(screenshotPath)));
            if (missingScreenshot is not null)
            {
                return Results.Conflict(new { error = "question_source_screenshot_missing", regionId = missingScreenshot.Id, missingScreenshot.ScreenshotRelativePath });
            }

            return Results.Ok(new QuestionSourceReviewResponse(
                id,
                regions.Select(region =>
                {
                    documents.TryGetValue(region.SourceDocumentId, out var document);
                    return QuestionSourceRegionResponse.From(region, document);
                }).ToArray()));
        })
        .WithName("GetQuestionSources");
    }
}
