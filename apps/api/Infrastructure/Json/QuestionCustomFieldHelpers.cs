using System.Globalization;
using System.Text.Json;

namespace K12QuestionGraph.Api.Infrastructure.Json;

public static class QuestionCustomFieldHelpers
{
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

    public static string Merge(string json, JsonElement? answer, JsonElement? solution)
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

        return JsonSerializer.Serialize(fields);
    }

    public static bool HasMeaningfulValue(string json, string propertyName)
    {
        var value = TryGetElement(json, propertyName);
        if (!value.HasValue || value.Value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
        {
            return false;
        }

        return value.Value.ValueKind != JsonValueKind.Object ||
               value.Value.EnumerateObject().Any(x =>
                   x.Value.ValueKind is not JsonValueKind.Null and not JsonValueKind.Undefined &&
                   !string.IsNullOrWhiteSpace(x.Value.ToString()));
    }
}
