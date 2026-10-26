namespace K12QuestionGraph.Api.Questions;

using System.Globalization;
using System.Text.Json;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.Infrastructure.Json;
using static K12QuestionGraph.Api.FileStore.FormHelpers;

    public static class QuestionHelpers
{
    public static string GetQuestionPreview(IReadOnlyList<QuestionBlock> blocks)
{
    foreach (var block in blocks.OrderBy(x => x.SortOrder))
    {
        var preview = GetBlockPreview(block);
        if (!string.IsNullOrWhiteSpace(preview))
        {
            return preview.Length <= 120 ? preview : string.Concat(preview.AsSpan(0, 120), "...");
        }
    }

    return string.Empty;
}

    public static string GetBlockPreview(QuestionBlock block)
{
    try
    {
        using var document = JsonDocument.Parse(block.Content);
        var root = document.RootElement;
        if (root.ValueKind == JsonValueKind.Object)
        {
            foreach (var propertyName in new[] { "text", "answer", "latex", "label" })
            {
                if (root.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String)
                {
                    return property.GetString() ?? string.Empty;
                }
            }
        }

        return root.ToString();
    }
    catch (JsonException)
    {
        return block.Content;
    }
}

    public static bool RequiresTableBlockReview(QuestionBlock block)
{
    if (!string.Equals(block.BlockType, "table", StringComparison.OrdinalIgnoreCase))
    {
        return false;
    }

    try
    {
        using var document = JsonDocument.Parse(block.Content);
        var root = document.RootElement;
        var reviewStatus = TryGetStringProperty(root, "reviewStatus");
        if (string.Equals(reviewStatus, "pending_review", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        var confidence = TryGetDoubleProperty(root, "confidence");
        return confidence.HasValue && confidence.Value < 0.8;
    }
    catch (JsonException)
    {
        return true;
    }
}

    public static ReviewQueueItem CreateTableBlockReviewItem(QuestionItem item, QuestionBlock block, DateTimeOffset now)
{
    double? confidence = null;
    string? caption = null;
    string? reviewStatus = null;
    try
    {
        using var document = JsonDocument.Parse(block.Content);
        var root = document.RootElement;
        confidence = TryGetDoubleProperty(root, "confidence");
        caption = TryGetStringProperty(root, "caption");
        reviewStatus = TryGetStringProperty(root, "reviewStatus");
    }
    catch (JsonException)
    {
        reviewStatus = "pending_review";
    }

    return new ReviewQueueItem
    {
        ReviewType = "question_table_block_review",
        Status = ReviewStatuses.Open,
        CreatedAt = now,
        Payload = JsonSerializer.Serialize(new
        {
            questionItemId = item.Id,
            questionBlockId = block.Id,
            sourceRegionId = block.SourceRegionId,
            blockType = block.BlockType,
            caption,
            confidence,
            reviewStatus = string.IsNullOrWhiteSpace(reviewStatus) ? "pending_review" : reviewStatus,
            riskLevel = "medium",
            requiredAction = "review_table_structure",
            reason = "table_block_low_confidence_or_pending_review",
            sourceWorkflowKey = "real009_table_structure"
        })
    };
}

    public static bool RequiresFormulaBlockReview(QuestionBlock block)
{
    if (!string.Equals(block.BlockType, "formula", StringComparison.OrdinalIgnoreCase))
    {
        return false;
    }

    try
    {
        using var document = JsonDocument.Parse(block.Content);
        var root = document.RootElement;
        var sourceFormat = TryGetStringProperty(root, "sourceFormat");
        var reviewStatus = TryGetStringProperty(root, "reviewStatus");
        var confidence = TryGetDoubleProperty(root, "confidence");
        if (string.Equals(reviewStatus, "pending_review", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (confidence.HasValue && confidence.Value < 0.9)
        {
            return true;
        }

        if (sourceFormat is not null &&
            !string.Equals(sourceFormat, "omml", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(sourceFormat, "latex", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return false;
    }
    catch (JsonException)
    {
        return true;
    }
}

    public static ReviewQueueItem CreateFormulaBlockReviewItem(QuestionItem item, QuestionBlock block, DateTimeOffset now)
{
    double? confidence = null;
    string? sourceFormat = null;
    string? reviewStatus = null;
    string? fallbackImageUrl = null;
    try
    {
        using var document = JsonDocument.Parse(block.Content);
        var root = document.RootElement;
        confidence = TryGetDoubleProperty(root, "confidence");
        sourceFormat = TryGetStringProperty(root, "sourceFormat");
        reviewStatus = TryGetStringProperty(root, "reviewStatus");
        fallbackImageUrl = TryGetStringProperty(root, "fallbackImageUrl");
    }
    catch (JsonException)
    {
        reviewStatus = "pending_review";
    }

    return new ReviewQueueItem
    {
        ReviewType = "question_formula_block_review",
        Status = ReviewStatuses.Open,
        CreatedAt = now,
        Payload = JsonSerializer.Serialize(new
        {
            questionItemId = item.Id,
            questionBlockId = block.Id,
            sourceRegionId = block.SourceRegionId,
            blockType = block.BlockType,
            sourceFormat = string.IsNullOrWhiteSpace(sourceFormat) ? "unknown" : sourceFormat,
            confidence,
            fallbackImageUrl,
            reviewStatus = string.IsNullOrWhiteSpace(reviewStatus) ? "pending_review" : reviewStatus,
            riskLevel = "medium",
            requiredAction = "review_formula_structure",
            reason = "formula_block_low_confidence_or_non_omml_candidate",
            sourceWorkflowKey = "real010_formula_fidelity"
        })
    };
}

    public static string? TryGetStringProperty(JsonElement root, string propertyName)
{
    return root.ValueKind == JsonValueKind.Object &&
        root.TryGetProperty(propertyName, out var property) &&
        property.ValueKind == JsonValueKind.String
        ? property.GetString()
        : null;
}

    public static double? TryGetDoubleProperty(JsonElement root, string propertyName)
{
    if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty(propertyName, out var property))
    {
        return null;
    }

    if (property.ValueKind == JsonValueKind.Number && property.TryGetDouble(out var number))
    {
        return number;
    }

    return property.ValueKind == JsonValueKind.String &&
        double.TryParse(property.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out number)
        ? number
        : null;
}

    public static bool QuestionBlockLooksLikeRetainedNoise(QuestionBlock block)
{
    if (!string.Equals(block.BlockType, "text", StringComparison.OrdinalIgnoreCase))
    {
        return false;
    }

    try
    {
        using var document = JsonDocument.Parse(block.Content);
        if (document.RootElement.ValueKind != JsonValueKind.Object ||
            !document.RootElement.TryGetProperty("text", out var textElement) ||
            textElement.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        var text = textElement.GetString() ?? string.Empty;
        return NoiseMarkers().Any(marker => text.Contains(marker, StringComparison.OrdinalIgnoreCase));
    }
    catch (JsonException)
    {
        return false;
    }
}

    public static string BuildSourceDocumentRollbackSql(Guid sourceDocumentId)
{
    return string.Join(Environment.NewLine,
        $"-- REAL012 dry-run rollback reference for source_document {sourceDocumentId}",
        "begin;",
        "delete from review_queue_items where payload::text like '%" + sourceDocumentId + "%';",
        "delete from question_assets where source_region_id in (select id from source_regions where source_document_id = '" + sourceDocumentId + "');",
        "delete from question_blocks where source_region_id in (select id from source_regions where source_document_id = '" + sourceDocumentId + "');",
        "delete from source_regions where source_document_id = '" + sourceDocumentId + "';",
        "rollback;");
}

    public static string[] NoiseMarkers() =>
[
    "姓名",
    "准考证",
    "装订线",
    "密封线",
    "考试注意",
    "注意事项",
    "本试卷",
    "水印",
    "页码"
];

public static string? ValidateQuestionCreateRequest(QuestionCreateRequest request)
{
    if (request.Blocks.Count == 0)
    {
        return "question_blocks_required";
    }

    foreach (var block in request.Blocks)
    {
        if (!IsAllowedQuestionBlockType(NormalizeToken(block.BlockType, "text")))
        {
            return "invalid_block_type";
        }
    }

    return null;
}

    public static bool IsAllowedQuestionBlockType(string blockType)
{
    return blockType is
        "text" or
        "stem" or
        "option" or
        "sub_question" or
        "subquestion" or
        "scoring_point" or
        "answer" or
        "solution" or
        "formula" or
        "image" or
        "table" or
        "chart" or
        "group_ref";
}



    public static string ResolveCandidateText(CutCandidate candidate)
{
    try
    {
        using var document = JsonDocument.Parse(candidate.CandidatePayload);
        var root = document.RootElement;
        var textPreview = JsonElementReaders.ReadString(root, "textPreview", string.Empty).Trim();
        if (!string.IsNullOrWhiteSpace(textPreview))
        {
            return textPreview;
        }
    }
    catch (JsonException)
    {
        return $"候选片段 {candidate.SequenceNo}";
    }

    return $"候选片段 {candidate.SequenceNo}";
}

}
