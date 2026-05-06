using System.Text.Json;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace K12QuestionGraph.Api.Application.Workflows;

public interface ICutCandidateGenerationService
{
    Task<CutCandidateGenerationResult> GenerateAsync(Guid sourceDocumentId, CancellationToken cancellationToken);
}

public sealed record CutCandidateGenerationResult(
    Guid SourceDocumentId,
    int GeneratedCount,
    int LowConfidenceReviewQueueCount,
    decimal LowConfidenceThreshold);

public sealed class CutCandidateGenerationService(KqgDbContext dbContext) : ICutCandidateGenerationService
{
    private const decimal LowConfidenceThreshold = 0.85m;

    public async Task<CutCandidateGenerationResult> GenerateAsync(Guid sourceDocumentId, CancellationToken cancellationToken)
    {
        var sourceExists = await dbContext.SourceDocuments
            .AsNoTracking()
            .AnyAsync(x => x.Id == sourceDocumentId, cancellationToken);
        if (!sourceExists)
        {
            throw new InvalidOperationException("source_document_not_found");
        }

        var regions = await dbContext.SourceRegions
            .Where(x => x.SourceDocumentId == sourceDocumentId)
            .OrderBy(x => x.PageNumber)
            .ThenBy(x => x.CreatedAt)
            .ToListAsync(cancellationToken);

        if (regions.Count == 0)
        {
            return new CutCandidateGenerationResult(sourceDocumentId, 0, 0, LowConfidenceThreshold);
        }

        var previous = await dbContext.CutCandidates
            .Where(x => x.SourceDocumentId == sourceDocumentId)
            .ToListAsync(cancellationToken);
        if (previous.Count > 0)
        {
            dbContext.CutCandidates.RemoveRange(previous);
        }

        var queueItems = new List<ReviewQueueItem>();
        var candidates = new List<CutCandidate>(regions.Count);
        var now = DateTimeOffset.UtcNow;
        var sequenceNo = 1;
        foreach (var region in regions)
        {
            var confidence = EstimateConfidence(region);
            var payload = JsonSerializer.Serialize(new
            {
                sourceDocumentId = sourceDocumentId,
                sourceRegionId = region.Id,
                pageNumber = region.PageNumber,
                regionType = region.RegionType,
                coordinateUnit = region.CoordinateUnit,
                bbox = new { region.X, region.Y, region.Width, region.Height },
                extractionMode = "source_region_seed"
            });

            var candidate = new CutCandidate
            {
                SourceDocumentId = sourceDocumentId,
                SourceRegionId = region.Id,
                Status = CutCandidateStatuses.PendingReview,
                Confidence = confidence,
                SegmentType = "question_stem",
                SequenceNo = sequenceNo++,
                CandidatePayload = payload,
                FailureReason = confidence < LowConfidenceThreshold ? "low_confidence_requires_manual_takeover" : string.Empty,
                TakeoverAction = confidence < LowConfidenceThreshold ? "manual_review" : "skip",
                Metadata = JsonSerializer.Serialize(new
                {
                    generatedBy = "s005b-cut-candidate-service",
                    generatedAt = now,
                    autoAccepted = false
                }),
                CreatedAt = now,
                UpdatedAt = now
            };
            candidates.Add(candidate);

            if (confidence < LowConfidenceThreshold)
            {
                queueItems.Add(new ReviewQueueItem
                {
                    ReviewType = "cut_candidate",
                    Status = ReviewStatuses.Open,
                    Payload = JsonSerializer.Serialize(new
                    {
                        sourceDocumentId,
                        sourceRegionId = region.Id,
                        confidence,
                        requiredAction = "manual_review",
                        reason = "low_confidence_requires_manual_takeover"
                    }),
                    CreatedAt = now
                });
            }
        }

        dbContext.CutCandidates.AddRange(candidates);
        if (queueItems.Count > 0)
        {
            dbContext.ReviewQueueItems.AddRange(queueItems);
        }

        await dbContext.SaveChangesAsync(cancellationToken);
        return new CutCandidateGenerationResult(sourceDocumentId, candidates.Count, queueItems.Count, LowConfidenceThreshold);
    }

    private static decimal EstimateConfidence(SourceRegion region)
    {
        if (string.Equals(region.RegionType, "preview", StringComparison.OrdinalIgnoreCase))
        {
            return 0.80m;
        }

        if (string.Equals(region.CoordinateUnit, "percent", StringComparison.OrdinalIgnoreCase))
        {
            return 0.88m;
        }

        return 0.90m;
    }
}
