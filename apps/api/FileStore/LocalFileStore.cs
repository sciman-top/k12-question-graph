using System.Security.Cryptography;
using System.Text.Json;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace K12QuestionGraph.Api.FileStore;

public sealed class LocalFileStore(KqgDbContext dbContext, IOptions<KqgPathsOptions> pathsOptions) : IFileStore
{
    public async Task<FileAssetResponse> StoreOriginalAsync(
        Stream content,
        string originalFileName,
        string? contentType,
        long sizeBytes,
        SourceDocumentMetadata sourceMetadata,
        CancellationToken cancellationToken)
    {
        var paths = pathsOptions.Value;
        var safeName = Path.GetFileName(originalFileName);
        if (string.IsNullOrWhiteSpace(safeName))
        {
            safeName = "upload.bin";
        }

        Directory.CreateDirectory(paths.FileStoreRoot);

        var tempPath = Path.Combine(paths.FileStoreRoot, $".upload-{Guid.NewGuid():N}.tmp");
        string sha256;

        await using (var target = File.Create(tempPath))
        {
            using var hash = SHA256.Create();
            await content.CopyToAsync(target, cancellationToken);
            await target.FlushAsync(cancellationToken);
            target.Position = 0;
            sha256 = Convert.ToHexString(await hash.ComputeHashAsync(target, cancellationToken)).ToLowerInvariant();
        }

        var extension = Path.GetExtension(safeName);
        var shard = Path.Combine("original", sha256[..2], sha256[2..4]);
        var relativePath = Path.Combine(shard, $"{sha256}{extension}").Replace('\\', '/');
        var absoluteDirectory = Path.Combine(paths.FileStoreRoot, shard);
        var absolutePath = Path.Combine(paths.FileStoreRoot, relativePath);

        var normalizedSourceMetadata = Normalize(sourceMetadata);
        var existingByHash = await dbContext.FileAssets
            .FirstOrDefaultAsync(x => x.StorageScope == "original" && x.Sha256 == sha256 && x.SizeBytes == sizeBytes, cancellationToken);
        if (existingByHash is not null)
        {
            File.Delete(tempPath);
            var sourceDocument = await AddSourceDocumentAsync(existingByHash.Id, normalizedSourceMetadata, cancellationToken);
            return ToResponse(existingByHash, isDuplicate: true, duplicateOfFileAssetId: existingByHash.Id, sourceDocument);
        }

        Directory.CreateDirectory(absoluteDirectory);
        if (!File.Exists(absolutePath))
        {
            File.Move(tempPath, absolutePath);
        }
        else
        {
            File.Delete(tempPath);
        }

        var existing = await dbContext.FileAssets
            .FirstOrDefaultAsync(x => x.StorageScope == "original" && x.RelativePath == relativePath, cancellationToken);
        if (existing is not null)
        {
            var sourceDocument = await AddSourceDocumentAsync(existing.Id, normalizedSourceMetadata, cancellationToken);
            return ToResponse(existing, isDuplicate: true, duplicateOfFileAssetId: existing.Id, sourceDocument);
        }

        var asset = new FileAsset
        {
            OriginalFileName = safeName,
            RelativePath = relativePath,
            StorageScope = "original",
            ContentType = string.IsNullOrWhiteSpace(contentType) ? "application/octet-stream" : contentType,
            Sha256 = sha256,
            SizeBytes = sizeBytes,
            SourceMetadata = JsonSerializer.Serialize(new
            {
                normalizedSourceMetadata.SourceType,
                normalizedSourceMetadata.SourceTitle,
                normalizedSourceMetadata.OwnerScope,
                normalizedSourceMetadata.LicenseOrPermission,
                normalizedSourceMetadata.SharingAllowed,
                normalizedSourceMetadata.ContainsStudentPii,
                normalizedSourceMetadata.AnonymizationStatus
            })
        };

        dbContext.FileAssets.Add(asset);
        await dbContext.SaveChangesAsync(cancellationToken);

        var createdSourceDocument = await AddSourceDocumentAsync(asset.Id, normalizedSourceMetadata, cancellationToken);

        return ToResponse(asset, isDuplicate: false, duplicateOfFileAssetId: null, createdSourceDocument);
    }

