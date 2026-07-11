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
}
