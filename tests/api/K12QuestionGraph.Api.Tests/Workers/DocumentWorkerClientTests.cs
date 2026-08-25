using System.Diagnostics;
using K12QuestionGraph.Api.Configuration;
using K12QuestionGraph.Api.Workers;
using Microsoft.Extensions.Options;
using Xunit;

namespace K12QuestionGraph.Api.Tests;

public class DocumentWorkerClientTests : IDisposable
{
    private readonly string _contentRoot = WorkerTestHarness.CreateTempDirectory();

    public void Dispose()
    {
        WorkerTestHarness.DeleteDirectoryBestEffort(_contentRoot);
    }

    private static DocumentWorkerClient CreateClient(
        string scriptPath,
        int timeoutSeconds,
        string contentRoot,
        string fileStoreRoot) =>
        new(
            Options.Create(new PythonWorkerOptions
            {
                PythonExecutable = WorkerTestHarness.PythonExecutable.Value,
                DocumentWorkerScript = scriptPath,
                TimeoutSeconds = timeoutSeconds,
            }),
            Options.Create(new KqgPathsOptions { FileStoreRoot = fileStoreRoot }),
            new FakeHostEnvironment { ContentRootPath = contentRoot });

    [Fact]
    public async Task RunSmokeAsync_PassesThroughUtf8StdoutAndExitCode()
    {
        WorkerTestHarness.WriteStubScript(
            _contentRoot,
            "ok_stub.py",
            "import sys\nsys.stdout.write('{\"msg\": \"中文 ok\", \"jobId\": \"abc\"}')\nsys.stdout.flush()\n");

        var client = CreateClient("ok_stub.py", 30, _contentRoot, WorkerTestHarness.CreateTempDirectory());

        var result = await client.RunSmokeAsync(Guid.NewGuid(), "unused.docx", simulateFailure: false, CancellationToken.None);

        Assert.Equal(0, result.ExitCode);
        Assert.Contains("中文 ok", result.StandardOutput);
        Assert.Equal(string.Empty, result.StandardError);
    }

    [Fact]
    public async Task RunSmokeAsync_PassesThroughWorkerFailureExitCodeAndStderr()
    {
        WorkerTestHarness.WriteStubScript(
            _contentRoot,
            "fail_stub.py",
            "import sys\nsys.stderr.write('simulated boom 中文')\nsys.stderr.flush()\nsys.exit(2)\n");

        var client = CreateClient("fail_stub.py", 30, _contentRoot, WorkerTestHarness.CreateTempDirectory());

        var result = await client.RunSmokeAsync(Guid.NewGuid(), "unused.docx", simulateFailure: false, CancellationToken.None);

        Assert.Equal(2, result.ExitCode);
        Assert.Contains("simulated boom 中文", result.StandardError);
    }

    [Fact]
    public async Task RunSmokeAsync_TimesOutAndKillsWorker()
    {
        WorkerTestHarness.WriteStubScript(
            _contentRoot,
            "slow_stub.py",
            "import time\ntime.sleep(30)\n");

        var client = CreateClient("slow_stub.py", 2, _contentRoot, WorkerTestHarness.CreateTempDirectory());
        var stopwatch = Stopwatch.StartNew();

        var result = await client.RunSmokeAsync(Guid.NewGuid(), "unused.docx", simulateFailure: false, CancellationToken.None);

        stopwatch.Stop();
        Assert.Equal(-1, result.ExitCode);
        Assert.Equal("document worker timeout", result.StandardError);
        Assert.True(stopwatch.Elapsed < TimeSpan.FromSeconds(20),
            $"timeout kill took {stopwatch.Elapsed}; expected prompt termination after 2s budget");
    }

