using K12QuestionGraph.Api.Application.Workflows.Contracts;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;

namespace K12QuestionGraph.Api.Application.Workflows;

public interface IScoreAnalysisWorkflowService
{
    Task<ScoreWorkflowDto> GetScoreImportSummaryAsync(Guid assessmentId, CancellationToken cancellationToken);
    Task<AnalysisWorkflowDto> GetAnalysisSummaryAsync(Guid assessmentId, CancellationToken cancellationToken);
    Task<ScoreImportServiceResult> ImportScoresAsync(ScoreImportServiceRequest request, CancellationToken cancellationToken);
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
