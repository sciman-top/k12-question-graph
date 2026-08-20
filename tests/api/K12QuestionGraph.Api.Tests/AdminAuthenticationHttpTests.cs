using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace K12QuestionGraph.Api.Tests;

public sealed class AdminAuthenticationHttpTests : IClassFixture<AdminAuthenticationHttpTests.KqgWebFactory>
{
    private readonly KqgWebFactory factory;

    public AdminAuthenticationHttpTests(KqgWebFactory factory)
    {
        this.factory = factory;
    }

    [Fact]
    public async Task ProtectedEndpoint_RejectsAnonymousRequestInDevelopment()
    {
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/api/admin/storage/summary");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.DoesNotContain("draft-test-unguarded", response.Headers.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task SessionLogin_UsesHttpOnlyCookieForSubsequentProtectedRequest()
    {
        using var client = factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            HandleCookies = true,
            BaseAddress = new Uri("https://localhost")
        });

        var login = await client.PostAsJsonAsync("/auth/session", new { apiKey = KqgWebFactory.ApiKey });
        var protectedResponse = await client.GetAsync("/api/admin/storage/summary");

        Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        Assert.Contains(login.Headers, header =>
            string.Equals(header.Key, "Set-Cookie", StringComparison.OrdinalIgnoreCase) &&
            string.Join(';', header.Value).Contains("httponly", StringComparison.OrdinalIgnoreCase));
        Assert.Equal(HttpStatusCode.OK, protectedResponse.StatusCode);
    }

    [Fact]
    public async Task TeacherCredential_CannotReachCurriculumReviewWriteEndpoint()
    {
        using var client = factory.WithWebHostBuilder(builder =>
            builder.ConfigureAppConfiguration((_, configuration) =>
                configuration.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["AdminInternalGuard:TrustedRole"] = "teacher",
                    ["AdminInternalGuard:TrustedOperatorId"] = "teacher-http-test"
                })))
            .CreateClient();
        client.DefaultRequestHeaders.Add("X-KQG-Admin-Key", KqgWebFactory.ApiKey);

        var response = await client.PostAsJsonAsync(
            "/knowledge-evidence/reviews/decisions",
            new
            {
                candidateType = "asset",
                candidateId = Guid.NewGuid(),
                decision = "approve",
                reviewer = "forged-admin",
                reason = "test",
                actorRole = "administrator"
            });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    public sealed class KqgWebFactory : WebApplicationFactory<Program>
    {
        internal const string ApiKey = "http-integration-test-secret";

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, configuration) =>
                configuration.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["AdminInternalGuard:ApiKey"] = ApiKey,
                    ["AdminInternalGuard:AllowUnguardedDraftTest"] = "false",
                    ["AdminInternalGuard:TrustedRole"] = "admin",
                    ["AdminInternalGuard:TrustedOperatorId"] = "http-test-admin",
                    ["AdminInternalRoleAudit:Enabled"] = "false"
                }));
        }
    }
}