    [Fact]
    public async Task RunSmokeAsync_RunsRealWorkerAndReportsMissingInputFile()
    {
        var fileStoreRoot = WorkerTestHarness.CreateTempDirectory();
        var client = CreateClient(WorkerTestHarness.WorkerScript.Value, 60, _contentRoot, fileStoreRoot);

        var result = await client.RunSmokeAsync(Guid.NewGuid(), "missing.docx", simulateFailure: false, CancellationToken.None);

        Assert.Equal(3, result.ExitCode);
        Assert.Contains("input file missing", result.StandardError);
    }

    [Fact]
    public async Task RunSmokeAsync_RunsRealWorkerAndRejectsParentTraversalPath()
    {
        var fileStoreRoot = WorkerTestHarness.CreateTempDirectory();
        var client = CreateClient(WorkerTestHarness.WorkerScript.Value, 60, _contentRoot, fileStoreRoot);

        var result = await client.RunSmokeAsync(Guid.NewGuid(), "../escape.docx", simulateFailure: false, CancellationToken.None);

        Assert.Equal(4, result.ExitCode);
        Assert.Contains("invalid input path", result.StandardError);
    }

    [Fact]
    public async Task RunSmokeAsync_RunsRealWorkerAndRejectsOversizedInput()
    {
        var fileStoreRoot = WorkerTestHarness.CreateTempDirectory();
        Directory.CreateDirectory(Path.Combine(fileStoreRoot, "original"));
        var oversizedPath = Path.Combine(fileStoreRoot, "original", "oversized.docx");
        // NTFS 只扩展长度不落盘数据,128MB 上限检查看 stat().st_size,无需真实写入。
        using (var stream = new FileStream(oversizedPath, FileMode.CreateNew, FileAccess.Write))
        {
            stream.SetLength(128L * 1024 * 1024 + 1);
        }

        var client = CreateClient(WorkerTestHarness.WorkerScript.Value, 60, _contentRoot, fileStoreRoot);

        var result = await client.RunSmokeAsync(Guid.NewGuid(), "original/oversized.docx", simulateFailure: false, CancellationToken.None);

        Assert.Equal(5, result.ExitCode);
        Assert.Contains("exceeds", result.StandardError);
    }

    [Fact]
    public async Task RunSmokeAsync_PassesThroughNonJsonStdoutWithoutParsing()
    {
        WorkerTestHarness.WriteStubScript(
            _contentRoot,
            "garbage_stub.py",
            "import sys\nsys.stdout.write('not-json {{{ partial')\nsys.stdout.flush()\n");

        var client = CreateClient("garbage_stub.py", 30, _contentRoot, WorkerTestHarness.CreateTempDirectory());

        var result = await client.RunSmokeAsync(Guid.NewGuid(), "unused.docx", simulateFailure: false, CancellationToken.None);

        Assert.Equal(0, result.ExitCode);
        Assert.Equal("not-json {{{ partial", result.StandardOutput);
    }

    [Fact]
    public async Task RunSmokeAsync_PropagatesRequestCancellation()
    {
        WorkerTestHarness.WriteStubScript(
            _contentRoot,
            "slow_cancel_stub.py",
            "import time\ntime.sleep(30)\n");

        var client = CreateClient("slow_cancel_stub.py", 60, _contentRoot, WorkerTestHarness.CreateTempDirectory());
        using var cancellationTokenSource = new CancellationTokenSource();
        await cancellationTokenSource.CancelAsync();

        await Assert.ThrowsAsync<OperationCanceledException>(() =>
            client.RunSmokeAsync(Guid.NewGuid(), "unused.docx", simulateFailure: false, cancellationTokenSource.Token));
    }

    [Fact]
    public void PythonWorkerOptions_DefaultTimeoutCoversWorkerSubprocessBudget()
    {
        // worker 内部对 pdftotext/pdftoppm 每个子进程预算 60s;
        // 外层默认必须大于该值,否则扫描 PDF 的 OCR 链会被提前整树杀掉。
        Assert.True(new PythonWorkerOptions().TimeoutSeconds >= 60,
            $"default TimeoutSeconds {new PythonWorkerOptions().TimeoutSeconds} must cover the 60s per-subprocess budget inside worker.py");
    }
}
