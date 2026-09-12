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

        coordinator.RecordAvailabilityFailure("astra", statusCode);

        Assert.Equal(opensCooldown ? "sol" : "astra", coordinator.SelectActivePresetId());
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
}
