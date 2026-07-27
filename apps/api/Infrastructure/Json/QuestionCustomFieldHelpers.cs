using System.Globalization;
using System.Text.Json;

namespace K12QuestionGraph.Api.Infrastructure.Json;

public static class QuestionCustomFieldHelpers
{
    public static string BuildContainmentFilter(string propertyName, int value)
    {
        return JsonSerializer.Serialize(new Dictionary<string, int> { [propertyName] = value });
    }

    public static string BuildArrayContainmentFilter(string propertyName, string value)
    {
        return JsonSerializer.Serialize(new Dictionary<string, string[]> { [propertyName] = [value] });
    }

    public static JsonElement? TryGetElement(string json, string propertyName)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            return document.RootElement.ValueKind == JsonValueKind.Object &&
                   document.RootElement.TryGetProperty(propertyName, out var property)
                ? property.Clone()
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

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

    public static string? TryGetStringField(string json, string propertyName)
    {
        var value = TryGetElement(json, propertyName);
        if (!value.HasValue || value.Value.ValueKind != JsonValueKind.String)
        {
            return null;
        }

        var text = value.Value.GetString()?.Trim();
        return string.IsNullOrWhiteSpace(text) ? null : text;
    }

    public static IReadOnlyList<string> TryGetStringArrayField(string json, string propertyName)
    {
        var value = TryGetElement(json, propertyName);
        if (!value.HasValue || value.Value.ValueKind != JsonValueKind.Array)
        {
            return [];
        }

        return value.Value
            .EnumerateArray()
            .Where(item => item.ValueKind == JsonValueKind.String)
            .Select(item => item.GetString()?.Trim())
            .Where(item => !string.IsNullOrWhiteSpace(item))
            .Select(item => item!)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    public static bool? TryGetBoolField(string json, string propertyName)
    {
        var value = TryGetElement(json, propertyName);
        return value.HasValue && value.Value.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? value.Value.GetBoolean()
            : null;
    }

    public static string Merge(
        string json,
        JsonElement? answer,
        JsonElement? solution,
        string? primaryKnowledgeLabel = null,
        IReadOnlyList<string>? knowledgeTags = null)
    {
        var fields = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind == JsonValueKind.Object)
            {
                foreach (var property in document.RootElement.EnumerateObject())
                {
                    fields[property.Name] = property.Value.Clone();
                }
            }
        }
        catch (JsonException)
        {
            fields.Clear();
        }

        if (answer.HasValue)
        {
            fields["answer"] = answer.Value.Clone();
        }

        if (solution.HasValue)
        {
            fields["solution"] = solution.Value.Clone();
        }

        if (primaryKnowledgeLabel is not null)
        {
            fields["primaryKnowledgeLabel"] = JsonSerializer.SerializeToElement(primaryKnowledgeLabel.Trim());
        }

        if (knowledgeTags is not null)
        {
            var normalizedTags = knowledgeTags
                .Where(tag => !string.IsNullOrWhiteSpace(tag))
                .Select(tag => tag.Trim())
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();
            fields["knowledgeTags"] = JsonSerializer.SerializeToElement(normalizedTags);
        }

        return JsonSerializer.Serialize(fields);
    }

    public static bool HasMeaningfulValue(string json, string propertyName)
    {
        var value = TryGetElement(json, propertyName);
        if (!value.HasValue || value.Value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
        {
            return false;
        }

        if (value.Value.ValueKind != JsonValueKind.Object)
        {
            return !string.IsNullOrWhiteSpace(value.Value.ToString());
        }

        var contentKeys = propertyName.Equals("answer", StringComparison.OrdinalIgnoreCase)
            ? new[] { "value", "text" }
            : propertyName.Equals("solution", StringComparison.OrdinalIgnoreCase)
                ? new[] { "text", "value" }
                : value.Value.EnumerateObject().Select(x => x.Name).ToArray();
        return contentKeys.Any(key =>
            value.Value.TryGetProperty(key, out var content) &&
            content.ValueKind is not JsonValueKind.Null and not JsonValueKind.Undefined &&
            !string.IsNullOrWhiteSpace(content.ToString()));
    }
}
