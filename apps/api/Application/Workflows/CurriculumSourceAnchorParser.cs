using System.Text.Json;

namespace K12QuestionGraph.Api.Application.Workflows;

public sealed record CurriculumSourceAnchor(
    Guid SourceDocumentId,
    Guid? SourceRegionId,
    int PageNumber,
    string AnchorSha256);

public static class CurriculumSourceAnchorParser
{
    public static CurriculumSourceAnchor? ReadFirst(string sourceEvidence)
    {
        if (string.IsNullOrWhiteSpace(sourceEvidence))
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(sourceEvidence);
            if (!TryGetProperty(document.RootElement, out var anchors, "evidenceAnchors", "evidence_anchors")
                || anchors.ValueKind != JsonValueKind.Array)
            {
                return null;
            }

            foreach (var anchor in anchors.EnumerateArray())
            {
                if (!TryReadGuid(anchor, out var sourceDocumentId, "sourceDocumentId", "source_document_id")
                    || !TryReadPositiveInt(anchor, out var pageNumber, "pdfPageNumber", "pdf_page_number"))
                {
                    continue;
                }

                Guid? sourceRegionId = null;
                if (TryReadGuid(anchor, out var regionId, "sourceRegionId", "source_region_id"))
                {
                    sourceRegionId = regionId;
                }

                var sha256 = ReadString(anchor, "textBlockSha256", "text_block_sha256") ?? string.Empty;
                return new CurriculumSourceAnchor(sourceDocumentId, sourceRegionId, pageNumber, sha256);
            }
        }
        catch (JsonException)
        {
            return null;
        }

        return null;
    }

    private static bool TryGetProperty(JsonElement element, out JsonElement value, params string[] names)
    {
        foreach (var name in names)
        {
            if (element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out value))
            {
                return true;
            }
        }

        value = default;
        return false;
    }

    private static bool TryReadGuid(JsonElement element, out Guid value, params string[] names)
    {
        value = Guid.Empty;
        return TryGetProperty(element, out var property, names)
            && property.ValueKind == JsonValueKind.String
            && Guid.TryParse(property.GetString(), out value);
    }

    private static bool TryReadPositiveInt(JsonElement element, out int value, params string[] names)
    {
        value = 0;
        return TryGetProperty(element, out var property, names)
            && property.TryGetInt32(out value)
            && value > 0;
    }

    private static string? ReadString(JsonElement element, params string[] names) =>
        TryGetProperty(element, out var property, names) && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
}
