using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using Microsoft.EntityFrameworkCore;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace K12QuestionGraph.Api.Application.Workflows;

public interface IScoreAnalysisWorkflowService
{
    Task<ScoreImportServiceResult> ImportScoresAsync(ScoreImportServiceRequest request, CancellationToken cancellationToken);
    Task<ItemScoreMappingPreviewServiceResult?> PreviewItemScoreMappingsAsync(Guid assessmentId, ItemScoreMappingPreviewServiceRequest request, CancellationToken cancellationToken);
    Task<ScoreEvidenceAnalysisServiceResult?> PreviewScoreEvidenceAnalysisAsync(Guid assessmentId, ScoreEvidenceAnalysisServiceRequest request, CancellationToken cancellationToken);
    Task<CommentaryReportExportServiceResult?> ExportCommentaryReportAsync(Guid assessmentId, CommentaryReportExportServiceRequest request, CancellationToken cancellationToken);
}

public sealed class ScoreAnalysisWorkflowService(KqgDbContext dbContext) : IScoreAnalysisWorkflowService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<ScoreImportServiceResult> ImportScoresAsync(ScoreImportServiceRequest request, CancellationToken cancellationToken)
    {
        var errors = ValidateRequest(request);
        if (errors.Count > 0)
        {
            return Blocked(request, errors);
        }

        var now = DateTimeOffset.UtcNow;
        var assessment = new Assessment
        {
            Id = Guid.NewGuid(),
            AssessmentKey = UniqueKey("s011a-assessment", request.AssessmentKey),
            Title = BlankToDefault(request.AssessmentTitle, "S011A score import assessment"),
            Subject = NormalizeToken(request.Subject, "physics"),
            Stage = NormalizeToken(request.Stage, "junior_middle_school"),
            Grade = BlankToDefault(request.Grade, "grade_8"),
            Status = AssessmentStatuses.Draft,
            Mode = "draft_test",
            ProductionEligible = false,
            SyntheticFixture = true,
            ContainsStudentPii = false,
            AnonymizationStatus = "synthetic",
            StudentPortalEnabled = false,
            Blueprint = SerializeJson(new
            {
                maxTotalScore = request.MaxTotalScore,
                itemMaxScores = request.ItemMaxScores
            }),
            Metadata = SerializeJson(new { task = "S011A", source = "score_import_api_productization" }),
            CreatedAt = now,
            UpdatedAt = now
        };

        var template = new ScoreImportTemplate
        {
            Id = Guid.NewGuid(),
            TemplateKey = UniqueKey("s011a-template", request.TemplateKey),
            DisplayName = BlankToDefault(request.TemplateDisplayName, "S011A Excel score import template"),
            Version = 1,
            Mode = "draft_test",
            ProductionEligible = false,
            SyntheticFixture = true,
            ReviewStatus = DomainAssetReviewStatuses.PendingReview,
            FieldMapping = SerializeJson(request.FieldMapping),
            MigrationPolicy = SerializeJson(new
            {
                dynamicAsset = "score_import_template",
                templateReusable = true,
                requiresRollbackSnapshot = true
            }),
            CreatedAt = now,
            UpdatedAt = now
        };

        var validRows = new List<ParsedScoreImportRow>();
        var rowErrors = new List<ScoreImportRowError>();
        foreach (var row in request.Rows)
        {
            var parsed = ParseRow(row, request);
            if (parsed.Error is not null)
            {
                rowErrors.Add(parsed.Error);
            }
            else if (parsed.Row is not null)
            {
                validRows.Add(parsed.Row);
            }
        }

        var batch = new ScoreImportBatch
        {
            Id = Guid.NewGuid(),
            AssessmentId = assessment.Id,
            TemplateId = template.Id,
            Mode = "draft_test",
            Status = validRows.Count > 0 ? ScoreImportStatuses.Imported : ScoreImportStatuses.Failed,
            SourceFileName = BlankToDefault(request.SourceFileName, "s011a-score-import.xlsx"),
            ProductionEligible = false,
            SyntheticFixture = true,
            ContainsStudentPii = false,
            RowCount = request.Rows.Count,
            ImportedCount = validRows.Count,
            ErrorCount = rowErrors.Count,
            ErrorSummary = SerializeJson(rowErrors),
            Metadata = SerializeJson(new
            {
                task = "S011A",
                templateReusable = true,
                centralizedExceptionRows = rowErrors.Count,
                aiAgentUsed = false
            }),
            CreatedAt = now
        };

        dbContext.Assessments.Add(assessment);
        dbContext.ScoreImportTemplates.Add(template);
        dbContext.ScoreImportBatches.Add(batch);

        foreach (var parsed in validRows)
        {
            var student = new Student
            {
                Id = Guid.NewGuid(),
                StudentKey = UniqueKey("s011a-student", parsed.StudentKey),
                DisplayCode = parsed.StudentKey,
                Stage = assessment.Stage,
                Grade = assessment.Grade,
                SyntheticFixture = true,
                ContainsStudentPii = false,
                AnonymizationStatus = "synthetic",
                StudentPortalEnabled = false,
                Metadata = SerializeJson(new { task = "S011A" }),
                CreatedAt = now,
                UpdatedAt = now
            };
            var record = new ScoreRecord
            {
                Id = Guid.NewGuid(),
                AssessmentId = assessment.Id,
                StudentId = student.Id,
                ImportBatchId = batch.Id,
                StudentKey = student.StudentKey,
                TotalScore = parsed.TotalScore,
                MaxScore = request.MaxTotalScore,
                Status = "imported",
                SyntheticFixture = true,
                ContainsStudentPii = false,
                RawRow = SerializeJson(parsed.Raw),
                CreatedAt = now
            };

            dbContext.Students.Add(student);
            dbContext.ScoreRecords.Add(record);
            foreach (var item in parsed.ItemScores)
            {
                dbContext.ItemScores.Add(new ItemScore
                {
                    Id = Guid.NewGuid(),
                    ScoreRecordId = record.Id,
                    QuestionNo = item.QuestionNo,
                    FieldName = item.FieldName,
                    Score = item.Score,
                    MaxScore = item.MaxScore,
                    Metadata = SerializeJson(new { task = "S011A" }),
                    CreatedAt = now
                });
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);

        return new ScoreImportServiceResult(
            Status: "imported",
            Mode: "draft_test",
            ProductionEligible: false,
            RealStudentDataUsed: false,
            ContainsStudentPii: false,
            AssessmentId: assessment.Id,
            TemplateId: template.Id,
            BatchId: batch.Id,
            RowCount: batch.RowCount,
            ImportedCount: batch.ImportedCount,
            ErrorCount: batch.ErrorCount,
            Errors: rowErrors,
            TeacherMessage: rowErrors.Count == 0
                ? "成绩已导入，可继续生成分析。"
                : "成绩已导入，部分异常行已集中列出，请先处理异常行。",
            AuditTrail:
            [
                "used_deterministic_excel_field_mapping",
                "blocked_pii",
                "centralized_abnormal_rows",
                "wrote_draft_test_score_records",
                "no_ai_runtime_dependency"
            ]);
    }

    public async Task<ItemScoreMappingPreviewServiceResult?> PreviewItemScoreMappingsAsync(
        Guid assessmentId,
        ItemScoreMappingPreviewServiceRequest request,
        CancellationToken cancellationToken)
    {
        var assessment = await dbContext.Assessments
            .AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == assessmentId, cancellationToken);
        if (assessment is null)
        {
            return null;
        }

        var itemScores = await (
            from scoreRecord in dbContext.ScoreRecords.AsNoTracking()
            join itemScore in dbContext.ItemScores.AsNoTracking() on scoreRecord.Id equals itemScore.ScoreRecordId
            where scoreRecord.AssessmentId == assessmentId
            select new
            {
                itemScore.QuestionNo,
                itemScore.FieldName,
                itemScore.Score,
                itemScore.MaxScore
            })
            .ToListAsync(cancellationToken);

        var groupedScores = itemScores
            .GroupBy(x => x.QuestionNo)
            .OrderBy(x => x.Key, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var requestedMappings = (request.Mappings ?? Array.Empty<ItemScoreMappingRequestItem>())
            .Where(x => !string.IsNullOrWhiteSpace(x.QuestionNo))
            .ToDictionary(x => NormalizeQuestionNo(x.QuestionNo), x => x, StringComparer.OrdinalIgnoreCase);

        var questionIds = requestedMappings.Values
            .Select(x => x.QuestionItemId)
            .Where(x => x.HasValue && x.Value != Guid.Empty)
            .Select(x => x!.Value)
            .Distinct()
            .ToArray();

        var questions = await dbContext.QuestionItems
            .AsNoTracking()
            .Where(x => questionIds.Contains(x.Id))
            .ToDictionaryAsync(x => x.Id, cancellationToken);

        var knowledgeRows = await (
            from mapping in dbContext.KnowledgeMappings.AsNoTracking()
            join node in dbContext.KnowledgeNodes.AsNoTracking() on mapping.KnowledgeNodeId equals node.Id
            where questionIds.Contains(mapping.QuestionItemId) && mapping.IsPrimary
            select new { mapping.QuestionItemId, node.Id, node.Title, node.Status, node.Version })
            .ToListAsync(cancellationToken);
        var primaryKnowledge = knowledgeRows
            .GroupBy(x => x.QuestionItemId)
            .ToDictionary(x => x.Key, x => x.OrderByDescending(row => row.Version).First());

        var rows = new List<ItemScoreMappingPreviewRow>();
        foreach (var scoreGroup in groupedScores)
        {
            var questionNo = NormalizeQuestionNo(scoreGroup.Key);
            requestedMappings.TryGetValue(questionNo, out var requestedMapping);

            QuestionItem? question = null;
            if (requestedMapping?.QuestionItemId is { } questionItemId)
            {
                questions.TryGetValue(questionItemId, out question);
            }

            ItemScoreKnowledgePreview? knowledge = null;
            if (question is not null && primaryKnowledge.TryGetValue(question.Id, out var knowledgeRow))
            {
                knowledge = new ItemScoreKnowledgePreview(
                    knowledgeRow.Id,
                    knowledgeRow.Title,
                    knowledgeRow.Status,
                    knowledgeRow.Version);
            }

            var issueCodes = new List<string>();
            if (requestedMapping is null || requestedMapping.QuestionItemId is null || requestedMapping.QuestionItemId == Guid.Empty)
            {
                issueCodes.Add("question_mapping_missing");
            }
            else if (question is null)
            {
                issueCodes.Add("question_not_found");
            }

            if (question is not null && knowledge is null)
            {
                issueCodes.Add("knowledge_mapping_missing");
            }

            var scoreCount = scoreGroup.Count();
            var maxScore = scoreGroup.Max(x => x.MaxScore);
            var averageScoreRate = scoreGroup.Sum(x => x.Score) / Math.Max(1, scoreGroup.Sum(x => x.MaxScore));
            rows.Add(new ItemScoreMappingPreviewRow(
                questionNo,
                scoreGroup.Select(x => x.FieldName).Distinct(StringComparer.OrdinalIgnoreCase).ToArray(),
                scoreCount,
                maxScore,
                decimal.Round(averageScoreRate, 4),
                question?.Id,
                question is null ? null : ResolveQuestionPreview(question),
                knowledge,
                issueCodes.Count == 0 ? "mapped" : "needs_review",
                issueCodes));
        }

        var unresolved = rows.Where(x => x.Status != "mapped").ToArray();
        return new ItemScoreMappingPreviewServiceResult(
            "draft_test",
            ProductionEligible: false,
            RealStudentDataUsed: false,
            WritesProductionHistory: false,
            assessment.Id,
            assessment.Title,
            rows.Count,
            rows.Count - unresolved.Length,
            unresolved.Length,
            rows,
            unresolved.Select(x => new ItemScoreMappingIssue(x.QuestionNo, x.IssueCodes)).ToArray(),
            unresolved.Length == 0
                ? "小题分已映射到题目和知识点，可继续生成讲评草稿。"
                : "部分小题映射不清，请集中处理后再生成讲评草稿。",
            [
                "deterministic_item_score_mapping_preview",
                "centralized_unclear_mappings",
                "no_real_student_data",
                "no_production_history_write",
                "no_ai_runtime_dependency"
            ]);
    }

    public async Task<ScoreEvidenceAnalysisServiceResult?> PreviewScoreEvidenceAnalysisAsync(
        Guid assessmentId,
        ScoreEvidenceAnalysisServiceRequest request,
        CancellationToken cancellationToken)
    {
        var assessment = await dbContext.Assessments
            .AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == assessmentId, cancellationToken);
        if (assessment is null)
        {
            return null;
        }

        var scoreRows = await (
            from scoreRecord in dbContext.ScoreRecords.AsNoTracking()
            join itemScore in dbContext.ItemScores.AsNoTracking() on scoreRecord.Id equals itemScore.ScoreRecordId
            where scoreRecord.AssessmentId == assessmentId
            select new
            {
                itemScore.QuestionNo,
                itemScore.Score,
                itemScore.MaxScore,
                scoreRecord.ContainsStudentPii
            })
            .ToListAsync(cancellationToken);

        var requestedMappings = (request.Mappings ?? Array.Empty<ItemScoreMappingRequestItem>())
            .Where(x => !string.IsNullOrWhiteSpace(x.QuestionNo))
            .GroupBy(x => NormalizeQuestionNo(x.QuestionNo), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(x => x.Key, x => x.ToArray(), StringComparer.OrdinalIgnoreCase);
        var questionIds = requestedMappings.Values
            .SelectMany(x => x)
            .Where(x => x.QuestionItemId.HasValue && x.QuestionItemId != Guid.Empty)
            .Select(x => x.QuestionItemId!.Value)
            .Distinct()
            .ToArray();
        var questions = await dbContext.QuestionItems
            .AsNoTracking()
            .Where(x => questionIds.Contains(x.Id))
            .ToDictionaryAsync(x => x.Id, cancellationToken);
        var targets = await dbContext.AssessmentTargets
            .AsNoTracking()
            .Where(x => questionIds.Contains(x.QuestionItemId))
            .ToListAsync(cancellationToken);
        var targetIds = targets.Select(x => x.Id).Distinct().ToArray();
        var targetKnowledgeRows = await (
            from mapping in dbContext.AssessmentTargetKnowledgeMappings.AsNoTracking()
            join asset in dbContext.DomainAssetVersions.AsNoTracking() on mapping.DomainAssetVersionId equals asset.Id
            where targetIds.Contains(mapping.AssessmentTargetId)
            select new ScoreEvidenceKnowledgeInput(
                mapping.AssessmentTargetId,
                asset.Id,
                asset.StableId,
                asset.DisplayName,
                asset.Version,
                asset.Status,
                mapping.Role,
                mapping.Status,
                mapping.ReviewStatus))
            .ToListAsync(cancellationToken);
        var observedPerformance = await dbContext.ObservedPerformanceEvidence
            .AsNoTracking()
            .Where(x => targetIds.Contains(x.AssessmentTargetId))
            .ToListAsync(cancellationToken);
        var observedErrors = await dbContext.ObservedErrorEvidence
            .AsNoTracking()
            .Where(x => targetIds.Contains(x.AssessmentTargetId))
            .ToListAsync(cancellationToken);
        var recommendations = await dbContext.TeachingRecommendations
            .AsNoTracking()
            .Where(x => targetIds.Contains(x.AssessmentTargetId))
            .ToListAsync(cancellationToken);
        var reviewedErrorPatterns = (await dbContext.DomainAssetVersions
                .AsNoTracking()
                .Where(x => x.AssetType == "error_pattern"
                    && (x.Status == DomainAssetStatuses.Reviewed || x.Status == DomainAssetStatuses.Active))
                .ToListAsync(cancellationToken))
            .Where(IsReviewedErrorPattern)
            .SelectMany(asset => ReadGuidArray(asset.Metadata, "evidenceTargetIds")
                .Select(targetId => new ScoreEvidenceErrorPatternInput(
                    targetId,
                    asset.Id,
                    asset.StableId,
                    asset.DisplayName,
                    asset.Version,
                    "reviewed_association_not_cause")))
            .Where(x => targetIds.Contains(x.AssessmentTargetId))
            .ToArray();

        var itemInputs = new List<ScoreEvidenceAnalysisItemInput>();
        foreach (var scoreGroup in scoreRows
                     .GroupBy(x => NormalizeQuestionNo(x.QuestionNo), StringComparer.OrdinalIgnoreCase)
                     .OrderBy(x => x.Key, StringComparer.OrdinalIgnoreCase))
        {
            requestedMappings.TryGetValue(scoreGroup.Key, out var mappingCandidates);
            var mappedIds = (mappingCandidates ?? [])
                .Where(x => x.QuestionItemId.HasValue && x.QuestionItemId != Guid.Empty)
                .Select(x => x.QuestionItemId!.Value)
                .Distinct()
                .ToArray();
            var mappedQuestionId = mappedIds.Length == 1 ? mappedIds[0] : (Guid?)null;
            questions.TryGetValue(mappedQuestionId ?? Guid.Empty, out var question);
            var itemTargets = question is null
                ? []
                : targets.Where(x => x.QuestionItemId == question.Id).ToArray();
            var reviewedTargets = itemTargets
                .Where(x => x.IsPrimaryTarget && IsReviewedEvidence(x.Status, x.ReviewStatus))
                .ToArray();
            var target = reviewedTargets.Length == 1 ? reviewedTargets[0] : null;
            var knowledge = target is null
                ? []
                : targetKnowledgeRows
                    .Where(x => x.AssessmentTargetId == target.Id
                        && string.Equals(x.Role, "primary", StringComparison.Ordinal)
                        && IsReviewedEvidence(x.MappingStatus, x.MappingReviewStatus)
                        && x.AssetStatus is DomainAssetStatuses.Reviewed or DomainAssetStatuses.Active)
                    .ToArray();
            var issues = new List<string>();
            if (mappingCandidates is null || mappedIds.Length == 0)
            {
                issues.Add("question_mapping_missing");
            }
            else if (mappedIds.Length > 1 || mappingCandidates.Length > 1)
            {
                issues.Add("question_mapping_ambiguous");
            }
            else if (question is null)
            {
                issues.Add("question_not_found");
            }
            else if (itemTargets.Length == 0)
            {
                issues.Add("assessment_target_mapping_missing");
            }
            else if (reviewedTargets.Length == 0)
            {
                issues.Add("assessment_target_not_reviewed");
            }
            else if (reviewedTargets.Length > 1)
            {
                issues.Add("assessment_target_ambiguous");
            }
            if (target is not null && knowledge.Length == 0)
            {
                issues.Add("knowledge_version_mapping_missing");
            }
            else if (knowledge.Length > 1)
            {
                issues.Add("knowledge_version_ambiguous");
            }

            var metadata = target is null ? default : ParseJson(target.Metadata);
            itemInputs.Add(new ScoreEvidenceAnalysisItemInput(
                scoreGroup.Key,
                scoreGroup.Count(),
                decimal.Round(scoreGroup.Sum(x => x.Score) / Math.Max(1, scoreGroup.Sum(x => x.MaxScore)), 4),
                question?.Id,
                target?.Id,
                target?.StableKey,
                target?.TargetStatement,
                target is null ? [] : ReadStringArray(metadata, "abilityDimensions"),
                target is null ? [] : ReadStringArray(metadata, "cognitiveDemands"),
                knowledge.Length == 1 ? knowledge[0] : null,
                target is null
                    ? []
                    : observedPerformance.Where(x => x.AssessmentTargetId == target.Id && IsReviewedEvidence(x.Status, x.ReviewStatus))
                        .Select(x => new ScoreEvidenceObservedContextInput(
                            x.Id, x.DifficultyObserved, x.ScoreRate, x.DifficultyDirection,
                            x.SampleScope, x.SourceRegionId, "historical_year_report_context_not_current_cohort_measurement"))
                        .ToArray(),
                target is null
                    ? []
                    : observedErrors.Where(x => x.AssessmentTargetId == target.Id && IsReviewedEvidence(x.Status, x.ReviewStatus))
                        .Select(x => new ScoreEvidenceErrorAssociationInput(
                            x.Id, x.RecordKind, x.Content, x.SourceRegionId, "reviewed_association_not_cause"))
                        .Concat(reviewedErrorPatterns.Where(x => x.AssessmentTargetId == target.Id)
                            .Select(x => new ScoreEvidenceErrorAssociationInput(
                                x.ErrorPatternId, x.StableId, x.DisplayName, null, x.Relation)))
                        .ToArray(),
                target is null
                    ? []
                    : recommendations.Where(x => x.AssessmentTargetId == target.Id && IsReviewedEvidence(x.Status, x.ReviewStatus))
                        .Select(x => new ScoreEvidenceTeachingRecommendationInput(
                            x.Id, x.Content, x.AuthorKind, x.GenerationMethod, x.SourceRegionId,
                            "source_authored_recommendation_not_curriculum_fact"))
                        .ToArray(),
                issues));
        }

        return BuildScoreEvidenceAnalysis(new ScoreEvidenceAnalysisInput(
            assessment.Id,
            assessment.Title,
            request.ContainsStudentPii || assessment.ContainsStudentPii || scoreRows.Any(x => x.ContainsStudentPii),
            itemInputs));
    }

    public async Task<CommentaryReportExportServiceResult?> ExportCommentaryReportAsync(
        Guid assessmentId,
        CommentaryReportExportServiceRequest request,
        CancellationToken cancellationToken)
    {
        var mappingPreview = await PreviewItemScoreMappingsAsync(
            assessmentId,
            new ItemScoreMappingPreviewServiceRequest(request.Mappings),
            cancellationToken);
        if (mappingPreview is null)
        {
            return null;
        }

        if (mappingPreview.UnclearCount > 0)
        {
            return new CommentaryReportExportServiceResult(
                "blocked",
                mappingPreview.Mode,
                ProductionEligible: false,
                RealStudentDataUsed: false,
                WritesProductionHistory: false,
                AllowAiDraftText: false,
                mappingPreview.AssessmentId,
                mappingPreview.AssessmentTitle,
                "md",
                ArtifactPath: null,
                ManifestSha256: null,
                ReportMarkdown: string.Empty,
                Sections: [],
                WeakKnowledgePoints: [],
                PracticeSuggestions: [],
                BlockingIssues: mappingPreview.Issues.Select(x => new CommentaryReportIssue(x.QuestionNo, x.Codes)).ToArray(),
                TeacherMessage: "小题映射仍不清，讲评报告暂不生成。",
                AuditTrail:
                [
                    "blocked_unclear_item_score_mapping",
                    "no_real_student_data",
                    "no_production_history_write",
                    "no_ai_runtime_dependency"
                ]);
        }

        var weakRows = mappingPreview.Rows
            .Where(x => x.PrimaryKnowledge is not null)
            .OrderBy(x => x.AverageScoreRate)
            .Take(3)
            .Select(x => new CommentaryWeakKnowledgePoint(
                x.PrimaryKnowledge!.KnowledgeNodeId,
                x.PrimaryKnowledge.Title,
                x.PrimaryKnowledge.Version,
                x.AverageScoreRate,
                x.QuestionNo))
            .ToArray();

        var sections = new[]
        {
            new CommentaryReportSection("class_summary", "班级概览", $"已导入 {mappingPreview.ItemCount} 个小题，{mappingPreview.MappedCount} 个已映射。"),
            new CommentaryReportSection("weak_points", "优先讲评", weakRows.Length == 0 ? "暂无薄弱知识点。" : string.Join("；", weakRows.Select(x => $"{x.Title} {decimal.Round(x.ScoreRate * 100, 1)}%"))),
            new CommentaryReportSection("practice_plan", "巩固练习", "按已确认知识点生成 draft/test 练习建议，教师确认后再使用。")
        };
        var suggestions = weakRows
            .Select(x => new CommentaryPracticeSuggestion(
                x.KnowledgeNodeId,
                x.Title,
                $"补充 2 道 {x.Title} 的基础巩固题，先用于课堂讲评草稿。"))
            .ToArray();
        var markdown = BuildCommentaryMarkdown(mappingPreview, sections, suggestions);
        var manifest = new
        {
            task = "S011C",
            assessmentId,
            format = NormalizeToken(request.Format, "md"),
            sections = sections.Select(x => x.SectionId).ToArray(),
            weakKnowledgePointCount = weakRows.Length,
            noRealStudentData = true,
            noProductionHistoryWrite = true,
            generatedAt = DateTimeOffset.UtcNow.ToString("O")
        };
        var manifestJson = SerializeJson(manifest);
        var sha256 = Sha256Hex($"{manifestJson}\n{markdown}");

        return new CommentaryReportExportServiceResult(
            "ready",
            mappingPreview.Mode,
            ProductionEligible: false,
            RealStudentDataUsed: false,
            WritesProductionHistory: false,
            AllowAiDraftText: request.AllowAiDraftText,
            mappingPreview.AssessmentId,
            mappingPreview.AssessmentTitle,
            NormalizeToken(request.Format, "md"),
            $"draft://commentary-reports/{assessmentId:N}.{NormalizeToken(request.Format, "md")}",
            sha256,
            markdown,
            sections,
            weakRows,
            suggestions,
            BlockingIssues: [],
            TeacherMessage: "讲评报告草稿已生成，可导出给备课使用。",
            AuditTrail:
            [
                "deterministic_score_metrics",
                "draft_commentary_report_export",
                "no_real_student_data",
                "no_production_history_write",
                request.AllowAiDraftText ? "ai_draft_text_allowed_after_metrics" : "no_ai_runtime_dependency"
            ]);
    }

    internal static ScoreEvidenceAnalysisServiceResult BuildScoreEvidenceAnalysis(ScoreEvidenceAnalysisInput input)
    {
        var blockingIssues = new List<ScoreEvidenceAnalysisIssue>();
        if (input.ContainsStudentPii)
        {
            blockingIssues.Add(new ScoreEvidenceAnalysisIssue("assessment", ["student_pii_detected"]));
        }
        if (input.Items.Count == 0)
        {
            blockingIssues.Add(new ScoreEvidenceAnalysisIssue("assessment", ["score_rows_missing"]));
        }
        blockingIssues.AddRange(input.Items
            .Where(x => x.IssueCodes.Count > 0)
            .Select(x => new ScoreEvidenceAnalysisIssue(x.QuestionNo, x.IssueCodes)));

        var usableItems = input.ContainsStudentPii
            ? []
            : input.Items.Where(x => x.IssueCodes.Count == 0 && x.AssessmentTargetId.HasValue).ToArray();
        var performance = usableItems.Select(x => new ScoreDerivedPerformanceItem(
            x.QuestionNo,
            x.QuestionItemId!.Value,
            x.AssessmentTargetId!.Value,
            x.AssessmentTargetStableKey!,
            x.TargetStatement!,
            x.ScoreRecordCount,
            x.AverageScoreRate,
            x.AbilityDimensions,
            x.CognitiveDemands,
            "score_derived_performance"))
            .ToArray();
        var knowledge = usableItems
            .Where(x => x.Knowledge is not null)
            .GroupBy(x => new
            {
                x.Knowledge!.AssetId,
                x.Knowledge.StableId,
                x.Knowledge.DisplayName,
                x.Knowledge.Version
            })
            .Select(group => new ScoreEvidenceDimensionSummary(
                group.Key.StableId,
                group.Key.DisplayName,
                WeightedScoreRate(group),
                group.Sum(x => x.ScoreRecordCount),
                group.Select(x => x.QuestionNo).Distinct(StringComparer.OrdinalIgnoreCase).Order(StringComparer.OrdinalIgnoreCase).ToArray(),
                group.Key.Version,
                "score_derived_knowledge_mastery"))
            .OrderBy(x => x.ScoreRate)
            .ToArray();
        var abilities = AggregateDimension(usableItems, x => x.AbilityDimensions, "score_derived_ability_performance");
        var cognitive = AggregateDimension(usableItems, x => x.CognitiveDemands, "score_derived_cognitive_performance");
        var contexts = usableItems
            .SelectMany(x => x.ObservedContexts.Select(context => new ScoreEvidenceObservedContext(
                context.Id,
                x.AssessmentTargetId!.Value,
                context.DifficultyObserved,
                context.ScoreRate,
                context.DifficultyDirection,
                context.SampleScope,
                context.SourceRegionId,
                context.ContextRole)))
            .GroupBy(x => x.EvidenceId)
            .Select(x => x.First())
            .ToArray();
        var errorAssociations = usableItems
            .SelectMany(x => x.ErrorAssociations.Select(error => new ScoreEvidenceErrorAssociation(
                error.Id,
                x.AssessmentTargetId!.Value,
                error.Kind,
                error.Content,
                error.SourceRegionId,
                error.Relation,
                "pending_teacher_confirmation")))
            .GroupBy(x => x.EvidenceId)
            .Select(x => x.First())
            .ToArray();
        var teachingRecommendations = usableItems
            .SelectMany(x => x.TeachingRecommendations.Select(recommendation => new ScoreEvidenceTeachingRecommendation(
                recommendation.Id,
                x.AssessmentTargetId!.Value,
                recommendation.Content,
                recommendation.AuthorKind,
                recommendation.GenerationMethod,
                recommendation.SourceRegionId,
                recommendation.FactRole)))
            .GroupBy(x => x.RecommendationId)
            .Select(x => x.First())
            .ToArray();
        var blocked = blockingIssues.Count > 0;

        return new ScoreEvidenceAnalysisServiceResult(
            blocked ? "blocked" : "ready",
            "draft_test",
            ProductionEligible: false,
            RealStudentDataUsed: input.ContainsStudentPii,
            WritesProductionHistory: false,
            input.AssessmentId,
            input.AssessmentTitle,
            performance,
            knowledge,
            abilities,
            cognitive,
            contexts,
            errorAssociations,
            teachingRecommendations,
            TeacherConfirmedDiagnoses: [],
            DiagnosisStatus: "pending_teacher_confirmation",
            blockingIssues,
            blocked
                ? "证据分析被阻断：请先处理隐私、小题映射、考查目标审核或版本歧义。"
                : "证据分析预览已生成；错因仅表示相关线索，需教师确认后才能形成诊断。",
            [
                "mapped_item_scores_to_reviewed_assessment_targets",
                "separated_score_performance_from_year_report_context",
                "error_patterns_are_associations_not_causal_diagnoses",
                "preserved_teaching_recommendation_authorship",
                input.ContainsStudentPii ? "pii_detected_analysis_blocked" : "no_real_student_data",
                "no_production_history_write",
                "no_ai_runtime_dependency"
            ]);
    }

    private static IReadOnlyList<ScoreEvidenceDimensionSummary> AggregateDimension(
        IReadOnlyList<ScoreEvidenceAnalysisItemInput> items,
        Func<ScoreEvidenceAnalysisItemInput, IReadOnlyList<string>> selector,
        string evidenceRole)
    {
        return items
            .SelectMany(item => selector(item)
                .Where(value => !string.IsNullOrWhiteSpace(value))
                .Distinct(StringComparer.Ordinal)
                .Select(value => new { Value = value.Trim(), Item = item }))
            .GroupBy(x => x.Value, StringComparer.Ordinal)
            .Select(group => new ScoreEvidenceDimensionSummary(
                group.Key,
                group.Key,
                decimal.Round(
                    group.Sum(x => x.Item.AverageScoreRate * x.Item.ScoreRecordCount)
                    / Math.Max(1, group.Sum(x => x.Item.ScoreRecordCount)),
                    4),
                group.Sum(x => x.Item.ScoreRecordCount),
                group.Select(x => x.Item.QuestionNo).Distinct(StringComparer.OrdinalIgnoreCase).Order(StringComparer.OrdinalIgnoreCase).ToArray(),
                Version: null,
                evidenceRole))
            .OrderBy(x => x.ScoreRate)
            .ToArray();
    }

    private static decimal WeightedScoreRate(IEnumerable<ScoreEvidenceAnalysisItemInput> items)
    {
        var rows = items.ToArray();
        return decimal.Round(
            rows.Sum(x => x.AverageScoreRate * x.ScoreRecordCount)
            / Math.Max(1, rows.Sum(x => x.ScoreRecordCount)),
            4);
    }

    private static bool IsReviewedEvidence(string status, string reviewStatus) =>
        reviewStatus == DomainAssetReviewStatuses.Approved
        && status is DomainAssetStatuses.Reviewed or DomainAssetStatuses.Active;

    private static bool IsReviewedErrorPattern(DomainAssetVersion asset)
    {
        var metadata = ParseJson(asset.Metadata);
        var reviewStatus = ReadString(metadata, "reviewerStatus") ?? ReadString(metadata, "review_status");
        var productionEligible = ReadBoolean(metadata, "productionEligible") ?? ReadBoolean(metadata, "production_eligible");
        return reviewStatus == DomainAssetReviewStatuses.Approved && productionEligible is false;
    }

    private static JsonElement ParseJson(string? value)
    {
        try
        {
            using var document = JsonDocument.Parse(string.IsNullOrWhiteSpace(value) ? "{}" : value);
            return document.RootElement.Clone();
        }
        catch (JsonException)
        {
            return JsonSerializer.SerializeToElement(new { });
        }
    }

    private static string? ReadString(JsonElement element, string propertyName) =>
        element.ValueKind == JsonValueKind.Object
        && element.TryGetProperty(propertyName, out var value)
        && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static bool? ReadBoolean(JsonElement element, string propertyName) =>
        element.ValueKind == JsonValueKind.Object
        && element.TryGetProperty(propertyName, out var value)
        && value.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? value.GetBoolean()
            : null;

    private static IReadOnlyList<string> ReadStringArray(JsonElement element, string propertyName) =>
        element.ValueKind == JsonValueKind.Object
        && element.TryGetProperty(propertyName, out var value)
        && value.ValueKind == JsonValueKind.Array
            ? value.EnumerateArray()
                .Where(x => x.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(x.GetString()))
                .Select(x => x.GetString()!.Trim())
                .Distinct(StringComparer.Ordinal)
                .ToArray()
            : [];

    private static IReadOnlyList<Guid> ReadGuidArray(string json, string propertyName) =>
        ReadStringArray(ParseJson(json), propertyName)
            .Select(value => Guid.TryParse(value, out var parsed) ? parsed : Guid.Empty)
            .Where(value => value != Guid.Empty)
            .Distinct()
            .ToArray();

    private static ScoreImportServiceResult Blocked(ScoreImportServiceRequest request, IReadOnlyList<ScoreImportRowError> errors)
    {
        return new ScoreImportServiceResult(
            Status: "blocked",
            Mode: "draft_test",
            ProductionEligible: false,
            RealStudentDataUsed: false,
            ContainsStudentPii: request.ContainsStudentPii,
            AssessmentId: null,
            TemplateId: null,
            BatchId: null,
            RowCount: request.Rows.Count,
            ImportedCount: 0,
            ErrorCount: errors.Count,
            Errors: errors,
            TeacherMessage: "成绩导入被阻断，请先移除真实学生隐私数据或补齐字段映射。",
            AuditTrail:
            [
                "fail_closed_before_database_write",
                "blocked_pii_or_invalid_mapping",
                "no_ai_runtime_dependency"
            ]);
    }

    private static List<ScoreImportRowError> ValidateRequest(ScoreImportServiceRequest request)
    {
        var errors = new List<ScoreImportRowError>();
        if (request.ContainsStudentPii)
        {
            errors.Add(new ScoreImportRowError(0, "pii_not_allowed", "S011A 不接收真实学生隐私数据。", []));
        }
        if (request.ProductionEligible)
        {
            errors.Add(new ScoreImportRowError(0, "production_import_not_allowed", "S011A 只能写入 draft/test 成绩。", []));
        }
        if (request.Rows.Count == 0)
        {
            errors.Add(new ScoreImportRowError(0, "rows_required", "缺少成绩行。", []));
        }
        if (string.IsNullOrWhiteSpace(request.FieldMapping.StudentKey))
        {
            errors.Add(new ScoreImportRowError(0, "student_key_mapping_required", "缺少学生标识字段映射。", []));
        }
        if (string.IsNullOrWhiteSpace(request.FieldMapping.TotalScore))
        {
            errors.Add(new ScoreImportRowError(0, "total_score_mapping_required", "缺少总分字段映射。", []));
        }
        if (request.FieldMapping.ItemScores.Count == 0 || request.ItemMaxScores.Count == 0)
        {
            errors.Add(new ScoreImportRowError(0, "item_score_mapping_required", "缺少小题分字段映射。", []));
        }

        return errors;
    }

    private static ParsedScoreImportResult ParseRow(ScoreImportRowRequest row, ScoreImportServiceRequest request)
    {
        var missingFields = new List<string>();
        if (!TryGet(row.Values, request.FieldMapping.StudentKey, out var studentKey))
        {
            missingFields.Add(request.FieldMapping.StudentKey);
        }
        if (!TryGetDecimal(row.Values, request.FieldMapping.TotalScore, out var totalScore))
        {
            missingFields.Add(request.FieldMapping.TotalScore);
        }

        var itemScores = new List<ParsedItemScore>();
        foreach (var mapping in request.FieldMapping.ItemScores)
        {
            if (!request.ItemMaxScores.TryGetValue(mapping.Key, out var maxScore))
            {
                missingFields.Add($"max:{mapping.Key}");
                continue;
            }
            if (!TryGetDecimal(row.Values, mapping.Value, out var score))
            {
                missingFields.Add(mapping.Value);
                continue;
            }
            if (score < 0 || score > maxScore)
            {
                return ParsedScoreImportResult.FromError(row, "item_score_out_of_range", $"小题 {mapping.Key} 分数超出范围。", [mapping.Value]);
            }
            itemScores.Add(new ParsedItemScore(mapping.Key, mapping.Value, score, maxScore));
        }

        if (missingFields.Count > 0)
        {
            return ParsedScoreImportResult.FromError(row, "required_field_missing", "成绩行缺少必要字段或不是数字。", missingFields);
        }
        if (totalScore < 0 || totalScore > request.MaxTotalScore)
        {
            return ParsedScoreImportResult.FromError(row, "total_score_out_of_range", "总分超出范围。", [request.FieldMapping.TotalScore]);
        }
        if (string.IsNullOrWhiteSpace(studentKey))
        {
            return ParsedScoreImportResult.FromError(row, "student_key_required", "学生标识为空。", [request.FieldMapping.StudentKey]);
        }

        return new ParsedScoreImportResult(
            new ParsedScoreImportRow(studentKey.Trim(), totalScore, itemScores, row.Values),
            Error: null);
    }

    private static bool TryGet(IReadOnlyDictionary<string, string> values, string key, out string value)
    {
        value = string.Empty;
        return !string.IsNullOrWhiteSpace(key) &&
               values.TryGetValue(key, out value!) &&
               !string.IsNullOrWhiteSpace(value);
    }

    private static bool TryGetDecimal(IReadOnlyDictionary<string, string> values, string key, out decimal value)
    {
        value = 0;
        return TryGet(values, key, out var raw) && decimal.TryParse(raw, out value);
    }

    private static string NormalizeToken(string? value, string fallback)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return fallback;
        }

        return value.Trim().ToLowerInvariant().Replace('-', '_').Replace(' ', '_');
    }

    private static string BlankToDefault(string? value, string fallback)
    {
        return string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
    }

    private static string UniqueKey(string prefix, string? requested)
    {
        var safe = string.IsNullOrWhiteSpace(requested) ? prefix : NormalizeToken(requested, prefix);
        return $"{safe}-{Guid.NewGuid():N}";
    }

    private static string NormalizeQuestionNo(string value)
    {
        return string.IsNullOrWhiteSpace(value) ? string.Empty : value.Trim().ToUpperInvariant();
    }

    private static string ResolveQuestionPreview(QuestionItem question)
    {
        try
        {
            using var document = JsonDocument.Parse(question.Blocks);
            foreach (var block in document.RootElement.EnumerateArray())
            {
                if (!block.TryGetProperty("content", out var content) ||
                    !content.TryGetProperty("text", out var textElement) ||
                    textElement.ValueKind != JsonValueKind.String)
                {
                    continue;
                }

                var text = textElement.GetString();
                if (!string.IsNullOrWhiteSpace(text))
                {
                    return text.Length > 80 ? text[..80] : text;
                }
            }
        }
        catch
        {
            return $"题目 {question.Id:N}";
        }

        return $"题目 {question.Id:N}";
    }

    private static string BuildCommentaryMarkdown(
        ItemScoreMappingPreviewServiceResult mappingPreview,
        IReadOnlyList<CommentaryReportSection> sections,
        IReadOnlyList<CommentaryPracticeSuggestion> suggestions)
    {
        var builder = new StringBuilder();
        builder.AppendLine($"# {mappingPreview.AssessmentTitle} 讲评草稿");
        builder.AppendLine();
        foreach (var section in sections)
        {
            builder.AppendLine($"## {section.Title}");
            builder.AppendLine(section.Summary);
            builder.AppendLine();
        }

        if (suggestions.Count > 0)
        {
            builder.AppendLine("## 分层练习建议");
            foreach (var suggestion in suggestions)
            {
                builder.AppendLine($"- {suggestion.KnowledgeTitle}: {suggestion.Suggestion}");
            }
        }

        return builder.ToString().TrimEnd();
    }

    private static string Sha256Hex(string value)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    private static string SerializeJson<T>(T value)
    {
        return JsonSerializer.Serialize(value, JsonOptions);
    }
}

