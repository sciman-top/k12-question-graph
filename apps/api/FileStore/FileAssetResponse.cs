namespace K12QuestionGraph.Api.FileStore;

public sealed record FileAssetResponse(
    Guid Id,
    string OriginalFileName,
    string RelativePath,
    string StorageScope,
    string ContentType,
    string Sha256,
    long SizeBytes,
    bool IsDuplicate,
    Guid? DuplicateOfFileAssetId,
    SourceDocumentResponse? SourceDocument);

public sealed record SourceDocumentResponse(
    Guid Id,
    Guid FileAssetId,
    string SourceType,
    string SourceTitle,
    string Region,
    int? Year,
    string GradeOrScope,
    string EditionOrVersion,
    string MaterialBatchKey,
    string OwnerScope,
    string LicenseOrPermission,
    bool SharingAllowed,
    bool ContainsStudentPii,
    string AnonymizationStatus,
    bool ExternalAiAllowed,
    bool MayUseForKnowledgeExtraction,
    bool MayUseForExamPointExtraction,
    bool MayUseForTrendAnalysis);

public sealed record SourceDocumentMetadata(
    string SourceType,
    string SourceTitle,
    string Region,
    int? Year,
    string GradeOrScope,
    string EditionOrVersion,
    string MaterialBatchKey,
    string OwnerScope,
    string LicenseOrPermission,
    bool SharingAllowed,
    bool ContainsStudentPii,
    string AnonymizationStatus,
    bool MayUseForKnowledgeExtraction,
    bool MayUseForExamPointExtraction,
    bool MayUseForTrendAnalysis)
{
    public static SourceDocumentMetadata Defaults(string originalFileName)
    {
        return new SourceDocumentMetadata(
            SourceType: "unknown",
            SourceTitle: originalFileName,
            Region: string.Empty,
            Year: null,
            GradeOrScope: string.Empty,
            EditionOrVersion: string.Empty,
            MaterialBatchKey: string.Empty,
            OwnerScope: "teacher_private",
            LicenseOrPermission: "unknown",
            SharingAllowed: false,
            ContainsStudentPii: false,
            AnonymizationStatus: "not_applicable",
            MayUseForKnowledgeExtraction: false,
            MayUseForExamPointExtraction: false,
            MayUseForTrendAnalysis: false);
    }
}
