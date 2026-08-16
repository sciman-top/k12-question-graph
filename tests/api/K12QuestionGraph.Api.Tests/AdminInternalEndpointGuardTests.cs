using K12QuestionGraph.Api.Security;
using Microsoft.AspNetCore.Http;

namespace K12QuestionGraph.Api.Tests;

public class AdminInternalEndpointGuardTests
{
    [Theory]
    [InlineData("/api/admin/ai/provider-settings", true)]
    [InlineData("/internal/ai/model-route", true)]
    [InlineData("/source-documents/27f5ad82-0ee9-4920-b4b8-b844551f35c6/authorization", true)]
    [InlineData("/source-documents/27f5ad82-0ee9-4920-b4b8-b844551f35c6/preview", false)]
    [InlineData("/questions", false)]
    public void RequiresGuard_CoversAdminAndSourceAuthorizationPaths(string path, bool expected)
    {
        Assert.Equal(expected, AdminInternalEndpointGuard.RequiresGuard(new PathString(path)));
    }
}
