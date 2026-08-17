using K12QuestionGraph.Api.Security;
using Microsoft.AspNetCore.Http;

namespace K12QuestionGraph.Api.Tests;

public class AdminInternalEndpointGuardTests
{
    [Theory]
    [InlineData("/api/admin/ai/provider-settings", true)]
    [InlineData("/internal/ai/model-route", true)]
    [InlineData("/source-documents/27f5ad82-0ee9-4920-b4b8-b844551f35c6/authorization", true)]
    [InlineData("/source-documents/27f5ad82-0ee9-4920-b4b8-b844551f35c6/preview", true)]
    [InlineData("/questions", true)]
    [InlineData("/score-imports", true)]
    [InlineData("/health/ready", true)]
    [InlineData("/health", false)]
    [InlineData("/auth/session", false)]
    [InlineData("/", false)]
    public void RequiresGuard_DefaultsDynamicApiPathsToProtected(string path, bool expected)
    {
        Assert.Equal(expected, AdminInternalEndpointGuard.RequiresGuard(new PathString(path)));
    }

    [Theory]
    [InlineData("/questions", "GET", "teacher", true)]
    [InlineData("/questions", "POST", "teacher", true)]
    [InlineData("/questions", "POST", "group_lead", false)]
    [InlineData("/questions", "GET", "group_lead", true)]
    [InlineData("/api/admin/storage/summary", "GET", "group_lead", true)]
    [InlineData("/api/admin/cache/cleanup", "POST", "group_lead", false)]
    [InlineData("/internal/ai/model-route", "POST", "teacher", false)]
    [InlineData("/source-documents/abc/authorization", "PATCH", "teacher", false)]
    public void IsRoleAuthorized_UsesServerPrincipalAndRouteRisk(
        string path,
        string method,
        string role,
        bool expected)
    {
        Assert.Equal(expected, AdminInternalEndpointGuard.IsRoleAuthorized(new PathString(path), method, role));
    }

    [Fact]
    public void CreateTrustedPrincipal_DerivesIdentityFromServerConfiguration()
    {
        var principal = AdminInternalEndpointGuard.CreateTrustedPrincipal(
            new AdminInternalGuardOptions
            {
                TrustedRole = "teacher",
                TrustedOperatorId = "configured-teacher"
            },
            "server-secret",
            "test");

        Assert.Equal("configured-teacher", principal.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value);
        Assert.Equal("teacher", principal.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value);
        Assert.NotNull(principal.FindFirst(AdminInternalEndpointGuard.CredentialFingerprintClaim));
    }
}
