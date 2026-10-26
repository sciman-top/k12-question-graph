namespace K12QuestionGraph.Api.FileStore;

using System.Text.Json;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.ImportJobs;
using K12QuestionGraph.Api.Infrastructure.Json;
using K12QuestionGraph.Api.Security;
using Microsoft.AspNetCore.Http;

public static class FormHelpers
{
    public static SourceDocumentMetadata SourceMetadataFromForm(IFormCollection form, string originalFileName)
    {
        var defaults = SourceDocumentMetadata.Defaults(Path.GetFileName(originalFileName));

        var metadata = defaults with
        {
            SourceType = FormValue(form, "sourceType", defaults.SourceType),
            SourceTitle = FormValue(form, "sourceTitle", defaults.SourceTitle),
            Region = FormValue(form, "region", defaults.Region),
            Year = FormInt(form, "year", defaults.Year),
            GradeOrScope = FormValue(form, "gradeOrScope", defaults.GradeOrScope),
            EditionOrVersion = FormValue(form, "editionOrVersion", defaults.EditionOrVersion),
            MaterialBatchKey = FormValue(form, "materialBatchKey", defaults.MaterialBatchKey),
            OwnerScope = FormValue(form, "ownerScope", defaults.OwnerScope),
            LicenseOrPermission = FormValue(form, "licenseOrPermission", defaults.LicenseOrPermission),
            SharingAllowed = FormBool(form, "sharingAllowed", defaults.SharingAllowed),
            ContainsStudentPii = FormBool(form, "containsStudentPii", defaults.ContainsStudentPii),
            AnonymizationStatus = FormValue(form, "anonymizationStatus", defaults.AnonymizationStatus),
            MayUseForKnowledgeExtraction = FormBool(form, "mayUseForKnowledgeExtraction", defaults.MayUseForKnowledgeExtraction),
            MayUseForExamPointExtraction = FormBool(form, "mayUseForExamPointExtraction", defaults.MayUseForExamPointExtraction),
            MayUseForTrendAnalysis = FormBool(form, "mayUseForTrendAnalysis", defaults.MayUseForTrendAnalysis)
        };

        return SourceMaterialClassifier.Classify(metadata, originalFileName);
    }

    public static string FormValue(IFormCollection form, string key, string fallback)
    {
        return form.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value)
            ? value.ToString()
            : fallback;
    }

    public static bool FormBool(IFormCollection form, string key, bool fallback)
    {
        return form.TryGetValue(key, out var value) && bool.TryParse(value.ToString(), out var parsed)
            ? parsed
            : fallback;
    }

    public static int? FormInt(IFormCollection form, string key, int? fallback)
    {
        return form.TryGetValue(key, out var value) && int.TryParse(value.ToString(), out var parsed)
            ? parsed
            : fallback;
    }

    public static bool TryResolveFileStorePath(string fileStoreRoot, string relativePath, out string fullPath)
    {
        fullPath = string.Empty;
        if (string.IsNullOrWhiteSpace(relativePath) || Path.IsPathRooted(relativePath))
        {
            return false;
        }

        var normalizedRelative = relativePath.Replace('\\', '/');
        if (normalizedRelative.Split('/').Any(x => x is "" or "." or ".."))
        {
            return false;
        }

        var root = Path.GetFullPath(fileStoreRoot);
        var candidate = Path.GetFullPath(Path.Combine(root, normalizedRelative));
        var rootPrefix = root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) +
            Path.DirectorySeparatorChar;
        var comparison = OperatingSystem.IsWindows()
            ? StringComparison.OrdinalIgnoreCase
            : StringComparison.Ordinal;
        if (!candidate.StartsWith(rootPrefix, comparison))
        {
            return false;
        }

        fullPath = candidate;
        return true;
    }

    public static string InferContentType(string path)
    {
        return Path.GetExtension(path).ToLowerInvariant() switch
        {
            ".png" => "image/png",
            ".jpg" or ".jpeg" => "image/jpeg",
            ".webp" => "image/webp",
            ".gif" => "image/gif",
            ".svg" => "image/svg+xml",
            ".json" => "application/json; charset=utf-8",
            ".txt" => "text/plain; charset=utf-8",
            ".pdf" => "application/pdf",
            _ => "application/octet-stream"
        };
    }

    public static string NormalizeToken(string value, string fallback)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return fallback;
        }

        return value.Trim().ToLowerInvariant().Replace('-', '_').Replace(' ', '_');
    }

    public static string SerializeJson<T>(T value)
    {
        return JsonSerializer.Serialize(value, new JsonSerializerOptions(JsonSerializerDefaults.Web));
    }

    public static string ResolveAuditedActor(HttpContext httpContext) =>
    AdminInternalEndpointGuard.ResolveActorIdentity(httpContext.User).OperatorId;


    public static string? ValidateSourceRegionRequest(SourceRegionCreateRequest request)
{
    if (request.PageNumber < 1)
    {
        return "invalid_page_number";
    }

    if (request.X < 0 || request.Y < 0 || request.Width <= 0 || request.Height <= 0)
    {
        return "invalid_bbox";
    }

    var unit = NormalizeToken(request.CoordinateUnit, "percent");
    return unit is "pixel" or "point" or "percent" ? null : "invalid_coordinate_unit";
}
}
