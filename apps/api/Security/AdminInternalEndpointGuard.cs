using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Net;
using K12QuestionGraph.Api.Configuration;
using Microsoft.AspNetCore.Authorization;

namespace K12QuestionGraph.Api.Security;

public sealed class AdminInternalGuardOptions
{
    public string? ApiKey { get; set; }
    public bool AllowUnguardedDraftTest { get; set; }
    public string TrustedRole { get; set; } = "admin";
    public string TrustedOperatorId { get; set; } = "kqg-local-admin";
    public bool RequireHttpsForRemoteSessions { get; set; } = true;
    public int SessionLifetimeMinutes { get; set; } = 480;
}

public sealed class AdminInternalRoleAuditOptions
{
    public bool Enabled { get; set; } = true;
    public bool EnableAuditLog { get; set; } = true;
    public string AuditLogFileName { get; set; } = "admin-internal-audit.jsonl";
}

public static class AdminInternalEndpointGuard
{
    private static readonly SemaphoreSlim AuditWriteLock = new(1, 1);

    public const string HeaderName = "X-KQG-Admin-Key";
    public const string RoleHeaderName = "X-KQG-Operator-Role";
    public const string OperatorIdHeaderName = "X-KQG-Operator-Id";
    public const string RollbackRefHeaderName = "X-KQG-Rollback-Ref";
    public const string DraftTestHeaderName = "X-KQG-Auth-Boundary";
    public const string DraftTestHeaderValue = "draft-test-unguarded-admin-internal";
    internal const string CredentialFingerprintClaim = "kqg:credential-fingerprint";

    public static WebApplication UseAdminInternalEndpointGuard(this WebApplication app)
    {
        app.Use(async (context, next) =>
        {
            var endpointAllowsAnonymous = context.GetEndpoint()?.Metadata.GetMetadata<IAllowAnonymous>() is not null;
            var requiresGuard = !endpointAllowsAnonymous && RequiresGuard(context.Request.Path);
            var options = app.Configuration
                .GetSection("AdminInternalGuard")
                .Get<AdminInternalGuardOptions>() ?? new AdminInternalGuardOptions();
            var roleAuditOptions = app.Configuration
                .GetSection("AdminInternalRoleAudit")
                .Get<AdminInternalRoleAuditOptions>() ?? new AdminInternalRoleAuditOptions();
            var paths = app.Configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
            var configuredKey = options.ApiKey?.Trim();
            var draftTestBypassAllowed = IsDraftTestBypassAllowed(
                app.Environment.IsDevelopment(),
                options.AllowUnguardedDraftTest,
                context.Connection.LocalIpAddress,
                context.Connection.RemoteIpAddress);
            var isHighRiskWrite = IsHighRiskWrite(context.Request.Method);

            if (!HasCurrentCredential(context.User, configuredKey))
            {
                context.User = new ClaimsPrincipal(new ClaimsIdentity());
            }

            var suppliedInternalKey = context.Request.Headers.TryGetValue(HeaderName, out var keyValues)
                ? keyValues.FirstOrDefault()
                : null;
            if (!IsAuthenticated(context.User) && !string.IsNullOrWhiteSpace(suppliedInternalKey))
            {
                if (string.IsNullOrWhiteSpace(configuredKey) || !FixedTimeEquals(suppliedInternalKey, configuredKey))
                {
                    if (requiresGuard)
                    {
                        context.Response.StatusCode = StatusCodes.Status403Forbidden;
                        await context.Response.WriteAsJsonAsync(new { error = "invalid_admin_internal_key" });
                        return;
                    }
                }
                else
                {
                    context.User = CreateTrustedPrincipal(options, configuredKey, "InternalKey");
                }
            }

            if (!IsAuthenticated(context.User) && draftTestBypassAllowed)
            {
                context.User = CreateDraftTestPrincipal(options);
                context.Response.Headers[DraftTestHeaderName] = DraftTestHeaderValue;
            }

            var operatorRole = NormalizeRole(context.User.FindFirstValue(ClaimTypes.Role));
            var operatorId = context.User.FindFirstValue(ClaimTypes.NameIdentifier)?.Trim() ?? string.Empty;
            var rollbackRef = context.Request.Headers.TryGetValue(RollbackRefHeaderName, out var rollbackValues)
                ? rollbackValues.FirstOrDefault()?.Trim() ?? string.Empty
                : string.Empty;

            async Task AuditAsync(int statusCode, string decision)
            {
                if (!roleAuditOptions.Enabled || !roleAuditOptions.EnableAuditLog)
                {
                    return;
                }

                try
                {
                    Directory.CreateDirectory(paths.LogsRoot);
                    var logPath = Path.Combine(paths.LogsRoot, roleAuditOptions.AuditLogFileName);
                    var payload = new
                    {
                        timestampUtc = DateTimeOffset.UtcNow.ToString("O"),
                        path = context.Request.Path.Value,
                        method = context.Request.Method,
                        operatorRole = string.IsNullOrWhiteSpace(operatorRole) ? "unknown" : operatorRole,
                        operatorId = string.IsNullOrWhiteSpace(operatorId) ? "unknown" : operatorId,
                        objectRef = context.Request.Path.Value,
                        highRisk = isHighRiskWrite,
                        rollbackRef = string.IsNullOrWhiteSpace(rollbackRef) ? null : rollbackRef,
                        decision,
                        statusCode
                    };
                    var line = JsonSerializer.Serialize(payload) + Environment.NewLine;
                    await AuditWriteLock.WaitAsync(CancellationToken.None);
                    try
                    {
                        await File.AppendAllTextAsync(logPath, line, Encoding.UTF8, CancellationToken.None);
                    }
                    finally
                    {
                        AuditWriteLock.Release();
                    }
                }
                catch
                {
                    // 审计写入失败不能压垮业务接口，鉴权判断仍保持 fail-closed。
                }
            }

            async Task ContinueAndAuditAsync(string decision)
            {
                try
                {
                    await next();
                }
                catch
                {
                    await AuditAsync(StatusCodes.Status500InternalServerError, $"{decision}_endpoint_failed");
                    throw;
                }

                await AuditAsync(context.Response.StatusCode, decision);
            }

            if (!requiresGuard)
            {
                await next();
                return;
            }

            if (!IsAuthenticated(context.User))
            {
                if (string.IsNullOrWhiteSpace(configuredKey))
                {
                    context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
                    await context.Response.WriteAsJsonAsync(new
                    {
                        error = "admin_internal_guard_not_configured"
                    });
                    await AuditAsync(StatusCodes.Status503ServiceUnavailable, "deny_guard_not_configured");
                    return;
                }

                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsJsonAsync(new { error = "authentication_required" });
                await AuditAsync(StatusCodes.Status401Unauthorized, "deny_authentication_required");
                return;
            }

            if (!IsRoleAuthorized(context.Request.Path, context.Request.Method, operatorRole))
            {
                context.Response.StatusCode = StatusCodes.Status403Forbidden;
                await context.Response.WriteAsJsonAsync(new { error = "role_not_authorized", role = operatorRole });
                await AuditAsync(StatusCodes.Status403Forbidden, "deny_role_not_authorized");
                return;
            }

            await ContinueAndAuditAsync("allow");
        });

        return app;
    }

