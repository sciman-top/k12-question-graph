namespace K12QuestionGraph.Api.Endpoints;

using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Configuration;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.FileStore;
using K12QuestionGraph.Api.Infrastructure.Json;
using K12QuestionGraph.Api.Infrastructure.Workers;
using K12QuestionGraph.Api.ImportJobs;
using K12QuestionGraph.Api.Questions;
using K12QuestionGraph.Api.Workers;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using static K12QuestionGraph.Api.FileStore.FormHelpers;
using static K12QuestionGraph.Api.Questions.QuestionHelpers;

public static class SourceDocumentEndpoints
{
    public static void MapSourceDocumentEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapPost("/files", async (HttpRequest request, LocalFileStore fileStore, CancellationToken cancellationToken) =>
        {
            var form = await request.ReadFormAsync(cancellationToken);
            var file = form.Files.GetFile("file");
            if (file is null)
            {
                return Results.BadRequest(new { error = "missing_file" });
            }

            if (file.Length <= 0)
            {
                return Results.BadRequest(new { error = "empty_file" });
            }

            if (file.Length > UploadStoragePolicy.MaxUploadBytes)
            {
                return Results.Json(
                    new { error = "file_too_large", maxBytes = UploadStoragePolicy.MaxUploadBytes },
                    statusCode: StatusCodes.Status413PayloadTooLarge);
            }

            FileAssetResponse stored;
            try
            {
                await using var stream = file.OpenReadStream();
                stored = await fileStore.StoreOriginalAsync(
                    stream,
                    file.FileName,
                    file.ContentType,
                    file.Length,
                    SourceMetadataFromForm(form, file.FileName),
                    cancellationToken);
            }
            catch (UnsupportedUploadTypeException exception)
            {
                return Results.Json(
                    new { error = exception.Code },
                    statusCode: StatusCodes.Status415UnsupportedMediaType);
            }

            return Results.Created($"/files/{stored.Id}", stored);
        })
        .DisableAntiforgery()
        .WithName("UploadFile");
        app.MapGet("/source-documents", async (
            string? sourceType,
            string? materialBatchKey,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            var query =
                from document in dbContext.SourceDocuments.AsNoTracking()
                join file in dbContext.FileAssets.AsNoTracking() on document.FileAssetId equals file.Id
                select new { document, file };

            if (!string.IsNullOrWhiteSpace(sourceType))
            {
                var value = NormalizeToken(sourceType, "unknown");
                query = query.Where(x => x.document.SourceType == value);
            }

            if (!string.IsNullOrWhiteSpace(materialBatchKey))
            {
                var value = NormalizeToken(materialBatchKey, string.Empty);
                query = query.Where(x => x.document.MaterialBatchKey == value);
            }

            var rows = await query
                .OrderByDescending(x => x.document.CreatedAt)
                .Take(100)
                .ToListAsync(cancellationToken);

            return Results.Ok(new SourceMaterialListResponse(
                Mode: "source_material_workbench_mvp",
                Items: rows.Select(x => SourceMaterialResponse.From(x.document, x.file)).ToArray()));
        })
        .WithName("ListSourceDocuments");
        app.MapPatch("/source-documents/{id:guid}/authorization", async (
            Guid id,
            SourceDocumentAuthorizationUpdateRequest request,
            HttpContext httpContext,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            if (string.IsNullOrWhiteSpace(request.Reason))
            {
                return Results.BadRequest(new { error = "reason_required" });
            }

            var sourceDocument = await dbContext.SourceDocuments
                .FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (sourceDocument is null)
            {
                return Results.NotFound(new { error = "source_document_not_found" });
            }
            var file = await dbContext.FileAssets
                .AsNoTracking()
                .FirstOrDefaultAsync(x => x.Id == sourceDocument.FileAssetId, cancellationToken);
            if (file is null)
            {
                return Results.Conflict(new { error = "source_file_missing", fileAssetId = sourceDocument.FileAssetId });
            }

            var before = SourceMaterialResponse.From(sourceDocument, file);
            if (!string.IsNullOrWhiteSpace(request.LicenseOrPermission))
            {
                sourceDocument.LicenseOrPermission = NormalizeToken(request.LicenseOrPermission, "unknown");
            }
            if (request.SharingAllowed.HasValue)
            {
                sourceDocument.SharingAllowed = request.SharingAllowed.Value;
            }
            if (request.ContainsStudentPii.HasValue)
            {
                sourceDocument.ContainsStudentPii = request.ContainsStudentPii.Value;
            }
            if (!string.IsNullOrWhiteSpace(request.AnonymizationStatus))
            {
                sourceDocument.AnonymizationStatus = NormalizeToken(request.AnonymizationStatus, "not_applicable");
            }
            if (request.MayUseForKnowledgeExtraction.HasValue)
            {
                sourceDocument.MayUseForKnowledgeExtraction = request.MayUseForKnowledgeExtraction.Value;
            }
            if (request.MayUseForExamPointExtraction.HasValue)
            {
                sourceDocument.MayUseForExamPointExtraction = request.MayUseForExamPointExtraction.Value;
            }
            if (request.MayUseForTrendAnalysis.HasValue)
            {
                sourceDocument.MayUseForTrendAnalysis = request.MayUseForTrendAnalysis.Value;
            }

            var normalizedAuthorization = SourceDocumentMetadataPolicy.Normalize(new SourceDocumentMetadata(
                sourceDocument.SourceType,
                sourceDocument.SourceTitle,
                sourceDocument.Region,
                sourceDocument.Year,
                sourceDocument.GradeOrScope,
                sourceDocument.EditionOrVersion,
                sourceDocument.MaterialBatchKey,
                sourceDocument.OwnerScope,
                sourceDocument.LicenseOrPermission,
                sourceDocument.SharingAllowed,
                sourceDocument.ContainsStudentPii,
                sourceDocument.AnonymizationStatus,
                sourceDocument.MayUseForKnowledgeExtraction,
                sourceDocument.MayUseForExamPointExtraction,
                sourceDocument.MayUseForTrendAnalysis));
            bool externalAiAllowed;
            try
            {
                externalAiAllowed = SourceDocumentMetadataPolicy.ResolveExternalAiAllowed(
                    normalizedAuthorization,
                    sourceDocument.ExternalAiAllowed,
                    request.ExternalAiAllowed);
            }
            catch (ArgumentException exception) when (exception.Message.Contains("external_ai_policy_not_satisfied", StringComparison.Ordinal))
            {
                return Results.BadRequest(new { error = "external_ai_policy_not_satisfied" });
            }

            sourceDocument.SourceType = normalizedAuthorization.SourceType;
            sourceDocument.SourceTitle = normalizedAuthorization.SourceTitle;
            sourceDocument.Region = normalizedAuthorization.Region;
            sourceDocument.GradeOrScope = normalizedAuthorization.GradeOrScope;
            sourceDocument.EditionOrVersion = normalizedAuthorization.EditionOrVersion;
            sourceDocument.MaterialBatchKey = normalizedAuthorization.MaterialBatchKey;
            sourceDocument.OwnerScope = normalizedAuthorization.OwnerScope;
            sourceDocument.LicenseOrPermission = normalizedAuthorization.LicenseOrPermission;
            sourceDocument.SharingAllowed = normalizedAuthorization.SharingAllowed;
            sourceDocument.AnonymizationStatus = normalizedAuthorization.AnonymizationStatus;
            sourceDocument.MayUseForKnowledgeExtraction = normalizedAuthorization.MayUseForKnowledgeExtraction;
            sourceDocument.MayUseForExamPointExtraction = normalizedAuthorization.MayUseForExamPointExtraction;
            sourceDocument.MayUseForTrendAnalysis = normalizedAuthorization.MayUseForTrendAnalysis;
            sourceDocument.ExternalAiAllowed = externalAiAllowed;

            var now = DateTimeOffset.UtcNow;
            var auditedActor = ResolveAuditedActor(httpContext);
            var after = SourceMaterialResponse.From(sourceDocument, file);
            var audit = new ReviewQueueItem
            {
                ReviewType = "source_document_authorization",
                Status = ReviewStatuses.Resolved,
                CreatedAt = now,
                ResolvedAt = now,
                Payload = JsonSerializer.Serialize(new
                {
                    sourceDocumentId = id,
                    before,
                    after,
                    reviewAudit = new
                    {
                        reviewedBy = auditedActor,
                        decision = "source_document_authorization_updated",
                        reason = request.Reason.Trim(),
                        reviewedAt = now.ToString("O")
                    }
                })
            };
            dbContext.ReviewQueueItems.Add(audit);
            await dbContext.SaveChangesAsync(cancellationToken);

            return Results.Ok(new SourceDocumentAuthorizationUpdateResponse(after, audit.Id));
        })
        .WithName("UpdateSourceDocumentAuthorization");
        app.MapPost("/imports", async (HttpRequest request, LocalFileStore fileStore, KqgDbContext dbContext, CancellationToken cancellationToken) =>
        {
            var form = await request.ReadFormAsync(cancellationToken);
            var file = form.Files.GetFile("file");
            if (file is null)
            {
                return Results.BadRequest(new { error = "missing_file" });
            }

            if (file.Length <= 0)
            {
                return Results.BadRequest(new { error = "empty_file" });
            }

            if (file.Length > UploadStoragePolicy.MaxUploadBytes)
            {
                return Results.Json(
                    new { error = "file_too_large", maxBytes = UploadStoragePolicy.MaxUploadBytes },
                    statusCode: StatusCodes.Status413PayloadTooLarge);
            }

            FileAssetResponse stored;
            try
            {
                await using var stream = file.OpenReadStream();
                stored = await fileStore.StoreOriginalAsync(
                    stream,
                    file.FileName,
                    file.ContentType,
                    file.Length,
                    SourceMetadataFromForm(form, file.FileName),
                    cancellationToken);
            }
            catch (UnsupportedUploadTypeException exception)
            {
                return Results.Json(
                    new { error = exception.Code },
                    statusCode: StatusCodes.Status415UnsupportedMediaType);
            }

            var creation = await ImportJobCreation.CreateOrGetAsync(
                dbContext,
                stored,
                dbContext.SaveChangesAsync,
                cancellationToken);
            if (creation.ExistingJob is not null)
            {
                return Results.Ok(ImportJobResponse.From(creation.ExistingJob, stored));
            }

            return Results.Created($"/imports/{creation.CreatedJob!.Id}", ImportJobResponse.From(creation.CreatedJob, stored));
        })
        .DisableAntiforgery()
        .WithName("CreateImportJob");
        app.MapGet("/imports/{id:guid}", async (Guid id, KqgDbContext dbContext, CancellationToken cancellationToken) =>
        {
            var job = await dbContext.ImportJobs
                .AsNoTracking()
                .FirstOrDefaultAsync(x => x.Id == id, cancellationToken);

            return job is null ? Results.NotFound() : Results.Ok(ImportJobResponse.From(job));
        })
        .WithName("GetImportJob");
        app.MapPost("/source-documents/{id:guid}/regions", async (
            Guid id,
            SourceRegionCreateRequest request,
            KqgDbContext dbContext,
            IConfiguration configuration,
            CancellationToken cancellationToken) =>
        {
            var sourceDocument = await dbContext.SourceDocuments.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (sourceDocument is null)
            {
                return Results.NotFound(new { error = "source_document_not_found" });
            }

            var validationError = ValidateSourceRegionRequest(request);
            if (validationError is not null)
            {
                return Results.BadRequest(new { error = validationError });
            }

            if (!string.IsNullOrWhiteSpace(request.ScreenshotRelativePath))
            {
                var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
                if (!TryResolveFileStorePath(paths.FileStoreRoot, request.ScreenshotRelativePath, out var screenshotPath))
                {
                    return Results.BadRequest(new { error = "invalid_screenshot_relative_path" });
                }

                if (!File.Exists(screenshotPath))
                {
                    return Results.Conflict(new { error = "source_region_screenshot_missing", screenshotRelativePath = request.ScreenshotRelativePath });
                }
            }

            var region = new SourceRegion
            {
                SourceDocumentId = id,
                PageNumber = request.PageNumber,
                X = request.X,
                Y = request.Y,
                Width = request.Width,
                Height = request.Height,
                CoordinateUnit = NormalizeToken(request.CoordinateUnit, "percent"),
                ScreenshotRelativePath = string.IsNullOrWhiteSpace(request.ScreenshotRelativePath) ? null : request.ScreenshotRelativePath.Trim().Replace('\\', '/'),
                RegionType = string.IsNullOrWhiteSpace(request.RegionType) ? "preview" : NormalizeToken(request.RegionType, "preview")
            };

            dbContext.SourceRegions.Add(region);
            await dbContext.SaveChangesAsync(cancellationToken);

            return Results.Created($"/source-regions/{region.Id}", SourceRegionResponse.From(region));
        })
        .WithName("CreateSourceRegion");
        app.MapPatch("/source-regions/{id:guid}", async (
            Guid id,
            SourceRegionUpdateRequest request,
            HttpContext httpContext,
            KqgDbContext dbContext,
            IConfiguration configuration,
            CancellationToken cancellationToken) =>
        {
            if (string.IsNullOrWhiteSpace(request.Reason))
            {
                return Results.BadRequest(new { error = "reason_required" });
            }

            var region = await dbContext.SourceRegions.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (region is null)
            {
                return Results.NotFound(new { error = "source_region_not_found" });
            }

            if (request.ClearScreenshot is true && request.ScreenshotRelativePath is not null)
            {
                return Results.BadRequest(new { error = "source_region_screenshot_clear_conflict" });
            }

            var next = new SourceRegionCreateRequest(
                request.PageNumber ?? region.PageNumber,
                request.X ?? region.X,
                request.Y ?? region.Y,
                request.Width ?? region.Width,
                request.Height ?? region.Height,
                request.CoordinateUnit ?? region.CoordinateUnit,
                request.ClearScreenshot is true ? null : request.ScreenshotRelativePath ?? region.ScreenshotRelativePath,
                request.RegionType ?? region.RegionType);
            var validationError = ValidateSourceRegionRequest(next);
            if (validationError is not null)
            {
                return Results.BadRequest(new { error = validationError });
            }

            var normalizedScreenshotPath = string.IsNullOrWhiteSpace(next.ScreenshotRelativePath)
                ? null
                : next.ScreenshotRelativePath.Trim().Replace('\\', '/');
            if (!string.IsNullOrWhiteSpace(normalizedScreenshotPath))
            {
                var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
                if (!TryResolveFileStorePath(paths.FileStoreRoot, normalizedScreenshotPath, out var screenshotPath))
                {
                    return Results.BadRequest(new { error = "invalid_screenshot_relative_path" });
                }

                if (!File.Exists(screenshotPath))
                {
                    return Results.Conflict(new { error = "source_region_screenshot_missing", screenshotRelativePath = normalizedScreenshotPath });
                }
            }

            var before = SourceRegionResponse.From(region);
            region.PageNumber = next.PageNumber;
            region.X = next.X;
            region.Y = next.Y;
            region.Width = next.Width;
            region.Height = next.Height;
            region.CoordinateUnit = NormalizeToken(next.CoordinateUnit, "percent");
            region.ScreenshotRelativePath = normalizedScreenshotPath;
            region.RegionType = string.IsNullOrWhiteSpace(next.RegionType) ? "preview" : NormalizeToken(next.RegionType, "preview");

            var now = DateTimeOffset.UtcNow;
            var auditedActor = ResolveAuditedActor(httpContext);
            var audit = new ReviewQueueItem
            {
                ReviewType = "source_region_revision",
                Status = ReviewStatuses.Resolved,
                ResolvedAt = now,
                CreatedAt = now,
                Payload = JsonSerializer.Serialize(new
                {
                    sourceRegionId = region.Id,
                    sourceDocumentId = region.SourceDocumentId,
                    before,
                    after = SourceRegionResponse.From(region),
                    reviewAudit = new
                    {
                        reviewedBy = auditedActor,
                        decision = "source_region_updated",
                        reason = request.Reason.Trim(),
                        reviewedAt = now.ToString("O")
                    }
                })
            };
            dbContext.ReviewQueueItems.Add(audit);
            await dbContext.SaveChangesAsync(cancellationToken);

            return Results.Ok(new SourceRegionUpdateResponse(SourceRegionResponse.From(region), audit.Id));
        })
        .WithName("UpdateSourceRegion");
        app.MapGet("/source-documents/{id:guid}/preview", async (
            Guid id,
            KqgDbContext dbContext,
            IConfiguration configuration,
            CancellationToken cancellationToken) =>
        {
            var sourceDocument = await dbContext.SourceDocuments.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (sourceDocument is null)
            {
                return Results.NotFound(new { error = "source_document_not_found" });
            }

            var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
            var regions = await dbContext.SourceRegions
                .AsNoTracking()
                .Where(x => x.SourceDocumentId == id)
                .OrderBy(x => x.PageNumber)
                .ThenBy(x => x.CreatedAt)
                .ToListAsync(cancellationToken);

            var missingScreenshot = regions.FirstOrDefault(x =>
                !string.IsNullOrWhiteSpace(x.ScreenshotRelativePath) &&
                (!TryResolveFileStorePath(paths.FileStoreRoot, x.ScreenshotRelativePath, out var screenshotPath) || !File.Exists(screenshotPath)));
            if (missingScreenshot is not null)
            {
                return Results.Conflict(new { error = "source_region_screenshot_missing", regionId = missingScreenshot.Id, missingScreenshot.ScreenshotRelativePath });
            }

            var pages = regions
                .GroupBy(x => x.PageNumber)
                .Select(x => new SourcePreviewPageResponse(
                    x.Key,
                    x.Select(SourceRegionResponse.From).ToArray()))
                .ToArray();

            return Results.Ok(new SourceDocumentPreviewResponse(id, pages));
        })
        .WithName("GetSourceDocumentPreview");
        app.MapGet("/source-documents/{id:guid}/quality-report", async (
            Guid id,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            var sourceDocument = await dbContext.SourceDocuments
                .AsNoTracking()
                .FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (sourceDocument is null)
            {
                return Results.NotFound(new { error = "source_document_not_found" });
            }

            var blockQuestionIds =
                from block in dbContext.QuestionBlocks.AsNoTracking()
                where block.SourceRegionId != null
                join region in dbContext.SourceRegions.AsNoTracking() on block.SourceRegionId!.Value equals region.Id
                where region.SourceDocumentId == id
                select block.QuestionItemId;
            var assetQuestionIds =
                from asset in dbContext.QuestionAssets.AsNoTracking()
                where asset.SourceRegionId != null
                join region in dbContext.SourceRegions.AsNoTracking() on asset.SourceRegionId!.Value equals region.Id
                where region.SourceDocumentId == id
                select asset.QuestionItemId;
            var questionIds = await blockQuestionIds
                .Concat(assetQuestionIds)
                .Distinct()
                .ToListAsync(cancellationToken);

            var questions = await dbContext.QuestionItems
                .AsNoTracking()
                .Where(x => questionIds.Contains(x.Id))
                .ToListAsync(cancellationToken);
            var blocks = await dbContext.QuestionBlocks
                .AsNoTracking()
                .Where(x => questionIds.Contains(x.QuestionItemId))
                .ToListAsync(cancellationToken);
            var assets = await dbContext.QuestionAssets
                .AsNoTracking()
                .Where(x => questionIds.Contains(x.QuestionItemId))
                .ToListAsync(cancellationToken);
            var regions = await dbContext.SourceRegions
                .AsNoTracking()
                .Where(x => x.SourceDocumentId == id)
                .ToListAsync(cancellationToken);

            var openReviewItems = await dbContext.ReviewQueueItems
                .AsNoTracking()
                .Where(x =>
                    x.Status == ReviewStatuses.Open &&
                    (x.SourceDocumentId == id ||
                     (x.QuestionItemId.HasValue && questionIds.Contains(x.QuestionItemId.Value))))
                .Select(x => new { x.ReviewType, x.Payload })
                .ToListAsync(cancellationToken);
            var relatedOpenReviewItems = openReviewItems.ToArray();

            var questionNumbers = questions
                .Select(x => QuestionCustomFieldHelpers.TryGetIntField(x.CustomFields, "questionNo"))
                .Where(x => x.HasValue)
                .Select(x => x!.Value)
                .Distinct()
                .OrderBy(x => x)
                .ToArray();
            var missingQuestionNumbers = questionNumbers.Length == 0
                ? Array.Empty<int>()
                : Enumerable.Range(questionNumbers.Min(), questionNumbers.Max() - questionNumbers.Min() + 1)
                    .Except(questionNumbers)
                    .ToArray();
            var linkedRegionIds = blocks
                .Select(x => x.SourceRegionId)
                .Concat(assets.Select(x => x.SourceRegionId))
                .Where(x => x.HasValue)
                .Select(x => x!.Value)
                .Distinct()
                .ToHashSet();
            var linkedRegions = regions.Where(x => linkedRegionIds.Contains(x.Id)).ToArray();
            var missingLinkedScreenshots = linkedRegions
                .Where(x => string.IsNullOrWhiteSpace(x.ScreenshotRelativePath))
                .Select(x => x.Id)
                .ToArray();

            var answerCoveredCount = questions.Count(x => QuestionCustomFieldHelpers.HasMeaningfulValue(x.CustomFields, "answer"));
            var solutionCoveredCount = questions.Count(x => QuestionCustomFieldHelpers.HasMeaningfulValue(x.CustomFields, "solution"));
            var tableCount = blocks.Count(x => string.Equals(x.BlockType, "table", StringComparison.OrdinalIgnoreCase));
            var formulaCount = blocks.Count(x => string.Equals(x.BlockType, "formula", StringComparison.OrdinalIgnoreCase));
            var imageAssets = assets.Where(x => string.Equals(x.AssetType, "image", StringComparison.OrdinalIgnoreCase)).ToArray();
            var imageMatchedQuestionCount = imageAssets.Select(x => x.QuestionItemId).Distinct().Count();
            var externalAiCalls = questions.Sum(x => QuestionCustomFieldHelpers.TryGetIntField(x.QualitySignals, "externalAiCalls") ?? 0);
            var noiseRetainedBlockCount = blocks.Count(QuestionBlockLooksLikeRetainedNoise);

            var gaps = new List<string>();
            if (questions.Count == 0)
            {
                gaps.Add("question_items_missing");
            }
            if (questionNumbers.Length != questions.Count || missingQuestionNumbers.Length > 0)
            {
                gaps.Add("question_number_incomplete");
            }
            if (answerCoveredCount != questions.Count)
            {
                gaps.Add("answer_coverage_incomplete");
            }
            if (missingLinkedScreenshots.Length > 0)
            {
                gaps.Add("linked_source_screenshot_missing");
            }
            if (relatedOpenReviewItems.Length > 0)
            {
                gaps.Add("manual_review_pending");
            }
            if (noiseRetainedBlockCount > 0)
            {
                gaps.Add("possible_layout_noise_retained");
            }

            var metrics = new SourceDocumentQualityMetricsResponse(
                QuestionCount: questions.Count,
                QuestionNumberCount: questionNumbers.Length,
                AnswerCoveredCount: answerCoveredCount,
                SolutionCoveredCount: solutionCoveredCount,
                SourceRegionCount: regions.Count,
                LinkedSourceRegionCount: linkedRegions.Length,
                LinkedSourceScreenshotCount: linkedRegions.Count(x => !string.IsNullOrWhiteSpace(x.ScreenshotRelativePath)),
                MissingLinkedSourceScreenshotCount: missingLinkedScreenshots.Length,
                ImageAssetCount: imageAssets.Length,
                ImageMatchedQuestionCount: imageMatchedQuestionCount,
                TableBlockCount: tableCount,
                FormulaBlockCount: formulaCount,
                PendingManualItemCount: relatedOpenReviewItems.Length,
                NoiseRetainedBlockCount: noiseRetainedBlockCount,
                ExternalAiCallCount: externalAiCalls);

            var closureStatus = gaps.Count == 0 ? "paper_quality_pass" : "not_closed";
            return Results.Ok(new SourceDocumentQualityReportResponse(
                SourceDocumentId: sourceDocument.Id,
                SourceTitle: sourceDocument.SourceTitle,
                SourceType: sourceDocument.SourceType,
                Region: sourceDocument.Region,
                Year: sourceDocument.Year,
                MaterialBatchKey: sourceDocument.MaterialBatchKey,
                ClosureStatus: closureStatus,
                FullClosureAllowed: false,
                Metrics: metrics,
                QuestionNumbers: questionNumbers,
                MissingQuestionNumbers: missingQuestionNumbers,
                MissingLinkedSourceRegionIds: missingLinkedScreenshots,
                PendingReviewTypes: relatedOpenReviewItems
                    .Select(x => x.ReviewType)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .OrderBy(x => x)
                    .ToArray(),
                Gaps: gaps,
                ExternalAiPolicy: externalAiCalls == 0 ? "no_external_ai_calls" : "external_ai_calls_require_review",
                RollbackSql: BuildSourceDocumentRollbackSql(sourceDocument.Id),
                SummaryChinese: gaps.Count == 0
                    ? "本份试卷题号、答案、来源截图和结构化质量指标通过；全量 REAL005 仍需逐年逐题证据。"
                    : $"本份试卷仍有 {gaps.Count} 类缺口：{string.Join("、", gaps)}。"));
        })
        .WithName("GetSourceDocumentQualityReport");
        app.MapGet("/source-regions/{id:guid}/screenshot", async (
            Guid id,
            KqgDbContext dbContext,
            IConfiguration configuration,
            CancellationToken cancellationToken) =>
        {
            var region = await dbContext.SourceRegions
                .AsNoTracking()
                .FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (region is null)
            {
                return Results.NotFound(new { error = "source_region_not_found" });
            }

            if (string.IsNullOrWhiteSpace(region.ScreenshotRelativePath))
            {
                return Results.Conflict(new { error = "source_region_screenshot_not_available", regionId = id });
            }

            var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
            if (!TryResolveFileStorePath(paths.FileStoreRoot, region.ScreenshotRelativePath, out var screenshotPath))
            {
                return Results.BadRequest(new { error = "invalid_screenshot_relative_path", regionId = id });
            }

            if (!File.Exists(screenshotPath))
            {
                return Results.Conflict(new { error = "source_region_screenshot_missing", regionId = id, region.ScreenshotRelativePath });
            }

            return Results.File(screenshotPath, InferContentType(screenshotPath), enableRangeProcessing: true);
        })
        .WithName("GetSourceRegionScreenshot");
        app.MapGet("/source-regions/{id:guid}/page-screenshot", async (
            Guid id,
            KqgDbContext dbContext,
            IConfiguration configuration,
            CancellationToken cancellationToken) =>
        {
            var region = await dbContext.SourceRegions
                .AsNoTracking()
                .FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (region is null)
            {
                return Results.NotFound(new { error = "source_region_not_found" });
            }

            var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
            var document = await dbContext.SourceDocuments
                .AsNoTracking()
                .FirstOrDefaultAsync(x => x.Id == region.SourceDocumentId, cancellationToken);
            if (document is null)
            {
                return Results.Conflict(new { error = "source_region_document_missing", regionId = id });
            }

            var relative = SourcePageScreenshotPathResolver.ResolveExistingRelativePath(
                paths.FileStoreRoot,
                document,
                region.PageNumber);
            if (relative is null)
            {
                return Results.Conflict(new
                {
                    error = "source_region_page_screenshot_missing",
                    regionId = id,
                    pageNumber = region.PageNumber,
                    candidateRelativePaths = SourcePageScreenshotPathResolver.GetCandidateRelativePaths(document, region.PageNumber)
                });
            }

            if (!TryResolveFileStorePath(paths.FileStoreRoot, relative, out var screenshotPath))
            {
                return Results.BadRequest(new { error = "invalid_page_screenshot_relative_path", regionId = id });
            }

            if (!File.Exists(screenshotPath))
            {
                return Results.Conflict(new
                {
                    error = "source_region_page_screenshot_missing",
                    regionId = id,
                    pageNumber = region.PageNumber,
                    screenshotRelativePath = relative
                });
            }

            return Results.File(screenshotPath, InferContentType(screenshotPath), enableRangeProcessing: true);
        })
        .WithName("GetSourceRegionPageScreenshot");
        app.MapGet("/source-documents/{id:guid}/pages/{pageNumber:int:min(1)}/screenshot", async (
            Guid id,
            int pageNumber,
            KqgDbContext dbContext,
            IConfiguration configuration,
            CancellationToken cancellationToken) =>
        {
            var document = await dbContext.SourceDocuments
                .AsNoTracking()
                .FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (document is null)
            {
                return Results.NotFound(new { error = "source_document_not_found" });
            }

            var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
            var relative = SourcePageScreenshotPathResolver.ResolveExistingRelativePath(paths.FileStoreRoot, document, pageNumber);
            if (relative is null)
            {
                return Results.Conflict(new
                {
                    error = "source_document_page_screenshot_missing",
                    sourceDocumentId = id,
                    pageNumber,
                    candidateRelativePaths = SourcePageScreenshotPathResolver.GetCandidateRelativePaths(document, pageNumber)
                });
            }

            if (!TryResolveFileStorePath(paths.FileStoreRoot, relative, out var screenshotPath))
            {
                return Results.BadRequest(new { error = "invalid_page_screenshot_relative_path", sourceDocumentId = id });
            }

            return Results.File(screenshotPath, InferContentType(screenshotPath), enableRangeProcessing: true);
        })
        .WithName("GetSourceDocumentPageScreenshot");
        app.MapPost("/source-documents/{id:guid}/cut-candidates/generate", async (
            Guid id,
            CutCandidateGenerationService service,
            CancellationToken cancellationToken) =>
        {
            try
            {
                var result = await service.GenerateAsync(id, cancellationToken);
                return Results.Ok(new CutCandidateGenerationResponse(
                    result.SourceDocumentId,
                    result.GeneratedCount,
                    result.LowConfidenceReviewQueueCount,
                    result.LowConfidenceThreshold));
            }
            catch (InvalidOperationException ex) when (ex.Message == "source_document_not_found")
            {
                return Results.NotFound(new { error = "source_document_not_found" });
            }
        })
        .WithName("GenerateCutCandidates");
        app.MapGet("/source-documents/{id:guid}/cut-candidates", async (
            Guid id,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            var sourceExists = await dbContext.SourceDocuments
                .AsNoTracking()
                .AnyAsync(x => x.Id == id, cancellationToken);
            if (!sourceExists)
            {
                return Results.NotFound(new { error = "source_document_not_found" });
            }

            var rows = await dbContext.CutCandidates
                .AsNoTracking()
                .Where(x => x.SourceDocumentId == id)
                .OrderBy(x => x.SequenceNo)
                .ThenBy(x => x.CreatedAt)
                .ToListAsync(cancellationToken);

            return Results.Ok(new CutCandidateListResponse(
                id,
                rows.Select(CutCandidateResponse.From).ToArray()));
        })
        .WithName("ListCutCandidates");
        app.MapPost("/imports/{id:guid}/status", async (
            Guid id,
            ImportJobStatusUpdate request,
            KqgDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            var job = await dbContext.ImportJobs.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (job is null)
            {
                return Results.NotFound();
            }

            var now = DateTimeOffset.UtcNow;
            if (request.LockedBy is not null || request.LockedUntil.HasValue)
            {
                return Results.BadRequest(new { error = "lease_fields_server_managed" });
            }

            if (job.LockedUntil > now)
            {
                return Results.Conflict(new
                {
                    error = "worker_lease_active",
                    lockedUntil = job.LockedUntil
                });
            }

            if (!ImportJobTransitions.IsAllowed(job.Status, request.Status))
            {
                return Results.Conflict(new
                {
                    error = "invalid_status_transition",
                    from = job.Status,
                    to = request.Status
                });
            }

            job.Status = request.Status;
            job.LastErrorCode = request.LastErrorCode;
            job.LastErrorMessage = request.LastErrorMessage;

            if (request.Status == JobStatuses.Running)
            {
                job.StartedAt ??= now;
                job.FinishedAt = null;
                job.AttemptCount += 1;
            }

            if (request.Status is JobStatuses.Succeeded or JobStatuses.Failed or JobStatuses.Cancelled)
            {
                job.FinishedAt = now;
                job.LockedBy = null;
                job.LockedUntil = null;
            }

            await dbContext.SaveChangesAsync(cancellationToken);

            return Results.Ok(ImportJobResponse.From(job));
        })
        .WithName("UpdateImportJobStatus");
        app.MapPost("/imports/{id:guid}/worker-smoke", async (
            Guid id,
            bool? simulateFailure,
            KqgDbContext dbContext,
            DocumentWorkerClient workerClient,
            IImportJobLeaseStore leaseStore,
            CancellationToken cancellationToken) =>
        {
            var job = await dbContext.ImportJobs.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (job is null)
            {
                return Results.NotFound();
            }

            var fileAsset = await dbContext.FileAssets.FirstOrDefaultAsync(x => x.Id == job.InputFileAssetId, cancellationToken);
            if (fileAsset is null)
            {
                return Results.Conflict(new { error = "input_file_asset_missing" });
            }

            var sourceDocument = await dbContext.SourceDocuments
                .Where(x => x.FileAssetId == fileAsset.Id)
                .OrderByDescending(x => x.CreatedAt)
                .FirstOrDefaultAsync(cancellationToken);
            if (sourceDocument is not null)
            {
                var alreadyMaterialized = await dbContext.CutCandidates
                    .AnyAsync(
                        x => x.SourceDocumentId == sourceDocument.Id &&
                            x.Metadata.Contains("document_worker_local"),
                        cancellationToken);
                if (alreadyMaterialized)
                {
                    return Results.Conflict(new
                    {
                        error = "worker_replay_requires_new_generation",
                        sourceDocumentId = sourceDocument.Id
                    });
                }
            }

            var now = DateTimeOffset.UtcNow;
            if (!ImportJobLeaseService.CanAcquire(
                job.Status,
                simulateFailure == true,
                job.AttemptCount,
                job.MaxAttempts,
                job.LockedUntil,
                now))
            {
                return Results.Conflict(new
                {
                    error = job.LockedUntil > now ? "worker_lease_unavailable" : "invalid_status_transition",
                    from = job.Status,
                    to = JobStatuses.Running,
                    lockedUntil = job.LockedUntil
                });
            }

            var lease = await leaseStore.TryAcquireAsync(
                dbContext,
                job.Id,
                simulateFailure == true,
                now,
                cancellationToken);
            if (!lease.Acquired || string.IsNullOrWhiteSpace(lease.LeaseOwner))
            {
                return Results.Conflict(new { error = "worker_lease_unavailable" });
            }

            dbContext.Entry(job).State = EntityState.Detached;
            job = await dbContext.ImportJobs.SingleAsync(x => x.Id == id, cancellationToken);

            var result = await workerClient.RunSmokeAsync(job.Id, fileAsset.RelativePath, simulateFailure == true, cancellationToken);
            var ownsMaterializationLease = await leaseStore.RenewForMaterializationAsync(
                dbContext,
                job.Id,
                lease.LeaseOwner,
                DateTimeOffset.UtcNow,
                cancellationToken);
            if (!ownsMaterializationLease)
            {
                return Results.Conflict(new { error = "worker_lease_lost" });
            }

            await dbContext.Entry(job).ReloadAsync(cancellationToken);
            if (result.OutputTruncated)
            {
                // worker 输出超过字节上限已被整树终止;必须落入可重试失败终态,而非
                // 把截断文本当成功输出解析。
                job.Status = JobStatuses.Failed;
                job.LastErrorCode = "worker_output_oversized";
                job.LastErrorMessage = result.StandardError.Length > 0
                    ? result.StandardError
                    : (result.StandardOutput.Length > 512 ? result.StandardOutput[..512] : result.StandardOutput);
            }
            else if (result.ExitCode == 0)
            {
                job.Status = JobStatuses.Succeeded;
                job.LastErrorCode = null;
                job.LastErrorMessage = null;
            }
            else
            {
                job.Status = JobStatuses.Failed;
                job.LastErrorCode = "worker_failed";
                job.LastErrorMessage = result.StandardError.Length > 0 ? result.StandardError : result.StandardOutput;
            }

            job.LockedBy = null;
            job.LockedUntil = null;
            job.FinishedAt = DateTimeOffset.UtcNow;

            var processing = ImportWorkerProcessingSummary.Empty;
            if (result.ExitCode == 0 && sourceDocument is not null)
            {
                try
                {
                    processing = await ImportWorkerCandidateSeeder.SeedAsync(
                        dbContext,
                        sourceDocument,
                        result.StandardOutput,
                        lease.LeaseOwner,
                        cancellationToken);
                }
                catch (JsonException)
                {
                    // worker 声明成功但输出不是合法 JSON 时,任务必须落入可重试的失败终态,
                    // 而不是 500 加悬挂租约。
                    job.Status = JobStatuses.Failed;
                    job.LastErrorCode = "worker_output_invalid_json";
                    job.LastErrorMessage = result.StandardOutput.Length > 512
                        ? result.StandardOutput[..512]
                        : result.StandardOutput;
                }
            }

            await dbContext.SaveChangesAsync(cancellationToken);

            return Results.Ok(new
            {
                job.Id,
                job.Status,
                result.ExitCode,
                result.StandardOutput,
                result.StandardError,
                Processing = processing
            });
        })
        .WithName("RunDocumentWorkerSmoke");
    }
}
