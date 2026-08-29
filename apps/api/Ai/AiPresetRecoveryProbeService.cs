using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace K12QuestionGraph.Api.Ai;

/// <summary>
/// Low-priority recovery loop. It never marks the active preset unhealthy: a
/// failed recovery check only delays the next check for the higher-priority
/// preset, while ordinary requests continue on the active preset.
/// </summary>
public sealed class AiPresetRecoveryProbeService(
    IOptions<AiRoutingOptions> options,
    AiModelRouter modelRouter,
    OpenAiCompatibleSmokeTestService smokeTestService,
    ILogger<AiPresetRecoveryProbeService> logger) : BackgroundService
{
    private readonly AiRoutingOptions routing = options.Value;
    private readonly Dictionary<string, int> consecutiveSuccesses = new(StringComparer.OrdinalIgnoreCase);
    private DateTimeOffset nextProbeAtUtc = DateTimeOffset.MinValue;
    private string? observedActivePresetId;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await ProbeOnceAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "AI preset recovery probe failed before a provider result was available.");
            }

            await Task.Delay(TimeSpan.FromSeconds(routing.ModelFailover.RecoveryProbeIntervalSeconds), stoppingToken);
        }
    }

    internal async Task<AiPresetRecoveryProbeRunResult> ProbeOnceAsync(CancellationToken cancellationToken)
    {
        if (!routing.ModelFailover.RecoveryProbeEnabled)
        {
            return new("disabled", string.Empty, null, false, "恢复探测已由运行时配置禁用。");
        }

        if (modelRouter.GetPinnedPresetId() is not null)
        {
            consecutiveSuccesses.Clear();
            return new("pinned", string.Empty, null, false, "临时 preset pin 生效，恢复探测不跨模型族切换。");
        }

        var activePresetId = modelRouter.SelectActivePresetId();
        if (!string.Equals(observedActivePresetId, activePresetId, StringComparison.OrdinalIgnoreCase))
        {
            observedActivePresetId = activePresetId;
            consecutiveSuccesses.Clear();
            nextProbeAtUtc = DateTimeOffset.MinValue;
        }

        var recoveryCandidates = GetHigherPriorityPresetIds(activePresetId);
        if (recoveryCandidates.Count == 0)
        {
            return new("primary_active", activePresetId, null, false, "当前已是首选 preset，无需恢复探测。");
        }

        var now = DateTimeOffset.UtcNow;
        if (now < nextProbeAtUtc)
        {
            return new("backoff", activePresetId, null, false, "恢复探测处于退避窗口。");
        }

        foreach (var candidatePresetId in recoveryCandidates)
        {
            var probe = await smokeTestService.ProbePresetAsync(candidatePresetId, cancellationToken);
            if (probe.Skipped)
            {
                return new("skipped", activePresetId, candidatePresetId, false, probe.Message);
            }

            if (!probe.Passed || probe.Candidate is null)
            {
                consecutiveSuccesses.Remove(candidatePresetId);
                logger.LogInformation(
                    "AI recovery probe kept {ActivePreset} active because {CandidatePreset} failed with HTTP {StatusCode}.",
                    activePresetId,
                    candidatePresetId,
                    probe.HttpStatusCode);
                continue;
            }

            var successCount = consecutiveSuccesses.TryGetValue(candidatePresetId, out var previousCount)
                ? previousCount + 1
                : 1;
            consecutiveSuccesses[candidatePresetId] = successCount;
            if (successCount < routing.ModelFailover.RecoveryProbeSuccessesRequired)
            {
                logger.LogInformation(
                    "AI recovery probe confirmed {CandidatePreset} once ({SuccessCount}/{RequiredSuccesses}); keeping {ActivePreset} active until the stability threshold is met.",
                    candidatePresetId,
                    successCount,
                    routing.ModelFailover.RecoveryProbeSuccessesRequired,
                    activePresetId);
                return new("stability_wait", activePresetId, candidatePresetId, false, "恢复候选尚未达到连续成功阈值。");
            }

            modelRouter.RecordProviderExecutionSuccess(probe.Candidate);
            consecutiveSuccesses.Clear();
            nextProbeAtUtc = now.AddSeconds(routing.ModelFailover.RecoveryProbeIntervalSeconds);
            logger.LogInformation(
                "AI recovery probe promoted {CandidatePreset} after {SuccessCount} consecutive successful checks.",
                candidatePresetId,
                successCount);
            return new("promoted", activePresetId, candidatePresetId, true, "恢复探测已提升高优先级 preset。");
        }

        nextProbeAtUtc = now.AddSeconds(routing.ModelFailover.RecoveryProbeFailureBackoffSeconds);
        return new("failed", activePresetId, recoveryCandidates[^1], false, "所有高优先级恢复候选均未通过，当前 preset 保持不变。");
    }

    private IReadOnlyList<string> GetHigherPriorityPresetIds(string activePresetId)
    {
        var activeIndex = Array.FindIndex(
            routing.ModelFailover.PreferredPresetOrder,
            presetId => string.Equals(presetId, activePresetId, StringComparison.OrdinalIgnoreCase));
        return activeIndex <= 0
            ? []
            : routing.ModelFailover.PreferredPresetOrder[..activeIndex];
    }
}

internal sealed record AiPresetRecoveryProbeRunResult(
    string Status,
    string ActivePresetId,
    string? TargetPresetId,
    bool Promoted,
    string Message);
