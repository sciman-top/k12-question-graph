using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace K12QuestionGraph.Api.Application.Workflows;

/// <summary>
/// 蓝图确认的串行化闸门。默认实现用条件 ExecuteUpdate 抢占:仅当 review 仍为
/// pending_review 时原子地置为 confirmed 并写入确认人/时间,并发确认只有一个请求
/// 能拿到 1 行,失败方拿 0 行。抢占后整个确认事务要么全部提交,要么回滚恢复
/// pending_review。测试环境可注入 InMemory 兼容镜像(ExecuteUpdate 仅关系型可用)。
/// </summary>
public interface IPaperBlueprintConfirmClaimStore
{
    Task<bool> TryClaimAsync(
        KqgDbContext dbContext,
        Guid blueprintReviewId,
        string teacherConfirmedBy,
        DateTimeOffset now,
        CancellationToken cancellationToken);
}

internal sealed class PaperBlueprintConfirmClaimStore : IPaperBlueprintConfirmClaimStore
{
    public async Task<bool> TryClaimAsync(
        KqgDbContext dbContext,
        Guid blueprintReviewId,
        string teacherConfirmedBy,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var affected = await dbContext.PaperBlueprintReviews
            .Where(x => x.Id == blueprintReviewId && x.Status == WorkflowReviewStatuses.PendingReview)
            .ExecuteUpdateAsync(
                updates => updates
                    .SetProperty(review => review.Status, WorkflowReviewStatuses.Confirmed)
                    .SetProperty(review => review.TeacherConfirmedBy, teacherConfirmedBy)
                    .SetProperty(review => review.TeacherConfirmedAt, now)
                    .SetProperty(review => review.UpdatedAt, now),
                cancellationToken);
        return affected == 1;
    }
}
