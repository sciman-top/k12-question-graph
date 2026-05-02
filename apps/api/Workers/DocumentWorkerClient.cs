using System.Diagnostics;
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
        var repoRoot = Path.GetFullPath(Path.Combine(environment.ContentRootPath, "..", ".."));
        var scriptPath = Path.GetFullPath(Path.Combine(repoRoot, workerOptions.DocumentWorkerScript));

        var startInfo = new ProcessStartInfo
        {
            FileName = workerOptions.PythonExecutable,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            WorkingDirectory = repoRoot
        };
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

        var waitForExit = process.WaitForExitAsync(cancellationToken);
        var timeout = TimeSpan.FromSeconds(Math.Max(1, workerOptions.TimeoutSeconds));
        var completed = await Task.WhenAny(waitForExit, Task.Delay(timeout, cancellationToken));
        if (completed != waitForExit)
        {
            process.Kill(entireProcessTree: true);
            return new DocumentWorkerResult(-1, string.Empty, "document worker timeout");
        }

        var stdout = await process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderr = await process.StandardError.ReadToEndAsync(cancellationToken);

        return new DocumentWorkerResult(process.ExitCode, stdout.Trim(), stderr.Trim());
    }
}
