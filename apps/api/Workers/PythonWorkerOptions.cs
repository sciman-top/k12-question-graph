namespace K12QuestionGraph.Api.Workers;

public sealed record PythonWorkerOptions
{
    public string PythonExecutable { get; init; } = "python";

    public string DocumentWorkerScript { get; init; } = @"workers\document\worker.py";

    // 必须大于 worker 内部单个外部子进程超时(60s)并覆盖多页扫描 PDF 的逐页 OCR 耗时;
    // 与 apps/web worker-smoke 请求超时保持同一下限。
    public int TimeoutSeconds { get; init; } = 300;

    // stdout/stderr 单流字节上限:超限即终止整个 worker 进程树并标记
    // worker_output_oversized,防止病态输出在读取阶段占满 API 内存。
    public long MaxOutputBytes { get; init; } = 16L * 1024 * 1024;
}
