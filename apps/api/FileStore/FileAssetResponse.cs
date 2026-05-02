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
    string OwnerScope,
    string LicenseOrPermission,
    bool SharingAllowed,
    bool ContainsStudentPii,
    string AnonymizationStatus,
    bool ExternalAiAllowed);

public sealed record SourceDocumentMetadata(
    string SourceType,
    string SourceTitle,
    string OwnerScope,
    string LicenseOrPermission,
    bool SharingAllowed,
    bool ContainsStudentPii,
    string AnonymizationStatus)
{
    public static SourceDocumentMetadata Defaults(string originalFileName)
    {
        return new SourceDocumentMetadata(
            SourceType: "unknown",
            SourceTitle: originalFileName,
            OwnerScope: "teacher_private",
            LicenseOrPermission: "unknown",
            SharingAllowed: false,
            ContainsStudentPii: false,
            AnonymizationStatus: "not_applicable");
    }
}
