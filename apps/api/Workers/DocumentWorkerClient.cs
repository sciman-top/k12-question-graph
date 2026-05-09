using System.Diagnostics;
using System.Text;
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

        var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
        var waitForExit = process.WaitForExitAsync(cancellationToken);
        var timeout = TimeSpan.FromSeconds(Math.Max(1, workerOptions.TimeoutSeconds));
        var completed = await Task.WhenAny(waitForExit, Task.Delay(timeout, cancellationToken));
        if (completed != waitForExit)
        {
            process.Kill(entireProcessTree: true);
            return new DocumentWorkerResult(-1, string.Empty, "document worker timeout");
        }

        var stdout = await stdoutTask;
        var stderr = await stderrTask;

        return new DocumentWorkerResult(process.ExitCode, stdout.Trim(), stderr.Trim());
    }
}
