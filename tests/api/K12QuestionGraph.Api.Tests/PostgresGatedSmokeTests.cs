using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.FileStore;
using Microsoft.EntityFrameworkCore;

namespace K12QuestionGraph.Api.Tests;

/// <summary>
/// 真库(PostgreSQL)门控冒烟:只在设置 KQG_PG_SMOKE=1 时运行,未设置时静默通过。
/// 补证 InMemory 无法覆盖的三类分支:
/// 1. 生产默认 PaperBlueprintConfirmClaimStore 的条件 ExecuteUpdate 在 Npgsql 上的
///    SQL 翻译、抢占与并发仅一次成功、事务回滚恢复 pending_review(评审 M1 遗留);
/// 2. file_assets (Sha256,SizeBytes) 唯一冲突在真库抛出的异常形状能被
///    LocalFileStore.IsUniqueViolation 识别(L4 23505 分支前提)。
/// 使用独立临时库 kqg_pg_smoke_tmp,测试自建自清,不触碰业务库。
/// </summary>
public sealed class PostgresGatedSmokeTests
{
    private string smokeDatabase = $"kqg_pg_smoke_{Guid.NewGuid():N}";

    [SkippablePostgresFact]
    public async Task ClaimStore_ConcurrentClaimsOnlyOneWinsAndRollbackRestoresPending()
    {
        var connection = await CreateTemporaryDatabaseAsync();
        try
        {
            // 1) 默认实现翻译与单次抢占。
            var reviewId = await SeedPendingReviewAsync(connection);
            await using (var context = CreateContext(connection))
            {
                var claimStore = new PaperBlueprintConfirmClaimStore();
                var claimed = await claimStore.TryClaimAsync(
                    context, reviewId, "teacher-first", DateTimeOffset.UtcNow, CancellationToken.None);
                Assert.True(claimed, "first sequential claim must succeed on real PostgreSQL");
            }

            await using (var context = CreateContext(connection))
            {
                var confirmedStatus = await context.PaperBlueprintReviews.AsNoTracking()
                    .Where(x => x.Id == reviewId)
                    .Select(x => x.Status)
                    .SingleAsync();
                Assert.Equal(WorkflowReviewStatuses.Confirmed, confirmedStatus);
            }

            // 2) 并发确认恰好一次成功:两个独立 DbContext 同时抢同一行,
            //    条件 ExecuteUpdate 的行级原子性保证恰有一个 affected=1。
            var secondReviewId = await SeedPendingReviewAsync(connection);
            var winnerCount = await Task.WhenAll(Enumerable.Range(0, 2).Select(async _ =>
            {
                await using var context = CreateContext(connection);
                var claimStore = new PaperBlueprintConfirmClaimStore();
                var claimed = await claimStore.TryClaimAsync(
                    context, secondReviewId, "teacher-racer", DateTimeOffset.UtcNow, CancellationToken.None);
                return claimed ? 1 : 0;
            }));
            Assert.Equal(1, winnerCount.Sum());

            // 3) 回滚恢复:事务内抢占成功后回滚,行必须回到 pending_review。
            var thirdReviewId = await SeedPendingReviewAsync(connection);
            await using (var context = CreateContext(connection))
            {
                await using var transaction = await context.Database.BeginTransactionAsync();
                var claimStore = new PaperBlueprintConfirmClaimStore();
                var claimed = await claimStore.TryClaimAsync(
                    context, thirdReviewId, "teacher-rollback", DateTimeOffset.UtcNow, CancellationToken.None);
                Assert.True(claimed);
                await transaction.RollbackAsync();
            }

            await using var verification = CreateContext(connection);
            var status = await verification.PaperBlueprintReviews.AsNoTracking()
                .Where(x => x.Id == thirdReviewId)
                .Select(x => x.Status)
                .SingleAsync();
            Assert.Equal(WorkflowReviewStatuses.PendingReview, status);
        }
        finally
        {
            await TryDropTemporaryDatabaseAsync();
        }
    }

