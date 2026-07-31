using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Application.Workflows.Contracts;

namespace K12QuestionGraph.Api.Scores;

public sealed record ScoreImportRequest(
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
    ScoreImportFieldMappingRequest FieldMapping,
    IReadOnlyDictionary<string, decimal> ItemMaxScores,
    IReadOnlyList<ScoreImportRowApiRequest> Rows);

public sealed record ScoreImportFieldMappingRequest(
    string StudentKey,
    string TotalScore,
    IReadOnlyDictionary<string, string> ItemScores);

public sealed record ScoreImportRowApiRequest(
    int RowNumber,
    IReadOnlyDictionary<string, string> Values);

public sealed record ScoreImportResponse(
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
    IReadOnlyList<ScoreImportRowErrorResponse> Errors,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail)
{
    public static ScoreImportResponse From(ScoreImportServiceResult result)
    {
        return new ScoreImportResponse(
            result.Status,
            result.Mode,
            result.ProductionEligible,
            result.RealStudentDataUsed,
            result.ContainsStudentPii,
            result.AssessmentId,
            result.TemplateId,
            result.BatchId,
            result.RowCount,
            result.ImportedCount,
            result.ErrorCount,
            result.Errors.Select(ScoreImportRowErrorResponse.From).ToArray(),
            result.TeacherMessage,
            result.AuditTrail);
    }
}

public sealed record ScoreImportRowErrorResponse(
    int RowNumber,
    string Code,
    string Message,
    IReadOnlyList<string> Fields)
{
    public static ScoreImportRowErrorResponse From(ScoreImportRowError error)
    {
        return new ScoreImportRowErrorResponse(error.RowNumber, error.Code, error.Message, error.Fields);
    }
}

public sealed record ItemScoreMappingPreviewRequest(
    IReadOnlyList<ItemScoreMappingRequest> Mappings);

public sealed record ItemScoreMappingRequest(
    string QuestionNo,
    Guid? QuestionItemId);

public sealed record ItemScoreMappingPreviewResponse(
    string Mode,
    bool ProductionEligible,
    bool RealStudentDataUsed,
    bool WritesProductionHistory,
    Guid AssessmentId,
    string AssessmentTitle,
    int ItemCount,
    int MappedCount,
    int UnclearCount,
    IReadOnlyList<ItemScoreMappingPreviewRowResponse> Rows,
    IReadOnlyList<ItemScoreMappingIssueResponse> Issues,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail)
{
    public static ItemScoreMappingPreviewResponse From(ItemScoreMappingPreviewServiceResult result)
    {
        return new ItemScoreMappingPreviewResponse(
            result.Mode,
            result.ProductionEligible,
            result.RealStudentDataUsed,
            result.WritesProductionHistory,
            result.AssessmentId,
            result.AssessmentTitle,
            result.ItemCount,
            result.MappedCount,
            result.UnclearCount,
            result.Rows.Select(ItemScoreMappingPreviewRowResponse.From).ToArray(),
            result.Issues.Select(ItemScoreMappingIssueResponse.From).ToArray(),
            result.TeacherMessage,
            result.AuditTrail);
    }
}

public sealed record ItemScoreMappingPreviewRowResponse(
    string QuestionNo,
    IReadOnlyList<string> FieldNames,
    int ScoreRecordCount,
    decimal MaxScore,
    decimal AverageScoreRate,
    Guid? QuestionItemId,
    string? QuestionPreview,
    ItemScoreKnowledgePreviewResponse? PrimaryKnowledge,
    string Status,
    IReadOnlyList<string> IssueCodes)
{
    public static ItemScoreMappingPreviewRowResponse From(ItemScoreMappingPreviewRow row)
    {
        return new ItemScoreMappingPreviewRowResponse(
            row.QuestionNo,
            row.FieldNames,
            row.ScoreRecordCount,
            row.MaxScore,
            row.AverageScoreRate,
            row.QuestionItemId,
            row.QuestionPreview,
            row.PrimaryKnowledge is null ? null : ItemScoreKnowledgePreviewResponse.From(row.PrimaryKnowledge),
            row.Status,
            row.IssueCodes);
    }
}

public sealed record ItemScoreKnowledgePreviewResponse(
    Guid KnowledgeNodeId,
    string Title,
    string Status,
    int Version)
{
    public static ItemScoreKnowledgePreviewResponse From(ItemScoreKnowledgePreview knowledge)
    {
        return new ItemScoreKnowledgePreviewResponse(
            knowledge.KnowledgeNodeId,
            knowledge.Title,
            knowledge.Status,
            knowledge.Version);
    }
}

