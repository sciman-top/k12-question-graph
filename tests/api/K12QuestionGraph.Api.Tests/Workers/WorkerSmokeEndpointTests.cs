using System.Text.Json;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.ImportJobs;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace K12QuestionGraph.Api.Tests;

/// <summary>
/// /imports/{id}/worker-smoke 的端点级编排测试:走真实路由、真实 worker.py 子进程与
/// 候选物化;租约数据访问替换为 InMemory 兼容实现(原子 ExecuteUpdate 语义的镜像),
/// 详见 ImportJobLeaseStore 注释与 docs/18_TestStrategy.md 的 PostgreSQL 边界。
/// </summary>
public class WorkerSmokeEndpointTests
{
    [Fact]
    public async Task WorkerSmoke_MaterializesCandidatesThenRejectsReplay()
    {
        await using var harness = await WorkerSmokeHarness.CreateAsync();
        var (jobId, _) = await harness.SeedImportAsync("original/physics.docx", withSourceDocument: true);
        var client = harness.CreateClient();

        var first = await client.PostAsync($"/imports/{jobId}/worker-smoke", null);
        Assert.Equal(System.Net.HttpStatusCode.OK, first.StatusCode);
        using var firstBody = JsonDocument.Parse(await first.Content.ReadAsStringAsync());
        var firstRoot = firstBody.RootElement;
        Assert.Equal("succeeded", firstRoot.GetProperty("status").GetString());
        Assert.Equal(0, firstRoot.GetProperty("exitCode").GetInt32());
        Assert.Equal(3, firstRoot.GetProperty("processing").GetProperty("cutCandidateCount").GetInt32());
        Assert.Equal(2, firstRoot.GetProperty("processing").GetProperty("lowConfidenceReviewQueueCount").GetInt32());

        await using var dbContext = harness.CreateDbContext();
        var job = await dbContext.ImportJobs.SingleAsync(x => x.Id == jobId);
        Assert.Equal(JobStatuses.Succeeded, job.Status);
        Assert.Null(job.LockedBy);
        Assert.Null(job.LockedUntil);
        Assert.NotNull(job.FinishedAt);

        var candidates = await dbContext.CutCandidates.ToListAsync();
        Assert.Equal(3, candidates.Count);
        Assert.All(candidates, candidate => Assert.Contains("document_worker_local", candidate.Metadata));
        Assert.Equal(2, await dbContext.ReviewQueueItems.CountAsync());

        var replay = await client.PostAsync($"/imports/{jobId}/worker-smoke", null);
        Assert.Equal(System.Net.HttpStatusCode.Conflict, replay.StatusCode);
        using var replayBody = JsonDocument.Parse(await replay.Content.ReadAsStringAsync());
        Assert.Equal(
            "worker_replay_requires_new_generation",
            replayBody.RootElement.GetProperty("error").GetString());
    }

