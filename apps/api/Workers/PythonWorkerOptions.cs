namespace K12QuestionGraph.Api.Workers;

public sealed record PythonWorkerOptions
{
    public string PythonExecutable { get; init; } = "python";

    public string DocumentWorkerScript { get; init; } = @"workers\document\worker.py";

    public int TimeoutSeconds { get; init; } = 20;
}
