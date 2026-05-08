using K12QuestionGraph.Api.Application.Workflows.Contracts;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using Microsoft.EntityFrameworkCore;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace K12QuestionGraph.Api.Application.Workflows;

public interface IScoreAnalysisWorkflowService
{
    Task<ScoreWorkflowDto> GetScoreImportSummaryAsync(Guid assessmentId, CancellationToken cancellationToken);
    Task<AnalysisWorkflowDto> GetAnalysisSummaryAsync(Guid assessmentId, CancellationToken cancellationToken);
    Task<ScoreImportServiceResult> ImportScoresAsync(ScoreImportServiceRequest request, CancellationToken cancellationToken);
    Task<ItemScoreMappingPreviewServiceResult?> PreviewItemScoreMappingsAsync(Guid assessmentId, ItemScoreMappingPreviewServiceRequest request, CancellationToken cancellationToken);
    Task<CommentaryReportExportServiceResult?> ExportCommentaryReportAsync(Guid assessmentId, CommentaryReportExportServiceRequest request, CancellationToken cancellationToken);
}

public sealed class ScoreAnalysisWorkflowService(KqgDbContext dbContext) : IScoreAnalysisWorkflowService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<ScoreWorkflowDto> GetScoreImportSummaryAsync(Guid assessmentId, CancellationToken cancellationToken)
    {
        var importedRowCount = await dbContext.ScoreRecords
            .AsNoTracking()
            .CountAsync(x => x.AssessmentId == assessmentId, cancellationToken);

        var exceptionRowCount = await dbContext.ScoreImportBatches
            .AsNoTracking()
            .Where(x => x.AssessmentId == assessmentId)
            .Select(x => x.ErrorCount)
            .FirstOrDefaultAsync(cancellationToken);

        return new ScoreWorkflowDto(
            assessmentId,
            "score-template-v1",
            importedRowCount,
            exceptionRowCount,
            new WorkflowStatusEnvelope(
                WorkflowTypes.Score,
                WorkflowStatuses.PendingReview,
                $"score:{assessmentId:N}",
                DateTimeOffset.UtcNow,
                Rollback: null,
                Error: null));
    }

    public async Task<AnalysisWorkflowDto> GetAnalysisSummaryAsync(Guid assessmentId, CancellationToken cancellationToken)
    {
        var weakKnowledgePointCount = await dbContext.KnowledgeMappings
            .AsNoTracking()
            .CountAsync(x => x.Confidence.HasValue && x.Confidence < 0.7m, cancellationToken);

        return new AnalysisWorkflowDto(
            assessmentId,
            "analysis-v1",
            weakKnowledgePointCount,
            new WorkflowStatusEnvelope(
                WorkflowTypes.Analysis,
                WorkflowStatuses.PendingReview,
                $"analysis:{assessmentId:N}",
                DateTimeOffset.UtcNow,
                Rollback: null,
                Error: null));
    }

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
