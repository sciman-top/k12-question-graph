using System.Net;
using System.Security.Claims;
using K12QuestionGraph.Api.Configuration;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;

namespace K12QuestionGraph.Api.Security;

public sealed record AdminSessionLoginRequest(string ApiKey);

public sealed record AdminSessionResponse(
    bool Authenticated,
    string? OperatorId,
    string? Role,
    DateTimeOffset? ExpiresAt);

public static class AdminSessionEndpoints
{
    public static WebApplication MapAdminSessionEndpoints(this WebApplication app)
    {
        app.MapGet("/auth/session", (HttpContext context) =>
            Results.Ok(CurrentSession(context)))
            .AllowAnonymous()
            .WithName("GetAdminSession");

        app.MapPost("/auth/session", async Task<IResult> (
            AdminSessionLoginRequest request,
            HttpContext context,
            IConfiguration configuration) =>
        {
            var options = configuration
                .GetSection("AdminInternalGuard")
                .Get<AdminInternalGuardOptions>() ?? new AdminInternalGuardOptions();
            var configuredKey = options.ApiKey?.Trim();
            if (string.IsNullOrWhiteSpace(configuredKey))
            {
                await AuditLoginAsync(context, configuration, "login_guard_not_configured", StatusCodes.Status503ServiceUnavailable);
                return Results.Json(
                    new { error = "admin_internal_guard_not_configured" },
                    statusCode: StatusCodes.Status503ServiceUnavailable);
            }

            if (!IsSecureSessionRequest(context, options))
            {
                await AuditLoginAsync(context, configuration, "login_https_required", StatusCodes.Status426UpgradeRequired);
                return Results.Json(
                    new { error = "https_required_for_remote_session" },
                    statusCode: StatusCodes.Status426UpgradeRequired);
            }

            var clientKey = context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
            var now = DateTimeOffset.UtcNow;
            if (AdminLoginRateLimiter.IsLockedOut(clientKey, now))
            {
                var retryAfterSeconds = (int)Math.Ceiling(
                    AdminLoginRateLimiter.GetLockoutRemaining(clientKey, now).TotalSeconds);
                await AuditLoginAsync(context, configuration, "login_rate_limited", StatusCodes.Status429TooManyRequests);
                return Results.Json(
                    new { error = "login_rate_limited", retryAfterSeconds },
                    statusCode: StatusCodes.Status429TooManyRequests);
            }

            if (!AdminInternalEndpointGuard.FixedTimeEquals(request.ApiKey?.Trim(), configuredKey))
            {
                AdminLoginRateLimiter.RecordFailure(clientKey, DateTimeOffset.UtcNow);
                await AuditLoginAsync(context, configuration, "login_invalid_key", StatusCodes.Status403Forbidden);
                return Results.Json(
                    new { error = "invalid_admin_internal_key" },
                    statusCode: StatusCodes.Status403Forbidden);
            }

            AdminLoginRateLimiter.RecordSuccess(clientKey);

            var lifetimeMinutes = Math.Clamp(options.SessionLifetimeMinutes, 15, 1440);
            var expiresAt = DateTimeOffset.UtcNow.AddMinutes(lifetimeMinutes);
            var principal = AdminInternalEndpointGuard.CreateTrustedPrincipal(
                options,
                configuredKey,
                CookieAuthenticationDefaults.AuthenticationScheme);
            await context.SignInAsync(
                CookieAuthenticationDefaults.AuthenticationScheme,
                principal,
                new AuthenticationProperties
                {
                    AllowRefresh = true,
                    IsPersistent = false,
                    ExpiresUtc = expiresAt
                });

            await AuditLoginAsync(
                context,
                configuration,
                "login_success",
                StatusCodes.Status200OK,
                principal.FindFirstValue(ClaimTypes.NameIdentifier),
                principal.FindFirstValue(ClaimTypes.Role));

            return Results.Ok(new AdminSessionResponse(
                true,
                principal.FindFirstValue(ClaimTypes.NameIdentifier),
                principal.FindFirstValue(ClaimTypes.Role),
                expiresAt));
        })
        .AllowAnonymous()
        .WithName("CreateAdminSession");

        app.MapDelete("/auth/session", async (HttpContext context) =>
        {
            await context.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
            return Results.NoContent();
        })
        .AllowAnonymous()
        .WithName("DeleteAdminSession");

        return app;
    }

    internal static bool IsSecureSessionRequest(HttpContext context, AdminInternalGuardOptions options)
    {
        if (!options.RequireHttpsForRemoteSessions || context.Request.IsHttps)
        {
            return true;
        }

        var remoteAddress = context.Connection.RemoteIpAddress;
        return remoteAddress is not null && IPAddress.IsLoopback(remoteAddress);
    }

