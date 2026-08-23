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

    [Fact]
    public void LoginRateLimiter_AllowsFewFailures_ThenLocksOutAtThreshold()
    {
        var clientKey = $"unit-{Guid.NewGuid():N}";
        var now = DateTimeOffset.UtcNow;

        for (var i = 0; i < 4; i++)
        {
            AdminLoginRateLimiter.RecordFailure(clientKey, now.AddSeconds(i));
        }
        Assert.False(AdminLoginRateLimiter.IsLockedOut(clientKey, now.AddSeconds(4)));

        AdminLoginRateLimiter.RecordFailure(clientKey, now.AddSeconds(5));
        Assert.True(AdminLoginRateLimiter.IsLockedOut(clientKey, now.AddSeconds(5).AddMilliseconds(500)));
    }

    [Fact]
    public void LoginRateLimiter_SuccessClearsFailureCount()
    {
        var clientKey = $"unit-{Guid.NewGuid():N}";
        var now = DateTimeOffset.UtcNow;

        for (var i = 0; i < 5; i++)
        {
            AdminLoginRateLimiter.RecordFailure(clientKey, now.AddSeconds(i));
        }
        AdminLoginRateLimiter.RecordSuccess(clientKey);

        Assert.False(AdminLoginRateLimiter.IsLockedOut(clientKey, now.AddSeconds(5)));
        Assert.Equal(TimeSpan.Zero, AdminLoginRateLimiter.GetLockoutRemaining(clientKey, now.AddSeconds(5)));
    }

    [Fact]
    public void LoginRateLimiter_LockoutDelayStaysBounded()
    {
        var clientKey = $"unit-{Guid.NewGuid():N}";
        var now = DateTimeOffset.UtcNow;

        for (var i = 0; i < 50; i++)
        {
            AdminLoginRateLimiter.RecordFailure(clientKey, now.AddSeconds(i));
        }

        var remaining = AdminLoginRateLimiter.GetLockoutRemaining(clientKey, now.AddSeconds(50));
        Assert.True(remaining > TimeSpan.Zero);
        Assert.True(remaining <= TimeSpan.FromSeconds(60));
    }
}
