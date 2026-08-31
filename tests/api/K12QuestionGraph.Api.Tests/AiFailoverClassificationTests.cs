using K12QuestionGraph.Api.Ai;
using Microsoft.Extensions.Options;

namespace K12QuestionGraph.Api.Tests;

public sealed class AiFailoverClassificationTests
{
    [Theory]
    [InlineData(0, true)]
    [InlineData(404, true)]
    [InlineData(408, true)]
    [InlineData(429, true)]
    [InlineData(500, true)]
    [InlineData(400, false)]
    [InlineData(401, false)]
    [InlineData(403, false)]
    public void AvailabilityFailureClassificationKeepsBusinessErrorsOnTheCurrentPreset(int statusCode, bool opensCooldown)
    {
        var coordinator = new AiPresetAvailabilityCoordinator(Options.Create(CreateOptions()));

        coordinator.RecordAvailabilityFailure("sol", statusCode);

        Assert.Equal(opensCooldown ? "terra" : "sol", coordinator.SelectActivePresetId());
    }

    private static AiRoutingOptions CreateOptions() => new()
    {
        ModelPresets = new Dictionary<string, AiModelPresetOptions>(StringComparer.OrdinalIgnoreCase)
        {
            ["sol"] = new() { ModelName = "gpt-5.6-sol", ReasoningEfforts = ["high", "medium", "low"], GradeToReasoningEffort = new() { ["quality"] = "high", ["balanced"] = "medium", ["economy"] = "low" } },
            ["terra"] = new() { ModelName = "gpt-5.6-terra", ReasoningEfforts = ["max", "xhigh", "high"], GradeToReasoningEffort = new() { ["quality"] = "max", ["balanced"] = "xhigh", ["economy"] = "high" } },
            ["luna"] = new() { ModelName = "gpt-5.6-luna", ReasoningEfforts = ["max", "xhigh", "high"], GradeToReasoningEffort = new() { ["quality"] = "max", ["balanced"] = "xhigh", ["economy"] = "high" } }
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
