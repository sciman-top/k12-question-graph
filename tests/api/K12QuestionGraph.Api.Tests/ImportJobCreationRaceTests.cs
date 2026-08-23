using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.FileStore;
using K12QuestionGraph.Api.ImportJobs;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace K12QuestionGraph.Api.Tests;

/// <summary>
/// 2026-08-23 审计 L5 竞态分支覆盖:并发上传同一文件时,存在性检查通过后
/// 撞 IdempotencyKey 唯一索引的路径必须重查并返回既有 job。真实唯一约束
/// 行为由 PostgreSQL 保证;这里通过 saveChangesAsync 接缝模拟"并发赢家已
/// 写入同幂等键、本请求保存失败"的数据库可见状态,覆盖 handler 的
/// catch-重查分支(此前为无状态验证缺口)。
/// </summary>
public sealed class ImportJobCreationRaceTests
{
    private static FileAssetResponse StoredAsset(string sha256) => new(
        Id: Guid.NewGuid(),
        OriginalFileName: "paper.pdf",
        RelativePath: $"original/{sha256[..2]}/{sha256}.pdf",
        StorageScope: "original",
        ContentType: "application/pdf",
        Sha256: sha256,
        SizeBytes: 10,
        IsDuplicate: false,
        DuplicateOfFileAssetId: null,
        SourceDocument: null!);

    [Fact]
    public async Task CreateOrGet_ReturnsWinnerJobWhenSaveHitsUniqueViolation()
    {
        var databaseRoot = new InMemoryDatabaseRoot();
        var options = new DbContextOptionsBuilder<KqgDbContext>()
            .UseInMemoryDatabase("import-race", databaseRoot)
            .Options;
        var sha256 = new string('a', 64);
        var stored = StoredAsset(sha256);
        var idempotencyKey = ImportJobCreation.BuildIdempotencyKey(sha256);

        using var seedingContext = new KqgDbContext(options);
        seedingContext.Database.EnsureCreated();
        using var racingContext = new KqgDbContext(options);
        racingContext.Database.EnsureCreated();

        var saveAttempts = 0;
        Task<int> SimulatedSave(CancellationToken cancellationToken)
        {
            if (Interlocked.Increment(ref saveAttempts) == 1)
            {
                seedingContext.ImportJobs.Add(new ImportJob
                {
                    InputFileAssetId = Guid.NewGuid(),
                    Status = JobStatuses.Queued,
                    IdempotencyKey = idempotencyKey,
                    Input = "{}"
                });
                seedingContext.SaveChanges();
                throw new DbUpdateException(
                    "duplicate key value violates unique constraint",
                    new InvalidOperationException("simulated unique violation"));
            }

            return racingContext.SaveChangesAsync(cancellationToken);
        }

        var raced = await ImportJobCreation.CreateOrGetAsync(
            racingContext, stored, SimulatedSave, CancellationToken.None);

        Assert.Null(raced.CreatedJob);
        Assert.NotNull(raced.ExistingJob);
        Assert.Equal(idempotencyKey, raced.ExistingJob.IdempotencyKey);
        Assert.Equal(1, saveAttempts);

        // 竞态窗口过后,后续同文件上传直接命中存在性检查,返回既有 job。
        var followUp = await ImportJobCreation.CreateOrGetAsync(
            racingContext, stored, racingContext.SaveChangesAsync, CancellationToken.None);

        Assert.Null(followUp.CreatedJob);
        Assert.NotNull(followUp.ExistingJob);
        Assert.Equal(idempotencyKey, followUp.ExistingJob.IdempotencyKey);
    }

    [Fact]
    public async Task CreateOrGet_CreatesJobWhenNoExistingKey()
    {
        var options = new DbContextOptionsBuilder<KqgDbContext>()
            .UseInMemoryDatabase("import-create")
            .Options;
        var sha256 = new string('b', 64);
        var stored = StoredAsset(sha256);

        using var context = new KqgDbContext(options);
        context.Database.EnsureCreated();

        var result = await ImportJobCreation.CreateOrGetAsync(
            context, stored, context.SaveChangesAsync, CancellationToken.None);

        Assert.Null(result.ExistingJob);
        Assert.NotNull(result.CreatedJob);
        Assert.Equal(ImportJobCreation.BuildIdempotencyKey(sha256), result.CreatedJob.IdempotencyKey);
        Assert.Equal(stored.Id, result.CreatedJob.InputFileAssetId);
        Assert.Equal(JobStatuses.Queued, result.CreatedJob.Status);
        Assert.Contains(stored.RelativePath, result.CreatedJob.Input);
    }
}
