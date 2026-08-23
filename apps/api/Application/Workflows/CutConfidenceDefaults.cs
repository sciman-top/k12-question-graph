namespace K12QuestionGraph.Api.Application.Workflows;

/// <summary>
/// 切题/导入置信度阈值的 C# 单一来源。workers/document/worker.py 保有镜像常量
/// (PDFTOTEXT_STEM_CONFIDENCE / PDFTOTEXT_OTHER_CONFIDENCE / OCR_TAKEOVER_CONFIDENCE):
/// worker 输出 takeoverRequired 时以 worker 的 OCR 阈为准,这里仅在 worker 未提供该标志时回退。
/// 两侧数值若要统一,必须先定义统一业务语义,不得只改一处数字。
/// </summary>
public static class CutConfidenceDefaults
{
    public const decimal SeedStemConfidence = 0.88m;

    public const decimal SeedOtherConfidence = 0.78m;

    public const decimal FallbackTakeoverThreshold = 0.85m;

    public const decimal LowConfidenceReviewThreshold = 0.85m;
}
