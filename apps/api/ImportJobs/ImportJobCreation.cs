using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.FileStore;
using Microsoft.EntityFrameworkCore;

namespace K12QuestionGraph.Api.ImportJobs;

internal sealed record ImportJobCreationResult(ImportJob? ExistingJob, ImportJob? CreatedJob);

/// <summary>
/// POST /imports 的幂等创建逻辑。并发上传同一文件时,两个请求可能同时通过
/// 存在性检查后撞 IdempotencyKey 唯一索引;此路径捕获冲突后重查并返回既有
/// job,而不是让第二次上传收到 500。saveChangesAsync 接缝用于测试注入
/// 模拟的唯一约束冲突(唯一约束本身的行为由数据库保证)。
/// </summary>
internal static class ImportJobCreation
{
    public static async Task<ImportJobCreationResult> CreateOrGetAsync(
        KqgDbContext dbContext,
        FileAssetResponse stored,
        Func<CancellationToken, Task<int>> saveChangesAsync,
        CancellationToken cancellationToken)
    {
        var idempotencyKey = BuildIdempotencyKey(stored.Sha256);
        var existing = await dbContext.ImportJobs
            .FirstOrDefaultAsync(x => x.IdempotencyKey == idempotencyKey, cancellationToken);

        if (existing is not null)
        {
            return new ImportJobCreationResult(ExistingJob: existing, CreatedJob: null);
        }

        var job = new ImportJob
        {
            InputFileAssetId = stored.Id,
            Status = JobStatuses.Queued,
            IdempotencyKey = idempotencyKey,
            Input = $$"""
        {"fileAssetId":"{{stored.Id}}","relativePath":"{{stored.RelativePath}}","sha256":"{{stored.Sha256}}"}
        """
        };

        dbContext.ImportJobs.Add(job);
        try
        {
            await saveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            var raced = await dbContext.ImportJobs
                .AsNoTracking()
                .FirstOrDefaultAsync(x => x.IdempotencyKey == idempotencyKey, cancellationToken);
            if (raced is null)
            {
                throw;
            }

            return new ImportJobCreationResult(ExistingJob: raced, CreatedJob: null);
        }

        return new ImportJobCreationResult(ExistingJob: null, CreatedJob: job);
    }

    internal static string BuildIdempotencyKey(string sha256) => $"import:original:{sha256}";
}
