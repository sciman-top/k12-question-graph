using System.Net;
using System.Net.Http.Json;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace K12QuestionGraph.Api.Tests;

/// <summary>
/// 2026-08-23 审计 M1 回归:请求体 ReviewedBy 不得作为业务审计身份来源,
/// 持久化审计必须取服务器解析出的认证 actor;teacher 角色路径不受影响。
/// 使用共享 DatabaseRoot 的 EF InMemory 库做端到端断言,不依赖 PostgreSQL。
/// </summary>
public sealed class AuditedActorIdentityHttpTests : IClassFixture<AuditedActorIdentityHttpTests.ActorFactory>
{
    private readonly ActorFactory factory;

    public AuditedActorIdentityHttpTests(ActorFactory factory)
    {
        this.factory = factory;
    }

    [Fact]
    public async Task ResolveReviewQueue_IgnoresForgedReviewedByAndPersistsServerIdentity()
    {
        var itemId = await SeedOpenReviewItemAsync();
        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-KQG-Admin-Key", ActorFactory.ApiKey);

        var response = await client.PostAsJsonAsync($"/review-queue/{itemId}/resolve", new
        {
            reviewedBy = "forged-teacher-name",
            decision = "resolved",
            reason = "audit identity regression"
        });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var payload = await ReadReviewItemPayloadAsync(itemId);
        Assert.Contains("\"reviewedBy\":\"audited-actor-operator\"", payload);
        Assert.DoesNotContain("forged-teacher-name", payload, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ResolveReviewQueue_TeacherRoleStillSucceedsWithServerIdentity()
    {
        var itemId = await SeedOpenReviewItemAsync();
        using var client = factory.WithWebHostBuilder(builder =>
            builder.ConfigureAppConfiguration((_, configuration) =>
                configuration.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["AdminInternalGuard:TrustedRole"] = "teacher"
                })))
            .CreateClient();
        client.DefaultRequestHeaders.Add("X-KQG-Admin-Key", ActorFactory.ApiKey);

        var response = await client.PostAsJsonAsync($"/review-queue/{itemId}/resolve", new
        {
            decision = "resolved",
            reason = "teacher path must keep working"
        });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var payload = await ReadReviewItemPayloadAsync(itemId);
        Assert.Contains("\"reviewedBy\":\"audited-actor-operator\"", payload);
    }

    [Fact]
    public async Task ResolveReviewQueue_ReviewedByFieldIsNoLongerRequired()
    {
        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-KQG-Admin-Key", ActorFactory.ApiKey);

        var response = await client.PostAsJsonAsync($"/review-queue/{Guid.NewGuid()}/resolve", new
        {
            decision = "resolved",
            reason = "field optional"
        });

        // ReviewedBy 缺省不再返回 400 reviewed_by_required,而是继续执行后命中 404。
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    private async Task<Guid> SeedOpenReviewItemAsync()
    {
        using var scope = factory.Services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<KqgDbContext>();
        await dbContext.Database.EnsureCreatedAsync();
        var item = new ReviewQueueItem
        {
            ReviewType = "cut_candidate",
            Status = ReviewStatuses.Open,
            Payload = "{}",
            CreatedAt = DateTimeOffset.UtcNow
        };
        dbContext.ReviewQueueItems.Add(item);
        await dbContext.SaveChangesAsync();
        return item.Id;
    }

    private async Task<string> ReadReviewItemPayloadAsync(Guid itemId)
    {
        using var scope = factory.Services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<KqgDbContext>();
        var item = await dbContext.ReviewQueueItems.AsNoTracking().SingleAsync(x => x.Id == itemId);
        return item.Payload;
    }

    public sealed class ActorFactory : WebApplicationFactory<Program>
    {
        internal const string ApiKey = "audited-actor-test-secret";

        // 静态 DatabaseRoot 让 WithWebHostBuilder 派生工厂(独立 service provider)
        // 与主工厂共享同一份 InMemory 数据。
        private static readonly InMemoryDatabaseRoot DatabaseRoot = new();

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, configuration) =>
                configuration.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["AdminInternalGuard:ApiKey"] = ApiKey,
                    ["AdminInternalGuard:AllowUnguardedDraftTest"] = "false",
                    ["AdminInternalGuard:TrustedRole"] = "admin",
                    ["AdminInternalGuard:TrustedOperatorId"] = "audited-actor-operator",
                    ["AdminInternalRoleAudit:Enabled"] = "false"
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
                    options.UseInMemoryDatabase("audited-actor-tests", DatabaseRoot));
            });
        }
    }
}
