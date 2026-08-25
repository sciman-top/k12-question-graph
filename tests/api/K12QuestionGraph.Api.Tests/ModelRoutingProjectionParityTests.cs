using System.Text.Json;
using YamlDotNet.RepresentationModel;

namespace K12QuestionGraph.Api.Tests;

public sealed class ModelRoutingProjectionParityTests
{
    private static readonly (string YamlName, string JsonName)[] ComparedFields =
    [
        ("handler", "Handler"),
        ("stage", "Stage"),
        ("model_role", "ModelRole"),
        ("model", "ModelName"),
        ("reasoning_effort", "ReasoningEffort"),
        ("escalate_to_role", "EscalateToRole"),
        ("escalate_to", "EscalateToModel"),
        ("escalate_reasoning_effort", "EscalateReasoningEffort"),
        ("structured_output_schema", "StructuredOutputSchema"),
        ("require_human_review_below_confidence", "RequireHumanReviewBelowConfidence"),
        ("batchable", "Batchable"),
        ("escalation_signals", "EscalationSignals")
    ];

    [Fact]
    public void YamlRoutesMatchRuntimeAppsettingsProjection()
    {
        var yamlPath = Path.Combine(RepoRoot, "configs", "model_routing.defaults.yaml");
        var appsettingsPath = Path.Combine(RepoRoot, "apps", "api", "appsettings.json");
        var yamlRoutes = ReadYamlRoutes(yamlPath);
        using var appsettings = JsonDocument.Parse(File.ReadAllText(appsettingsPath));
        var jsonRoutes = appsettings.RootElement.GetProperty("AiRouting").GetProperty("Routes");

        var yamlNames = yamlRoutes.Keys.OrderBy(x => x, StringComparer.Ordinal).ToArray();
        var jsonNames = jsonRoutes.EnumerateObject().Select(x => x.Name).OrderBy(x => x, StringComparer.Ordinal).ToArray();
        Assert.Equal(yamlNames, jsonNames);

        foreach (var routeName in yamlNames)
        {
            var yamlRoute = yamlRoutes[routeName];
            var jsonRoute = jsonRoutes.GetProperty(routeName);
            foreach (var (yamlName, jsonName) in ComparedFields)
            {
                var yamlValue = ReadYamlValue(yamlRoute, yamlName);
                var jsonValue = ReadJsonValue(jsonRoute, jsonName);
                Assert.True(
                    string.Equals(yamlValue, jsonValue, StringComparison.Ordinal),
                    $"Route '{routeName}' field '{yamlName}' differs: YAML='{yamlValue ?? "<null>"}', appsettings='{jsonValue ?? "<null>"}'.");
            }
        }
    }

    private static Dictionary<string, YamlMappingNode> ReadYamlRoutes(string path)
    {
        using var reader = new StringReader(File.ReadAllText(path));
        var stream = new YamlStream();
        stream.Load(reader);
        var root = (YamlMappingNode)stream.Documents[0].RootNode;
        var routes = (YamlMappingNode)GetYamlChild(root, "routes");
        return routes.Children.ToDictionary(
            pair => ((YamlScalarNode)pair.Key).Value!,
            pair => (YamlMappingNode)pair.Value,
            StringComparer.Ordinal);
    }

    private static string? ReadYamlValue(YamlMappingNode route, string name)
    {
        var child = route.Children.FirstOrDefault(pair =>
            string.Equals(((YamlScalarNode)pair.Key).Value, name, StringComparison.OrdinalIgnoreCase)).Value;
        return child switch
        {
            null => null,
            YamlScalarNode scalar => NormalizeScalar(scalar.Value),
            YamlSequenceNode sequence => string.Join("|", sequence.Children.OfType<YamlScalarNode>().Select(x => NormalizeScalar(x.Value))),
            _ => child.ToString()
        };
    }

    private static string? ReadJsonValue(JsonElement route, string name)
    {
        if (!route.TryGetProperty(name, out var value))
        {
            return null;
        }

        return value.ValueKind switch
        {
            JsonValueKind.String => NormalizeScalar(value.GetString()),
            JsonValueKind.Number => value.GetRawText(),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            JsonValueKind.Array => string.Join("|", value.EnumerateArray().Select(item => NormalizeScalar(item.GetString()))),
            _ => value.GetRawText()
        };
    }

    private static string? NormalizeScalar(string? value) => value?.Trim();

    private static YamlNode GetYamlChild(YamlMappingNode mapping, string name)
    {
        var match = mapping.Children.FirstOrDefault(pair =>
            string.Equals(((YamlScalarNode)pair.Key).Value, name, StringComparison.OrdinalIgnoreCase));
        return match.Value ?? throw new InvalidDataException($"YAML key '{name}' is missing.");
    }

    private static string RepoRoot
    {
        get
        {
            var current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current is not null)
            {
                if (File.Exists(Path.Combine(current.FullName, "configs", "model_routing.defaults.yaml")))
                {
                    return current.FullName;
                }

                current = current.Parent;
            }

            throw new DirectoryNotFoundException("Could not locate the repository root for parity tests.");
        }
    }
}