    internal static bool RequiresGuard(PathString path) =>
        path != "/" &&
        path != "/health" &&
        !path.StartsWithSegments("/auth/session", StringComparison.OrdinalIgnoreCase);

    internal static bool IsRoleAuthorized(PathString path, string method, string role)
    {
        if (string.IsNullOrWhiteSpace(role))
        {
            return false;
        }

        if (IsSourceAuthorizationPath(path) ||
            path.StartsWithSegments("/internal/ai", StringComparison.OrdinalIgnoreCase))
        {
            return role == "admin";
        }

        if (IsCurriculumEvidenceDecisionPath(path))
        {
            return role is "admin" or "group_lead";
        }

        if (IsImportStatusPath(path))
        {
            return role == "admin";
        }

        if (path.StartsWithSegments("/api/admin", StringComparison.OrdinalIgnoreCase))
        {
            return HttpMethods.IsGet(method) || HttpMethods.IsHead(method)
                ? role is "admin" or "group_lead"
                : role == "admin";
        }

        return HttpMethods.IsGet(method) || HttpMethods.IsHead(method)
            ? role is "admin" or "group_lead" or "teacher"
            : role is "admin" or "group_lead" or "teacher";
    }

    internal static bool IsDraftTestBypassAllowed(
        bool isDevelopment,
        bool allowUnguardedDraftTest,
        IPAddress? localAddress,
        IPAddress? remoteAddress) =>
        isDevelopment &&
        allowUnguardedDraftTest &&
        localAddress is not null &&
        remoteAddress is not null &&
        IPAddress.IsLoopback(localAddress) &&
        IPAddress.IsLoopback(remoteAddress);