    // 登录失败退避只在当前进程内计数:单机试点足够;多实例部署需换共享存储,
    // 不得以此内存计数冒充分布式防护。审计不记录 API key、Cookie 或其指纹。
    private static async Task AuditLoginAsync(
        HttpContext context,
        IConfiguration configuration,
        string decision,
        int statusCode,
        string? operatorId = null,
        string? operatorRole = null)
    {
        var roleAuditOptions = configuration
            .GetSection("AdminInternalRoleAudit")
            .Get<AdminInternalRoleAuditOptions>() ?? new AdminInternalRoleAuditOptions();
        if (!roleAuditOptions.Enabled || !roleAuditOptions.EnableAuditLog)
        {
            return;
        }

        try
        {
            var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
            var payload = new
            {
                timestampUtc = DateTimeOffset.UtcNow.ToString("O"),
                path = context.Request.Path.Value,
                method = context.Request.Method,
                operatorRole = string.IsNullOrWhiteSpace(operatorRole) ? "unknown" : operatorRole,
                operatorId = string.IsNullOrWhiteSpace(operatorId) ? "unknown" : operatorId,
                objectRef = context.Request.Path.Value,
                highRisk = true,
                rollbackRef = (string?)null,
                decision,
                statusCode
            };
            await AdminInternalEndpointGuard.WriteAuditEntryAsync(paths, roleAuditOptions.AuditLogFileName, payload);
        }
        catch
        {
            // 审计写入失败不改变登录判定;退避与鉴权仍生效。
        }
    }

    private static AdminSessionResponse CurrentSession(HttpContext context)
    {
        if (context.User.Identity?.IsAuthenticated != true)
        {
            return new AdminSessionResponse(false, null, null, null);
        }

        return new AdminSessionResponse(
            true,
            context.User.FindFirstValue(ClaimTypes.NameIdentifier),
            context.User.FindFirstValue(ClaimTypes.Role),
            null);
    }
}

internal sealed class AdminLoginRateLimiter
{
    private const int FailureThreshold = 5;
    private const int MaxLockoutSeconds = 60;
    private const int MaxTrackedClients = 1024;
    private static readonly object SyncRoot = new();
    private static readonly Dictionary<string, LoginFailureRecord> Failures = new(StringComparer.Ordinal);

    private sealed record LoginFailureRecord(int ConsecutiveFailures, DateTimeOffset LockedUntilUtc, DateTimeOffset LastSeenUtc);

    internal static bool IsLockedOut(string clientKey, DateTimeOffset now)
    {
        lock (SyncRoot)
        {
            return Failures.TryGetValue(clientKey, out var record) && record.LockedUntilUtc > now;
        }
    }

    internal static TimeSpan GetLockoutRemaining(string clientKey, DateTimeOffset now)
    {
        lock (SyncRoot)
        {
            return Failures.TryGetValue(clientKey, out var record) && record.LockedUntilUtc > now
                ? record.LockedUntilUtc - now
                : TimeSpan.Zero;
        }
    }

    internal static void RecordFailure(string clientKey, DateTimeOffset now)
    {
        lock (SyncRoot)
        {
            EvictStaleEntries(now);
            var consecutive = Failures.TryGetValue(clientKey, out var record)
                ? record.ConsecutiveFailures + 1
                : 1;
            var lockedUntil = now;
            if (consecutive >= FailureThreshold)
            {
                // 指数退避: 第 5 次失败锁 1s,之后逐次翻倍,封顶 60s。
                var delaySeconds = Math.Min(
                    1 << Math.Min(consecutive - FailureThreshold, 6),
                    MaxLockoutSeconds);
                lockedUntil = now.AddSeconds(delaySeconds);
            }

            Failures[clientKey] = new LoginFailureRecord(consecutive, lockedUntil, now);
        }
    }

    internal static void RecordSuccess(string clientKey)
    {
        lock (SyncRoot)
        {
            Failures.Remove(clientKey);
        }
    }

    internal static void ResetForTests()
    {
        lock (SyncRoot)
        {
            Failures.Clear();
        }
    }

    private static void EvictStaleEntries(DateTimeOffset now)
    {
        if (Failures.Count <= MaxTrackedClients)
        {
            return;
        }

        var staleKeys = Failures
            .Where(entry => entry.Value.LockedUntilUtc <= now && now - entry.Value.LastSeenUtc > TimeSpan.FromHours(1))
            .Select(entry => entry.Key)
            .ToArray();
        foreach (var key in staleKeys)
        {
            Failures.Remove(key);
        }

        if (Failures.Count > MaxTrackedClients)
        {
            // 有界内存优先于精确计数:极端规模下宁可放过退避也不无界增长。
            Failures.Clear();
        }
    }
}
