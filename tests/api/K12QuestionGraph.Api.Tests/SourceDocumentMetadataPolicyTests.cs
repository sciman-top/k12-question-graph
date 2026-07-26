using K12QuestionGraph.Api.FileStore;

namespace K12QuestionGraph.Api.Tests;

public class SourceDocumentMetadataPolicyTests
{
    [Fact]
    public void Normalize_DisablesSharing_ForUnknownOrUnsafePiiSources()
    {
        var metadata = new SourceDocumentMetadata(
            SourceType: " Unknown ",
            SourceTitle: "  ",
            Region: "  ",
            Year: null,
            GradeOrScope: "  ",
            EditionOrVersion: "  ",
            MaterialBatchKey: "  ",
            OwnerScope: " Teacher-Private ",
            LicenseOrPermission: "  ",
            SharingAllowed: true,
            ContainsStudentPii: true,
            AnonymizationStatus: "none",
            MayUseForKnowledgeExtraction: false,
            MayUseForExamPointExtraction: false,
            MayUseForTrendAnalysis: false);

        var normalized = SourceDocumentMetadataPolicy.Normalize(metadata);

        Assert.Equal("unknown", normalized.SourceType);
        Assert.Equal("untitled source", normalized.SourceTitle);
        Assert.Equal("teacher_private", normalized.OwnerScope);
        Assert.False(normalized.SharingAllowed);
        Assert.Equal("none", normalized.AnonymizationStatus);
    }

    [Fact]
    public void ComputeExternalAiAllowed_RequiresAuthorizedShareableNonPiiSource()
    {
        var normalized = SourceDocumentMetadataPolicy.Normalize(new SourceDocumentMetadata(
            SourceType: "school_paper",
            SourceTitle: "Physics paper",
            Region: "guangzhou",
            Year: 2025,
            GradeOrScope: "grade_9",
            EditionOrVersion: "local",
            MaterialBatchKey: "gzh",
            OwnerScope: "school",
            LicenseOrPermission: "internal_authorized",
            SharingAllowed: true,
            ContainsStudentPii: false,
            AnonymizationStatus: "not_applicable",
            MayUseForKnowledgeExtraction: true,
            MayUseForExamPointExtraction: true,
            MayUseForTrendAnalysis: true));

        Assert.True(SourceDocumentMetadataPolicy.ComputeExternalAiAllowed(normalized));

        var pendingReview = normalized with { LicenseOrPermission = "pending_source_workbench_review" };
        Assert.False(SourceDocumentMetadataPolicy.ComputeExternalAiAllowed(pendingReview));
    }

    [Theory]
    [InlineData("2021广州中考-参考答案.pdf", "answer_or_solution")]
    [InlineData("2024广州中考（解析版）.pdf", "answer_or_solution")]
    [InlineData("2020广州中考（含答案）.pdf", "local_exam_paper")]
    [InlineData("2025广州中考年报.pdf", "exam_analysis_report")]
    [InlineData("2025广州中考.pdf", "local_exam_paper")]
    public void Classify_RecognizesFlatGuangzhouSourceNames(string fileName, string expectedSourceType)
    {
        var classified = SourceMaterialClassifier.Classify(SourceDocumentMetadata.Defaults(fileName), fileName);

        Assert.Equal(expectedSourceType, classified.SourceType);
        Assert.Equal(int.Parse(fileName[..4]), classified.Year);
        Assert.Equal("guangzhou", classified.Region);
    }
}
