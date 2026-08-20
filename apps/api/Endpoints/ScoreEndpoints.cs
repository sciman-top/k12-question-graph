using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Application.Workflows.Contracts;
using K12QuestionGraph.Api.Scores;

namespace K12QuestionGraph.Api.Endpoints;

public static class ScoreEndpoints
{
    public static IEndpointRouteBuilder MapScoreEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/score-imports/xlsx", async (
            HttpRequest request,
            ScoreSpreadsheetImportAdapter spreadsheetAdapter,
            ScoreAnalysisWorkflowService workflowService,
            CancellationToken cancellationToken) =>
        {
            var form = await request.ReadFormAsync(cancellationToken);
            var file = form.Files.GetFile("file");
            if (file is null)
            {
                return Results.BadRequest(new { error = "missing_file" });
            }

            var containsStudentPii = bool.TryParse(form["containsStudentPii"], out var pii) && pii;
            try
            {
                await using var stream = file.OpenReadStream();
                var serviceRequest = await spreadsheetAdapter.ParseAsync(
                    stream,
                    file.FileName,
                    containsStudentPii,
                    cancellationToken);
                var result = await workflowService.ImportScoresAsync(serviceRequest, cancellationToken);
                var response = ScoreImportResponse.From(result);
                return result.Status == "blocked"
                    ? Results.BadRequest(response)
                    : Results.Created($"/score-imports/{result.BatchId}", response);
            }
            catch (ScoreSpreadsheetImportException ex)
            {
                return Results.Json(new
                {
                    status = "blocked",
                    mode = "draft_test",
                    productionEligible = false,
                    realStudentDataUsed = false,
                    containsStudentPii,
                    teacherMessage = ex.Message,
                    errors = new[] { new { rowNumber = 0, code = ex.Code, message = ex.Message, fields = Array.Empty<string>() } },
                    auditTrail = new[] { "blocked_invalid_xlsx", "no_production_history_write" }
                }, statusCode: ex.StatusCode);
            }
        })
        .WithName("ImportScoreSpreadsheet");

        endpoints.MapPost("/score-imports", async (
            ScoreImportRequest request,
            ScoreAnalysisWorkflowService workflowService,
            CancellationToken cancellationToken) =>
        {
            var fieldMapping = request.FieldMapping ?? new ScoreImportFieldMappingRequest(
                string.Empty,
                string.Empty,
                new Dictionary<string, string>());
            var rows = request.Rows ?? Array.Empty<ScoreImportRowApiRequest>();
            var result = await workflowService.ImportScoresAsync(
                new ScoreImportServiceRequest(
                    request.AssessmentKey,
                    request.AssessmentTitle,
                    request.Subject,
                    request.Stage,
                    request.Grade,
                    request.TemplateKey,
                    request.TemplateDisplayName,
                    request.SourceFileName,
                    request.ContainsStudentPii,
                    request.ProductionEligible,
                    request.MaxTotalScore,
                    new ScoreImportFieldMapping(
                        fieldMapping.StudentKey,
                        fieldMapping.TotalScore,
                        fieldMapping.ItemScores ?? new Dictionary<string, string>()),
                    request.ItemMaxScores ?? new Dictionary<string, decimal>(),
                    rows.Select(x => new ScoreImportRowRequest(
                        x.RowNumber,
                        x.Values ?? new Dictionary<string, string>())).ToArray()),
                cancellationToken);

            var response = ScoreImportResponse.From(result);
            return result.Status == "blocked"
                ? Results.BadRequest(response)
                : Results.Created($"/score-imports/{result.BatchId}", response);
        })
        .WithName("ImportScores");

        endpoints.MapPost("/assessments/{assessmentId:guid}/item-score-mappings/preview", async (
            Guid assessmentId,
            ItemScoreMappingPreviewRequest request,
            ScoreAnalysisWorkflowService workflowService,
            CancellationToken cancellationToken) =>
        {
            var result = await workflowService.PreviewItemScoreMappingsAsync(
                assessmentId,
                new ItemScoreMappingPreviewServiceRequest(
                    (request.Mappings ?? Array.Empty<ItemScoreMappingRequest>())
                        .Select(x => new ItemScoreMappingRequestItem(x.QuestionNo, x.QuestionItemId))
                        .ToArray()),
                cancellationToken);
            if (result is null)
            {
                return Results.NotFound(new { error = "assessment_not_found" });
            }

            return Results.Ok(ItemScoreMappingPreviewResponse.From(result));
        })
        .WithName("PreviewItemScoreMappings");

        endpoints.MapPost("/assessments/{assessmentId:guid}/score-evidence-analysis/preview", async (
            Guid assessmentId,
            ScoreEvidenceAnalysisPreviewRequest request,
            ScoreAnalysisWorkflowService workflowService,
            CancellationToken cancellationToken) =>
        {
            var result = await workflowService.PreviewScoreEvidenceAnalysisAsync(
                assessmentId,
                new ScoreEvidenceAnalysisServiceRequest(
                    request.ContainsStudentPii,
                    (request.Mappings ?? Array.Empty<ItemScoreMappingRequest>())
                        .Select(x => new ItemScoreMappingRequestItem(x.QuestionNo, x.QuestionItemId))
                        .ToArray()),
                cancellationToken);
            if (result is null)
            {
                return Results.NotFound(new { error = "assessment_not_found" });
            }

            return Results.Ok(ScoreEvidenceAnalysisPreviewResponse.From(result));
        })
        .WithName("PreviewScoreEvidenceAnalysis");

        endpoints.MapPost("/assessments/{assessmentId:guid}/commentary-report/export", async (
            Guid assessmentId,
            CommentaryReportExportRequest request,
            ScoreAnalysisWorkflowService workflowService,
            CancellationToken cancellationToken) =>
        {
            var result = await workflowService.ExportCommentaryReportAsync(
                assessmentId,
                new CommentaryReportExportServiceRequest(
                    request.Format,
                    request.AllowAiDraftText,
                    (request.Mappings ?? Array.Empty<ItemScoreMappingRequest>())
                        .Select(x => new ItemScoreMappingRequestItem(x.QuestionNo, x.QuestionItemId))
                        .ToArray()),
                cancellationToken);
            if (result is null)
            {
                return Results.NotFound(new { error = "assessment_not_found" });
            }

            var response = CommentaryReportExportResponse.From(result);
            return result.Status == "blocked"
                ? Results.Conflict(response)
                : Results.Ok(response);
        })
        .WithName("ExportCommentaryReport");

        return endpoints;
    }
}
