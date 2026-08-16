using System.Diagnostics;
using System.Text;
using K12QuestionGraph.Api.Configuration;
using K12QuestionGraph.Api.Infrastructure.Workers;
using Microsoft.Extensions.Options;

namespace K12QuestionGraph.Api.Workers;

public sealed class DocumentWorkerClient(
    IOptions<PythonWorkerOptions> options,
    IOptions<KqgPathsOptions> pathsOptions,
    IHostEnvironment environment) : IDocumentWorkerClient
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

        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
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

        return new DocumentWorkerResult(process.ExitCode, stdout.Trim(), stderr.Trim());
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
