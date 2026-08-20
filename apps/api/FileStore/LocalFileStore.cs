using System.Security.Cryptography;
using System.Text.Json;
using K12QuestionGraph.Api.Configuration;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace K12QuestionGraph.Api.FileStore;

public sealed class LocalFileStore(KqgDbContext dbContext, IOptions<KqgPathsOptions> pathsOptions)
{
    private static readonly SemaphoreSlim[] BlobLocks = Enumerable.Range(0, 64)
        .Select(static _ => new SemaphoreSlim(1, 1))
        .ToArray();

    public async Task<FileAssetResponse> StoreOriginalAsync(
        Stream content,
        string originalFileName,
        string? contentType,
        long sizeBytes,
        SourceDocumentMetadata sourceMetadata,
        CancellationToken cancellationToken)
    {
        var paths = pathsOptions.Value;
        var uploadIdentity = UploadStoragePolicy.Normalize(originalFileName, contentType);
        UploadStoragePolicy.ValidateDeclaredLength(sizeBytes);

        Directory.CreateDirectory(paths.FileStoreRoot);

        var tempPath = Path.Combine(paths.FileStoreRoot, $".upload-{Guid.NewGuid():N}.tmp");
        try
        {
            string sha256;
            await using (var target = File.Create(tempPath))
            {
                var copyResult = await CopyAndHashAsync(content, target, cancellationToken);
                sha256 = copyResult.Sha256;
                await target.FlushAsync(cancellationToken);
                if (copyResult.Length != sizeBytes)
                {
                    throw new InvalidDataException($"Upload stream length {copyResult.Length} does not match declared length {sizeBytes}.");
                }
            }

            UploadStoragePolicy.ValidateContent(tempPath, uploadIdentity);

            var shard = Path.Combine("original", sha256[..2], sha256[2..4]);
            var relativePath = Path.Combine(shard, $"{sha256}{uploadIdentity.StorageExtension}").Replace('\\', '/');

            var normalizedSourceMetadata = Normalize(sourceMetadata);
            var blobLock = BlobLocks[(sha256.GetHashCode(StringComparison.OrdinalIgnoreCase) & int.MaxValue) % BlobLocks.Length];
            await blobLock.WaitAsync(cancellationToken);
            try
            {
                await using var transaction = await dbContext.Database.BeginTransactionAsync(cancellationToken);
                var existingByHash = await dbContext.FileAssets
                    .FirstOrDefaultAsync(x => x.StorageScope == "original" && x.Sha256 == sha256 && x.SizeBytes == sizeBytes, cancellationToken);
                if (existingByHash is not null)
                {
                    OriginalBlobMaterializer.Reconcile(
                        paths.FileStoreRoot,
                        existingByHash.RelativePath,
                        tempPath,
                        sha256,
                        sizeBytes);
                    var sourceDocument = await AddSourceDocumentAsync(existingByHash.Id, normalizedSourceMetadata, cancellationToken);
                    await dbContext.SaveChangesAsync(cancellationToken);
                    await transaction.CommitAsync(cancellationToken);
                    return ToResponse(existingByHash, isDuplicate: true, duplicateOfFileAssetId: existingByHash.Id, sourceDocument);
                }

                var createdBlob = OriginalBlobMaterializer.Reconcile(paths.FileStoreRoot, relativePath, tempPath, sha256, sizeBytes);
                var commitAttempted = false;

                try
                {
                    var existing = await dbContext.FileAssets
                        .FirstOrDefaultAsync(x => x.StorageScope == "original" && x.RelativePath == relativePath, cancellationToken);
                    if (existing is not null)
                    {
                        var sourceDocument = await AddSourceDocumentAsync(existing.Id, normalizedSourceMetadata, cancellationToken);
                        await dbContext.SaveChangesAsync(cancellationToken);
                        await transaction.CommitAsync(cancellationToken);
                        return ToResponse(existing, isDuplicate: true, duplicateOfFileAssetId: existing.Id, sourceDocument);
                    }

                    var asset = new FileAsset
                    {
                        Id = Guid.NewGuid(),
                        OriginalFileName = uploadIdentity.OriginalFileName,
                        RelativePath = relativePath,
                        StorageScope = "original",
                        ContentType = uploadIdentity.ContentType,
                        Sha256 = sha256,
                        SizeBytes = sizeBytes,
                        SourceMetadata = JsonSerializer.Serialize(new
                        {
                            normalizedSourceMetadata.SourceType,
                            normalizedSourceMetadata.SourceTitle,
                            normalizedSourceMetadata.Region,
                            normalizedSourceMetadata.Year,
                            normalizedSourceMetadata.GradeOrScope,
                            normalizedSourceMetadata.EditionOrVersion,
                            normalizedSourceMetadata.MaterialBatchKey,
                            normalizedSourceMetadata.OwnerScope,
                            normalizedSourceMetadata.LicenseOrPermission,
                            normalizedSourceMetadata.SharingAllowed,
                            normalizedSourceMetadata.ContainsStudentPii,
                            normalizedSourceMetadata.AnonymizationStatus,
                            normalizedSourceMetadata.MayUseForKnowledgeExtraction,
                            normalizedSourceMetadata.MayUseForExamPointExtraction,
                            normalizedSourceMetadata.MayUseForTrendAnalysis
                        })
                    };

                    dbContext.FileAssets.Add(asset);
                    var createdSourceDocument = await AddSourceDocumentAsync(asset.Id, normalizedSourceMetadata, cancellationToken);
                    await dbContext.SaveChangesAsync(cancellationToken);
                    commitAttempted = true;
                    await transaction.CommitAsync(cancellationToken);

                    return ToResponse(asset, isDuplicate: false, duplicateOfFileAssetId: null, createdSourceDocument);
                }
                catch
                {
                    if (createdBlob && !commitAttempted)
                {
                    try
                    {
                        OriginalBlobMaterializer.DeleteIfMatches(
                            paths.FileStoreRoot,
                            relativePath,
                            sha256,
                            sizeBytes);
                    }
                    catch (Exception cleanupException) when (cleanupException is IOException or UnauthorizedAccessException)
                    {
                        // Best-effort compensation must not hide the database failure.
                    }
                }
                    throw;
                }
            }
            finally
            {
                blobLock.Release();
            }
        }
        finally
        {
            TryDeleteTempFile(tempPath);
        }
    }

