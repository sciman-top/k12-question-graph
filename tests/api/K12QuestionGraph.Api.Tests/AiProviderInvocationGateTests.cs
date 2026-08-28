using K12QuestionGraph.Api.Ai;

namespace K12QuestionGraph.Api.Tests;

public sealed class AiProviderInvocationGateTests
{
    [Fact]
    public async Task RespectsConfiguredConcurrencyUntilTheExistingRequestCompletes()
    {
        var gate = new AiProviderInvocationGate();
        using var first = await gate.EnterAsync(1, CancellationToken.None);
        var enteredSecond = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var second = Task.Run(async () =>
        {
            using var permit = await gate.EnterAsync(1, CancellationToken.None);
            enteredSecond.SetResult();
        });

        await Task.Delay(50);
        Assert.False(enteredSecond.Task.IsCompleted);

        first.Dispose();
        await enteredSecond.Task.WaitAsync(TimeSpan.FromSeconds(2));
        await second;
    }
}