public sealed record ScoreImportServiceRequest(
    string? AssessmentKey,
    string? AssessmentTitle,
    string? Subject,
    string? Stage,
    string? Grade,
    string? TemplateKey,
    string? TemplateDisplayName,
    string? SourceFileName,
    bool ContainsStudentPii,
    bool ProductionEligible,
    decimal MaxTotalScore,
    ScoreImportFieldMapping FieldMapping,
    IReadOnlyDictionary<string, decimal> ItemMaxScores,
    IReadOnlyList<ScoreImportRowRequest> Rows);

public sealed record ScoreImportFieldMapping(
    string StudentKey,
    string TotalScore,
    IReadOnlyDictionary<string, string> ItemScores);

public sealed record ScoreImportRowRequest(
    int RowNumber,
    IReadOnlyDictionary<string, string> Values);

public sealed record ScoreImportServiceResult(
    string Status,
    string Mode,
    bool ProductionEligible,
    bool RealStudentDataUsed,
    bool ContainsStudentPii,
    Guid? AssessmentId,
    Guid? TemplateId,
    Guid? BatchId,
    int RowCount,
    int ImportedCount,
    int ErrorCount,
    IReadOnlyList<ScoreImportRowError> Errors,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail);

public sealed record ScoreImportRowError(
    int RowNumber,
    string Code,
    string Message,
    IReadOnlyList<string> Fields);