    private static async Task<(long Length, string Sha256)> CopyAndHashAsync(
        Stream source,
        Stream destination,
        CancellationToken cancellationToken)
    {
        var buffer = GC.AllocateUninitializedArray<byte>(81920);
        long length = 0;
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);

        while (true)
        {
            var bytesRead = await source.ReadAsync(buffer, cancellationToken);
            if (bytesRead == 0)
            {
                break;
            }

            if (length > UploadStoragePolicy.MaxUploadBytes - bytesRead)
            {
                throw new InvalidDataException($"Upload stream exceeds the {UploadStoragePolicy.MaxUploadBytes} byte limit.");
            }

            await destination.WriteAsync(buffer.AsMemory(0, bytesRead), cancellationToken);
            hash.AppendData(buffer, 0, bytesRead);
            length += bytesRead;
        }

        var sha256 = Convert.ToHexString(hash.GetHashAndReset()).ToLowerInvariant();
        return (length, sha256);
    }

    private static void TryDeleteTempFile(string tempPath)
    {
        try
        {
            File.Delete(tempPath);
        }
        catch (IOException)
        {
            // Best-effort cleanup must not hide the upload or persistence failure.
        }
        catch (UnauthorizedAccessException)
        {
            // Best-effort cleanup must not hide the upload or persistence failure.
        }
    }

    private async Task<SourceDocument> AddSourceDocumentAsync(
        Guid fileAssetId,
        SourceDocumentMetadata metadata,
        CancellationToken cancellationToken)
    {
        var normalized = Normalize(metadata);
        var externalAiAllowed = ComputeExternalAiAllowed(normalized);
        var existing = await dbContext.SourceDocuments
            .Where(x =>
                x.FileAssetId == fileAssetId &&
                x.SourceType == normalized.SourceType &&
                x.SourceTitle == normalized.SourceTitle &&
                x.Region == normalized.Region &&
                x.Year == normalized.Year &&
                x.GradeOrScope == normalized.GradeOrScope &&
                x.EditionOrVersion == normalized.EditionOrVersion &&
                x.MaterialBatchKey == normalized.MaterialBatchKey &&
                x.OwnerScope == normalized.OwnerScope &&
                x.LicenseOrPermission == normalized.LicenseOrPermission &&
                x.SharingAllowed == normalized.SharingAllowed &&
                x.ContainsStudentPii == normalized.ContainsStudentPii &&
                x.AnonymizationStatus == normalized.AnonymizationStatus &&
                x.ExternalAiAllowed == externalAiAllowed &&
                x.MayUseForKnowledgeExtraction == normalized.MayUseForKnowledgeExtraction &&
                x.MayUseForExamPointExtraction == normalized.MayUseForExamPointExtraction &&
                x.MayUseForTrendAnalysis == normalized.MayUseForTrendAnalysis)
            .OrderBy(x => x.CreatedAt)
            .ThenBy(x => x.Id)
            .FirstOrDefaultAsync(cancellationToken);
        if (existing is not null)
        {
            return existing;
        }

        var sourceDocument = new SourceDocument
        {
            FileAssetId = fileAssetId,
            SourceType = normalized.SourceType,
            SourceTitle = normalized.SourceTitle,
            Region = normalized.Region,
            Year = normalized.Year,
            GradeOrScope = normalized.GradeOrScope,
            EditionOrVersion = normalized.EditionOrVersion,
            MaterialBatchKey = normalized.MaterialBatchKey,
            OwnerScope = normalized.OwnerScope,
            LicenseOrPermission = normalized.LicenseOrPermission,
            SharingAllowed = normalized.SharingAllowed,
            ContainsStudentPii = normalized.ContainsStudentPii,
            AnonymizationStatus = normalized.AnonymizationStatus,
            ExternalAiAllowed = externalAiAllowed,
            MayUseForKnowledgeExtraction = normalized.MayUseForKnowledgeExtraction,
            MayUseForExamPointExtraction = normalized.MayUseForExamPointExtraction,
            MayUseForTrendAnalysis = normalized.MayUseForTrendAnalysis
        };

        dbContext.SourceDocuments.Add(sourceDocument);
        return sourceDocument;
    }

    private static SourceDocumentMetadata Normalize(SourceDocumentMetadata metadata)
    {
        return SourceDocumentMetadataPolicy.Normalize(metadata);
    }

    private static bool ComputeExternalAiAllowed(SourceDocumentMetadata metadata)
    {
        return SourceDocumentMetadataPolicy.ComputeExternalAiAllowed(metadata);
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
                sourceDocument.Region,
                sourceDocument.Year,
                sourceDocument.GradeOrScope,
                sourceDocument.EditionOrVersion,
                sourceDocument.MaterialBatchKey,
                sourceDocument.OwnerScope,
                sourceDocument.LicenseOrPermission,
                sourceDocument.SharingAllowed,
                sourceDocument.ContainsStudentPii,
                sourceDocument.AnonymizationStatus,
                sourceDocument.ExternalAiAllowed,
                sourceDocument.MayUseForKnowledgeExtraction,
                sourceDocument.MayUseForExamPointExtraction,
                sourceDocument.MayUseForTrendAnalysis));
    }
}
