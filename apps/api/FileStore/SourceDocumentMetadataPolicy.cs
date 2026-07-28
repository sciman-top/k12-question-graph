namespace K12QuestionGraph.Api.FileStore;

public static class SourceDocumentMetadataPolicy
{
    private static readonly HashSet<string> AllowedAnonymizationStatuses = new(StringComparer.OrdinalIgnoreCase)
    {
        "none",
        "anonymized",
        "synthetic",
        "not_applicable"
    };

    public static SourceDocumentMetadata Normalize(SourceDocumentMetadata metadata)
    {
        var sourceType = NormalizeToken(metadata.SourceType, "unknown");
        var sourceTitle = string.IsNullOrWhiteSpace(metadata.SourceTitle) ? "untitled source" : metadata.SourceTitle.Trim();
        var region = string.IsNullOrWhiteSpace(metadata.Region) ? string.Empty : metadata.Region.Trim();
        var gradeOrScope = string.IsNullOrWhiteSpace(metadata.GradeOrScope) ? string.Empty : metadata.GradeOrScope.Trim();
        var editionOrVersion = string.IsNullOrWhiteSpace(metadata.EditionOrVersion) ? string.Empty : metadata.EditionOrVersion.Trim();
        var materialBatchKey = NormalizeToken(metadata.MaterialBatchKey, string.Empty);
        var ownerScope = NormalizeToken(metadata.OwnerScope, "teacher_private");
        var license = string.IsNullOrWhiteSpace(metadata.LicenseOrPermission) ? "unknown" : metadata.LicenseOrPermission.Trim();
        var anonymizationStatus = NormalizeToken(metadata.AnonymizationStatus, "not_applicable");

        if (!AllowedAnonymizationStatuses.Contains(anonymizationStatus))
        {
            anonymizationStatus = "not_applicable";
        }

        var sharingAllowed = metadata.SharingAllowed && !string.Equals(sourceType, "unknown", StringComparison.OrdinalIgnoreCase);
        if (metadata.ContainsStudentPii && anonymizationStatus is not ("anonymized" or "synthetic"))
        {
            sharingAllowed = false;
        }

        var mayUseForExamPointExtraction = metadata.MayUseForExamPointExtraction;
        var mayUseForTrendAnalysis = metadata.MayUseForTrendAnalysis;
        if (string.Equals(sourceType, "curriculum_standard", StringComparison.OrdinalIgnoreCase))
        {
            mayUseForExamPointExtraction = false;
            mayUseForTrendAnalysis = false;
        }

        return metadata with
        {
            SourceType = sourceType,
            SourceTitle = sourceTitle,
            Region = region,
            GradeOrScope = gradeOrScope,
            EditionOrVersion = editionOrVersion,
            MaterialBatchKey = materialBatchKey,
            OwnerScope = ownerScope,
            LicenseOrPermission = license,
            SharingAllowed = sharingAllowed,
            AnonymizationStatus = anonymizationStatus,
            MayUseForExamPointExtraction = mayUseForExamPointExtraction,
            MayUseForTrendAnalysis = mayUseForTrendAnalysis
        };
    }

    public static bool ComputeExternalAiAllowed(SourceDocumentMetadata metadata)
    {
        if (string.Equals(metadata.SourceType, "unknown", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (!metadata.SharingAllowed)
        {
            return false;
        }

        var license = metadata.LicenseOrPermission.Trim();
        if (string.Equals(license, "unknown", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(license, "none", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(license, "pending_source_workbench_review", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (metadata.ContainsStudentPii && metadata.AnonymizationStatus is not ("anonymized" or "synthetic"))
        {
            return false;
        }

        return true;
    }

    private static string NormalizeToken(string value, string fallback)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return fallback;
        }

        return value.Trim().ToLowerInvariant().Replace('-', '_').Replace(' ', '_');
    }
}