public sealed record ItemScoreMappingPreviewServiceRequest(
    IReadOnlyList<ItemScoreMappingRequestItem>? Mappings);

public sealed record ItemScoreMappingRequestItem(
    string QuestionNo,
    Guid? QuestionItemId);

public sealed record ItemScoreMappingPreviewServiceResult(
    string Mode,
    bool ProductionEligible,
    bool RealStudentDataUsed,
    bool WritesProductionHistory,
    Guid AssessmentId,
    string AssessmentTitle,
    int ItemCount,
    int MappedCount,
    int UnclearCount,
    IReadOnlyList<ItemScoreMappingPreviewRow> Rows,
    IReadOnlyList<ItemScoreMappingIssue> Issues,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail);

public sealed record ItemScoreMappingPreviewRow(
    string QuestionNo,
    IReadOnlyList<string> FieldNames,
    int ScoreRecordCount,
    decimal MaxScore,
    decimal AverageScoreRate,
    Guid? QuestionItemId,
    string? QuestionPreview,
    ItemScoreKnowledgePreview? PrimaryKnowledge,
    string Status,
    IReadOnlyList<string> IssueCodes);

public sealed record ItemScoreKnowledgePreview(
    Guid KnowledgeNodeId,
    string Title,
    string Status,
    int Version);