public sealed record ItemScoreMappingIssueResponse(
    string QuestionNo,
    IReadOnlyList<string> Codes)
{
    public static ItemScoreMappingIssueResponse From(ItemScoreMappingIssue issue)
    {
        return new ItemScoreMappingIssueResponse(issue.QuestionNo, issue.Codes);
    }
}

public sealed record ScoreEvidenceAnalysisPreviewRequest(
    bool ContainsStudentPii = false,
    IReadOnlyList<ItemScoreMappingRequest>? Mappings = null);

public sealed record ScoreEvidenceAnalysisPreviewResponse(
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
    IReadOnlyList<string> AuditTrail)
{
    public static ScoreEvidenceAnalysisPreviewResponse From(ScoreEvidenceAnalysisServiceResult result) =>
        new(
            result.Status,
            result.Mode,
            result.ProductionEligible,
            result.RealStudentDataUsed,
            result.WritesProductionHistory,
            result.AssessmentId,
            result.AssessmentTitle,
            result.ScoreDerivedPerformance,
            result.KnowledgeMastery,
            result.AbilityPerformance,
            result.CognitivePerformance,
            result.ObservedContexts,
            result.ErrorPatternAssociations,
            result.TeachingRecommendations,
            result.TeacherConfirmedDiagnoses,
            result.DiagnosisStatus,
            result.BlockingIssues,
            result.TeacherMessage,
            result.AuditTrail);
}

public sealed record CommentaryReportExportRequest(
    string Format,
    bool AllowAiDraftText,
    IReadOnlyList<ItemScoreMappingRequest> Mappings);

public sealed record CommentaryReportExportResponse(
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
    IReadOnlyList<CommentaryReportSectionResponse> Sections,
    IReadOnlyList<CommentaryWeakKnowledgePointResponse> WeakKnowledgePoints,
    IReadOnlyList<CommentaryPracticeSuggestionResponse> PracticeSuggestions,
    IReadOnlyList<CommentaryReportIssueResponse> BlockingIssues,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail)
{
    public static CommentaryReportExportResponse From(CommentaryReportExportServiceResult result)
    {
        return new CommentaryReportExportResponse(
            result.Status,
            result.Mode,
            result.ProductionEligible,
            result.RealStudentDataUsed,
            result.WritesProductionHistory,
            result.AllowAiDraftText,
            result.AssessmentId,
            result.AssessmentTitle,
            result.Format,
            result.ArtifactPath,
            result.ManifestSha256,
            result.ReportMarkdown,
            result.Sections.Select(CommentaryReportSectionResponse.From).ToArray(),
            result.WeakKnowledgePoints.Select(CommentaryWeakKnowledgePointResponse.From).ToArray(),
            result.PracticeSuggestions.Select(CommentaryPracticeSuggestionResponse.From).ToArray(),
            result.BlockingIssues.Select(CommentaryReportIssueResponse.From).ToArray(),
            result.TeacherMessage,
            result.AuditTrail);
    }
}

public sealed record CommentaryReportSectionResponse(
    string SectionId,
    string Title,
    string Summary)
{
    public static CommentaryReportSectionResponse From(CommentaryReportSection section)
    {
        return new CommentaryReportSectionResponse(section.SectionId, section.Title, section.Summary);
    }
}

public sealed record CommentaryWeakKnowledgePointResponse(
    Guid KnowledgeNodeId,
    string Title,
    int Version,
    decimal ScoreRate,
    string QuestionNo)
{
    public static CommentaryWeakKnowledgePointResponse From(CommentaryWeakKnowledgePoint point)
    {
        return new CommentaryWeakKnowledgePointResponse(point.KnowledgeNodeId, point.Title, point.Version, point.ScoreRate, point.QuestionNo);
    }
}

public sealed record CommentaryPracticeSuggestionResponse(
    Guid KnowledgeNodeId,
    string KnowledgeTitle,
    string Suggestion)
{
    public static CommentaryPracticeSuggestionResponse From(CommentaryPracticeSuggestion suggestion)
    {
        return new CommentaryPracticeSuggestionResponse(suggestion.KnowledgeNodeId, suggestion.KnowledgeTitle, suggestion.Suggestion);
    }
}

public sealed record CommentaryReportIssueResponse(
    string QuestionNo,
    IReadOnlyList<string> Codes)
{
    public static CommentaryReportIssueResponse From(CommentaryReportIssue issue)
    {
        return new CommentaryReportIssueResponse(issue.QuestionNo, issue.Codes);
    }
}