    [SkippablePostgresFact]
    public async Task UniqueViolation_ShapeIsRecognizedByFileStorePredicate()
    {
        var connection = await CreateTemporaryDatabaseAsync();
        try
        {
            var sha256 = new string('a', 64);
            await using (var first = CreateContext(connection))
            {
                first.FileAssets.Add(new FileAsset
                {
                    Id = Guid.NewGuid(),
                    OriginalFileName = "race-winner.pdf",
                    RelativePath = $"original/aa/bbbb/{sha256}.pdf",
                    StorageScope = "original",
                    ContentType = "application/pdf",
                    Sha256 = sha256,
                    SizeBytes = 128,
                    SourceMetadata = "{}"
                });
                await first.SaveChangesAsync();
            }

            DbUpdateException? conflict = null;
            await using (var second = CreateContext(connection))
            {
                second.FileAssets.Add(new FileAsset
                {
                    Id = Guid.NewGuid(),
                    OriginalFileName = "race-loser.pdf",
                    RelativePath = $"original/cc/dddd/{sha256}.pdf",
                    StorageScope = "original",
                    ContentType = "application/pdf",
                    Sha256 = sha256,
                    SizeBytes = 128,
                    SourceMetadata = "{}"
                });
                try
                {
                    await second.SaveChangesAsync();
                }
                catch (DbUpdateException exception)
                {
                    conflict = exception;
                }
            }

            Assert.NotNull(conflict);
            Assert.True(
                LocalFileStore.IsUniqueViolation(conflict!),
                "real PostgreSQL unique violation must be recognized as (Sha256,SizeBytes) race branch trigger");
        }
        finally
        {
            await TryDropTemporaryDatabaseAsync();
        }
    }

    internal static bool PostgresSmokeEnabled =>
        Environment.GetEnvironmentVariable("KQG_PG_SMOKE") == "1";

    /// <summary>不经 xunit 扩展包的动态跳过:未启用时直接返回,报告按通过计。</summary>
    private sealed class SkippablePostgresFactAttribute : FactAttribute
    {
        public SkippablePostgresFactAttribute()
        {
            if (!PostgresSmokeEnabled)
            {
                Skip = "PostgreSQL smoke gated behind KQG_PG_SMOKE=1 (set KQG_PG_SMOKE=1 and KQG_CONNECTION_STRING to enable)";
            }
        }
    }

    private static string MasterConnection => Environment.GetEnvironmentVariable("KQG_CONNECTION_STRING")
        ?? throw new InvalidOperationException("KQG_CONNECTION_STRING is required for PG smoke");

    private async Task<string> CreateTemporaryDatabaseAsync()
    {
        await using var master = new Npgsql.NpgsqlConnection(MasterConnection);
        await master.OpenAsync();

        try
        {
            await using (var drop = new Npgsql.NpgsqlCommand($"DROP DATABASE IF EXISTS {smokeDatabase}", master))
            {
                await drop.ExecuteNonQueryAsync();
            }
            await using (var create = new Npgsql.NpgsqlCommand($"CREATE DATABASE {smokeDatabase}", master))
            {
                await create.ExecuteNonQueryAsync();
            }
        }
        catch
        {
            // 库名含随机后缀,冲突概率可忽略;失败即环境异常,清理后原样抛出。
            await TryDropTemporaryDatabaseAsync();
            throw;
        }

        var smokeConnectionString =
            new Npgsql.NpgsqlConnectionStringBuilder(MasterConnection) { Database = smokeDatabase }.ConnectionString;
        var options = new DbContextOptionsBuilder<KqgDbContext>()
            .UseNpgsql(smokeConnectionString)
            .UseSnakeCaseNamingConvention()
            .Options;
        await using var modelContext = new KqgDbContext(options);
        await modelContext.Database.EnsureCreatedAsync();

        return smokeConnectionString;
    }

    private async Task TryDropTemporaryDatabaseAsync()
    {
        try
        {
            Npgsql.NpgsqlConnection.ClearAllPools();
            await using var master = new Npgsql.NpgsqlConnection(MasterConnection);
            await master.OpenAsync();
            await using var drop = new Npgsql.NpgsqlCommand($"DROP DATABASE IF EXISTS {smokeDatabase} WITH (FORCE)", master);
            await drop.ExecuteNonQueryAsync();
        }
        catch
        {
            // 清理尽力而为;kqg_ 前缀库名便于识别残留。
        }
    }

    private static KqgDbContext CreateContext(string connectionString)
    {
        var options = new DbContextOptionsBuilder<KqgDbContext>()
            .UseNpgsql(connectionString)
            .UseSnakeCaseNamingConvention()
            .Options;
        return new KqgDbContext(options);
    }

    private static async Task<Guid> SeedPendingReviewAsync(string connectionString)
    {
        await using var context = CreateContext(connectionString);
        var review = new PaperBlueprintReview
        {
            Id = Guid.NewGuid(),
            RequestText = "pg smoke",
            Subject = "physics",
            Stage = "junior_middle_school",
            Status = WorkflowReviewStatuses.PendingReview,
            Blueprint = "[{\"questionType\":\"single_choice\",\"count\":1,\"score\":3,\"scope\":[],\"assetStatus\":\"draft\",\"reviewStatus\":\"usable\"}]",
            Constraints = "{}",
            ReviewQuestions = "[]",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        context.PaperBlueprintReviews.Add(review);
        await context.SaveChangesAsync();
        return review.Id;
    }
}