public sealed record ItemScoreMappingIssue(
    string QuestionNo,
    IReadOnlyList<string> Codes);

public sealed record ScoreEvidenceAnalysisServiceRequest(
    bool ContainsStudentPii,
    IReadOnlyList<ItemScoreMappingRequestItem>? Mappings);

public sealed record ScoreEvidenceAnalysisServiceResult(
    string Status,
    string Mode,
    bool ProductionEligible,
    bool RealStudentDataUsed,
    bool WritesProductionHistory,
    Guid AssessmentId,
    string AssessmentTitle,
    IReadOnlyList<ScoreDerivedPerformanceItem> ScoreDerivedPerformance,
    IReadOnlyList<ScoreEvidenceDimensionSummary> KnowledgeMastery,
    IReadOnlyList<ScoreEvidenceDimensionSummary> AbilityPerformance,
    IReadOnlyList<ScoreEvidenceDimensionSummary> CognitivePerformance,
    IReadOnlyList<ScoreEvidenceObservedContext> ObservedContexts,
    IReadOnlyList<ScoreEvidenceErrorAssociation> ErrorPatternAssociations,
    IReadOnlyList<ScoreEvidenceTeachingRecommendation> TeachingRecommendations,
    IReadOnlyList<ScoreEvidenceTeacherDiagnosis> TeacherConfirmedDiagnoses,
    string DiagnosisStatus,
    IReadOnlyList<ScoreEvidenceAnalysisIssue> BlockingIssues,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail);

