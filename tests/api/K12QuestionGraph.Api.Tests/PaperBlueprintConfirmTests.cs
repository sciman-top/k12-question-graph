using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace K12QuestionGraph.Api.Tests;

/// <summary>
/// 蓝图确认链路的原子性与并发确认护栏:
/// 1. 确认成功才创建篮子/条目并写确认字段;
/// 2. 抢占失败(并发确认已关闭 review)返回冲突且不产生第二个篮子;
/// 3. 确认持久化失败时不留下篮子/条目孤儿(生产 PostgreSQL 上由同一事务回滚
///    保证;InMemory 忽略事务,本测试只断言孤儿为零,不断言 review 回退状态)。
/// 抢占接缝以 InMemory 镜像替换条件 ExecuteUpdate(与 WorkerSmokeEndpointTests
/// 的租约镜像同一模式)。
/// </summary>
public sealed class PaperBlueprintConfirmTests
{
    [Fact]
    public async Task Confirm_CreatesBasketItemsAndConfirmedReview()
    {
        using var context = CreateContext();
        var (service, reviewId) = await CreateReviewWithPoolAsync(context, questionCount: 2);

        var result = await service.ConfirmBlueprintReviewAsync(reviewId, "teacher-1", CancellationToken.None);

        Assert.NotNull(result);
        Assert.True(result.Confirmed);
        Assert.Equal("confirmed", result.Status);
        var basket = await context.PaperBaskets.AsNoTracking().SingleAsync();
        Assert.Equal(basket.Id, result.PaperBasketId);
        Assert.Equal(2, await context.PaperBasketItems.AsNoTracking().CountAsync(x => x.PaperBasketId == basket.Id));
        var review = await context.PaperBlueprintReviews.AsNoTracking().SingleAsync(x => x.Id == reviewId);
        Assert.Equal("confirmed", review.Status);
        Assert.Equal(basket.Id, review.ConfirmedPaperBasketId);
        Assert.Equal("teacher-1", review.TeacherConfirmedBy);
    }

    [Fact]
    public async Task SecondConfirm_ReturnsConflictAndCreatesNoSecondBasket()
    {
        using var context = CreateContext();
        var (service, reviewId) = await CreateReviewWithPoolAsync(context, questionCount: 1);

        var first = await service.ConfirmBlueprintReviewAsync(reviewId, "teacher-1", CancellationToken.None);
        var second = await service.ConfirmBlueprintReviewAsync(reviewId, "teacher-2", CancellationToken.None);

        Assert.NotNull(first);
        Assert.True(first.Confirmed);
        Assert.NotNull(second);
        Assert.False(second.Confirmed);
        Assert.Equal("blueprint_already_closed", second.ErrorCode);
        Assert.Equal(1, await context.PaperBaskets.AsNoTracking().CountAsync());
        var review = await context.PaperBlueprintReviews.AsNoTracking().SingleAsync(x => x.Id == reviewId);
        Assert.Equal("teacher-1", review.TeacherConfirmedBy);
    }

    [Fact]
    public async Task Confirm_WhenClaimLost_ReturnsConflictWithoutCreatingBasket()
    {
        using var context = CreateContext();
        var (_, reviewId) = await CreateReviewWithPoolAsync(context, questionCount: 1);
        // 另一请求已抢先确认:镜像抢占闸门对本 context 只能看到非 pending_review。
        var loserStore = new RefusingPaperBlueprintConfirmClaimStore();
        var loser = new PaperWorkflowService(context, null!, loserStore);

        var result = await loser.ConfirmBlueprintReviewAsync(reviewId, "teacher-2", CancellationToken.None);

        Assert.NotNull(result);
        Assert.False(result.Confirmed);
        Assert.Equal("blueprint_already_closed", result.ErrorCode);
        Assert.Equal(0, await context.PaperBaskets.AsNoTracking().CountAsync());
        Assert.Equal(0, await context.PaperBasketItems.AsNoTracking().CountAsync());
    }

