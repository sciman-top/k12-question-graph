using System.Security.Cryptography;
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
            return ToResponse(existing);
        }

        var asset = new FileAsset
        {
            OriginalFileName = safeName,
            RelativePath = relativePath,
            StorageScope = "original",
            ContentType = string.IsNullOrWhiteSpace(contentType) ? "application/octet-stream" : contentType,
            Sha256 = sha256,
            SizeBytes = sizeBytes,
            SourceMetadata = "{}"
        };

        dbContext.FileAssets.Add(asset);
        await dbContext.SaveChangesAsync(cancellationToken);

        return ToResponse(asset);
    }

    private static FileAssetResponse ToResponse(FileAsset asset)
    {
        return new FileAssetResponse(
            asset.Id,
            asset.OriginalFileName,
            asset.RelativePath,
            asset.StorageScope,
            asset.ContentType,
            asset.Sha256,
            asset.SizeBytes);
    }
}
