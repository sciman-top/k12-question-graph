using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using Microsoft.Extensions.DependencyInjection;

namespace K12QuestionGraph.Api.Tests;

/// <summary>
/// 2026-08-23 独立评审 P1 回归护栏:/review-queue 的 question_no 与
/// year_question_no 排序必须作用于全匹配集——曾引入"最近 2000 行扫描
/// 窗口"导致 order=asc 时更早记录永远不可达,而 totalCount 仍声称全集。
/// 本测试把"最早创建且全局排序键最小"的行放在窗口之外(第 2050 条),
/// 断言 asc 排序仍以它开头。
/// </summary>
public sealed class ReviewQueueListGlobalSortTests : IClassFixture<AuditedActorIdentityHttpTests.ActorFactory>
{
    private readonly AuditedActorIdentityHttpTests.ActorFactory factory;

    public ReviewQueueListGlobalSortTests(AuditedActorIdentityHttpTests.ActorFactory factory)
    {
        this.factory = factory;
    }

    [Fact]
    public async Task ListReviewQueue_SortsAcrossEntireMatchedSetBeyondAnyScanWindow()
    {
        const int seededCount = 2050;
        var probeReviewType = $"global_sort_probe_{Guid.NewGuid():N}";
        using (var scope = factory.Services.CreateScope())
        {
            var dbContext = scope.ServiceProvider.GetRequiredService<KqgDbContext>();
            await dbContext.Database.EnsureCreatedAsync();
            var now = DateTimeOffset.UtcNow;
            // index 0 是最早创建、questionNo/year 全局最小的行;其余行排序键更大,
            // 任何"只扫最近 N 行"的实现都无法把它排到首位。
            var seededItems = Enumerable.Range(0, seededCount)
                .Select(index => new ReviewQueueItem
                {
                    ReviewType = probeReviewType,
                    Status = ReviewStatuses.Open,
                    Payload = $$"""{"year":{{(index == 0 ? 2000 : 2016)}},"questionNo":{{index + 1}},"confidence":0.9}""",
                    CreatedAt = now.AddSeconds(index)
                })
                .ToArray();
            dbContext.ReviewQueueItems.AddRange(seededItems);
            await dbContext.SaveChangesAsync();
        }

        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-KQG-Admin-Key", AuditedActorIdentityHttpTests.ActorFactory.ApiKey);

        var byQuestionNo = await GetListAsync(client, probeReviewType, "question_no");
        var byYearQuestionNo = await GetListAsync(client, probeReviewType, "year_question_no");

        Assert.Equal(seededCount, byQuestionNo.GetProperty("totalCount").GetInt32());
        AssertFirstItem(byQuestionNo, expectedQuestionNo: 1);
        AssertFirstItem(byYearQuestionNo, expectedQuestionNo: 1);
    }

    private static async Task<JsonElement> GetListAsync(
        HttpClient client,
        string probeReviewType,
        string sortBy)
    {
        var response = await client.GetAsync(
            $"/review-queue?status=open&reviewType={probeReviewType}&sortBy={sortBy}&order=asc&limit=100");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return await response.Content.ReadFromJsonAsync<JsonElement>();
    }

    private static void AssertFirstItem(JsonElement payload, int expectedQuestionNo)
    {
        var items = payload.GetProperty("items");
        Assert.True(items.GetArrayLength() > 0);
        var first = items[0];
        var questionNo = first.GetProperty("payload").GetProperty("questionNo").GetInt32();
        Assert.Equal(expectedQuestionNo, questionNo);
    }
}