    [Fact]
    public async Task WorkerSmoke_SimulateFailureMarksJobFailedWithoutMaterialization()
    {
        await using var harness = await WorkerSmokeHarness.CreateAsync();
        var (jobId, _) = await harness.SeedImportAsync("original/physics.docx", withSourceDocument: true);
        var client = harness.CreateClient();

        var response = await client.PostAsync($"/imports/{jobId}/worker-smoke?simulateFailure=true", null);

        Assert.Equal(System.Net.HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("failed", body.RootElement.GetProperty("status").GetString());
        Assert.Equal(2, body.RootElement.GetProperty("exitCode").GetInt32());

        await using var dbContext = harness.CreateDbContext();
        var job = await dbContext.ImportJobs.SingleAsync(x => x.Id == jobId);
        Assert.Equal(JobStatuses.Failed, job.Status);
        Assert.Equal("worker_failed", job.LastErrorCode);
        Assert.Null(job.LockedBy);
        Assert.Equal(0, await dbContext.CutCandidates.CountAsync());
    }

    [Fact]
    public async Task WorkerSmoke_RejectsWhenLeaseStillHeld()
    {
        await using var harness = await WorkerSmokeHarness.CreateAsync();
        var (jobId, _) = await harness.SeedImportAsync("original/physics.docx", withSourceDocument: true);
        await using (var dbContext = harness.CreateDbContext())
        {
            var job = await dbContext.ImportJobs.SingleAsync(x => x.Id == jobId);
            job.Status = JobStatuses.Running;
            job.LockedBy = "document-worker:other";
            job.LockedUntil = DateTimeOffset.UtcNow.AddMinutes(4);
            await dbContext.SaveChangesAsync();
        }

        var response = await harness.CreateClient().PostAsync($"/imports/{jobId}/worker-smoke", null);

        Assert.Equal(System.Net.HttpStatusCode.Conflict, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("worker_lease_unavailable", body.RootElement.GetProperty("error").GetString());
    }

    [Fact]
    public async Task WorkerSmoke_ReturnsConflictWhenMaterializationLeaseLost()
    {
        await using var harness = await WorkerSmokeHarness.CreateAsync();
        harness.LeaseStore.FailRenew = true;
        var (jobId, _) = await harness.SeedImportAsync("original/physics.docx", withSourceDocument: true);

        var response = await harness.CreateClient().PostAsync($"/imports/{jobId}/worker-smoke", null);

        Assert.Equal(System.Net.HttpStatusCode.Conflict, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("worker_lease_lost", body.RootElement.GetProperty("error").GetString());
        await using var dbContext = harness.CreateDbContext();
        Assert.Equal(0, await dbContext.CutCandidates.CountAsync());
    }

    [Fact]
    public async Task WorkerSmoke_FailsCleanWhenWorkerOutputIsNotJson()
    {
        await using var harness = await WorkerSmokeHarness.CreateAsync(workerStubCode: "import sys\nsys.stdout.write('not-json {{{ partial')\nsys.stdout.flush()\n");
        var (jobId, _) = await harness.SeedImportAsync("original/physics.docx", withSourceDocument: true);

        var response = await harness.CreateClient().PostAsync($"/imports/{jobId}/worker-smoke", null);

        Assert.Equal(System.Net.HttpStatusCode.OK, response.StatusCode);
        await using var dbContext = harness.CreateDbContext();
        var job = await dbContext.ImportJobs.SingleAsync(x => x.Id == jobId);
        Assert.Equal(JobStatuses.Failed, job.Status);
        Assert.Equal("worker_output_invalid_json", job.LastErrorCode);
        Assert.Null(job.LockedBy);
        Assert.Equal(0, await dbContext.CutCandidates.CountAsync());
    }

    [Fact]
    public async Task WorkerSmoke_MissingJobReturns404AndMissingFileAssetReturns409()
    {
        await using var harness = await WorkerSmokeHarness.CreateAsync();

        var missingJob = await harness.CreateClient().PostAsync($"/imports/{Guid.NewGuid()}/worker-smoke", null);
        Assert.Equal(System.Net.HttpStatusCode.NotFound, missingJob.StatusCode);

        // 任务指向不存在的 file asset,覆盖 input_file_asset_missing 分支。
        var (jobId, _) = await harness.SeedImportAsync("original/ghost.docx", withSourceDocument: false, withFileAsset: false);

        var response = await harness.CreateClient().PostAsync($"/imports/{jobId}/worker-smoke", null);
        Assert.Equal(System.Net.HttpStatusCode.Conflict, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("input_file_asset_missing", body.RootElement.GetProperty("error").GetString());
    }

    private sealed class WorkerSmokeHarness : IAsyncDisposable
    {
        private readonly WebApplicationFactory<Program> _factory;

        private WorkerSmokeHarness(WebApplicationFactory<Program> factory, string fileStoreRoot, InMemoryImportJobLeaseStore leaseStore)
        {
            _factory = factory;
            FileStoreRoot = fileStoreRoot;
            LeaseStore = leaseStore;
        }

        public string FileStoreRoot { get; }

        public InMemoryImportJobLeaseStore LeaseStore { get; }

        public static async Task<WorkerSmokeHarness> CreateAsync(string? workerStubCode = null)
        {
            var fileStoreRoot = WorkerTestHarness.CreateTempDirectory();
            Directory.CreateDirectory(Path.Combine(fileStoreRoot, "original"));
            WorkerTestHarness.WriteMinimalDocx(
                Path.Combine(fileStoreRoot, "original", "physics.docx"),
                "1. 下列关于声现象的说法正确的是",
                "A. 声音由物体振动产生",
                "答案:B");

            var workerScript = WorkerTestHarness.WorkerScript.Value;
            if (workerStubCode is not null)
            {
                workerScript = Path.Combine(fileStoreRoot, "garbage_stub.py");
                WorkerTestHarness.WriteStubScript(fileStoreRoot, "garbage_stub.py", workerStubCode);
            }

            var leaseStore = new InMemoryImportJobLeaseStore();
            var databaseName = $"worker-smoke-tests-{Guid.NewGuid():N}";
            var factory = new WorkerSmokeFactory(fileStoreRoot, workerScript, leaseStore, databaseName);
            using var scope = factory.Services.CreateScope();
            // 触发宿主构建,确保配置在首个请求前生效。
            _ = scope.ServiceProvider.GetRequiredService<KqgDbContext>();
            return new WorkerSmokeHarness(factory, fileStoreRoot, leaseStore);
        }

        public HttpClient CreateClient()
        {
            var client = _factory.CreateClient();
            client.DefaultRequestHeaders.Add("X-KQG-Admin-Key", WorkerSmokeFactory.ApiKey);
            return client;
        }

        public KqgDbContext CreateDbContext()
        {
            var scope = _factory.Services.CreateScope();
            return scope.ServiceProvider.GetRequiredService<KqgDbContext>();
        }

        public async Task<(Guid JobId, Guid FileAssetId)> SeedImportAsync(
            string relativePath,
            bool withSourceDocument,
            bool withFileAsset = true)
        {
            using var scope = _factory.Services.CreateScope();
            var dbContext = scope.ServiceProvider.GetRequiredService<KqgDbContext>();
            var fileAssetId = Guid.NewGuid();
            if (withFileAsset)
            {
                dbContext.FileAssets.Add(new FileAsset
                {
                    Id = fileAssetId,
                    RelativePath = relativePath,
                    OriginalFileName = "physics.docx",
                });
            }
            var job = new ImportJob { Id = Guid.NewGuid(), InputFileAssetId = fileAssetId };
            dbContext.ImportJobs.Add(job);
            if (withSourceDocument && withFileAsset)
            {
                dbContext.SourceDocuments.Add(new SourceDocument
                {
                    Id = Guid.NewGuid(),
                    FileAssetId = fileAssetId,
                    SourceType = "local_exam_paper",
                });
            }
            await dbContext.SaveChangesAsync();
            return (job.Id, fileAssetId);
        }

        public async ValueTask DisposeAsync()
        {
            await _factory.DisposeAsync();
            WorkerTestHarness.DeleteDirectoryBestEffort(FileStoreRoot);
        }
    }

    private sealed class WorkerSmokeFactory(
        string fileStoreRoot,
        string workerScript,
        InMemoryImportJobLeaseStore leaseStore,
        string databaseName) : WebApplicationFactory<Program>
    {
        internal const string ApiKey = "worker-smoke-test-secret";

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, configuration) =>
                configuration.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["AdminInternalGuard:ApiKey"] = ApiKey,
                    ["AdminInternalGuard:AllowUnguardedDraftTest"] = "false",
                    ["AdminInternalGuard:TrustedRole"] = "admin",
                    ["AdminInternalGuard:TrustedOperatorId"] = "worker-smoke-test",
                    ["AdminInternalRoleAudit:Enabled"] = "false",
                    ["PythonWorker:PythonExecutable"] = WorkerTestHarness.PythonExecutable.Value,
                    ["PythonWorker:DocumentWorkerScript"] = workerScript,
                    ["PythonWorker:TimeoutSeconds"] = "60",
                    ["KqgPaths:FileStoreRoot"] = fileStoreRoot,
                }));
            builder.ConfigureServices((_, services) =>
            {
                // 必须连同 IDbContextOptionsConfiguration 一起移除,否则
                // Npgsql 与 InMemory 双 provider 注册在同一容器内冲突。
                var efRegistrations = services
                    .Where(d =>
                        d.ServiceType == typeof(DbContextOptions<KqgDbContext>) ||
                        d.ServiceType == typeof(KqgDbContext) ||
                        (d.ServiceType.IsGenericType &&
                            d.ServiceType.GetGenericTypeDefinition() == typeof(IDbContextOptionsConfiguration<>)))
                    .ToList();
                foreach (var registration in efRegistrations)
                {
                    services.Remove(registration);
                }
                services.AddDbContext<KqgDbContext>(options =>
                    options.UseInMemoryDatabase(databaseName));

                services.RemoveAll<IImportJobLeaseStore>();
                services.AddSingleton<IImportJobLeaseStore>(leaseStore);
            });
        }
    }

    /// <summary>
    /// ImportJobLeaseService 条件 ExecuteUpdate 的 InMemory 镜像:同一守卫矩阵、
    /// 同一租约时长与归属检查,只是用跟踪实体 + SaveChanges 落地。
    /// </summary>
    internal sealed class InMemoryImportJobLeaseStore : IImportJobLeaseStore
    {
        public bool FailRenew { get; set; }

        public async Task<ImportJobLeaseAttempt> TryAcquireAsync(
            KqgDbContext dbContext,
            Guid jobId,
            bool simulateFailure,
            DateTimeOffset now,
            CancellationToken cancellationToken)
        {
            var job = await dbContext.ImportJobs.FirstOrDefaultAsync(x => x.Id == jobId, cancellationToken);
            if (job is null ||
                !ImportJobLeaseService.CanAcquire(
                    job.Status, simulateFailure, job.AttemptCount, job.MaxAttempts, job.LockedUntil, now))
            {
                return new ImportJobLeaseAttempt(false, null);
            }

            var leaseOwner = $"document-worker:{Guid.NewGuid():N}";
            job.Status = JobStatuses.Running;
            job.StartedAt ??= now;
            job.FinishedAt = null;
            job.AttemptCount += 1;
            job.LockedBy = leaseOwner;
            job.LockedUntil = now.AddMinutes(5);
            await dbContext.SaveChangesAsync(cancellationToken);
            return new ImportJobLeaseAttempt(true, leaseOwner);
        }

        public async Task<bool> RenewForMaterializationAsync(
            KqgDbContext dbContext,
            Guid jobId,
            string leaseOwner,
            DateTimeOffset now,
            CancellationToken cancellationToken)
        {
            if (FailRenew)
            {
                return false;
            }

            var job = await dbContext.ImportJobs.FirstOrDefaultAsync(x => x.Id == jobId, cancellationToken);
            if (job is null || job.Status != JobStatuses.Running || job.LockedBy != leaseOwner)
            {
                return false;
            }

            job.LockedUntil = now.AddMinutes(5);
            await dbContext.SaveChangesAsync(cancellationToken);
            return true;
        }
    }
}
