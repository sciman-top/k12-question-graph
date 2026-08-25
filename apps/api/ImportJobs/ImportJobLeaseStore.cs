using K12QuestionGraph.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace K12QuestionGraph.Api.ImportJobs;

/// <summary>
/// 导入任务租约的数据访问接缝。默认实现委托 <see cref="ImportJobLeaseService"/>(原子条件
/// ExecuteUpdate,语义真源);HTTP 编排通过本接口注入,便于在无关系型 provider 的
/// 测试环境中替换为等价的跟踪实体实现。
/// </summary>
internal interface IImportJobLeaseStore
{
    Task<ImportJobLeaseAttempt> TryAcquireAsync(
        KqgDbContext dbContext,
        Guid jobId,
        bool simulateFailure,
        DateTimeOffset now,
        CancellationToken cancellationToken);

    Task<bool> RenewForMaterializationAsync(
        KqgDbContext dbContext,
        Guid jobId,
        string leaseOwner,
        DateTimeOffset now,
        CancellationToken cancellationToken);
}

internal sealed class ImportJobLeaseStore : IImportJobLeaseStore
{
    public Task<ImportJobLeaseAttempt> TryAcquireAsync(
        KqgDbContext dbContext,
        Guid jobId,
        bool simulateFailure,
        DateTimeOffset now,
        CancellationToken cancellationToken) =>
        ImportJobLeaseService.TryAcquireAsync(dbContext, jobId, simulateFailure, now, cancellationToken);

    public Task<bool> RenewForMaterializationAsync(
        KqgDbContext dbContext,
        Guid jobId,
        string leaseOwner,
        DateTimeOffset now,
        CancellationToken cancellationToken) =>
        ImportJobLeaseService.RenewForMaterializationAsync(dbContext, jobId, leaseOwner, now, cancellationToken);
}
