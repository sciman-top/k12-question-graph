using Microsoft.Extensions.Options;

namespace K12QuestionGraph.Api.Ai;

/// <summary>
/// Owns the active single-model preset and its short availability cooldown.
/// Callers only select a preset chain and report provider outcomes; they never
/// keep their own model-family fallback state.
/// </summary>
public sealed class AiPresetAvailabilityCoordinator(IOptions<AiRoutingOptions> options, TimeProvider? timeProvider = null)
{
    private static readonly IReadOnlyDictionary<string, PresetContract> RequiredPresets =
        new Dictionary<string, PresetContract>(StringComparer.OrdinalIgnoreCase)
        {
            ["astra"] = new("gpt-6-astra", ["high", "medium", "low"], new() { ["quality"] = "high", ["balanced"] = "medium", ["economy"] = "low" }),
            ["sol"] = new("gpt-5.6-sol", ["high", "medium", "low"], new() { ["quality"] = "high", ["balanced"] = "medium", ["economy"] = "low" }),
            ["terra"] = new("gpt-5.6-terra", ["max", "xhigh", "high"], new() { ["quality"] = "max", ["balanced"] = "xhigh", ["economy"] = "high" }),
            ["luna"] = new("gpt-5.6-luna", ["max", "xhigh", "high"], new() { ["quality"] = "max", ["balanced"] = "xhigh", ["economy"] = "high" }),
            ["glm_flash"] = new("glm-5.3-flash", ["max", "high", "low"], new() { ["quality"] = "max", ["balanced"] = "high", ["economy"] = "low" }),
            ["deepseek_flash"] = new("deepseek-v4.1-flash", ["max", "high"], new() { ["quality"] = "max", ["balanced"] = "high", ["economy"] = "high" })
        };
    private static readonly HashSet<string> RequiredExecutionSlots =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "mechanical_cleanup",
            "bulk_prefilter",
            "engineering_review",
            "visual_review",
            "high_risk_adjudication"
        };

    private readonly AiRoutingOptions routing = options.Value;
    private readonly TimeProvider clock = timeProvider ?? TimeProvider.System;
    private readonly object gate = new();
    private readonly Dictionary<string, DateTimeOffset> cooldowns = new(StringComparer.OrdinalIgnoreCase);
    private string? activePresetId;

    public string SelectActivePresetId()
    {
        lock (gate)
        {
            EnsureValidConfiguration();
            var pinnedPresetId = ResolvePinnedPresetId();
            if (pinnedPresetId is not null)
            {
                return pinnedPresetId;
            }

            var anchor = IsKnownPreset(activePresetId)
                ? activePresetId!
                : routing.ModelFailover.PreferredPresetOrder.First();
            var now = clock.GetUtcNow();
            return GetCandidatePresetIdsCore(anchor)
                .FirstOrDefault(id => !cooldowns.TryGetValue(id, out var cooldownUntil) || cooldownUntil <= now)
                ?? anchor;
        }
    }

    public IReadOnlyList<string> GetCandidatePresetIds(string requestedPresetId)
    {
        lock (gate)
        {
            EnsureValidConfiguration();
            var pinnedPresetId = ResolvePinnedPresetId();
            if (pinnedPresetId is not null)
            {
                return [pinnedPresetId];
            }

            if (!IsKnownPreset(requestedPresetId))
            {
                throw new AiRouteException("unknown_model_preset");
            }

            return GetCandidatePresetIdsCore(requestedPresetId.Trim());
        }
    }

    public void RecordExecutionSuccess(string presetId)
    {
        lock (gate)
        {
            if (!IsKnownPreset(presetId))
            {
                return;
            }

            activePresetId = presetId.Trim();
            cooldowns.Remove(activePresetId);
        }
    }

    public void RecordAvailabilityFailure(string presetId, int httpStatusCode)
    {
        if (!ShouldOpenCooldown(httpStatusCode))
        {
            return;
        }

        lock (gate)
        {
            if (!IsKnownPreset(presetId))
            {
                return;
            }

            cooldowns[presetId.Trim()] = clock.GetUtcNow().AddSeconds(routing.ModelFailover.FailureCooldownSeconds);
        }
    }

    public string? GetPinnedPresetId()
    {
        lock (gate)
        {
            EnsureValidConfiguration();
            return ResolvePinnedPresetId();
        }
    }

    private IReadOnlyList<string> GetCandidatePresetIdsCore(string anchor)
    {
        return new[] { anchor }
            .Concat(routing.ModelFailover.PreferredPresetOrder)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private bool IsKnownPreset(string? presetId)
    {
        return !string.IsNullOrWhiteSpace(presetId)
            && routing.ModelPresets.ContainsKey(presetId.Trim());
    }

    private void EnsureValidConfiguration()
    {
        if (routing.ModelPresets.Count != RequiredPresets.Count
            || routing.ModelFailover.PreferredPresetOrder.Length != RequiredPresets.Count
            || !routing.ModelFailover.PreferredPresetOrder.SequenceEqual(RequiredPresets.Keys, StringComparer.OrdinalIgnoreCase))
        {
            throw new AiRouteException("invalid_single_model_preset_configuration");
        }

        foreach (var (presetId, contract) in RequiredPresets)
        {
            if (!routing.ModelPresets.TryGetValue(presetId, out var configured)
                || !string.Equals(configured.ModelName, contract.ModelName, StringComparison.OrdinalIgnoreCase)
                || !configured.ReasoningEfforts.OrderBy(value => value, StringComparer.OrdinalIgnoreCase)
                    .SequenceEqual(contract.ReasoningEfforts.OrderBy(value => value, StringComparer.OrdinalIgnoreCase), StringComparer.OrdinalIgnoreCase)
                || !configured.GradeToReasoningEffort.OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
                    .SequenceEqual(contract.GradeToReasoningEffort.OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)))
            {
                throw new AiRouteException("invalid_single_model_preset_configuration");
            }
        }

        if (!string.IsNullOrWhiteSpace(routing.ModelFailover.PinnedPresetId)
            && !IsKnownPreset(routing.ModelFailover.PinnedPresetId))
        {
            throw new AiRouteException("invalid_single_model_preset_configuration");
        }

        if (routing.ModelFailover.FailureCooldownSeconds is < 1 or > 300
            || routing.ModelFailover.RecoveryProbeIntervalSeconds is < 60 or > 3600
            || routing.ModelFailover.RecoveryProbeFailureBackoffSeconds is < 60 or > 86400
            || routing.ModelFailover.RecoveryProbeSuccessesRequired is < 1 or > 3
            || routing.ExecutionSlots.Count != RequiredExecutionSlots.Count
            || !routing.ExecutionSlots.Keys.ToHashSet(StringComparer.OrdinalIgnoreCase).SetEquals(RequiredExecutionSlots)
            || routing.ExecutionSlots.Values.Any(slot => slot.DefaultGrade is not ("economy" or "balanced" or "quality")))
        {
            throw new AiRouteException("invalid_execution_slot_configuration");
        }
    }

    private string? ResolvePinnedPresetId()
    {
        if (string.IsNullOrWhiteSpace(routing.ModelFailover.PinnedPresetId))
        {
            return null;
        }

        return routing.ModelPresets.Keys.First(id =>
            string.Equals(id, routing.ModelFailover.PinnedPresetId.Trim(), StringComparison.OrdinalIgnoreCase));
    }

    private static bool ShouldOpenCooldown(int httpStatusCode)
    {
        return httpStatusCode == 0
            || httpStatusCode == StatusCodes.Status408RequestTimeout
            || httpStatusCode == StatusCodes.Status429TooManyRequests
            || httpStatusCode == StatusCodes.Status404NotFound
            || httpStatusCode >= StatusCodes.Status500InternalServerError;
    }

    private sealed record PresetContract(
        string ModelName,
        string[] ReasoningEfforts,
        Dictionary<string, string> GradeToReasoningEffort);
}
