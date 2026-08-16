using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using K12QuestionGraph.Api.Configuration;

namespace K12QuestionGraph.Api.Security;

public sealed class AdminInternalGuardOptions
{
    public string? ApiKey { get; set; }
    public bool AllowUnguardedDraftTest { get; set; }
}

public sealed class AdminInternalRoleAuditOptions
{
    public bool Enabled { get; set; } = true;
    public bool RequireRoleHeader { get; set; } = true;
    public bool RequireOperatorIdHeader { get; set; } = true;
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

    public static WebApplication UseAdminInternalEndpointGuard(this WebApplication app)
    {
        app.Use(async (context, next) =>
        {
            if (!RequiresGuard(context.Request.Path))
            {
                await next();
                return;
            }

            var options = app.Configuration
                .GetSection("AdminInternalGuard")
                .Get<AdminInternalGuardOptions>() ?? new AdminInternalGuardOptions();
            var roleAuditOptions = app.Configuration
                .GetSection("AdminInternalRoleAudit")
                .Get<AdminInternalRoleAuditOptions>() ?? new AdminInternalRoleAuditOptions();
            var paths = app.Configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
            var configuredKey = options.ApiKey?.Trim();
            var draftTestBypassAllowed = app.Environment.IsDevelopment() && options.AllowUnguardedDraftTest;
            var isHighRiskWrite = IsHighRiskWrite(context.Request.Method);
            var operatorRole = context.Request.Headers.TryGetValue(RoleHeaderName, out var roleValues)
                ? NormalizeRole(roleValues.FirstOrDefault())
                : string.Empty;
            var operatorId = context.Request.Headers.TryGetValue(OperatorIdHeaderName, out var operatorValues)
                ? operatorValues.FirstOrDefault()?.Trim() ?? string.Empty
                : string.Empty;
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
                    // 审计写入失败不能压垮管理员接口可用性，保持 fail-open 但仍保留其余鉴权边界。
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

            if (string.IsNullOrWhiteSpace(configuredKey))
            {
                if (draftTestBypassAllowed)
                {
                    context.Response.Headers[DraftTestHeaderName] = DraftTestHeaderValue;
                    await ContinueAndAuditAsync("allow_draft_test_bypass");
                    return;
                }

                context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
                await context.Response.WriteAsJsonAsync(new
                {
                    error = "admin_internal_guard_not_configured",
                    requiredHeader = HeaderName
                });
                await AuditAsync(StatusCodes.Status503ServiceUnavailable, "deny_guard_not_configured");
                return;
            }

            if (!context.Request.Headers.TryGetValue(HeaderName, out var providedValues))
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsJsonAsync(new { error = "missing_admin_internal_key" });
                await AuditAsync(StatusCodes.Status401Unauthorized, "deny_missing_admin_key");
                return;
            }

            var providedKey = providedValues.FirstOrDefault();
            if (!FixedTimeEquals(providedKey, configuredKey))
            {
                context.Response.StatusCode = StatusCodes.Status403Forbidden;
                await context.Response.WriteAsJsonAsync(new { error = "invalid_admin_internal_key" });
                await AuditAsync(StatusCodes.Status403Forbidden, "deny_invalid_admin_key");
                return;
            }

            if (roleAuditOptions.Enabled && roleAuditOptions.RequireRoleHeader && string.IsNullOrWhiteSpace(operatorRole))
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsJsonAsync(new { error = "missing_operator_role", requiredHeader = RoleHeaderName });
                await AuditAsync(StatusCodes.Status401Unauthorized, "deny_missing_operator_role");
                return;
            }

            if (roleAuditOptions.Enabled && roleAuditOptions.RequireOperatorIdHeader && string.IsNullOrWhiteSpace(operatorId))
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsJsonAsync(new { error = "missing_operator_id", requiredHeader = OperatorIdHeaderName });
                await AuditAsync(StatusCodes.Status401Unauthorized, "deny_missing_operator_id");
                return;
            }

            if (roleAuditOptions.Enabled && !IsRoleAuthorized(context.Request.Path, context.Request.Method, operatorRole))
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
        path.StartsWithSegments("/api/admin", StringComparison.OrdinalIgnoreCase) ||
        path.StartsWithSegments("/internal/ai", StringComparison.OrdinalIgnoreCase) ||
        IsSourceAuthorizationPath(path);

    private static bool IsRoleAuthorized(PathString path, string method, string role)
    {
        if (string.IsNullOrWhiteSpace(role))
        {
            return false;
        }

        if (IsSourceAuthorizationPath(path))
        {
            return role == "admin";
        }

        if (path.StartsWithSegments("/internal/ai", StringComparison.OrdinalIgnoreCase))
        {
            return role == "admin";
        }

        if (path.StartsWithSegments("/api/admin", StringComparison.OrdinalIgnoreCase))
        {
            if (HttpMethods.IsGet(method) || HttpMethods.IsHead(method))
            {
                return role is "admin" or "group_lead";
            }

            return role == "admin";
        }

        return false;
    }

    private static bool IsSourceAuthorizationPath(PathString path)
    {
        if (!path.StartsWithSegments("/source-documents", out var remaining))
        {
            return false;
        }

        return remaining.Value?.EndsWith("/authorization", StringComparison.OrdinalIgnoreCase) == true;
    }

    private static bool IsHighRiskWrite(string method) =>
        HttpMethods.IsPost(method) || HttpMethods.IsPut(method) || HttpMethods.IsPatch(method) || HttpMethods.IsDelete(method);

    private static string NormalizeRole(string? role) =>
        string.IsNullOrWhiteSpace(role) ? string.Empty : role.Trim().ToLowerInvariant();

    private static bool FixedTimeEquals(string? providedKey, string configuredKey)
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
}
