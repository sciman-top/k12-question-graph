using System.Text.RegularExpressions;

namespace K12QuestionGraph.Api.FileStore;

public static class SourceMaterialClassifier
{
    private static readonly Regex YearRegex = new(@"(?<year>19\d{2}|20\d{2})", RegexOptions.Compiled);

    public static SourceDocumentMetadata Classify(SourceDocumentMetadata metadata, string originalFileName)
    {
        var fileName = Path.GetFileNameWithoutExtension(originalFileName);
        if (string.IsNullOrWhiteSpace(fileName))
        {
            return metadata;
        }

        if (LooksLikeGuangzhouZhongkao(fileName))
        {
            return ClassifyGuangzhouPhysicsZhongkao(metadata, fileName);
        }

        return metadata;
    }

    private static SourceDocumentMetadata ClassifyGuangzhouPhysicsZhongkao(SourceDocumentMetadata metadata, string fileName)
    {
        var year = ReadYear(fileName) ?? metadata.Year;
        var sourceType = ContainsAny(fileName, "年报", "质量分析", "分析报告")
            ? "exam_analysis_report"
            : "local_exam_paper";

        var mayUseForKnowledgeExtraction = sourceType == "local_exam_paper" || metadata.MayUseForKnowledgeExtraction;
        var mayUseForExamPointExtraction = sourceType is "local_exam_paper" or "exam_analysis_report" || metadata.MayUseForExamPointExtraction;
        var mayUseForTrendAnalysis = sourceType is "local_exam_paper" or "exam_analysis_report" || metadata.MayUseForTrendAnalysis;

        return metadata with
        {
            SourceType = IsUnknown(metadata.SourceType) ? sourceType : metadata.SourceType,
            SourceTitle = IsGenericTitle(metadata.SourceTitle, fileName) ? fileName.Trim() : metadata.SourceTitle,
            Region = IsBlank(metadata.Region) ? "guangzhou" : metadata.Region,
            Year = metadata.Year ?? year,
            GradeOrScope = IsBlank(metadata.GradeOrScope) ? "grade_9" : metadata.GradeOrScope,
            EditionOrVersion = IsBlank(metadata.EditionOrVersion) ? "guangzhou_physics_zhongkao" : metadata.EditionOrVersion,
            MaterialBatchKey = IsBlank(metadata.MaterialBatchKey) ? "guangzhou_physics_zhongkao" : metadata.MaterialBatchKey,
            OwnerScope = IsTeacherPrivate(metadata.OwnerScope) ? "school" : metadata.OwnerScope,
            LicenseOrPermission = IsUnknown(metadata.LicenseOrPermission) ? "pending_source_workbench_review" : metadata.LicenseOrPermission,
            SharingAllowed = metadata.SharingAllowed && !metadata.ContainsStudentPii,
            ContainsStudentPii = metadata.ContainsStudentPii,
            AnonymizationStatus = IsBlank(metadata.AnonymizationStatus) ? "not_applicable" : metadata.AnonymizationStatus,
            MayUseForKnowledgeExtraction = mayUseForKnowledgeExtraction,
            MayUseForExamPointExtraction = mayUseForExamPointExtraction,
            MayUseForTrendAnalysis = mayUseForTrendAnalysis
        };
    }

    private static bool LooksLikeGuangzhouZhongkao(string fileName)
    {
        return ContainsAny(fileName, "广州", "廣州") && ContainsAny(fileName, "中考");
    }

    private static int? ReadYear(string fileName)
    {
        var match = YearRegex.Match(fileName);
        return match.Success && int.TryParse(match.Groups["year"].Value, out var year) ? year : null;
    }

    private static bool ContainsAny(string value, params string[] needles)
    {
        return needles.Any(needle => value.Contains(needle, StringComparison.OrdinalIgnoreCase));
    }

    private static bool IsBlank(string value)
    {
        return string.IsNullOrWhiteSpace(value);
    }

    private static bool IsUnknown(string value)
    {
        return string.IsNullOrWhiteSpace(value) || string.Equals(value.Trim(), "unknown", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsTeacherPrivate(string value)
    {
        return string.IsNullOrWhiteSpace(value) || string.Equals(value.Trim(), "teacher_private", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsGenericTitle(string value, string fileNameWithoutExtension)
    {
        if (string.IsNullOrWhiteSpace(value) || string.Equals(value.Trim(), "untitled source", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return string.Equals(Path.GetFileNameWithoutExtension(value.Trim()), fileNameWithoutExtension, StringComparison.OrdinalIgnoreCase);
    }
}
