namespace K12QuestionGraph.Api.Endpoints;

using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Application.Workflows.Contracts;
using K12QuestionGraph.Api.Security;

public static class KnowledgeEvidenceEndpoints
            {
                public static void MapKnowledgeEvidenceEndpoints(this IEndpointRouteBuilder app)
            {
                app.MapGet("/knowledge-evidence/questions", async Task<IResult> (             string? evidenceMode,             bool? previewMode,             string? requirementId,             string? facetId,             string? ability,             string? cognitiveDemand,             string? methodOrExperiment,             string? context,             string? representation,             string? profileId,             decimal? observedDifficultyMin,             decimal? observedDifficultyMax,             double? estimatedDifficultyMin,             double? estimatedDifficultyMax,             string? sourceType,             int? page,             int? pageSize,             KnowledgeEvidenceWorkflowService workflowService,             CancellationToken cancellationToken) =>
            {
                try
            {
                var result = await workflowService.SearchQuestionsAsync(                     new QuestionEvidenceSearchRequest(                         evidenceMode ?? "active",                         previewMode ?? false,                         requirementId,                         facetId,                         ability,                         cognitiveDemand,                         methodOrExperiment,                         context,                         representation,                         profileId,                         observedDifficultyMin,                         observedDifficultyMax,                         estimatedDifficultyMin,                         estimatedDifficultyMax,                         sourceType,                         page ?? 1,                         pageSize ?? 20),                     cancellationToken);
            return Results.Ok(result);             }
            catch (ArgumentException exception) when (                 exception.Message.Contains("invalid_evidence_mode", StringComparison.Ordinal)                 || exception.Message.Contains("preview_mode_required", StringComparison.Ordinal)                 || exception.Message.Contains("invalid_difficulty_range", StringComparison.Ordinal))
            {
                var error = exception.Message.Contains("preview_mode_required", StringComparison.Ordinal)                     ? "preview_mode_required"                     : exception.Message.Contains("invalid_difficulty_range", StringComparison.Ordinal)                         ? "invalid_difficulty_range"                         : "invalid_evidence_mode";
            return Results.BadRequest(new
            {
                error });             }         })
        .WithName("SearchQuestionEvidence");
        app.MapGet("/knowledge-evidence/reviews", async Task<IResult> (             string? groupId,             int? page,             int? pageSize,             KnowledgeEvidenceWorkflowService workflowService,             CancellationToken cancellationToken) =>
            {
                var result = await workflowService.ListCurriculumEvidenceReviewsAsync(                 new CurriculumEvidenceReviewListRequest(groupId, page ?? 1, pageSize ?? 50),                 cancellationToken);
            return Results.Ok(result);         })
        .WithName("ListCurriculumEvidenceReviews");
        app.MapGet("/knowledge-evidence/reviews/{candidateId:guid}/replacement-options", async Task<IResult> (             Guid candidateId,             KnowledgeEvidenceWorkflowService workflowService,             CancellationToken cancellationToken) =>
            {
                var result = await workflowService.GetCurriculumEvidenceReplacementOptionsAsync(                 candidateId,                 cancellationToken);
            return result is null                 ? Results.NotFound(new
            {
                error = "curriculum_evidence_candidate_not_found" })                 : Results.Ok(result);         })
        .WithName("ListCurriculumEvidenceReplacementOptions");
        app.MapPost("/knowledge-evidence/reviews/decisions", async Task<IResult> (             CurriculumEvidenceDecisionRequest request,             HttpContext httpContext,             KnowledgeEvidenceWorkflowService workflowService,             CancellationToken cancellationToken) =>
            {
                try
            {
                var identity = AdminInternalEndpointGuard.ResolveReviewIdentity(httpContext.User);
            var authenticatedRequest = request with
            {
                Reviewer = identity.Reviewer,                     ActorRole = identity.ActorRole                 };
            return Results.Ok(await workflowService.DecideCurriculumEvidenceAsync(authenticatedRequest, cancellationToken));             }
            catch (ArgumentException exception)
            {
                return Results.BadRequest(new
            {
                error = exception.Message.Split(' ')[0] });             }
            catch (KeyNotFoundException exception)
            {
                return Results.NotFound(new
            {
                error = exception.Message });             }
            catch (InvalidOperationException exception)
            {
                return Results.Conflict(new
            {
                error = exception.Message });             }         })
        .WithName("DecideCurriculumEvidenceReview");
        app.MapPost("/knowledge-evidence/reviews/batch-approve", async Task<IResult> (             CurriculumEvidenceBatchDecisionRequest request,             HttpContext httpContext,             KnowledgeEvidenceWorkflowService workflowService,             CancellationToken cancellationToken) =>
            {
                try
            {
                var identity = AdminInternalEndpointGuard.ResolveReviewIdentity(httpContext.User);
            var authenticatedRequest = request with
            {
                Reviewer = identity.Reviewer,                     ActorRole = identity.ActorRole                 };
            return Results.Ok(await workflowService.BatchApproveCurriculumEvidenceAsync(authenticatedRequest, cancellationToken));             }
            catch (ArgumentException exception)
            {
                return Results.BadRequest(new
            {
                error = exception.Message.Split(' ')[0] });             }
            catch (KeyNotFoundException exception)
            {
                return Results.NotFound(new
            {
                error = exception.Message });             }
            catch (InvalidOperationException exception)
            {
                return Results.Conflict(new
            {
                error = exception.Message });             }         })
        .WithName("BatchApproveCurriculumEvidenceReviews");
        app.MapPost("/knowledge-evidence/reviews/decisions/{decisionId:guid}/undo", async Task<IResult> (             Guid decisionId,             CurriculumEvidenceUndoRequest request,             HttpContext httpContext,             KnowledgeEvidenceWorkflowService workflowService,             CancellationToken cancellationToken) =>
            {
                try
            {
                var identity = AdminInternalEndpointGuard.ResolveReviewIdentity(httpContext.User);
            var authenticatedRequest = request with
            {
                Reviewer = identity.Reviewer,                     ActorRole = identity.ActorRole                 };
            return Results.Ok(await workflowService.UndoCurriculumEvidenceDecisionAsync(                     decisionId,                     authenticatedRequest,                     cancellationToken));             }
            catch (ArgumentException exception)
            {
                return Results.BadRequest(new
            {
                error = exception.Message.Split(' ')[0] });             }
            catch (KeyNotFoundException exception)
            {
                return Results.NotFound(new
            {
                error = exception.Message });             }
            catch (InvalidOperationException exception)
            {
                return Results.Conflict(new
            {
                error = exception.Message });             }         })
        .WithName("UndoCurriculumEvidenceReviewDecision");
    }
}