public sealed record ScoreDerivedPerformanceItem(
    string QuestionNo,
    Guid QuestionItemId,
    Guid AssessmentTargetId,
    string AssessmentTargetStableKey,
    string TargetStatement,
    int ScoreRecordCount,
    decimal AverageScoreRate,
    IReadOnlyList<string> AbilityDimensions,
    IReadOnlyList<string> CognitiveDemands,
    string EvidenceRole);

public sealed record ScoreEvidenceDimensionSummary(
    string StableId,
    string DisplayName,
    decimal ScoreRate,
    int ScoreRecordCount,
    IReadOnlyList<string> QuestionNos,
    int? Version,
    string EvidenceRole);

public sealed record ScoreEvidenceObservedContext(
    Guid EvidenceId,
    Guid AssessmentTargetId,
    decimal? DifficultyObserved,
    decimal? ScoreRate,
    string DifficultyDirection,
    string SampleScope,
    Guid SourceRegionId,
    string ContextRole);

public sealed record ScoreEvidenceErrorAssociation(
    Guid EvidenceId,
    Guid AssessmentTargetId,
    string Kind,
    string Content,
    Guid? SourceRegionId,
    string Relation,
    string DiagnosisStatus);

public sealed record ScoreEvidenceTeachingRecommendation(
    Guid RecommendationId,
    Guid AssessmentTargetId,
    string Content,
    string AuthorKind,
    string GenerationMethod,
    Guid SourceRegionId,
    string FactRole);

