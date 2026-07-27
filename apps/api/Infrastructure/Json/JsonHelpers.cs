using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.ImportJobs;

namespace K12QuestionGraph.Api.Infrastructure.Json;

public static class JsonHelpers
{
    public static JsonElement ParseJsonElement(string value)
    {
        try
        {
            using var document = JsonDocument.Parse(string.IsNullOrWhiteSpace(value) ? "{}" : value);
            return document.RootElement.Clone();
        }
        catch (JsonException)
        {
            using var document = JsonDocument.Parse("{}");
            return document.RootElement.Clone();
        }
    }
}

public static class ReviewQueuePayloadHelpers
{
    public static string ResolveRiskLevel(string payloadJson)
    {
        try
        {
            var payload = JsonHelpers.ParseJsonElement(payloadJson);
            return ResolveRiskLevel(payload);
        }
        catch
        {
            return "high";
        }
    }

    public static string ResolveRiskLevel(JsonElement payload)
    {
        if (ResolveConfidence(payload) is { } confidence)
        {
            return confidence < 0.6m ? "high" : confidence < 0.85m ? "medium" : "low";
        }

        return "high";
    }

    public static string ResolveRequiredAction(JsonElement payload)
    {
        return ResolveRequiredActions(payload).FirstOrDefault() ?? "manual_review";
    }

    public static IReadOnlyList<string> ResolveRequiredActions(JsonElement payload)
    {
        if (payload.ValueKind != JsonValueKind.Object)
        {
            return [];
        }

        if (payload.TryGetProperty("requiredActions", out var actionsElement) &&
            actionsElement.ValueKind == JsonValueKind.Array)
        {
            return actionsElement
                .EnumerateArray()
                .Where(x => x.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(x.GetString()))
                .Select(x => x.GetString()!.Trim())
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();
        }

        if (payload.TryGetProperty("requiredAction", out var actionElement) &&
            actionElement.ValueKind == JsonValueKind.String &&
            !string.IsNullOrWhiteSpace(actionElement.GetString()))
        {
            return [actionElement.GetString()!.Trim()];
        }

        return [];
    }

    public static decimal? ResolveConfidence(JsonElement payload)
    {
        if (payload.ValueKind == JsonValueKind.Object &&
            payload.TryGetProperty("confidence", out var confidenceElement) &&
            confidenceElement.TryGetDecimal(out var confidence))
        {
            return confidence;
        }

        return null;
    }

    public static string? ResolveReason(JsonElement payload)
    {
        if (payload.ValueKind == JsonValueKind.Object &&
            payload.TryGetProperty("reason", out var reasonElement) &&
            reasonElement.ValueKind == JsonValueKind.String)
        {
            return reasonElement.GetString();
        }

        return null;
    }

    public static int? ResolveQuestionNo(JsonElement payload)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty("questionNo", out var questionNoElement))
        {
            return null;
        }

        if (questionNoElement.ValueKind == JsonValueKind.Number && questionNoElement.TryGetInt32(out var questionNo))
        {
            return questionNo;
        }

        if (questionNoElement.ValueKind == JsonValueKind.String &&
            int.TryParse(questionNoElement.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out questionNo))
        {
            return questionNo;
        }

        return null;
    }

    public static int? ResolveYear(JsonElement payload)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty("year", out var yearElement))
        {
            return null;
        }

        if (yearElement.ValueKind == JsonValueKind.Number && yearElement.TryGetInt32(out var year))
        {
            return year;
        }

        return yearElement.ValueKind == JsonValueKind.String &&
            int.TryParse(yearElement.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out year)
            ? year
            : null;
    }

    public static string WithReviewAudit(
        string payloadJson,
        string reviewedBy,
        string decision,
        string reason,
        DateTimeOffset reviewedAt,
        ReviewQueueRevisionRequest? revision = null)
    {
        JsonObject payload;
        try
        {
            payload = JsonNode.Parse(payloadJson) as JsonObject ?? new JsonObject();
        }
        catch
        {
            payload = new JsonObject();
        }

        var trimmedTags = revision?.KnowledgeTags?
            .Where(tag => !string.IsNullOrWhiteSpace(tag))
            .Select(tag => tag.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var hasRevision = revision is not null && (
            !string.IsNullOrWhiteSpace(revision.TextPreview) ||
            !string.IsNullOrWhiteSpace(revision.Answer) ||
            !string.IsNullOrWhiteSpace(revision.PrimaryKnowledgeLabel) ||
            (trimmedTags is { Length: > 0 }));

        var audit = new JsonObject
        {
            ["reviewedBy"] = reviewedBy,
            ["decision"] = decision,
            ["reason"] = reason,
            ["reviewedAt"] = reviewedAt.ToString("O"),
            ["revision"] = hasRevision
                ? new JsonObject
                {
                    ["textPreview"] = revision?.TextPreview?.Trim(),
                    ["answer"] = revision?.Answer?.Trim(),
                    ["primaryKnowledgeLabel"] = revision?.PrimaryKnowledgeLabel?.Trim(),
                    ["knowledgeTags"] = new JsonArray((trimmedTags ?? []).Select(tag => JsonValue.Create(tag)).ToArray())
                }
                : null
        };

        var history = payload["reviewAuditHistory"] as JsonArray ?? new JsonArray();
        history.Add(audit.DeepClone());
        payload["reviewAuditHistory"] = history;
        payload["reviewAudit"] = audit;

        return payload.ToJsonString();
    }
}