    internal static (string Reviewer, string ActorRole) ResolveReviewIdentity(ClaimsPrincipal principal)
    {
        if (!IsAuthenticated(principal))
        {
            throw new InvalidOperationException("authenticated_reviewer_required");
        }

        var reviewer = principal.FindFirstValue(ClaimTypes.NameIdentifier)?.Trim();
        var role = NormalizeRole(principal.FindFirstValue(ClaimTypes.Role));
        if (string.IsNullOrWhiteSpace(reviewer) || role is not ("admin" or "group_lead"))
        {
            throw new InvalidOperationException("authorized_reviewer_identity_required");
        }

        return (reviewer, role == "admin" ? "administrator" : role);
    }

    internal static ClaimsPrincipal CreateTrustedPrincipal(
        AdminInternalGuardOptions options,
        string configuredKey,
        string authenticationType)
    {
        var role = NormalizeRole(options.TrustedRole);
        if (role is not ("admin" or "group_lead" or "teacher"))
        {
            role = "admin";
        }

        var operatorId = string.IsNullOrWhiteSpace(options.TrustedOperatorId)
            ? "kqg-local-admin"
            : options.TrustedOperatorId.Trim();
        var identity = new ClaimsIdentity(
        [
            new Claim(ClaimTypes.NameIdentifier, operatorId),
            new Claim(ClaimTypes.Name, operatorId),
            new Claim(ClaimTypes.Role, role),
            new Claim(CredentialFingerprintClaim, CredentialFingerprint(configuredKey))
        ], authenticationType);
        return new ClaimsPrincipal(identity);
    }

    internal static bool FixedTimeEquals(string? providedKey, string configuredKey)
    {
        if (string.IsNullOrEmpty(providedKey))
        {
            return false;
        }

        var providedBytes = Encoding.UTF8.GetBytes(providedKey);
        var configuredBytes = Encoding.UTF8.GetBytes(configuredKey);
        return providedBytes.Length == configuredBytes.Length &&
            CryptographicOperations.FixedTimeEquals(providedBytes, configuredBytes);
    }

    private static bool HasCurrentCredential(ClaimsPrincipal principal, string? configuredKey)
    {
        if (!IsAuthenticated(principal) || string.IsNullOrWhiteSpace(configuredKey))
        {
            return false;
        }

        return FixedTimeEquals(
            principal.FindFirstValue(CredentialFingerprintClaim),
            CredentialFingerprint(configuredKey));
    }

    private static ClaimsPrincipal CreateDraftTestPrincipal(AdminInternalGuardOptions options)
    {
        var identity = new ClaimsIdentity(
        [
            new Claim(ClaimTypes.NameIdentifier, "draft-test-bypass"),
            new Claim(ClaimTypes.Name, "draft-test-bypass"),
            new Claim(ClaimTypes.Role, NormalizeRole(options.TrustedRole) is "teacher" ? "teacher" : "admin")
        ], "DraftTestBypass");
        return new ClaimsPrincipal(identity);
    }

    private static bool IsAuthenticated(ClaimsPrincipal principal) =>
        principal.Identity?.IsAuthenticated == true;

    private static bool IsSourceAuthorizationPath(PathString path)
    {
        if (!path.StartsWithSegments("/source-documents", out var remaining))
        {
            return false;
        }

        return remaining.Value?.EndsWith("/authorization", StringComparison.OrdinalIgnoreCase) == true;
    }

    private static bool IsCurriculumEvidenceDecisionPath(PathString path) =>
        path.StartsWithSegments("/knowledge-evidence/reviews/decisions", StringComparison.OrdinalIgnoreCase) ||
        path.StartsWithSegments("/knowledge-evidence/reviews/batch-approve", StringComparison.OrdinalIgnoreCase);

    private static bool IsImportStatusPath(PathString path)
    {
        if (!path.StartsWithSegments("/imports", out var remaining))
        {
            return false;
        }

        return remaining.Value?.EndsWith("/status", StringComparison.OrdinalIgnoreCase) == true;
    }

    private static bool IsHighRiskWrite(string method) =>
        HttpMethods.IsPost(method) || HttpMethods.IsPut(method) || HttpMethods.IsPatch(method) || HttpMethods.IsDelete(method);

    private static string NormalizeRole(string? role) =>
        string.IsNullOrWhiteSpace(role) ? string.Empty : role.Trim().ToLowerInvariant();

    private static string CredentialFingerprint(string configuredKey) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(configuredKey))).ToLowerInvariant();
}
