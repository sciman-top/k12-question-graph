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

        var noAuthorizedPurpose = normalized with
        {
            MayUseForKnowledgeExtraction = false,
            MayUseForExamPointExtraction = false,
            MayUseForTrendAnalysis = false,
        };
        Assert.False(SourceDocumentMetadataPolicy.ComputeExternalAiAllowed(noAuthorizedPurpose));
        Assert.Throws<ArgumentException>(() => SourceDocumentMetadataPolicy.ResolveExternalAiAllowed(
            noAuthorizedPurpose,
            currentlyAllowed: false,
            requestedAllowed: true));
        Assert.True(SourceDocumentMetadataPolicy.ResolveExternalAiAllowed(
            normalized,
            currentlyAllowed: false,
            requestedAllowed: true));
    }

    [Fact]
    public void Normalize_CurriculumStandard_DisablesExamPointAndTrendUseWithoutGrantingKnowledgeUse()
    {
        var normalized = SourceDocumentMetadataPolicy.Normalize(new SourceDocumentMetadata(
            SourceType: "curriculum-standard",
            SourceTitle: "Junior physics curriculum standard",
            Region: "China",
            Year: 2025,
            GradeOrScope: "junior-middle-school",
            EditionOrVersion: "2022-2025-revision",
            MaterialBatchKey: "curriculum-physics-junior-2022-2025-revision",
            OwnerScope: "school",
            LicenseOrPermission: "user_authorized_local_knowledge_extraction",
            SharingAllowed: false,
            ContainsStudentPii: false,
            AnonymizationStatus: "not-applicable",
            MayUseForKnowledgeExtraction: false,
            MayUseForExamPointExtraction: true,
            MayUseForTrendAnalysis: true));

        Assert.Equal("curriculum_standard", normalized.SourceType);
        Assert.Equal("curriculum_physics_junior_2022_2025_revision", normalized.MaterialBatchKey);
        Assert.False(normalized.MayUseForKnowledgeExtraction);
        Assert.False(normalized.MayUseForExamPointExtraction);
        Assert.False(normalized.MayUseForTrendAnalysis);
        Assert.False(SourceDocumentMetadataPolicy.ComputeExternalAiAllowed(normalized));

        var knowledgeAuthorized = SourceDocumentMetadataPolicy.Normalize(normalized with
        {
            MayUseForKnowledgeExtraction = true
        });
        Assert.True(knowledgeAuthorized.MayUseForKnowledgeExtraction);
        Assert.False(knowledgeAuthorized.MayUseForExamPointExtraction);
        Assert.False(knowledgeAuthorized.MayUseForTrendAnalysis);
    }

    [Fact]
    public void Normalize_BoundsValuesToThePersistedSchema()
    {
        var oversized = SourceDocumentMetadata.Defaults("paper.pdf") with
        {
            SourceType = new string('s', 80),
            SourceTitle = new string('t', 300),
            Region = new string('r', 150),
            GradeOrScope = new string('g', 150),
            EditionOrVersion = new string('e', 150),
            MaterialBatchKey = new string('b', 180),
            OwnerScope = new string('o', 80),
            LicenseOrPermission = new string('l', 300),
        };

        var normalized = SourceDocumentMetadataPolicy.Normalize(oversized);

        Assert.Equal(64, normalized.SourceType.Length);
        Assert.Equal(260, normalized.SourceTitle.Length);
        Assert.Equal(128, normalized.Region.Length);
        Assert.Equal(128, normalized.GradeOrScope.Length);
        Assert.Equal(128, normalized.EditionOrVersion.Length);
        Assert.Equal(160, normalized.MaterialBatchKey.Length);
        Assert.Equal(64, normalized.OwnerScope.Length);
        Assert.Equal(256, normalized.LicenseOrPermission.Length);
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