    [Fact]
    public async Task Confirm_WhenPersistenceFails_LeavesNoBasketOrItemOrphans()
    {
        var databaseName = $"paper-confirm-failure-{Guid.NewGuid():N}";
        using var context = CreateContext(databaseName);
        var (_, reviewId) = await CreateReviewWithPoolAsync(context, questionCount: 1);
        var service = new PaperWorkflowService(context, null!, new InMemoryPaperBlueprintConfirmClaimStore());

        // 模拟第二阶段持久化失败:待写入包含新增篮子/条目时提交抛出。抢占镜像的
        // SaveChanges 不含篮子,可正常通过,从而精确命中确认提交一步。
        Task<int> ThrowingSave(CancellationToken cancellationToken)
            => context.ChangeTracker.Entries().Any(entry =>
                    entry.Entity is PaperBasket or PaperBasketItem && entry.State == EntityState.Added)
                ? throw new InvalidOperationException("simulated confirm persistence failure")
                : context.SaveChangesAsync(cancellationToken);

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => service.ConfirmBlueprintReviewAsync(reviewId, "teacher-1", CancellationToken.None, ThrowingSave));

        using var fresh = CreateContext(databaseName);
        Assert.Equal(0, await fresh.PaperBaskets.AsNoTracking().CountAsync());
        Assert.Equal(0, await fresh.PaperBasketItems.AsNoTracking().CountAsync());
    }

    [Theory]
    [InlineData("blueprint_empty")]
    [InlineData("preview_blueprint_cannot_create_formal_basket")]
    [InlineData("evidence_constraints_insufficient")]
    public async Task Confirm_ValidationEarlyReturn_KeepsReviewPendingInResponseAndDatabase(string expectedError)
    {
        const string previewConstraints = "{\"evidence\":{\"evidenceMode\":\"active\",\"previewMode\":true,\"matchedQuestionIds\":[],\"versionReferences\":[],\"explanation\":[],\"shortages\":[],\"retrospectiveAlignmentCount\":0}}";
        const string shortageConstraints = "{\"evidence\":{\"evidenceMode\":\"active\",\"previewMode\":false,\"matchedQuestionIds\":[],\"versionReferences\":[],\"explanation\":[],\"shortages\":[{\"dimension\":\"knowledge\",\"required\":3,\"available\":0,\"reason\":\"insufficient\"}],\"retrospectiveAlignmentCount\":0}}";
        var constraintsJson = expectedError switch
        {
            "preview_blueprint_cannot_create_formal_basket" => previewConstraints,
            "evidence_constraints_insufficient" => shortageConstraints,
            _ => null,
        };
        using var context = CreateContext();
        var (_, reviewId) = await CreateReviewWithPoolAsync(
            context,
            questionCount: 1,
            blueprintJson: expectedError == "blueprint_empty" ? "[]" : null,
            constraintsJson: constraintsJson);
        var service = new PaperWorkflowService(context, null!, new InMemoryPaperBlueprintConfirmClaimStore());

        var result = await service.ConfirmBlueprintReviewAsync(reviewId, "teacher-1", CancellationToken.None);

        Assert.NotNull(result);
        Assert.False(result.Confirmed);
        Assert.Equal(expectedError, result.ErrorCode);
        // 早退发生在抢占之前:响应与数据库都必须保持 pending_review。
        Assert.Equal(WorkflowReviewStatuses.PendingReview, result.Status);
        var review = await context.PaperBlueprintReviews.AsNoTracking().SingleAsync(x => x.Id == reviewId);
        Assert.Equal(WorkflowReviewStatuses.PendingReview, review.Status);
        Assert.Equal(0, await context.PaperBaskets.AsNoTracking().CountAsync());
    }

    [Fact]
    public async Task Confirm_WhenQuestionPoolInsufficient_KeepsReviewPendingWithoutClaimOrBasket()
    {
        using var context = CreateContext();
        var (_, reviewId) = await CreateReviewWithPoolAsync(context, questionCount: 1, blueprintCount: 3);
        var service = new PaperWorkflowService(context, null!, new InMemoryPaperBlueprintConfirmClaimStore());

        var result = await service.ConfirmBlueprintReviewAsync(reviewId, "teacher-1", CancellationToken.None);

        Assert.NotNull(result);
        Assert.False(result.Confirmed);
        Assert.Equal("question_pool_insufficient", result.ErrorCode);
        Assert.Equal(WorkflowReviewStatuses.PendingReview, result.Status);
        var review = await context.PaperBlueprintReviews.AsNoTracking().SingleAsync(x => x.Id == reviewId);
        Assert.Equal(WorkflowReviewStatuses.PendingReview, review.Status);
        Assert.Equal(0, await context.PaperBaskets.AsNoTracking().CountAsync());
    }

    private static KqgDbContext CreateContext(string? name = null)
    {
        var options = new DbContextOptionsBuilder<KqgDbContext>()
            .UseInMemoryDatabase(name ?? $"paper-confirm-{Guid.NewGuid():N}")
            .ConfigureWarnings(warnings => warnings.Ignore(InMemoryEventId.TransactionIgnoredWarning))
            .Options;
        return new KqgDbContext(options);
    }

    private static async Task<(PaperWorkflowService Service, Guid ReviewId)> CreateReviewWithPoolAsync(
        KqgDbContext context,
        int questionCount,
        string? blueprintJson = null,
        string? constraintsJson = null,
        int blueprintCount = -1)
    {
        var review = new PaperBlueprintReview
        {
            Id = Guid.NewGuid(),
            RequestText = "生成一份初二物理力学练习卷",
            Subject = "physics",
            Stage = "junior_middle_school",
            Status = WorkflowReviewStatuses.PendingReview,
            Blueprint = blueprintJson ?? $$"""
                [{"questionType":"single_choice","count":{{(blueprintCount < 0 ? questionCount : blueprintCount)}},"score":3,"scope":["力学"],"assetStatus":"draft","reviewStatus":"usable"}]
                """,
            Constraints = constraintsJson ?? "{}",
            ReviewQuestions = "[]",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        context.PaperBlueprintReviews.Add(review);
        for (var index = 0; index < questionCount; index++)
        {
            context.QuestionItems.Add(new QuestionItem
            {
                Subject = "physics",
                Stage = "junior_middle_school",
                Status = QuestionStatuses.Usable,
                QuestionType = "single_choice",
                Blocks = "[]",
                CustomFields = "{}",
                QualitySignals = "{}",
                CreatedAt = DateTimeOffset.UtcNow,
                UpdatedAt = DateTimeOffset.UtcNow
            });
        }

        await context.SaveChangesAsync();
        return (new PaperWorkflowService(context, null!, new InMemoryPaperBlueprintConfirmClaimStore()), review.Id);
    }

    /// <summary>
    /// 条件 ExecuteUpdate 抢占的 InMemory 镜像:同一守卫(仅 pending_review 可抢占)。
    /// InMemory 无原子条件更新,真实并发语义由 PostgreSQL 上的默认实现保证。
    /// </summary>
    private sealed class InMemoryPaperBlueprintConfirmClaimStore : IPaperBlueprintConfirmClaimStore
    {
        public async Task<bool> TryClaimAsync(
            KqgDbContext dbContext,
            Guid blueprintReviewId,
            string teacherConfirmedBy,
            DateTimeOffset now,
            CancellationToken cancellationToken)
        {
            var review = await dbContext.PaperBlueprintReviews
                .FirstAsync(x => x.Id == blueprintReviewId, cancellationToken);
            if (!string.Equals(review.Status, WorkflowReviewStatuses.PendingReview, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            review.Status = WorkflowReviewStatuses.Confirmed;
            review.TeacherConfirmedBy = teacherConfirmedBy;
            review.TeacherConfirmedAt = now;
            review.UpdatedAt = now;
            await dbContext.SaveChangesAsync(cancellationToken);
            return true;
        }
    }

    private sealed class RefusingPaperBlueprintConfirmClaimStore : IPaperBlueprintConfirmClaimStore
    {
        public Task<bool> TryClaimAsync(
            KqgDbContext dbContext,
            Guid blueprintReviewId,
            string teacherConfirmedBy,
            DateTimeOffset now,
            CancellationToken cancellationToken)
            => Task.FromResult(false);
    }
}