public sealed record ScoreEvidenceTeacherDiagnosis(
    Guid AssessmentTargetId,
    string Diagnosis,
    string ConfirmedBy,
    DateTimeOffset ConfirmedAt);

public sealed record ScoreEvidenceAnalysisIssue(
    string Scope,
    IReadOnlyList<string> Codes);

internal sealed record ScoreEvidenceAnalysisInput(
    Guid AssessmentId,
    string AssessmentTitle,
    bool ContainsStudentPii,
    IReadOnlyList<ScoreEvidenceAnalysisItemInput> Items);

internal sealed record ScoreEvidenceAnalysisItemInput(
    string QuestionNo,
    int ScoreRecordCount,
    decimal AverageScoreRate,
    Guid? QuestionItemId,
    Guid? AssessmentTargetId,
    string? AssessmentTargetStableKey,
    string? TargetStatement,
    IReadOnlyList<string> AbilityDimensions,
    IReadOnlyList<string> CognitiveDemands,
    ScoreEvidenceKnowledgeInput? Knowledge,
    IReadOnlyList<ScoreEvidenceObservedContextInput> ObservedContexts,
    IReadOnlyList<ScoreEvidenceErrorAssociationInput> ErrorAssociations,
    IReadOnlyList<ScoreEvidenceTeachingRecommendationInput> TeachingRecommendations,
    IReadOnlyList<string> IssueCodes);

