using K12QuestionGraph.Api.Ai;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;

namespace K12QuestionGraph.Api.Tests;

public sealed class AiPresetAvailabilityCoordinatorTests
{
    [Fact]
    public void TracksActivePresetAndUsesRequiredRecoveryOrder()
    {
        var coordinator = new AiPresetAvailabilityCoordinator(Options.Create(CreateOptions()));

        Assert.Equal("astra", coordinator.SelectActivePresetId());
        coordinator.RecordExecutionSuccess("terra");
        Assert.Equal("terra", coordinator.SelectActivePresetId());
        Assert.Equal(["terra", "astra", "sol", "luna", "glm_flash", "deepseek_flash"], coordinator.GetCandidatePresetIds("terra"));

        coordinator.RecordAvailabilityFailure("terra", 503);
        Assert.Equal("astra", coordinator.SelectActivePresetId());
        coordinator.RecordAvailabilityFailure("astra", 503);
        Assert.Equal("sol", coordinator.SelectActivePresetId());
        coordinator.RecordAvailabilityFailure("sol", 503);
        Assert.Equal("luna", coordinator.SelectActivePresetId());
        coordinator.RecordAvailabilityFailure("luna", 503);
        Assert.Equal("glm_flash", coordinator.SelectActivePresetId());
        coordinator.RecordAvailabilityFailure("glm_flash", 503);
        Assert.Equal("deepseek_flash", coordinator.SelectActivePresetId());
        Assert.Equal(["luna", "astra", "sol", "terra", "glm_flash", "deepseek_flash"], coordinator.GetCandidatePresetIds("luna"));
    }

    [Fact]
    public void RejectsPresetConfigurationThatMixesAnUnsupportedEffort()
    {
        var options = CreateOptions();
        options.ModelPresets["sol"].GradeToReasoningEffort["balanced"] = "high";
        var coordinator = new AiPresetAvailabilityCoordinator(Options.Create(options));

        var exception = Assert.Throws<AiRouteException>(() => coordinator.SelectActivePresetId());

        Assert.Equal("invalid_single_model_preset_configuration", exception.Message);
    }

    [Fact]
    public void PinnedLunaOnlySuppressesAllOtherPresetsUntilTheOverrideIsRemoved()
    {
        var options = CreateOptions();
        options.ModelFailover.PinnedPresetId = "luna";
        var coordinator = new AiPresetAvailabilityCoordinator(Options.Create(options));

        Assert.Equal("luna", coordinator.SelectActivePresetId());
        Assert.Equal(["luna"], coordinator.GetCandidatePresetIds("sol"));

        coordinator.RecordAvailabilityFailure("luna", 503);

        Assert.Equal("luna", coordinator.SelectActivePresetId());
        Assert.Equal(["luna"], coordinator.GetCandidatePresetIds("terra"));
    }

    [Fact]
    public void RejectsPinnedPresetThatDoesNotExist()
    {
        var options = CreateOptions();
        options.ModelFailover.PinnedPresetId = "unknown";
        var coordinator = new AiPresetAvailabilityCoordinator(Options.Create(options));

        var exception = Assert.Throws<AiRouteException>(() => coordinator.SelectActivePresetId());

        Assert.Equal("invalid_single_model_preset_configuration", exception.Message);
    }

