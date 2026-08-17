using System.Net;
using System.Security.Claims;
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
                return Results.Json(
                    new { error = "admin_internal_guard_not_configured" },
                    statusCode: StatusCodes.Status503ServiceUnavailable);
            }

            if (!IsSecureSessionRequest(context, options))
            {
                return Results.Json(
                    new { error = "https_required_for_remote_session" },
                    statusCode: StatusCodes.Status426UpgradeRequired);
            }

            if (!AdminInternalEndpointGuard.FixedTimeEquals(request.ApiKey?.Trim(), configuredKey))
            {
                return Results.Json(
                    new { error = "invalid_admin_internal_key" },
                    statusCode: StatusCodes.Status403Forbidden);
            }

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
