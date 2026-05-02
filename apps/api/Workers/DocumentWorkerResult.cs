namespace K12QuestionGraph.Api.Workers;

public sealed record DocumentWorkerResult(int ExitCode, string StandardOutput, string StandardError);
