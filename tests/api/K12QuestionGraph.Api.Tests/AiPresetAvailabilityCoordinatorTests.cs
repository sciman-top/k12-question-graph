using K12QuestionGraph.Api.Ai;
using Microsoft.Extensions.Options;

namespace K12QuestionGraph.Api.Tests;

public sealed class AiPresetAvailabilityCoordinatorTests
{
    [Fact]
    public void TracksActivePresetAndUsesRequiredRecoveryOrder()
    {
        var coordinator = new AiPresetAvailabilityCoordinator(Options.Create(CreateOptions()));

        Assert.Equal("sol", coordinator.SelectActivePresetId());
        coordinator.RecordExecutionSuccess("terra");
        Assert.Equal("terra", coordinator.SelectActivePresetId());
        Assert.Equal(["terra", "sol", "luna"], coordinator.GetCandidatePresetIds("terra"));

        coordinator.RecordAvailabilityFailure("terra", 503);
        Assert.Equal("sol", coordinator.SelectActivePresetId());
        coordinator.RecordAvailabilityFailure("sol", 503);
        Assert.Equal("luna", coordinator.SelectActivePresetId());
        Assert.Equal(["luna", "sol", "terra"], coordinator.GetCandidatePresetIds("luna"));
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

    private static AiRoutingOptions CreateOptions() => new()
    {
        ModelPresets = new Dictionary<string, AiModelPresetOptions>(StringComparer.OrdinalIgnoreCase)
        {
            ["sol"] = new() { ModelName = "gpt-5.6-sol", ReasoningEfforts = ["xhigh", "medium", "low"], GradeToReasoningEffort = new() { ["quality"] = "xhigh", ["balanced"] = "medium", ["economy"] = "low" } },
            ["terra"] = new() { ModelName = "gpt-5.6-terra", ReasoningEfforts = ["xhigh", "high", "medium"], GradeToReasoningEffort = new() { ["quality"] = "xhigh", ["balanced"] = "high", ["economy"] = "medium" } },
            ["luna"] = new() { ModelName = "gpt-5.6-luna", ReasoningEfforts = ["xhigh", "high", "medium"], GradeToReasoningEffort = new() { ["quality"] = "xhigh", ["balanced"] = "high", ["economy"] = "medium" } }
        },
        ExecutionSlots = new Dictionary<string, AiExecutionSlotOptions>(StringComparer.OrdinalIgnoreCase)
        {
            ["mechanical_cleanup"] = new() { DefaultGrade = "economy" },
            ["bulk_prefilter"] = new() { DefaultGrade = "balanced" },
            ["engineering_review"] = new() { DefaultGrade = "balanced" },
            ["visual_review"] = new() { DefaultGrade = "quality" },
            ["high_risk_adjudication"] = new() { DefaultGrade = "quality" }
        },
        ModelFailover = new() { PreferredPresetOrder = ["sol", "terra", "luna"], FailureCooldownSeconds = 60 }
    };
}