public static class ReviewWorkbenchMutationHelpers
{
    public static string WithPatch(string json, Dictionary<string, object?> patch)
    {
        Dictionary<string, object?> payload;
        try
        {
            payload = JsonSerializer.Deserialize<Dictionary<string, object?>>(json) ?? new Dictionary<string, object?>();
        }
        catch
        {
            payload = new Dictionary<string, object?>();
        }

        foreach (var pair in patch)
        {
            payload[pair.Key] = pair.Value;
        }

        return JsonSerializer.Serialize(payload);
    }

    public static CutCandidate CloneCandidate(CutCandidate source, int sequenceNo, DateTimeOffset now, string splitTag)
    {
        return new CutCandidate
        {
            SourceDocumentId = source.SourceDocumentId,
            SourceRegionId = source.SourceRegionId,
            SuggestedQuestionItemId = null,
            Status = CutCandidateStatuses.PendingReview,
            Confidence = Math.Max(0m, source.Confidence - 0.05m),
            SegmentType = source.SegmentType,
            SequenceNo = sequenceNo,
            CandidatePayload = WithPatch(source.CandidatePayload, new Dictionary<string, object?>
            {
                ["splitTag"] = splitTag,
                ["splitFromCandidateId"] = source.Id
            }),
            FailureReason = "requires_manual_review_after_split",
            TakeoverAction = "manual_review",
            Metadata = WithPatch(source.Metadata, new Dictionary<string, object?>
            {
                ["generatedBy"] = "s006b-split",
                ["generatedAt"] = now.ToString("O")
            }),
            CreatedAt = now,
            UpdatedAt = now
        };
    }

    public static bool QueueItemMatchesCandidates(string payloadJson, HashSet<Guid> candidateSourceRegionIds)
    {
        try
        {
            using var document = JsonDocument.Parse(payloadJson);
            var payload = document.RootElement;
            if (payload.ValueKind != JsonValueKind.Object ||
                !payload.TryGetProperty("sourceRegionId", out var sourceRegionElement) ||
                sourceRegionElement.ValueKind != JsonValueKind.String)
            {
                return false;
            }

            var sourceRegionId = sourceRegionElement.GetString();
            if (string.IsNullOrWhiteSpace(sourceRegionId) || !Guid.TryParse(sourceRegionId, out var parsedRegionId))
            {
                return false;
            }

            return candidateSourceRegionIds.Contains(parsedRegionId);
        }
        catch
        {
            return false;
        }
    }
}

internal static class QuestionJsonMetadata
{
    public static int? TryGetIntField(string json, string propertyName)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Object ||
                !document.RootElement.TryGetProperty(propertyName, out var property))
            {
                return null;
            }

            if (property.ValueKind == JsonValueKind.Number && property.TryGetInt32(out var number))
            {
                return number;
            }

            return property.ValueKind == JsonValueKind.String &&
                int.TryParse(property.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out number)
                ? number
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