    private async Task<SourceDocument> AddSourceDocumentAsync(
        Guid fileAssetId,
        SourceDocumentMetadata metadata,
        CancellationToken cancellationToken)
    {
        var normalized = Normalize(metadata);
        var sourceDocument = new SourceDocument
        {
            FileAssetId = fileAssetId,
            SourceType = normalized.SourceType,
            SourceTitle = normalized.SourceTitle,
            OwnerScope = normalized.OwnerScope,
            LicenseOrPermission = normalized.LicenseOrPermission,
            SharingAllowed = normalized.SharingAllowed,
            ContainsStudentPii = normalized.ContainsStudentPii,
            AnonymizationStatus = normalized.AnonymizationStatus,
            ExternalAiAllowed = ComputeExternalAiAllowed(normalized)
        };

        dbContext.SourceDocuments.Add(sourceDocument);
        await dbContext.SaveChangesAsync(cancellationToken);
        return sourceDocument;
    }

    private static SourceDocumentMetadata Normalize(SourceDocumentMetadata metadata)
    {
        var sourceType = NormalizeToken(metadata.SourceType, "unknown");
        var sourceTitle = string.IsNullOrWhiteSpace(metadata.SourceTitle) ? "untitled source" : metadata.SourceTitle.Trim();
        var ownerScope = NormalizeToken(metadata.OwnerScope, "teacher_private");
        var license = string.IsNullOrWhiteSpace(metadata.LicenseOrPermission) ? "unknown" : metadata.LicenseOrPermission.Trim();
        var anonymizationStatus = NormalizeToken(metadata.AnonymizationStatus, "not_applicable");
        var allowedAnonymization = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "none",
            "anonymized",
            "synthetic",
            "not_applicable"
        };

        if (!allowedAnonymization.Contains(anonymizationStatus))
        {
            anonymizationStatus = "not_applicable";
        }

        var sharingAllowed = metadata.SharingAllowed && !string.Equals(sourceType, "unknown", StringComparison.OrdinalIgnoreCase);
        if (metadata.ContainsStudentPii && anonymizationStatus is not ("anonymized" or "synthetic"))
        {
            sharingAllowed = false;
        }

        return metadata with
        {
            SourceType = sourceType,
            SourceTitle = sourceTitle,
            OwnerScope = ownerScope,
            LicenseOrPermission = license,
            SharingAllowed = sharingAllowed,
            AnonymizationStatus = anonymizationStatus
        };
    }

    private static string NormalizeToken(string value, string fallback)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return fallback;
        }

        return value.Trim().ToLowerInvariant().Replace('-', '_').Replace(' ', '_');
    }

    private static bool ComputeExternalAiAllowed(SourceDocumentMetadata metadata)
    {
        if (string.Equals(metadata.SourceType, "unknown", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (metadata.ContainsStudentPii && metadata.AnonymizationStatus is not ("anonymized" or "synthetic"))
        {
            return false;
        }

        return true;
    }

    private static FileAssetResponse ToResponse(
        FileAsset asset,
        bool isDuplicate,
        Guid? duplicateOfFileAssetId,
        SourceDocument sourceDocument)
    {
        return new FileAssetResponse(
            asset.Id,
            asset.OriginalFileName,
            asset.RelativePath,
            asset.StorageScope,
            asset.ContentType,
            asset.Sha256,
            asset.SizeBytes,
            isDuplicate,
            duplicateOfFileAssetId,
            new SourceDocumentResponse(
                sourceDocument.Id,
                sourceDocument.FileAssetId,
                sourceDocument.SourceType,
                sourceDocument.SourceTitle,
                sourceDocument.OwnerScope,
                sourceDocument.LicenseOrPermission,
                sourceDocument.SharingAllowed,
                sourceDocument.ContainsStudentPii,
                sourceDocument.AnonymizationStatus,
                sourceDocument.ExternalAiAllowed));
    }
}
