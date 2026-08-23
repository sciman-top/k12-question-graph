using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using Microsoft.Extensions.DependencyInjection;

namespace K12QuestionGraph.Api.Tests;

/// <summary>
/// 2026-08-23 审计 L1 回归:/review-queue 不再全量物化匹配行,
/// 排序只在最近 maxScanRows 行内进行,total 用独立 COUNT 保持真实总数。
/// </summary>
public sealed class ReviewQueueListWindowTests : IClassFixture<AuditedActorIdentityHttpTests.ActorFactory>
{
    private readonly AuditedActorIdentityHttpTests.ActorFactory factory;

    public ReviewQueueListWindowTests(AuditedActorIdentityHttpTests.ActorFactory factory)
    {
        this.factory = factory;
    }

    [Fact]
    public async Task ListReviewQueue_BoundsInMemorySortWindowButKeepsTrueTotal()
    {
        const int seededCount = 2050;
        var probeReviewType = $"cap_probe_{Guid.NewGuid():N}";
        using (var scope = factory.Services.CreateScope())
        {
            var dbContext = scope.ServiceProvider.GetRequiredService<KqgDbContext>();
            await dbContext.Database.EnsureCreatedAsync();
            var now = DateTimeOffset.UtcNow;
            var seededItems = Enumerable.Range(0, seededCount)
                .Select(index => new ReviewQueueItem
                {
                    ReviewType = probeReviewType,
                    Status = ReviewStatuses.Open,
                    Payload = $$"""{"questionNo":{{(index % 50) + 1}},"confidence":0.9}""",
                    CreatedAt = now.AddSeconds(index)
                })
                .ToArray();
            dbContext.ReviewQueueItems.AddRange(seededItems);
            await dbContext.SaveChangesAsync();
        }

        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-KQG-Admin-Key", AuditedActorIdentityHttpTests.ActorFactory.ApiKey);

        var response = await client.GetAsync(
            $"/review-queue?status=open&reviewType={probeReviewType}&sortBy=question_no&limit=100");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var payload = await response.Content.ReadFromJsonAsync<JsonElement>();
        var items = payload.GetProperty("items");
        Assert.True(items.GetArrayLength() <= 100, $"expected bounded page, got {items.GetArrayLength()}");
        Assert.Equal(seededCount, payload.GetProperty("totalCount").GetInt32());
    }
}
