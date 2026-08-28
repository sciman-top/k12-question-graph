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
        ("execution_slot", "ExecutionSlot"),
        ("execution_grade", "ExecutionGrade"),
        ("model", "ModelName"),
        ("reasoning_effort", "ReasoningEffort"),
        ("escalate_to_role", "EscalateToRole"),
        ("escalate_to_execution_slot", "EscalateToExecutionSlot"),
        ("escalate_to_execution_grade", "EscalateToExecutionGrade"),
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

    [Fact]
    public void YamlModelPresetsAndFailoverMatchRuntimeAppsettingsProjection()
    {
        var yamlPath = Path.Combine(RepoRoot, "configs", "model_routing.defaults.yaml");
        var appsettingsPath = Path.Combine(RepoRoot, "apps", "api", "appsettings.json");
        using var reader = new StringReader(File.ReadAllText(yamlPath));
        var stream = new YamlStream();
        stream.Load(reader);
        var root = (YamlMappingNode)stream.Documents[0].RootNode;
        var yamlPresets = (YamlMappingNode)GetYamlChild(root, "model_presets");
        using var appsettings = JsonDocument.Parse(File.ReadAllText(appsettingsPath));
        var aiRouting = appsettings.RootElement.GetProperty("AiRouting");
        var jsonPresets = aiRouting.GetProperty("ModelPresets");

        var yamlNames = yamlPresets.Children
            .Select(pair => ((YamlScalarNode)pair.Key).Value!)
            .OrderBy(x => x, StringComparer.Ordinal)
            .ToArray();
        var jsonNames = jsonPresets.EnumerateObject()
            .Select(x => x.Name)
            .OrderBy(x => x, StringComparer.Ordinal)
            .ToArray();
        Assert.Equal(yamlNames, jsonNames);

        foreach (var presetName in yamlNames)
        {
            var yamlPreset = (YamlMappingNode)yamlPresets.Children.First(pair =>
                string.Equals(((YamlScalarNode)pair.Key).Value, presetName, StringComparison.Ordinal)).Value;
            var jsonPreset = jsonPresets.GetProperty(presetName);
            Assert.Equal(ReadYamlValue(yamlPreset, "model_name"), ReadJsonValue(jsonPreset, "ModelName"));
            Assert.Equal(ReadYamlValue(yamlPreset, "reasoning_efforts"), ReadJsonValue(jsonPreset, "ReasoningEfforts"));
            Assert.Equal(ReadYamlValue(yamlPreset, "fallback_reasoning_effort"), ReadJsonValue(jsonPreset, "FallbackReasoningEffort"));

            var yamlGrades = (YamlMappingNode)GetYamlChild(yamlPreset, "grade_to_reasoning_effort");
            var jsonGrades = jsonPreset.GetProperty("GradeToReasoningEffort");
            Assert.Equal(
                yamlGrades.Children.ToDictionary(
                    pair => ((YamlScalarNode)pair.Key).Value!,
                    pair => ReadYamlValue(yamlGrades, ((YamlScalarNode)pair.Key).Value!)!,
                    StringComparer.OrdinalIgnoreCase),
                jsonGrades.EnumerateObject().ToDictionary(
                    pair => pair.Name,
                    pair => pair.Value.GetString()!,
                    StringComparer.OrdinalIgnoreCase));
        }

        Assert.Equal("gpt-5.6-sol", jsonPresets.GetProperty("sol").GetProperty("ModelName").GetString());
        Assert.Equal("gpt-5.6-terra", jsonPresets.GetProperty("terra").GetProperty("ModelName").GetString());
        Assert.Equal("gpt-5.6-luna", jsonPresets.GetProperty("luna").GetProperty("ModelName").GetString());

        var yamlFailover = (YamlMappingNode)GetYamlChild(root, "model_failover");
        var jsonFailover = aiRouting.GetProperty("ModelFailover");
        Assert.Equal(ReadYamlValue(yamlFailover, "enabled"), ReadJsonValue(jsonFailover, "Enabled"));
        Assert.Equal(ReadYamlValue(yamlFailover, "preferred_preset_order"), ReadJsonValue(jsonFailover, "PreferredPresetOrder"));
        Assert.Equal(ReadYamlValue(yamlFailover, "availability_probe_path"), ReadJsonValue(jsonFailover, "AvailabilityProbePath"));
        Assert.Equal(ReadYamlValue(yamlFailover, "failure_cooldown_seconds"), ReadJsonValue(jsonFailover, "FailureCooldownSeconds"));

        var yamlSlots = (YamlMappingNode)GetYamlChild(root, "execution_slots");
        var jsonSlots = aiRouting.GetProperty("ExecutionSlots");
        var yamlSlotNames = yamlSlots.Children
            .Select(pair => ((YamlScalarNode)pair.Key).Value!)
            .OrderBy(x => x, StringComparer.Ordinal)
            .ToArray();
        var jsonSlotNames = jsonSlots.EnumerateObject()
            .Select(x => x.Name)
            .OrderBy(x => x, StringComparer.Ordinal)
            .ToArray();
        Assert.Equal(5, yamlSlotNames.Length);
        Assert.Equal(yamlSlotNames, jsonSlotNames);

        foreach (var slotName in yamlSlotNames)
        {
            var yamlSlot = (YamlMappingNode)yamlSlots.Children.First(pair =>
                string.Equals(((YamlScalarNode)pair.Key).Value, slotName, StringComparison.Ordinal)).Value;
            var jsonSlot = jsonSlots.GetProperty(slotName);
            Assert.Equal(ReadYamlValue(yamlSlot, "default_grade"), ReadJsonValue(jsonSlot, "DefaultGrade"));
            Assert.Equal(ReadYamlValue(yamlSlot, "description"), ReadJsonValue(jsonSlot, "Description"));

            Assert.DoesNotContain(yamlSlot.Children.Keys.OfType<YamlScalarNode>(), key =>
                string.Equals(key.Value, "grades", StringComparison.OrdinalIgnoreCase));
            Assert.False(jsonSlot.TryGetProperty("Grades", out _));
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