    [Fact]
    public void RuntimeAppsettingsBindingAcceptsAnEmptyTemporaryPresetPin()
    {
        var options = new ConfigurationBuilder()
            .AddJsonFile(Path.Combine(RepoRoot, "apps", "api", "appsettings.json"))
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["AiRouting:ModelFailover:PinnedPresetId"] = string.Empty
            })
            .Build()
            .GetSection("AiRouting")
            .Get<AiRoutingOptions>()!;
        var coordinator = new AiPresetAvailabilityCoordinator(Options.Create(options));

        Assert.Equal(["astra", "sol", "terra", "luna", "glm_flash", "deepseek_flash"], options.ModelFailover.PreferredPresetOrder);
        Assert.Equal(6, options.ModelPresets.Count);
        Assert.Equal(5, options.ExecutionSlots.Count);
        Assert.Equal("astra", coordinator.SelectActivePresetId());
    }

    [Theory]
    [InlineData("astra", "gpt-6-astra", "quality", "high")]
    [InlineData("astra", "gpt-6-astra", "balanced", "medium")]
    [InlineData("astra", "gpt-6-astra", "economy", "low")]
    [InlineData("glm_flash", "glm-5.3-flash", "quality", "max")]
    [InlineData("glm_flash", "glm-5.3-flash", "balanced", "high")]
    [InlineData("glm_flash", "glm-5.3-flash", "economy", "low")]
    [InlineData("deepseek_flash", "deepseek-v4.1-flash", "quality", "max")]
    [InlineData("deepseek_flash", "deepseek-v4.1-flash", "balanced", "high")]
    public void DefaultModelPresetsCanBePinnedWithTheirDeclaredEffortMapping(
        string presetId,
        string modelName,
        string grade,
        string expectedEffort)
    {
        var options = CreateOptions();
        options.ModelFailover.PinnedPresetId = presetId;
        var coordinator = new AiPresetAvailabilityCoordinator(Options.Create(options));

        Assert.Equal(presetId, coordinator.SelectActivePresetId());
        Assert.Equal([presetId], coordinator.GetCandidatePresetIds("sol"));
        Assert.Equal(modelName, options.ModelPresets[presetId].ModelName);
        Assert.Equal(expectedEffort, options.ModelPresets[presetId].GradeToReasoningEffort[grade]);
    }

    private static AiRoutingOptions CreateOptions() => new()
    {
        ModelPresets = new Dictionary<string, AiModelPresetOptions>(StringComparer.OrdinalIgnoreCase)
        {
            ["astra"] = new() { ModelName = "gpt-6-astra", ReasoningEfforts = ["high", "medium", "low"], GradeToReasoningEffort = new() { ["quality"] = "high", ["balanced"] = "medium", ["economy"] = "low" } },
            ["sol"] = new() { ModelName = "gpt-5.6-sol", ReasoningEfforts = ["high", "medium", "low"], GradeToReasoningEffort = new() { ["quality"] = "high", ["balanced"] = "medium", ["economy"] = "low" } },
            ["terra"] = new() { ModelName = "gpt-5.6-terra", ReasoningEfforts = ["max", "xhigh", "high"], GradeToReasoningEffort = new() { ["quality"] = "max", ["balanced"] = "xhigh", ["economy"] = "high" } },
            ["luna"] = new() { ModelName = "gpt-5.6-luna", ReasoningEfforts = ["max", "xhigh", "high"], GradeToReasoningEffort = new() { ["quality"] = "max", ["balanced"] = "xhigh", ["economy"] = "high" } },
            ["glm_flash"] = new() { ModelName = "glm-5.3-flash", ReasoningEfforts = ["max", "high", "low"], GradeToReasoningEffort = new() { ["quality"] = "max", ["balanced"] = "high", ["economy"] = "low" } },
            ["deepseek_flash"] = new() { ModelName = "deepseek-v4.1-flash", ReasoningEfforts = ["max", "high"], GradeToReasoningEffort = new() { ["quality"] = "max", ["balanced"] = "high", ["economy"] = "high" } },
        },
        ExecutionSlots = new Dictionary<string, AiExecutionSlotOptions>(StringComparer.OrdinalIgnoreCase)
        {
            ["mechanical_cleanup"] = new() { DefaultGrade = "economy" },
            ["bulk_prefilter"] = new() { DefaultGrade = "balanced" },
            ["engineering_review"] = new() { DefaultGrade = "balanced" },
            ["visual_review"] = new() { DefaultGrade = "quality" },
            ["high_risk_adjudication"] = new() { DefaultGrade = "quality" }
        },
        ModelFailover = new() { PreferredPresetOrder = ["astra", "sol", "terra", "luna", "glm_flash", "deepseek_flash"], FailureCooldownSeconds = 60 }
    };

    private static string RepoRoot
    {
        get
        {
            var current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current is not null)
            {
                if (File.Exists(Path.Combine(current.FullName, "apps", "api", "appsettings.json")))
                {
                    return current.FullName;
                }

                current = current.Parent;
            }

            throw new DirectoryNotFoundException("Could not locate the repository root for runtime configuration binding tests.");
        }
    }
}