internal sealed record ScoreEvidenceKnowledgeInput(
    Guid AssessmentTargetId,
    Guid AssetId,
    string StableId,
    string DisplayName,
    int Version,
    string AssetStatus,
    string Role,
    string MappingStatus,
    string MappingReviewStatus);

internal sealed record ScoreEvidenceObservedContextInput(
    Guid Id,
    decimal? DifficultyObserved,
    decimal? ScoreRate,
    string DifficultyDirection,
    string SampleScope,
    Guid SourceRegionId,
    string ContextRole);

internal sealed record ScoreEvidenceErrorAssociationInput(
    Guid Id,
    string Kind,
    string Content,
    Guid? SourceRegionId,
    string Relation);

internal sealed record ScoreEvidenceTeachingRecommendationInput(
    Guid Id,
    string Content,
    string AuthorKind,
    string GenerationMethod,
    Guid SourceRegionId,
    string FactRole);

internal sealed record ScoreEvidenceErrorPatternInput(
    Guid AssessmentTargetId,
    Guid ErrorPatternId,
    string StableId,
    string DisplayName,
    int Version,
    string Relation);

public sealed record CommentaryReportExportServiceRequest(
    string Format,
    bool AllowAiDraftText,
    IReadOnlyList<ItemScoreMappingRequestItem>? Mappings);

