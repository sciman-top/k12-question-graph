using System.Diagnostics;
using System.Text;
using K12QuestionGraph.Api.Configuration;
using K12QuestionGraph.Api.Infrastructure.Workers;
using Microsoft.Extensions.Options;

namespace K12QuestionGraph.Api.Workers;

public sealed class DocumentWorkerClient(
    IOptions<PythonWorkerOptions> options,
    IOptions<KqgPathsOptions> pathsOptions,
    IHostEnvironment environment)
{
    public async Task<DocumentWorkerResult> RunSmokeAsync(
        Guid jobId,
        string relativePath,
        bool simulateFailure,
        CancellationToken cancellationToken)
    {
        var workerOptions = options.Value;
        var contentRoot = Path.GetFullPath(environment.ContentRootPath);
        var scriptPath = WorkerPathHelpers.ResolveWorkerScriptPath(contentRoot, workerOptions.DocumentWorkerScript);

        var startInfo = new ProcessStartInfo
        {
            FileName = workerOptions.PythonExecutable,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            StandardErrorEncoding = Encoding.UTF8,
            StandardOutputEncoding = Encoding.UTF8,
            UseShellExecute = false,
            WorkingDirectory = contentRoot
        };
        startInfo.Environment["PYTHONIOENCODING"] = "utf-8";
        startInfo.ArgumentList.Add(scriptPath);
        startInfo.ArgumentList.Add("--job-id");
        startInfo.ArgumentList.Add(jobId.ToString());
        startInfo.ArgumentList.Add("--relative-path");
        startInfo.ArgumentList.Add(relativePath);
        startInfo.ArgumentList.Add("--file-root");
        startInfo.ArgumentList.Add(pathsOptions.Value.FileStoreRoot);
        if (simulateFailure)
        {
            startInfo.ArgumentList.Add("--simulate-failure");
        }

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Failed to start document worker.");

        var maxOutputBytes = Math.Max(1, workerOptions.MaxOutputBytes);
        // 双流必须并发有界读取:任一管道写满而无人读取会死锁,无界读取则可能
        // 在超时/杀进程之前占满内存。截断看门狗在读满上限时立即终止进程树,
        // 否则被截断的进程会阻塞在无人读取的管道写上,拖到总超时才结束。
        var stdoutTask = ReadStreamBoundedAsync(process.StandardOutput.BaseStream, maxOutputBytes);
        var stderrTask = ReadStreamBoundedAsync(process.StandardError.BaseStream, maxOutputBytes);
        _ = MonitorTruncationAsync(stdoutTask, process);
        _ = MonitorTruncationAsync(stderrTask, process);
        var timeout = TimeSpan.FromSeconds(Math.Max(1, workerOptions.TimeoutSeconds));
        using var timeoutSource = new CancellationTokenSource(timeout);
        using var linkedSource = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            timeoutSource.Token);

        try
        {
            await process.WaitForExitAsync(linkedSource.Token);
        }
        catch (OperationCanceledException) when (timeoutSource.IsCancellationRequested && !cancellationToken.IsCancellationRequested)
        {
            await TerminateAsync(process);
            await Task.WhenAll(stdoutTask, stderrTask);
            return new DocumentWorkerResult(-1, string.Empty, "document worker timeout");
        }
        catch
        {
            await TerminateAsync(process);
            await Task.WhenAll(stdoutTask, stderrTask);
            throw;
        }

        var stdout = await stdoutTask;
        var stderr = await stderrTask;
        if (stdout.Truncated || stderr.Truncated)
        {
            // 进程可能仍在写另一条流:超限同样按整树终止,不留活进程。
            await TerminateAsync(process);
            return new DocumentWorkerResult(
                -1,
                stdout.Truncated ? stdout.Text : stdout.Text.Trim(),
                $"document worker output exceeded the {maxOutputBytes} byte limit",
                OutputTruncated: true);
        }

        return new DocumentWorkerResult(process.ExitCode, stdout.Text.Trim(), stderr.Text.Trim());
    }

    private static async Task MonitorTruncationAsync(
        Task<(string Text, bool Truncated)> drainTask,
        Process process)
    {
        var result = await drainTask;
        if (!result.Truncated)
        {
            return;
        }

        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch (InvalidOperationException)
        {
            // 进程已退出、已被超时路径终止或已释放;截断语义仍由主流程标记。
            // ObjectDisposedException 属其子类,一并覆盖。
        }
    }

    private static async Task<(string Text, bool Truncated)> ReadStreamBoundedAsync(
        Stream stream,
        long maxBytes)
    {
        var buffer = GC.AllocateUninitializedArray<byte>(81920);
        using var memory = new MemoryStream();
        while (true)
        {
            var bytesRead = await stream.ReadAsync(buffer, CancellationToken.None);
            if (bytesRead == 0)
            {
                break;
            }

            if (memory.Length + bytesRead > maxBytes)
            {
                return (Encoding.UTF8.GetString(memory.ToArray()), Truncated: true);
            }

            memory.Write(buffer, 0, bytesRead);
        }

        return (Encoding.UTF8.GetString(memory.ToArray()), Truncated: false);
    }

    private static async Task TerminateAsync(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch (InvalidOperationException)
        {
            return;
        }

        try
        {
            await process.WaitForExitAsync(CancellationToken.None);
        }
        catch (InvalidOperationException)
        {
            // The process exited between the state check and the wait.
        }
    }
}
