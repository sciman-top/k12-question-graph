using System.Net;
using K12QuestionGraph.Api.Security;
using Microsoft.AspNetCore.Http;

namespace K12QuestionGraph.Api.Tests;

public class AdminSessionEndpointsTests
{
    [Fact]
    public void IsSecureSessionRequest_AllowsLoopbackHttpForLocalService()
    {
        var context = new DefaultHttpContext();
        context.Connection.RemoteIpAddress = IPAddress.Loopback;

        Assert.True(AdminSessionEndpoints.IsSecureSessionRequest(context, new AdminInternalGuardOptions()));
    }

    [Fact]
    public void IsSecureSessionRequest_RejectsRemoteHttp()
    {
        var context = new DefaultHttpContext();
        context.Connection.RemoteIpAddress = IPAddress.Parse("192.0.2.10");

        Assert.False(AdminSessionEndpoints.IsSecureSessionRequest(context, new AdminInternalGuardOptions()));
    }

    [Fact]
    public void IsSecureSessionRequest_AllowsRemoteHttps()
    {
        var context = new DefaultHttpContext();
        context.Connection.RemoteIpAddress = IPAddress.Parse("192.0.2.10");
        context.Request.Scheme = "https";

        Assert.True(AdminSessionEndpoints.IsSecureSessionRequest(context, new AdminInternalGuardOptions()));
    }
}