public sealed record CommentaryReportExportServiceResult(
    string Status,
    string Mode,
    bool ProductionEligible,
    bool RealStudentDataUsed,
    bool WritesProductionHistory,
    bool AllowAiDraftText,
    Guid AssessmentId,
    string AssessmentTitle,
    string Format,
    string? ArtifactPath,
    string? ManifestSha256,
    string ReportMarkdown,
    IReadOnlyList<CommentaryReportSection> Sections,
    IReadOnlyList<CommentaryWeakKnowledgePoint> WeakKnowledgePoints,
    IReadOnlyList<CommentaryPracticeSuggestion> PracticeSuggestions,
    IReadOnlyList<CommentaryReportIssue> BlockingIssues,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail);

public sealed record CommentaryReportSection(
    string SectionId,
    string Title,
    string Summary);

public sealed record CommentaryWeakKnowledgePoint(
    Guid KnowledgeNodeId,
    string Title,
    int Version,
    decimal ScoreRate,
    string QuestionNo);

public sealed record CommentaryPracticeSuggestion(
    Guid KnowledgeNodeId,
    string KnowledgeTitle,
    string Suggestion);

public sealed record CommentaryReportIssue(
    string QuestionNo,
    IReadOnlyList<string> Codes);

internal sealed record ParsedScoreImportRow(
    string StudentKey,
    decimal TotalScore,
    IReadOnlyList<ParsedItemScore> ItemScores,
    IReadOnlyDictionary<string, string> Raw);

internal sealed record ParsedItemScore(
    string QuestionNo,
    string FieldName,
    decimal Score,
    decimal MaxScore);

internal sealed record ParsedScoreImportResult(
    ParsedScoreImportRow? Row,
    ScoreImportRowError? Error)
{
    public static ParsedScoreImportResult FromError(ScoreImportRowRequest row, string code, string message, IReadOnlyList<string> fields)
    {
        return new ParsedScoreImportResult(null, new ScoreImportRowError(row.RowNumber, code, message, fields));
    }
}
