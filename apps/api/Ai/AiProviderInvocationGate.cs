using System.Collections.Concurrent;

namespace K12QuestionGraph.Api.Ai;

/// <summary>
/// Process-local concurrency gate for real Cockpit requests. The current
/// product exposes real calls only through administrator smoke; a future
/// business adapter must use this same module before issuing /responses.
/// </summary>
public sealed class AiProviderInvocationGate
{
    private readonly ConcurrentDictionary<int, SemaphoreSlim> semaphores = new();

    public async Task<IDisposable> EnterAsync(int configuredMaxConcurrency, CancellationToken cancellationToken)
    {
        var limit = Math.Clamp(configuredMaxConcurrency, 1, 8);
        var semaphore = semaphores.GetOrAdd(limit, static value => new SemaphoreSlim(value, value));
        await semaphore.WaitAsync(cancellationToken);
        return new Releaser(semaphore);
    }

    private sealed class Releaser(SemaphoreSlim semaphore) : IDisposable
    {
        private SemaphoreSlim? semaphore = semaphore;

        public void Dispose()
        {
            Interlocked.Exchange(ref semaphore, null)?.Release();
        }
    }
}
