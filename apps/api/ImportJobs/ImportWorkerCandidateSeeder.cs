using System.Text.Json;
using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.Infrastructure.Json;
using Microsoft.EntityFrameworkCore;

namespace K12QuestionGraph.Api.ImportJobs;

internal static class ImportWorkerCandidateSeeder
{
    public static async Task<ImportWorkerProcessingSummary> SeedAsync(
        KqgDbContext dbContext,
        SourceDocument sourceDocument,
        string workerOutput,
        string generationId,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(workerOutput))
        {
            return ImportWorkerProcessingSummary.Empty;
        }

        using var document = JsonDocument.Parse(workerOutput);
        var root = document.RootElement;
        var adapterName = ReadFirstAdapterName(root);
        if (!root.TryGetProperty("documentModel", out var documentModel) ||
            !documentModel.TryGetProperty("pages", out var pages) ||
            pages.ValueKind != JsonValueKind.Array)
        {
            return ImportWorkerProcessingSummary.Empty with { AdapterName = adapterName };
        }

        const int maxCandidates = 120;
        var now = DateTimeOffset.UtcNow;
        var sequenceNo = 1;
        var regions = new List<SourceRegion>();
        var candidates = new List<CutCandidate>();
        var queueItems = new List<ReviewQueueItem>();

        foreach (var page in pages.EnumerateArray())
        {
            var pageNumber = JsonElementReaders.ReadInt(page, "pageNumber", 1);
            if (!page.TryGetProperty("layoutBlocks", out var blocks) ||
                blocks.ValueKind != JsonValueKind.Array)
            {
                continue;
            }

            var blockIndex = 0;
            foreach (var block in blocks.EnumerateArray())
            {
                if (candidates.Count >= maxCandidates)
                {
                    break;
                }

                var textPreview = JsonElementReaders.ReadString(block, "textPreview", string.Empty).Trim();
                var blockType = NormalizeToken(JsonElementReaders.ReadString(block, "blockType", "document_block"), "document_block");
                if (string.IsNullOrWhiteSpace(textPreview))
                {
                    continue;
                }

                var confidence = JsonElementReaders.ReadDecimal(
                    block,
                    "confidence",
                    blockType == "question_stem" ? CutConfidenceDefaults.SeedStemConfidence : CutConfidenceDefaults.SeedOtherConfidence);
                var takeoverRequired = JsonElementReaders.ReadBool(block, "takeoverRequired", confidence < CutConfidenceDefaults.FallbackTakeoverThreshold);
                var region = new SourceRegion
                {
                    Id = Guid.NewGuid(),
                    SourceDocumentId = sourceDocument.Id,
                    PageNumber = pageNumber,
                    X = 0,
                    Y = Math.Min(95, blockIndex * 6),
                    Width = 100,
                    Height = 5,
                    CoordinateUnit = "percent",
                    RegionType = "document_block",
                    CreatedAt = now
                };
                regions.Add(region);

                var candidate = new CutCandidate
                {
                    Id = Guid.NewGuid(),
                    SourceDocumentId = sourceDocument.Id,
                    SourceRegionId = region.Id,
                    Status = CutCandidateStatuses.PendingReview,
                    Confidence = confidence,
                    SegmentType = blockType,
                    SequenceNo = sequenceNo++,
                    CandidatePayload = JsonSerializer.Serialize(new
                    {
                        extractionMode = "document_worker_local",
                        adapterName,
                        pageNumber,
                        blockType,
                        textPreview,
                        takeoverRequired,
                        generationId,
                        sourceRegionId = region.Id
                    }),
                    FailureReason = takeoverRequired ? "requires_manual_review" : string.Empty,
                    TakeoverAction = takeoverRequired ? "manual_review" : "skip",
                    Metadata = JsonSerializer.Serialize(new
                    {
                        generatedBy = "document_worker_local",
                        generatedAt = now,
                        generationId,
                        adapterName,
                        source = "ImportJob.worker-smoke"
                    }),
                    CreatedAt = now,
                    UpdatedAt = now
                };
                candidates.Add(candidate);

                if (takeoverRequired)
                {
                    queueItems.Add(new ReviewQueueItem
                    {
                        ReviewType = "cut_candidate",
                        Status = ReviewStatuses.Open,
                        Payload = JsonSerializer.Serialize(new
                        {
                            sourceDocumentId = sourceDocument.Id,
                            sourceRegionId = region.Id,
                            candidateId = candidate.Id,
                            generationId,
                            confidence,
                            requiredAction = "manual_review",
                            reason = "document_worker_low_confidence_or_header",
                            textPreview
                        }),
                        CreatedAt = now
                    });
                }

                blockIndex += 1;
            }
        }

        if (regions.Count == 0 || candidates.Count == 0)
        {
            return ImportWorkerProcessingSummary.Empty with { AdapterName = adapterName };
        }

        dbContext.SourceRegions.AddRange(regions);
        dbContext.CutCandidates.AddRange(candidates);
        if (queueItems.Count > 0)
        {
            dbContext.ReviewQueueItems.AddRange(queueItems);
        }

        return new ImportWorkerProcessingSummary(
            AdapterName: adapterName,
            SourceRegionCount: regions.Count,
            CutCandidateCount: candidates.Count,
            LowConfidenceReviewQueueCount: queueItems.Count);
    }

    static string ReadFirstAdapterName(JsonElement root)
    {
        if (root.TryGetProperty("adapterDiagnostics", out var diagnostics) &&
            diagnostics.ValueKind == JsonValueKind.Array &&
            diagnostics.GetArrayLength() > 0)
        {
            return JsonElementReaders.ReadString(diagnostics[0], "adapterName", string.Empty);
        }

        return string.Empty;
    }
    internal static string NormalizeToken(string value, string fallback)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return fallback;
        }

        return value.Trim().ToLowerInvariant().Replace('-', '_').Replace(' ', '_');
    }
}
