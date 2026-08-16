namespace K12QuestionGraph.Api.FileStore;

public static class SourceDocumentMetadataPolicy
{
    private const int SourceTypeMaxLength = 64;
    private const int SourceTitleMaxLength = 260;
    private const int RegionMaxLength = 128;
    private const int GradeOrScopeMaxLength = 128;
    private const int EditionOrVersionMaxLength = 128;
    private const int MaterialBatchKeyMaxLength = 160;
    private const int OwnerScopeMaxLength = 64;
    private const int LicenseOrPermissionMaxLength = 256;
    private const int AnonymizationStatusMaxLength = 64;

    private static readonly HashSet<string> AllowedAnonymizationStatuses = new(StringComparer.OrdinalIgnoreCase)
    {
        "none",
        "anonymized",
        "synthetic",
        "not_applicable"
    };

    public static SourceDocumentMetadata Normalize(SourceDocumentMetadata metadata)
    {
        var sourceType = NormalizeToken(metadata.SourceType, "unknown", SourceTypeMaxLength);
        var sourceTitle = NormalizeText(metadata.SourceTitle, "untitled source", SourceTitleMaxLength);
        var region = NormalizeText(metadata.Region, string.Empty, RegionMaxLength);
        var gradeOrScope = NormalizeText(metadata.GradeOrScope, string.Empty, GradeOrScopeMaxLength);
        var editionOrVersion = NormalizeText(metadata.EditionOrVersion, string.Empty, EditionOrVersionMaxLength);
        var materialBatchKey = NormalizeToken(metadata.MaterialBatchKey, string.Empty, MaterialBatchKeyMaxLength);
        var ownerScope = NormalizeToken(metadata.OwnerScope, "teacher_private", OwnerScopeMaxLength);
        var license = NormalizeText(metadata.LicenseOrPermission, "unknown", LicenseOrPermissionMaxLength);
        var anonymizationStatus = NormalizeToken(metadata.AnonymizationStatus, "not_applicable", AnonymizationStatusMaxLength);

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

        if (!metadata.MayUseForKnowledgeExtraction
            && !metadata.MayUseForExamPointExtraction
            && !metadata.MayUseForTrendAnalysis)
        {
            return false;
        }

        return true;
    }

    public static bool ResolveExternalAiAllowed(
        SourceDocumentMetadata metadata,
        bool currentlyAllowed,
        bool? requestedAllowed)
    {
        var policyAllows = ComputeExternalAiAllowed(metadata);
        if (requestedAllowed == true && !policyAllows)
        {
            throw new ArgumentException("external_ai_policy_not_satisfied", nameof(requestedAllowed));
        }

        return policyAllows && (requestedAllowed ?? currentlyAllowed);
    }

    private static string NormalizeToken(string value, string fallback, int maxLength)
    {
        return NormalizeText(value, fallback, maxLength)
            .ToLowerInvariant()
            .Replace('-', '_')
            .Replace(' ', '_');
    }

    private static string NormalizeText(string value, string fallback, int maxLength)
    {
        var normalized = string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
        if (normalized.Length <= maxLength)
        {
            return normalized;
        }

        var length = maxLength;
        if (char.IsHighSurrogate(normalized[length - 1]) && char.IsLowSurrogate(normalized[length]))
        {
            length -= 1;
        }

        return normalized[..length];
    }
}
