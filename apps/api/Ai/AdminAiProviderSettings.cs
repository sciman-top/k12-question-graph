using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using K12QuestionGraph.Api.Configuration;
using Microsoft.AspNetCore.DataProtection;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.NamingConventions;

namespace K12QuestionGraph.Api.Ai;

public sealed record AdminAiProviderSettingsContract(
    string Status,
    string Mode,
    bool ProductionEligible,
    string ProviderProfileId,
    string ProviderType,
    string BaseUrl,
    string ImageBaseUrl,
    string CredentialMode,
    string MaskedSecret,
    bool SecretConfigured,
    string MaskedImageSecret,
    bool ImageSecretConfigured,
    bool ImageUsesPrimarySecret,
    int MaxConcurrency,
    int MonthlyBudgetCny,
    bool DisabledByDefault,
    bool AllowRealModelCalls,
    string DefaultSmokeTaskType,
    string DefaultSmokeModel,
    string FallbackBaseUrl,
    string FallbackImageBaseUrl,
    string MaskedFallbackSecret,
    bool FallbackSecretConfigured,
    string MaskedFallbackImageSecret,
    bool FallbackImageSecretConfigured,
    bool FallbackImageUsesPrimarySecret,
    IReadOnlyList<AdminAiProviderEndpointContract> Endpoints,
    string LastUpdatedAt,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail);

public sealed record AdminAiProviderEndpointContract(
    string EndpointId,
    string Label,
    bool IsFallback,
    string BaseUrl,
    string ImageBaseUrl,
    string MaskedSecret,
    bool SecretConfigured,
    string MaskedImageSecret,
    bool ImageSecretConfigured,
    bool ImageUsesTextSecret);

public sealed record AdminAiProviderSettingsSaveRequest(
    string ProviderProfileId,
    string? BaseUrl,
    string? ApiKey,
    string? ImageBaseUrl,
    string? ImageApiKey,
    string? FallbackBaseUrl,
    string? FallbackApiKey,
    string? FallbackImageBaseUrl,
    string? FallbackImageApiKey,
    int MaxConcurrency,
    int MonthlyBudgetCny,
    bool DisabledByDefault,
    bool AllowRealModelCalls,
    string? DefaultSmokeTaskType,
    string? DefaultSmokeModel,
    string? OperatorNote);

public sealed record AdminAiProviderSettingsSaveResult(
    string Status,
    string Mode,
    bool ProductionEligible,
    string ProviderProfileId,
    bool SecretConfigured,
    string MaskedSecret,
    bool ImageSecretConfigured,
    string MaskedImageSecret,
    bool ImageUsesPrimarySecret,
    bool FallbackSecretConfigured,
    string MaskedFallbackSecret,
    bool FallbackImageSecretConfigured,
    string MaskedFallbackImageSecret,
    bool FallbackImageUsesPrimarySecret,
    string LastUpdatedAt,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail);

public sealed record AdminAiProviderSettingsTestRequest(
    string TaskType,
    string? InputJson,
    string? Model,
    string? BaseUrlOverride,
    string? ImageBaseUrlOverride,
    string? FallbackBaseUrlOverride,
    string? FallbackImageBaseUrlOverride,
    string? RoutingMode = null,
    AiRouteRiskSignals? RiskSignals = null,
    decimal? ExpectedConfidence = null,
    bool UseModelRouting = true);

public sealed record AdminAiProviderProbeAttempt(
    string ProviderEndpointId,
    string BaseUrl,
    string RouteKind,
    string EndpointPath,
    string Model,
    string ReasoningEffort,
    bool Passed,
    int HttpStatusCode,
    int LatencyMs,
    string Message);

public sealed record AdminAiProviderImageProbeAttempt(
    string ProviderEndpointId,
    string BaseUrl,
    string RouteKind,
    string EndpointPath,
    string Model,
    bool Passed,
    int HttpStatusCode,
    int LatencyMs,
    string Message);

public sealed record AdminAiProviderImageProbeResult(
    bool Attempted,
    bool Passed,
    string EffectiveProviderEndpointId,
    string EffectiveBaseUrl,
    string EffectiveRouteKind,
    string EffectiveModel,
    int HttpStatusCode,
    int LatencyMs,
    string Message,
    IReadOnlyList<string> Blockers,
    IReadOnlyList<AdminAiProviderImageProbeAttempt> Attempts,
    IReadOnlyList<string> AuditTrail);

public sealed record AdminAiProviderSettingsTestResult(
    string Status,
    string Mode,
    bool ProductionEligible,
    string ProviderProfileId,
    string ProviderType,
    string Model,
    string TaskType,
    string EffectiveReasoningEffort,
    string EffectiveExecutionSlot,
    string EffectiveExecutionGrade,
    string EffectivePreset,
    string RoutingMode,
    bool UsedModelRouting,
    string ReviewStatus,
    bool Passed,
    bool CombinedPassed,
    string EffectiveProviderEndpointId,
    string EffectiveBaseUrl,
    int HttpStatusCode,
    string Message,
    string OutputJson,
    int InputTokens,
    int OutputTokens,
    int CachedTokens,
    decimal Cost,
    int LatencyMs,
    IReadOnlyList<string> Blockers,
    IReadOnlyList<AdminAiProviderProbeAttempt> Attempts,
    AdminAiProviderImageProbeResult ImageProbe,
    IReadOnlyList<string> AuditTrail);

public sealed record AiPresetConnectivityProbeResult(
    string Status,
    string PresetId,
    string ModelName,
    string ReasoningEffort,
    bool Passed,
    bool Skipped,
    int HttpStatusCode,
    string Message,
    AiModelFailoverCandidate? Candidate);

internal sealed record StoredAdminAiProviderSettings(
    string SchemaVersion,
    string ProviderProfileId,
    string ProviderType,
    string BaseUrl,
    string ImageBaseUrl,
    string CredentialMode,
    string SecretCiphertext,
    string ImageSecretCiphertext,
    string FallbackBaseUrl,
    string FallbackImageBaseUrl,
    string FallbackSecretCiphertext,
    string FallbackImageSecretCiphertext,
    int MaxConcurrency,
    int MonthlyBudgetCny,
    bool DisabledByDefault,
    bool AllowRealModelCalls,
    string DefaultSmokeTaskType,
    string DefaultSmokeModel,
    DateTimeOffset UpdatedAtUtc,
    string LastOperatorNote);

public sealed record AiProviderRuntimeEndpoint(
    string EndpointId,
    string Label,
    bool IsFallback,
    string BaseUrl,
    string Secret,
    string ImageBaseUrl,
    string ImageSecret);

public sealed class FileAiProviderSettingsStore(
    IConfiguration configuration,
    IDataProtectionProvider dataProtectionProvider,
    IWebHostEnvironment environment)
{
    private const string SchemaVersion = "admin-ai-provider-settings.v0.1";
    private const string DefaultProviderProfileId = "cloud_openai_candidate";
    private const string DefaultProviderType = "openai_compatible";
    private const string DefaultCredentialMode = "dialog_secret_local_machine";
    private const string DefaultSmokeTaskType = "knowledge_tagging";
    private const string DefaultSmokeModel = "gpt-5.6-sol";
    private const string DefaultGatewayBaseUrl = CockpitGatewayPolicy.LocalBaseUrl;
    private const string PrimaryEnvSecretName = "KQG_AI_OPENAI_KEY";
    private const string PrimaryEnvBaseUrlName = "KQG_AI_OPENAI_BASE_URL";
    private const string ImageEnvSecretName = "KQG_AI_IMAGE_OPENAI_KEY";
    private const string ImageEnvBaseUrlName = "KQG_AI_IMAGE_OPENAI_BASE_URL";
    private const string LegacyPrimaryEnvSecretName = "TEXT_PROVIDER_API_KEY";
    private const string LegacyPrimaryEnvBaseUrlName = "TEXT_PROVIDER_BASE_URL";
    private const string LegacyImageEnvSecretName = "IMAGE_PROVIDER_API_KEY_1";
    private const string LegacyImageEnvBaseUrlName = "IMAGE_PROVIDER_BASE_URL";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web) { WriteIndented = true };
    private static readonly SemaphoreSlim SettingsWriteLock = new(1, 1);
    private readonly IDataProtector protector = dataProtectionProvider.CreateProtector("k12-question-graph.admin-ai-provider-settings.v0.1");

    public async Task<AdminAiProviderSettingsContract> GetAsync(CancellationToken cancellationToken)
    {
        var settings = await LoadStoredAsync(cancellationToken);
        return ToContract(settings);
    }

    public async Task<AdminAiProviderSettingsSaveResult> SaveAsync(
        AdminAiProviderSettingsSaveRequest request,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await SettingsWriteLock.WaitAsync(cancellationToken);

        try
        {
            var existing = await LoadStoredAsync(cancellationToken);
            RejectFallbackConfiguration(request);
            var normalizedSecret = request.ApiKey?.Trim();
            var normalizedImageSecret = request.ImageApiKey?.Trim();
            var secretCiphertext = string.IsNullOrWhiteSpace(normalizedSecret)
                ? existing.SecretCiphertext
                : ProtectSecret(normalizedSecret);
            var imageSecretCiphertext = normalizedImageSecret is null
                ? existing.ImageSecretCiphertext
                : string.IsNullOrWhiteSpace(normalizedImageSecret)
                    ? string.Empty
                    : ProtectSecret(normalizedImageSecret);
            var now = DateTimeOffset.UtcNow;
            var stored = new StoredAdminAiProviderSettings(
                SchemaVersion,
                DefaultProviderProfileId,
                DefaultProviderType,
                NormalizeBaseUrl(request.BaseUrl),
                NormalizeOptionalBaseUrl(request.ImageBaseUrl),
                DefaultCredentialMode,
                secretCiphertext,
                imageSecretCiphertext,
                string.Empty,
                string.Empty,
                string.Empty,
                string.Empty,
                NormalizeRange(request.MaxConcurrency, 1, 8, fallback: existing.MaxConcurrency),
                NormalizeRange(request.MonthlyBudgetCny, 0, 100000, fallback: existing.MonthlyBudgetCny),
                request.DisabledByDefault,
                request.AllowRealModelCalls,
                Normalize(request.DefaultSmokeTaskType, existing.DefaultSmokeTaskType),
                NormalizeSmokeModel(request.DefaultSmokeModel, existing.DefaultSmokeModel),
                now,
                Normalize(request.OperatorNote, existing.LastOperatorNote));

            await WriteStoredAtomicallyAsync(stored, cancellationToken);

            var plaintextPrimarySecret = UnprotectSecret(stored.SecretCiphertext);
            var plaintextImageSecret = ResolveEffectiveImageSecret(plaintextPrimarySecret, stored.ImageSecretCiphertext);
            var plaintextFallbackSecret = UnprotectSecret(stored.FallbackSecretCiphertext);
            var plaintextFallbackImageSecret = ResolveEffectiveImageSecret(plaintextFallbackSecret, stored.FallbackImageSecretCiphertext);
            return new AdminAiProviderSettingsSaveResult(
                Status: "ok",
                Mode: "draft_test",
                ProductionEligible: false,
                ProviderProfileId: stored.ProviderProfileId,
                SecretConfigured: !string.IsNullOrWhiteSpace(plaintextPrimarySecret),
                MaskedSecret: MaskSecret(plaintextPrimarySecret),
                ImageSecretConfigured: !string.IsNullOrWhiteSpace(plaintextImageSecret),
                MaskedImageSecret: MaskSecret(plaintextImageSecret),
                ImageUsesPrimarySecret: string.IsNullOrWhiteSpace(UnprotectSecret(stored.ImageSecretCiphertext)),
                FallbackSecretConfigured: !string.IsNullOrWhiteSpace(plaintextFallbackSecret),
                MaskedFallbackSecret: MaskSecret(plaintextFallbackSecret),
                FallbackImageSecretConfigured: !string.IsNullOrWhiteSpace(plaintextFallbackImageSecret),
                MaskedFallbackImageSecret: MaskSecret(plaintextFallbackImageSecret),
                FallbackImageUsesPrimarySecret: string.IsNullOrWhiteSpace(UnprotectSecret(stored.FallbackImageSecretCiphertext)),
                LastUpdatedAt: stored.UpdatedAtUtc.ToString("O"),
                TeacherMessage: "管理员 AI 设置已保存；固定 Cockpit 本地网关将按 preset 可用性顺序试跑，图片专用 key 留空时会复用同一路文本 key；本机仍只保留加密副本，试跑保持 pending_review。",
                AuditTrail: [
                    "save_admin_ai_provider_settings",
                $"provider_profile={stored.ProviderProfileId}",
                $"allow_real_model_calls={stored.AllowRealModelCalls.ToString().ToLowerInvariant()}",
                $"secret_configured={(!string.IsNullOrWhiteSpace(plaintextPrimarySecret)).ToString().ToLowerInvariant()}",
                $"image_secret_configured={(!string.IsNullOrWhiteSpace(plaintextImageSecret)).ToString().ToLowerInvariant()}",
                $"image_uses_primary_secret={(string.IsNullOrWhiteSpace(UnprotectSecret(stored.ImageSecretCiphertext))).ToString().ToLowerInvariant()}",
                $"fallback_secret_configured={(!string.IsNullOrWhiteSpace(plaintextFallbackSecret)).ToString().ToLowerInvariant()}",
                $"fallback_image_secret_configured={(!string.IsNullOrWhiteSpace(plaintextFallbackImageSecret)).ToString().ToLowerInvariant()}",
                $"fallback_image_uses_primary_secret={(string.IsNullOrWhiteSpace(UnprotectSecret(stored.FallbackImageSecretCiphertext))).ToString().ToLowerInvariant()}"
                ]);
        }
        finally
        {
            SettingsWriteLock.Release();
        }
    }

    public async Task<string> GetPlaintextSecretAsync(CancellationToken cancellationToken)
    {
        var stored = await LoadStoredAsync(cancellationToken);
        return UnprotectSecret(stored.SecretCiphertext);
    }

    public async Task<string> GetPlaintextImageSecretAsync(CancellationToken cancellationToken)
    {
        var stored = await LoadStoredAsync(cancellationToken);
        var plaintextPrimarySecret = UnprotectSecret(stored.SecretCiphertext);
        return ResolveEffectiveImageSecret(plaintextPrimarySecret, stored.ImageSecretCiphertext);
    }

    public async Task<IReadOnlyList<AiProviderRuntimeEndpoint>> GetRuntimeEndpointsAsync(CancellationToken cancellationToken)
    {
        var stored = await LoadStoredAsync(cancellationToken);
        return BuildRuntimeEndpoints(stored);
    }

    private async Task<StoredAdminAiProviderSettings> LoadStoredAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var path = GetSettingsFilePath();
        if (!File.Exists(path))
        {
            return BuildDefault();
        }

        try
        {
            var json = await File.ReadAllTextAsync(path, cancellationToken);
            var loaded = JsonSerializer.Deserialize<StoredAdminAiProviderSettings>(json, JsonOptions);
            return loaded is null
                ? throw new InvalidDataException($"AI provider settings file contains JSON null: {path}")
                : NormalizeLoaded(loaded);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception) when (exception is JsonException or IOException or UnauthorizedAccessException)
        {
            throw new InvalidDataException(
                $"AI provider settings could not be loaded. Inspect the primary file and its .bak recovery copy: {path}",
                exception);
        }
    }

    private async Task WriteStoredAtomicallyAsync(
        StoredAdminAiProviderSettings stored,
        CancellationToken cancellationToken)
    {
        var path = GetSettingsFilePath();
        var directory = Path.GetDirectoryName(path)!;
        Directory.CreateDirectory(directory);
        var tempPath = Path.Combine(directory, $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        var backupPath = path + ".bak";
        var json = JsonSerializer.Serialize(stored, JsonOptions);
        _ = JsonSerializer.Deserialize<StoredAdminAiProviderSettings>(json, JsonOptions)
            ?? throw new InvalidDataException("AI provider settings serialization produced JSON null.");

        try
        {
            await using (var stream = new FileStream(
                tempPath,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                4096,
                FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                var bytes = Encoding.UTF8.GetBytes(json);
                await stream.WriteAsync(bytes, cancellationToken);
                await stream.FlushAsync(cancellationToken);
                stream.Flush(flushToDisk: true);
            }

            var candidateJson = await File.ReadAllTextAsync(tempPath, cancellationToken);
            _ = JsonSerializer.Deserialize<StoredAdminAiProviderSettings>(candidateJson, JsonOptions)
                ?? throw new InvalidDataException("AI provider settings candidate contains JSON null.");

            if (File.Exists(path))
            {
                File.Replace(tempPath, path, backupPath, ignoreMetadataErrors: true);
            }
            else
            {
                File.Move(tempPath, path);
            }
        }
        finally
        {
            if (File.Exists(tempPath))
            {
                File.Delete(tempPath);
            }
        }
    }

    private AdminAiProviderSettingsContract ToContract(StoredAdminAiProviderSettings settings)
    {
        var plaintextSecret = UnprotectSecret(settings.SecretCiphertext);
        var plaintextImageSecret = ResolveEffectiveImageSecret(plaintextSecret, settings.ImageSecretCiphertext);
        var explicitImageSecret = UnprotectSecret(settings.ImageSecretCiphertext);
        var plaintextFallbackSecret = UnprotectSecret(settings.FallbackSecretCiphertext);
        var plaintextFallbackImageSecret = ResolveEffectiveImageSecret(plaintextFallbackSecret, settings.FallbackImageSecretCiphertext);
        var explicitFallbackImageSecret = UnprotectSecret(settings.FallbackImageSecretCiphertext);
        return new AdminAiProviderSettingsContract(
            Status: "ok",
            Mode: "draft_test",
            ProductionEligible: false,
            ProviderProfileId: settings.ProviderProfileId,
            ProviderType: settings.ProviderType,
            BaseUrl: settings.BaseUrl,
            ImageBaseUrl: ResolveEffectiveImageBaseUrl(settings.BaseUrl, settings.ImageBaseUrl),
            CredentialMode: settings.CredentialMode,
            MaskedSecret: MaskSecret(plaintextSecret),
            SecretConfigured: !string.IsNullOrWhiteSpace(plaintextSecret),
            MaskedImageSecret: MaskSecret(plaintextImageSecret),
            ImageSecretConfigured: !string.IsNullOrWhiteSpace(plaintextImageSecret),
            ImageUsesPrimarySecret: string.IsNullOrWhiteSpace(explicitImageSecret),
            MaxConcurrency: settings.MaxConcurrency,
            MonthlyBudgetCny: settings.MonthlyBudgetCny,
            DisabledByDefault: settings.DisabledByDefault,
            AllowRealModelCalls: settings.AllowRealModelCalls,
            DefaultSmokeTaskType: settings.DefaultSmokeTaskType,
            DefaultSmokeModel: settings.DefaultSmokeModel,
            FallbackBaseUrl: settings.FallbackBaseUrl,
            FallbackImageBaseUrl: ResolveEffectiveImageBaseUrl(settings.FallbackBaseUrl, settings.FallbackImageBaseUrl),
            MaskedFallbackSecret: MaskSecret(plaintextFallbackSecret),
            FallbackSecretConfigured: !string.IsNullOrWhiteSpace(plaintextFallbackSecret),
            MaskedFallbackImageSecret: MaskSecret(plaintextFallbackImageSecret),
            FallbackImageSecretConfigured: !string.IsNullOrWhiteSpace(plaintextFallbackImageSecret),
            FallbackImageUsesPrimarySecret: string.IsNullOrWhiteSpace(explicitFallbackImageSecret),
            Endpoints: BuildEndpointContracts(settings),
            LastUpdatedAt: settings.UpdatedAtUtc.ToString("O"),
            TeacherMessage: "当前为管理员级本机 AI 设置；固定 Cockpit 本地网关会按 preset 可用性顺序试跑，图片专用 key 可选覆盖；普通教师侧仍只看到简化模式。",
            AuditTrail: [
                "load_admin_ai_provider_settings",
                $"provider_profile={settings.ProviderProfileId}",
                $"secret_configured={(!string.IsNullOrWhiteSpace(plaintextSecret)).ToString().ToLowerInvariant()}",
                $"image_secret_configured={(!string.IsNullOrWhiteSpace(plaintextImageSecret)).ToString().ToLowerInvariant()}",
                $"image_uses_primary_secret={(string.IsNullOrWhiteSpace(explicitImageSecret)).ToString().ToLowerInvariant()}",
                $"fallback_secret_configured={(!string.IsNullOrWhiteSpace(plaintextFallbackSecret)).ToString().ToLowerInvariant()}",
                $"fallback_image_secret_configured={(!string.IsNullOrWhiteSpace(plaintextFallbackImageSecret)).ToString().ToLowerInvariant()}",
                $"fallback_image_uses_primary_secret={(string.IsNullOrWhiteSpace(explicitFallbackImageSecret)).ToString().ToLowerInvariant()}",
                $"allow_real_model_calls={settings.AllowRealModelCalls.ToString().ToLowerInvariant()}"
            ]);
    }

    private StoredAdminAiProviderSettings BuildDefault()
    {
        var defaults = LoadDefaultsFromYaml();
        var envPrimarySecret = ReadFirstEnvironmentValue(PrimaryEnvSecretName, LegacyPrimaryEnvSecretName);
        var envImageSecret = ReadFirstEnvironmentValue(ImageEnvSecretName, LegacyImageEnvSecretName);
        var envPrimaryBaseUrl = ReadFirstEnvironmentValue(PrimaryEnvBaseUrlName, LegacyPrimaryEnvBaseUrlName);
        var envImageBaseUrl = ReadFirstEnvironmentValue(ImageEnvBaseUrlName, LegacyImageEnvBaseUrlName);
        return new StoredAdminAiProviderSettings(
            SchemaVersion,
            DefaultProviderProfileId,
            DefaultProviderType,
            NormalizeBaseUrl(string.IsNullOrWhiteSpace(envPrimaryBaseUrl) ? defaults.baseUrl : envPrimaryBaseUrl),
            NormalizeOptionalBaseUrl(envImageBaseUrl),
            DefaultCredentialMode,
            string.IsNullOrWhiteSpace(envPrimarySecret) ? string.Empty : ProtectSecret(envPrimarySecret),
            string.IsNullOrWhiteSpace(envImageSecret) ? string.Empty : ProtectSecret(envImageSecret),
            string.Empty,
            string.Empty,
            string.Empty,
            string.Empty,
            defaults.maxConcurrency,
            defaults.monthlyBudgetCny,
            true,
            false,
            DefaultSmokeTaskType,
            DefaultSmokeModel,
            DateTimeOffset.MinValue,
            string.Empty);
    }

    private StoredAdminAiProviderSettings NormalizeLoaded(StoredAdminAiProviderSettings loaded)
    {
        var defaults = LoadDefaultsFromYaml();
        return loaded with
        {
            ProviderProfileId = DefaultProviderProfileId,
            ProviderType = DefaultProviderType,
            BaseUrl = NormalizeBaseUrl(string.IsNullOrWhiteSpace(loaded.BaseUrl) ? defaults.baseUrl : loaded.BaseUrl),
            ImageBaseUrl = NormalizeOptionalBaseUrl(loaded.ImageBaseUrl),
            FallbackBaseUrl = string.Empty,
            FallbackImageBaseUrl = string.Empty,
            FallbackSecretCiphertext = string.Empty,
            FallbackImageSecretCiphertext = string.Empty,
            CredentialMode = Normalize(loaded.CredentialMode, DefaultCredentialMode),
            MaxConcurrency = NormalizeRange(loaded.MaxConcurrency, 1, 8, defaults.maxConcurrency),
            MonthlyBudgetCny = NormalizeRange(loaded.MonthlyBudgetCny, 0, 100000, defaults.monthlyBudgetCny),
            DefaultSmokeTaskType = Normalize(loaded.DefaultSmokeTaskType, DefaultSmokeTaskType),
            DefaultSmokeModel = DefaultSmokeModel,
        };
    }

    private (string baseUrl, int maxConcurrency, int monthlyBudgetCny) LoadDefaultsFromYaml()
    {
        var repoRoot = Path.GetFullPath(Path.Combine(environment.ContentRootPath, "..", ".."));
        var yamlPath = Path.Combine(repoRoot, "configs", "ai-provider-profiles.defaults.yaml");
        if (!File.Exists(yamlPath))
        {
            return (DefaultGatewayBaseUrl, 2, 300);
        }

        try
        {
            var deserializer = new DeserializerBuilder()
                .WithNamingConvention(CamelCaseNamingConvention.Instance)
                .IgnoreUnmatchedProperties()
                .Build();
            var yaml = deserializer.Deserialize<AiProviderProfilesDefaultsDocument>(File.ReadAllText(yamlPath, Encoding.UTF8));
            var profile = yaml?.ProviderProfiles?.FirstOrDefault(x => string.Equals(x.Id, DefaultProviderProfileId, StringComparison.OrdinalIgnoreCase));
            return (
                profile?.BaseUrl ?? DefaultGatewayBaseUrl,
                profile?.MaxConcurrency ?? 2,
                profile?.MonthlyBudgetCny ?? 300);
        }
        catch
        {
            return (DefaultGatewayBaseUrl, 2, 300);
        }
    }

    private string GetSettingsFilePath()
    {
        var paths = configuration.GetSection("KqgPaths").Get<KqgPathsOptions>() ?? new KqgPathsOptions();
        var settingsRoot = Path.Combine(Path.GetFullPath(paths.DataRoot), "config", "admin");
        return Path.Combine(settingsRoot, "ai-provider-settings.local.json");
    }

    private static string Normalize(string? value, string fallback)
    {
        return string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
    }

    private static string NormalizeSmokeModel(string? value, string fallback)
    {
        var normalized = Normalize(value, fallback);
        if (!string.Equals(normalized, DefaultSmokeModel, StringComparison.OrdinalIgnoreCase))
        {
            throw new AiProviderSettingsException("single_model_preset_required");
        }

        return DefaultSmokeModel;
    }

    private static int NormalizeRange(int value, int min, int max, int fallback)
    {
        if (value < min || value > max)
        {
            return fallback;
        }

        return value;
    }

    private static string NormalizeBaseUrl(string? value)
    {
        return CockpitGatewayPolicy.NormalizeRequired(Normalize(value, DefaultGatewayBaseUrl));
    }

    private static string NormalizeOptionalBaseUrl(string? value)
    {
        return CockpitGatewayPolicy.NormalizeOptional(value);
    }

    private static void RejectFallbackConfiguration(AdminAiProviderSettingsSaveRequest request)
    {
        if (!string.IsNullOrWhiteSpace(request.FallbackBaseUrl)
            || !string.IsNullOrWhiteSpace(request.FallbackImageBaseUrl)
            || !string.IsNullOrWhiteSpace(request.FallbackApiKey)
            || !string.IsNullOrWhiteSpace(request.FallbackImageApiKey))
        {
            throw new AiProviderSettingsException("cockpit_endpoint_fallback_not_supported");
        }
    }

    private IReadOnlyList<AdminAiProviderEndpointContract> BuildEndpointContracts(StoredAdminAiProviderSettings settings)
    {
        var primarySecret = UnprotectSecret(settings.SecretCiphertext);
        var primaryImageSecret = ResolveEffectiveImageSecret(primarySecret, settings.ImageSecretCiphertext);
        var explicitPrimaryImageSecret = UnprotectSecret(settings.ImageSecretCiphertext);
        var endpoints = new List<AdminAiProviderEndpointContract>
        {
            new(
                EndpointId: "primary",
                Label: "Cockpit 本地网关",
                IsFallback: false,
                BaseUrl: settings.BaseUrl,
                ImageBaseUrl: ResolveEffectiveImageBaseUrl(settings.BaseUrl, settings.ImageBaseUrl),
                MaskedSecret: MaskSecret(primarySecret),
                SecretConfigured: !string.IsNullOrWhiteSpace(primarySecret),
                MaskedImageSecret: MaskSecret(primaryImageSecret),
                ImageSecretConfigured: !string.IsNullOrWhiteSpace(primaryImageSecret),
                ImageUsesTextSecret: string.IsNullOrWhiteSpace(explicitPrimaryImageSecret))
        };

        return endpoints;
    }

    private IReadOnlyList<AiProviderRuntimeEndpoint> BuildRuntimeEndpoints(StoredAdminAiProviderSettings settings)
    {
        var primarySecret = UnprotectSecret(settings.SecretCiphertext);
        var primaryImageSecret = ResolveEffectiveImageSecret(primarySecret, settings.ImageSecretCiphertext);
        var endpoints = new List<AiProviderRuntimeEndpoint>
        {
            new(
                EndpointId: "primary",
                Label: "Cockpit 本地网关",
                IsFallback: false,
                BaseUrl: settings.BaseUrl,
                Secret: primarySecret,
                ImageBaseUrl: ResolveEffectiveImageBaseUrl(settings.BaseUrl, settings.ImageBaseUrl),
                ImageSecret: primaryImageSecret)
        };

        return endpoints;
    }

    private string ProtectSecret(string value)
    {
        return protector.Protect(value);
    }

    private string UnprotectSecret(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        try
        {
            return protector.Unprotect(value);
        }
        catch (CryptographicException exception)
        {
            throw new CryptographicException(
                "AI provider secret could not be decrypted with the current Data Protection key ring.",
                exception);
        }
    }

    private static string MaskSecret(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "";
        }

        var trimmed = value.Trim();
        if (trimmed.Length <= 8)
        {
            return new string('*', trimmed.Length);
        }

        return $"{trimmed[..4]}****{trimmed[^4..]}";
    }

    private string ResolveEffectiveImageSecret(string primarySecret, string? imageSecretCiphertext)
    {
        var explicitImageSecret = UnprotectSecret(imageSecretCiphertext);
        return string.IsNullOrWhiteSpace(explicitImageSecret) ? primarySecret : explicitImageSecret;
    }

    private static string ResolveEffectiveImageBaseUrl(string primaryBaseUrl, string? imageBaseUrl)
    {
        return string.IsNullOrWhiteSpace(imageBaseUrl) ? primaryBaseUrl : imageBaseUrl.TrimEnd('/');
    }

    private static string ReadFirstEnvironmentValue(params string[] variableNames)
    {
        foreach (var variableName in variableNames)
        {
            var value = Environment.GetEnvironmentVariable(variableName)?.Trim();
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        return string.Empty;
    }
}

public sealed class OpenAiCompatibleSmokeTestService(
    HttpClient httpClient,
    FileAiProviderSettingsStore settingsStore,
    AiModelRouter modelRouter,
    AiProviderInvocationGate? invocationGate = null)
{
    private const string ImageProbePrompt = "Generate a simple flat icon of a blue paper plane on a white background.";
    private const string ImageProbeFallbackModel = "gpt-image-2";
    private const string GatewayUserAgent = "codex_exec/k12-question-graph";
    private const string GatewayAcceptHeader = "application/json, text/event-stream";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly AiProviderInvocationGate invocationGate = invocationGate ?? new AiProviderInvocationGate();

    public async Task<AiPresetConnectivityProbeResult> ProbePresetAsync(
        string presetId,
        CancellationToken cancellationToken)
    {
        var settings = await settingsStore.GetAsync(cancellationToken);
        if (settings.DisabledByDefault || !settings.AllowRealModelCalls || !modelRouter.AllowsRealModelCalls)
        {
            return new(
                Status: "skipped",
                PresetId: presetId,
                ModelName: string.Empty,
                ReasoningEffort: string.Empty,
                Passed: false,
                Skipped: true,
                HttpStatusCode: 0,
                Message: "恢复探测受真实 provider 门禁阻止。",
                Candidate: null);
        }

        if (modelRouter.GetPinnedPresetId() is not null)
        {
            return new(
                Status: "skipped",
                PresetId: presetId,
                ModelName: string.Empty,
                ReasoningEffort: string.Empty,
                Passed: false,
                Skipped: true,
                HttpStatusCode: 0,
                Message: "临时 preset pin 生效，恢复探测不跨模型族切换。",
                Candidate: null);
        }

        var candidate = modelRouter.GetFailoverCandidates(
                presetId,
                reasoningEffort: "medium",
                executionSlot: "bulk_prefilter",
                executionGrade: "balanced")
            .FirstOrDefault(item => string.Equals(item.PresetId, presetId, StringComparison.OrdinalIgnoreCase));
        if (candidate is null)
        {
            return new(
                Status: "skipped",
                PresetId: presetId,
                ModelName: string.Empty,
                ReasoningEffort: string.Empty,
                Passed: false,
                Skipped: true,
                HttpStatusCode: 0,
                Message: "恢复探测目标 preset 不可解析。",
                Candidate: null);
        }

        var endpoints = await settingsStore.GetRuntimeEndpointsAsync(cancellationToken);
        foreach (var endpoint in endpoints)
        {
            if (string.IsNullOrWhiteSpace(endpoint.BaseUrl) || string.IsNullOrWhiteSpace(endpoint.Secret))
            {
                continue;
            }

            var availability = await ProbeModelAvailabilityAsync(endpoint, candidate, cancellationToken);
            if (!availability.Passed)
            {
                return new(
                    Status: "failed",
                    PresetId: candidate.PresetId,
                    ModelName: candidate.ModelName,
                    ReasoningEffort: candidate.ReasoningEffort,
                    Passed: false,
                    Skipped: false,
                    HttpStatusCode: availability.HttpStatusCode,
                    Message: availability.Message,
                    Candidate: candidate);
            }

            using var providerPermit = await invocationGate.EnterAsync(settings.MaxConcurrency, cancellationToken);
            var response = await RunStructuredSmokeAsync(
                endpoint,
                candidate,
                taskType: "knowledge_tagging",
                inputJson: "恢复探测：仅返回 status。",
                routingAudit: ["recovery_probe=true", $"recovery_probe_target_preset={candidate.PresetId}"],
                cancellationToken: cancellationToken);
            return new(
                Status: response.Passed ? "ok" : "failed",
                PresetId: candidate.PresetId,
                ModelName: candidate.ModelName,
                ReasoningEffort: candidate.ReasoningEffort,
                Passed: response.Passed,
                Skipped: false,
                HttpStatusCode: response.HttpStatusCode,
                Message: response.Message,
                Candidate: candidate);
        }

        return new(
            Status: "skipped",
            PresetId: candidate.PresetId,
            ModelName: candidate.ModelName,
            ReasoningEffort: candidate.ReasoningEffort,
            Passed: false,
            Skipped: true,
            HttpStatusCode: 0,
            Message: "恢复探测没有可用的本地 Cockpit endpoint。",
            Candidate: candidate);
    }

    public async Task<AdminAiProviderSettingsTestResult> RunAsync(
        AdminAiProviderSettingsContract settings,
        AdminAiProviderSettingsTestRequest request,
        CancellationToken cancellationToken)
    {
        var normalizedTaskType = NormalizeTaskType(request.TaskType, settings.DefaultSmokeTaskType);
        var normalizedModel = NormalizeModel(request.Model, settings.DefaultSmokeModel);
        var effectiveReasoningEffort = "medium";
        var effectiveExecutionSlot = "";
        var effectiveExecutionGrade = "";
        var effectivePreset = "";
        var routingMode = NormalizeRoutingMode(request.RoutingMode);
        var usedModelRouting = request.UseModelRouting;
        var routingAudit = new List<string>();
        var runtimeEndpoints = ApplyEndpointOverrides(
            await settingsStore.GetRuntimeEndpointsAsync(cancellationToken),
            request);
        var blockers = new List<string>();
        if (!runtimeEndpoints.Any(x => !string.IsNullOrWhiteSpace(x.Secret) && !string.IsNullOrWhiteSpace(x.BaseUrl)))
        {
            blockers.Add("provider_secret_not_configured");
        }

        if (settings.DisabledByDefault)
        {
            blockers.Add("provider_profile_disabled_by_default");
        }

        if (!settings.AllowRealModelCalls)
        {
            blockers.Add("allow_real_model_calls_false");
        }

        if (!request.UseModelRouting)
        {
            blockers.Add("manual_model_override_not_supported");
        }

        if (blockers.Count > 0)
        {
            return CreateBlockedResult(
                settings,
                normalizedModel,
                normalizedTaskType,
                effectiveReasoningEffort,
                effectiveExecutionSlot,
                effectiveExecutionGrade,
                effectivePreset,
                routingMode,
                runtimeEndpoints,
                blockers,
                [
                    "test_admin_ai_provider_settings_blocked",
                    "routing_not_evaluated_before_provider_preconditions",
                    ..blockers
                ],
                usedModelRouting: false,
                "管理员 AI 设置未满足真实试跑前置条件；请启用 provider、配置密钥并明确允许 draft/test 试跑。");
        }

        if (request.UseModelRouting)
        {
            var route = modelRouter.Route(new(
                normalizedTaskType,
                routingMode,
                "active",
                request.ExpectedConfidence,
                request.RiskSignals));
            normalizedModel = route.EffectiveModelName;
            effectiveReasoningEffort = route.EffectiveReasoningEffort;
            effectiveExecutionSlot = route.EffectiveExecutionSlot;
            effectiveExecutionGrade = route.EffectiveExecutionGrade;
            effectivePreset = route.EffectivePreset;
            routingAudit.AddRange([
                $"routing_source=effective_route",
                $"routing_task_type={route.TaskType}",
                $"routing_mode={route.Mode}",
                $"routing_model_role={route.EffectiveModelRole}",
                $"routing_model={route.EffectiveModelName}",
                $"routing_reasoning_effort={route.EffectiveReasoningEffort}",
                $"routing_execution_slot={route.EffectiveExecutionSlot}",
                $"routing_execution_grade={route.EffectiveExecutionGrade}",
                $"routing_model_preset={route.EffectivePreset}",
                $"routing_escalated={route.Escalated.ToString().ToLowerInvariant()}",
                $"routing_escalation_reasons={string.Join(',', route.EscalationReasons)}"
            ]);

            if (route.Blockers.Count > 0)
            {
                return CreateBlockedResult(
                    settings,
                    normalizedModel,
                    normalizedTaskType,
                    effectiveReasoningEffort,
                    effectiveExecutionSlot,
                    effectiveExecutionGrade,
                    effectivePreset,
                    routingMode,
                    runtimeEndpoints,
                    route.Blockers,
                    [
                        "test_admin_ai_provider_settings_blocked",
                        "routing_blocked_before_provider_request",
                        ..routingAudit,
                        ..route.Blockers
                    ],
                    usedModelRouting: true,
                    "当前路由未满足真实试跑门禁，未执行 provider 请求。"
                );
            }
        }
        else
        {
            routingAudit.AddRange([
                "routing_source=manual_model_override",
                $"routing_model={normalizedModel}",
                $"routing_reasoning_effort={effectiveReasoningEffort}"
            ]);
        }

        using var providerPermit = await invocationGate.EnterAsync(settings.MaxConcurrency, cancellationToken);
        var smokeResult = await RunStructuredSmokeWithFallbackAsync(
            runtimeEndpoints,
            normalizedModel,
            normalizedTaskType,
            effectiveReasoningEffort,
            request.InputJson,
            routingAudit,
            executionSlot: effectiveExecutionSlot,
            executionGrade: effectiveExecutionGrade,
            allowModelFailover: request.UseModelRouting,
            cancellationToken: cancellationToken);
        var imageProbe = await RunImageProbeAsync(runtimeEndpoints, cancellationToken);

        var combinedPassed = smokeResult.Passed && imageProbe.Passed;
        var combinedBlockers = new List<string>();
        if (!smokeResult.Passed)
        {
            combinedBlockers.Add("primary_structured_smoke_failed");
        }

        if (!imageProbe.Passed)
        {
            combinedBlockers.Add("image_probe_failed");
        }

        var status = combinedPassed
            ? "ok"
            : smokeResult.Passed || imageProbe.Passed
                ? "partial"
                : "failed";

        return new AdminAiProviderSettingsTestResult(
            Status: status,
            Mode: "draft_test",
            ProductionEligible: false,
            ProviderProfileId: settings.ProviderProfileId,
            ProviderType: settings.ProviderType,
            Model: smokeResult.Model,
            TaskType: normalizedTaskType,
            EffectiveReasoningEffort: smokeResult.ReasoningEffort,
            EffectiveExecutionSlot: smokeResult.ExecutionSlot,
            EffectiveExecutionGrade: smokeResult.ExecutionGrade,
            EffectivePreset: smokeResult.PresetId,
            RoutingMode: routingMode,
            UsedModelRouting: usedModelRouting,
            ReviewStatus: "pending_review",
            Passed: smokeResult.Passed,
            CombinedPassed: combinedPassed,
            EffectiveProviderEndpointId: smokeResult.ProviderEndpointId,
            EffectiveBaseUrl: smokeResult.BaseUrl,
            HttpStatusCode: smokeResult.HttpStatusCode,
            Message: BuildCombinedSmokeMessage(smokeResult, imageProbe),
            OutputJson: smokeResult.OutputJson,
            InputTokens: smokeResult.InputTokens,
            OutputTokens: smokeResult.OutputTokens,
            CachedTokens: smokeResult.CachedTokens,
            Cost: 0,
            LatencyMs: smokeResult.LatencyMs,
            Blockers: combinedBlockers,
            Attempts: smokeResult.Attempts,
            ImageProbe: imageProbe,
            AuditTrail: [
                ..smokeResult.AuditTrail,
                ..imageProbe.AuditTrail,
                $"combined_passed={combinedPassed.ToString().ToLowerInvariant()}",
                $"fallback_attempt_count={Math.Max(0, smokeResult.Attempts.Select(x => x.Model).Distinct(StringComparer.OrdinalIgnoreCase).Count() - 1)}"
            ]);
    }

    private async Task<StructuredSmokeExecutionResult> RunStructuredSmokeWithFallbackAsync(
        IReadOnlyList<AiProviderRuntimeEndpoint> endpoints,
        string model,
        string taskType,
        string reasoningEffort,
        string? inputJson,
        IReadOnlyList<string> routingAudit,
        string executionSlot,
        string executionGrade,
        bool allowModelFailover,
        CancellationToken cancellationToken)
    {
        var attempts = new List<AdminAiProviderProbeAttempt>();
        StructuredSmokeExecutionResult? lastResult = null;
        var modelCandidates = allowModelFailover
            ? modelRouter.GetFailoverCandidates(model, reasoningEffort, executionSlot, executionGrade)
            : [new AiModelFailoverCandidate("manual", model, reasoningEffort, false, executionSlot, executionGrade)];

        foreach (var candidate in modelCandidates)
        {
            foreach (var endpoint in endpoints)
            {
                if (string.IsNullOrWhiteSpace(endpoint.BaseUrl) || string.IsNullOrWhiteSpace(endpoint.Secret))
                {
                    attempts.Add(new AdminAiProviderProbeAttempt(
                        ProviderEndpointId: endpoint.EndpointId,
                        BaseUrl: endpoint.BaseUrl,
                        RouteKind: "models_availability",
                        EndpointPath: modelRouter.ModelAvailabilityProbePath,
                        Model: candidate.ModelName,
                        ReasoningEffort: candidate.ReasoningEffort,
                        Passed: false,
                        HttpStatusCode: 0,
                        LatencyMs: 0,
                        Message: "endpoint base URL 或 key 未配置，已跳过。"));
                    continue;
                }

                if (!string.Equals(candidate.PresetId, "manual", StringComparison.OrdinalIgnoreCase))
                {
                    var availabilityAttempt = await ProbeModelAvailabilityAsync(endpoint, candidate, cancellationToken);
                    attempts.Add(availabilityAttempt);
                    if (!availabilityAttempt.Passed)
                    {
                        modelRouter.RecordProviderAvailabilityFailure(candidate, availabilityAttempt.HttpStatusCode);
                        lastResult = CreateModelUnavailableSmokeResult(endpoint, candidate, availabilityAttempt, routingAudit);
                        continue;
                    }
                }

                var result = await RunStructuredSmokeAsync(
                    endpoint,
                    candidate,
                    taskType,
                    inputJson,
                    routingAudit,
                    cancellationToken);
                attempts.Add(new AdminAiProviderProbeAttempt(
                    ProviderEndpointId: endpoint.EndpointId,
                    BaseUrl: endpoint.BaseUrl,
                    RouteKind: "responses_structured",
                    EndpointPath: "/responses",
                    Model: candidate.ModelName,
                    ReasoningEffort: candidate.ReasoningEffort,
                    Passed: result.Passed,
                    HttpStatusCode: result.HttpStatusCode,
                    LatencyMs: result.LatencyMs,
                    Message: result.Message));
                lastResult = result;
                if (result.Passed)
                {
                    modelRouter.RecordProviderExecutionSuccess(candidate);
                    return result with
                    {
                        Attempts = attempts,
                        AuditTrail = [
                            ..result.AuditTrail,
                            $"selected_provider_endpoint={endpoint.EndpointId}",
                            $"selected_provider_base_url={endpoint.BaseUrl}",
                            $"selected_model_preset={candidate.PresetId}",
                            $"selected_execution_slot={candidate.ExecutionSlot}",
                            $"selected_execution_grade={candidate.ExecutionGrade}",
                            $"selected_model={candidate.ModelName}",
                            $"selected_reasoning_effort={candidate.ReasoningEffort}",
                            $"model_failover_used={candidate.IsFallback.ToString().ToLowerInvariant()}"
                        ]
                    };
                }

                if (!IsRetryableProviderFailure(result.HttpStatusCode))
                {
                    return result with
                    {
                        Attempts = attempts,
                        AuditTrail = [
                            ..result.AuditTrail,
                            $"selected_provider_endpoint={endpoint.EndpointId}",
                            $"selected_provider_base_url={endpoint.BaseUrl}",
                            $"selected_model_preset={candidate.PresetId}",
                            "model_failover_skipped=non_retryable_provider_response"
                        ]
                    };
                }

                modelRouter.RecordProviderAvailabilityFailure(candidate, result.HttpStatusCode);
            }
        }

        return (lastResult ?? CreateNoEndpointSmokeResult()) with
        {
            Attempts = attempts,
            AuditTrail = [
                ..(lastResult?.AuditTrail ?? []),
                "selected_provider_endpoint=",
                "selected_provider_base_url="
            ]
        };
    }

    private async Task<AdminAiProviderProbeAttempt> ProbeModelAvailabilityAsync(
        AiProviderRuntimeEndpoint endpoint,
        AiModelFailoverCandidate candidate,
        CancellationToken cancellationToken)
    {
        using var message = new HttpRequestMessage(HttpMethod.Get, $"{endpoint.BaseUrl}{modelRouter.ModelAvailabilityProbePath}");
        ApplyGatewayCompatibilityHeaders(message);
        message.Headers.TryAddWithoutValidation("X-KQG-Model-Probe", candidate.ModelName);
        message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", endpoint.Secret);

        var startedAt = DateTimeOffset.UtcNow;
        try
        {
            using var response = await httpClient.SendAsync(message, cancellationToken);
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            var latencyMs = (int)Math.Max(1, (DateTimeOffset.UtcNow - startedAt).TotalMilliseconds);
            var modelListed = response.IsSuccessStatusCode && BodyListsModel(body, candidate.ModelName);
            var messageText = modelListed
                ? "模型可用性探测通过。"
                : response.IsSuccessStatusCode
                    ? $"模型 {candidate.ModelName} 未出现在可用模型列表中。"
                    : DescribeResponseFailure(body, (int)response.StatusCode);
            return new AdminAiProviderProbeAttempt(
                ProviderEndpointId: endpoint.EndpointId,
                BaseUrl: endpoint.BaseUrl,
                RouteKind: "models_availability",
                EndpointPath: modelRouter.ModelAvailabilityProbePath,
                Model: candidate.ModelName,
                ReasoningEffort: candidate.ReasoningEffort,
                Passed: modelListed,
                HttpStatusCode: (int)response.StatusCode,
                LatencyMs: latencyMs,
                Message: messageText);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            return new AdminAiProviderProbeAttempt(
                ProviderEndpointId: endpoint.EndpointId,
                BaseUrl: endpoint.BaseUrl,
                RouteKind: "models_availability",
                EndpointPath: modelRouter.ModelAvailabilityProbePath,
                Model: candidate.ModelName,
                ReasoningEffort: candidate.ReasoningEffort,
                Passed: false,
                HttpStatusCode: 0,
                LatencyMs: (int)Math.Max(1, (DateTimeOffset.UtcNow - startedAt).TotalMilliseconds),
                Message: ex.Message);
        }
    }

    private static StructuredSmokeExecutionResult CreateModelUnavailableSmokeResult(
        AiProviderRuntimeEndpoint endpoint,
        AiModelFailoverCandidate candidate,
        AdminAiProviderProbeAttempt availabilityAttempt,
        IReadOnlyList<string> routingAudit)
    {
        return new StructuredSmokeExecutionResult(
            Model: candidate.ModelName,
            ReasoningEffort: candidate.ReasoningEffort,
            PresetId: candidate.PresetId,
            ExecutionSlot: candidate.ExecutionSlot,
            ExecutionGrade: candidate.ExecutionGrade,
            ProviderEndpointId: endpoint.EndpointId,
            BaseUrl: endpoint.BaseUrl,
            Passed: false,
            HttpStatusCode: availabilityAttempt.HttpStatusCode,
            Message: $"模型可用性探测未通过：{availabilityAttempt.Message}",
            OutputJson: "{}",
            InputTokens: 0,
            OutputTokens: 0,
            CachedTokens: 0,
            LatencyMs: availabilityAttempt.LatencyMs,
            Attempts: [],
            AuditTrail: [
                "test_admin_ai_model_availability_probe_failed",
                ..routingAudit,
                $"provider_endpoint={endpoint.EndpointId}",
                $"model_preset={candidate.PresetId}",
                $"model={candidate.ModelName}",
                $"reasoning_effort={candidate.ReasoningEffort}"
            ]);
    }

    private async Task<StructuredSmokeExecutionResult> RunStructuredSmokeAsync(
        AiProviderRuntimeEndpoint endpoint,
        AiModelFailoverCandidate candidate,
        string taskType,
        string? inputJson,
        IReadOnlyList<string> routingAudit,
        CancellationToken cancellationToken)
    {
        using var schema = CreateConnectivitySmokeSchema();
        var payload = new
        {
            model = candidate.ModelName,
            store = false,
            reasoning = new
            {
                effort = candidate.ReasoningEffort
            },
            input = NormalizeInputJson(inputJson, taskType),
            text = new
            {
                format = new
                {
                    type = "json_schema",
                    name = "cockpit_connectivity_smoke_result",
                    strict = true,
                    schema
                }
            }
        };

        using var message = new HttpRequestMessage(HttpMethod.Post, $"{endpoint.BaseUrl}/responses");
        ApplyGatewayCompatibilityHeaders(message);
        message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", endpoint.Secret);
        message.Content = new StringContent(JsonSerializer.Serialize(payload, JsonOptions), Encoding.UTF8, "application/json");

        var startedAt = DateTimeOffset.UtcNow;
        try
        {
            using var response = await httpClient.SendAsync(message, cancellationToken);
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            var latencyMs = (int)Math.Max(1, (DateTimeOffset.UtcNow - startedAt).TotalMilliseconds);
            var parsed = ParseSmokeResponse(body);
            return new StructuredSmokeExecutionResult(
                Model: candidate.ModelName,
                ReasoningEffort: candidate.ReasoningEffort,
                PresetId: candidate.PresetId,
                ExecutionSlot: candidate.ExecutionSlot,
                ExecutionGrade: candidate.ExecutionGrade,
                ProviderEndpointId: endpoint.EndpointId,
                BaseUrl: endpoint.BaseUrl,
                Passed: response.IsSuccessStatusCode,
                HttpStatusCode: (int)response.StatusCode,
                Message: response.IsSuccessStatusCode ? "结构化 smoke 试跑完成。" : $"主 responses 试跑失败：{DescribeResponseFailure(body, (int)response.StatusCode)}",
                OutputJson: parsed.outputJson,
                InputTokens: parsed.inputTokens,
                OutputTokens: parsed.outputTokens,
                CachedTokens: parsed.cachedTokens,
                LatencyMs: latencyMs,
                Attempts: [],
                AuditTrail: [
                    "test_admin_ai_provider_settings",
                    ..routingAudit,
                    $"task_type={taskType}",
                    $"provider_endpoint={endpoint.EndpointId}",
                    $"http_status={(int)response.StatusCode}",
                    "review_status=pending_review"
                ]);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            return new StructuredSmokeExecutionResult(
                Model: candidate.ModelName,
                ReasoningEffort: candidate.ReasoningEffort,
                PresetId: candidate.PresetId,
                ExecutionSlot: candidate.ExecutionSlot,
                ExecutionGrade: candidate.ExecutionGrade,
                ProviderEndpointId: endpoint.EndpointId,
                BaseUrl: endpoint.BaseUrl,
                Passed: false,
                HttpStatusCode: 0,
                Message: $"主 responses 试跑异常：{ex.Message}",
                OutputJson: "{}",
                InputTokens: 0,
                OutputTokens: 0,
                CachedTokens: 0,
                LatencyMs: (int)Math.Max(1, (DateTimeOffset.UtcNow - startedAt).TotalMilliseconds),
                Attempts: [],
                AuditTrail: [
                    "test_admin_ai_provider_settings_exception",
                    $"provider_endpoint={endpoint.EndpointId}",
                    "provider_request_failed"
                ]);
        }
    }

    private static IReadOnlyList<AiProviderRuntimeEndpoint> ApplyEndpointOverrides(
        IReadOnlyList<AiProviderRuntimeEndpoint> endpoints,
        AdminAiProviderSettingsTestRequest request)
    {
        if (!string.IsNullOrWhiteSpace(request.FallbackBaseUrlOverride)
            || !string.IsNullOrWhiteSpace(request.FallbackImageBaseUrlOverride))
        {
            throw new AiProviderSettingsException("cockpit_endpoint_fallback_not_supported");
        }

        return endpoints
            .Select(endpoint =>
            {
                if (endpoint.EndpointId == "primary")
                {
                    var baseUrl = NormalizeBaseUrl(request.BaseUrlOverride, endpoint.BaseUrl);
                    var imageBaseUrl = NormalizeBaseUrl(request.ImageBaseUrlOverride, endpoint.ImageBaseUrl);
                    return endpoint with
                    {
                        BaseUrl = baseUrl,
                        ImageBaseUrl = imageBaseUrl
                    };
                }

                return endpoint;
            })
            .ToArray();
    }

    private static string GetFirstImageBaseUrl(IReadOnlyList<AiProviderRuntimeEndpoint> endpoints)
    {
        return endpoints.FirstOrDefault(x => !string.IsNullOrWhiteSpace(x.ImageBaseUrl))?.ImageBaseUrl ?? "";
    }

    private static StructuredSmokeExecutionResult CreateNoEndpointSmokeResult()
    {
        return new StructuredSmokeExecutionResult(
            Model: "",
            ReasoningEffort: "",
            PresetId: "",
            ExecutionSlot: "",
            ExecutionGrade: "",
            ProviderEndpointId: "",
            BaseUrl: "",
            Passed: false,
            HttpStatusCode: 0,
            Message: "没有可用的 provider endpoint，未执行结构化 smoke。",
            OutputJson: "{}",
            InputTokens: 0,
            OutputTokens: 0,
            CachedTokens: 0,
            LatencyMs: 0,
            Attempts: [],
            AuditTrail: ["test_admin_ai_provider_settings_no_endpoint"]);
    }

    private async Task<AdminAiProviderImageProbeResult> RunImageProbeAsync(
        IReadOnlyList<AiProviderRuntimeEndpoint> endpoints,
        CancellationToken cancellationToken)
    {
        if (!endpoints.Any(x => !string.IsNullOrWhiteSpace(x.ImageBaseUrl) && !string.IsNullOrWhiteSpace(x.ImageSecret)))
        {
            return CreateNotAttemptedImageProbe(
                GetFirstImageBaseUrl(endpoints),
                "图片 key 不可用，未执行图片链路探针。",
                ["image_secret_unavailable"]);
        }

        var attempts = new List<AdminAiProviderImageProbeAttempt>();
        foreach (var endpoint in endpoints)
        {
            if (string.IsNullOrWhiteSpace(endpoint.ImageBaseUrl) || string.IsNullOrWhiteSpace(endpoint.ImageSecret))
            {
                attempts.Add(new AdminAiProviderImageProbeAttempt(
                    ProviderEndpointId: endpoint.EndpointId,
                    BaseUrl: endpoint.ImageBaseUrl,
                    RouteKind: "images_generations",
                    EndpointPath: "/images/generations",
                    Model: ImageProbeFallbackModel,
                    Passed: false,
                    HttpStatusCode: 0,
                    LatencyMs: 0,
                    Message: "endpoint 图片 base URL 或 key 未配置，已跳过。"));
                continue;
            }

            var imagesApiAttempt = await ProbeImagesApiAsync(endpoint, cancellationToken);
            attempts.Add(imagesApiAttempt);
            if (imagesApiAttempt.Passed)
            {
                return new AdminAiProviderImageProbeResult(
                    Attempted: true,
                    Passed: true,
                    EffectiveProviderEndpointId: endpoint.EndpointId,
                    EffectiveBaseUrl: endpoint.ImageBaseUrl,
                    EffectiveRouteKind: imagesApiAttempt.RouteKind,
                    EffectiveModel: imagesApiAttempt.Model,
                    HttpStatusCode: imagesApiAttempt.HttpStatusCode,
                    LatencyMs: imagesApiAttempt.LatencyMs,
                    Message: "图片链路探针通过：Images API 成功返回图片结果。",
                    Blockers: [],
                    Attempts: attempts,
                    AuditTrail: [
                        "test_admin_ai_image_probe",
                        $"selected_provider_endpoint={endpoint.EndpointId}",
                        "image_probe_route=images_generations",
                        $"images_probe_http_status={imagesApiAttempt.HttpStatusCode}"
                    ]);
            }
        }

        var lastAttempt = attempts.LastOrDefault();
        return new AdminAiProviderImageProbeResult(
            Attempted: true,
            Passed: false,
            EffectiveProviderEndpointId: "",
            EffectiveBaseUrl: lastAttempt?.BaseUrl ?? GetFirstImageBaseUrl(endpoints),
            EffectiveRouteKind: "failed",
            EffectiveModel: ImageProbeFallbackModel,
            HttpStatusCode: lastAttempt?.HttpStatusCode ?? 0,
            LatencyMs: lastAttempt?.LatencyMs ?? 0,
            Message: $"图片链路探针未通过：已尝试 {attempts.Count} 次 Cockpit 图片链路。",
            Blockers: ["image_probe_failed"],
            Attempts: attempts,
            AuditTrail: [
                "test_admin_ai_image_probe_failed",
                "selected_provider_endpoint=",
                $"fallback_attempt_count={Math.Max(0, attempts.Select(x => x.ProviderEndpointId).Distinct().Count() - 1)}"
            ]);
    }

    private async Task<AdminAiProviderImageProbeAttempt> ProbeImagesApiAsync(
        AiProviderRuntimeEndpoint endpoint,
        CancellationToken cancellationToken)
    {
        var payload = new
        {
            model = ImageProbeFallbackModel,
            prompt = ImageProbePrompt,
            quality = "low",
            size = "1024x1024",
            output_format = "jpeg"
        };

        return await SendImageProbeRequestAsync(
            endpoint,
            "/images/generations",
            ImageProbeFallbackModel,
            payload,
            "images_generations",
            BodyHasImageApiOutput,
            cancellationToken);
    }

    private async Task<AdminAiProviderImageProbeAttempt> SendImageProbeRequestAsync(
        AiProviderRuntimeEndpoint endpoint,
        string endpointPath,
        string model,
        object payload,
        string routeKind,
        Func<string, bool> successPredicate,
        CancellationToken cancellationToken)
    {
        using var message = new HttpRequestMessage(HttpMethod.Post, $"{endpoint.ImageBaseUrl}{endpointPath}");
        ApplyGatewayCompatibilityHeaders(message);
        message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", endpoint.ImageSecret);
        message.Content = new StringContent(JsonSerializer.Serialize(payload, JsonOptions), Encoding.UTF8, "application/json");

        var startedAt = DateTimeOffset.UtcNow;
        try
        {
            using var response = await httpClient.SendAsync(message, cancellationToken);
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            var latencyMs = (int)Math.Max(1, (DateTimeOffset.UtcNow - startedAt).TotalMilliseconds);
            var passed = response.IsSuccessStatusCode && successPredicate(body);
            const string successMessage = "Images API 成功返回图片结果。";
            var failureMessage = passed
                ? successMessage
                : DescribeResponseFailure(body, (int)response.StatusCode);
            return new AdminAiProviderImageProbeAttempt(
                ProviderEndpointId: endpoint.EndpointId,
                BaseUrl: endpoint.ImageBaseUrl,
                RouteKind: routeKind,
                EndpointPath: endpointPath,
                Model: model,
                Passed: passed,
                HttpStatusCode: (int)response.StatusCode,
                LatencyMs: latencyMs,
                Message: failureMessage);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            return new AdminAiProviderImageProbeAttempt(
                ProviderEndpointId: endpoint.EndpointId,
                BaseUrl: endpoint.ImageBaseUrl,
                RouteKind: routeKind,
                EndpointPath: endpointPath,
                Model: model,
                Passed: false,
                HttpStatusCode: 0,
                LatencyMs: (int)Math.Max(1, (DateTimeOffset.UtcNow - startedAt).TotalMilliseconds),
                Message: ex.Message);
        }
    }

    private static AdminAiProviderImageProbeResult CreateNotAttemptedImageProbe(
        string imageBaseUrl,
        string message,
        IReadOnlyList<string> blockers)
    {
        return new AdminAiProviderImageProbeResult(
            Attempted: false,
            Passed: false,
            EffectiveProviderEndpointId: "",
            EffectiveBaseUrl: imageBaseUrl,
            EffectiveRouteKind: "not_attempted",
            EffectiveModel: "",
            HttpStatusCode: 0,
            LatencyMs: 0,
            Message: message,
            Blockers: blockers,
            Attempts: [],
            AuditTrail: [
                "test_admin_ai_image_probe_skipped",
                ..blockers
            ]);
    }

    private static string BuildCombinedSmokeMessage(
        StructuredSmokeExecutionResult smokeResult,
        AdminAiProviderImageProbeResult imageProbe)
    {
        var primarySummary = smokeResult.Passed
            ? $"结构化 smoke 已通过（{smokeResult.ProviderEndpointId}）"
            : $"结构化 smoke 未通过（HTTP {smokeResult.HttpStatusCode}）";
        var imageSummary = !imageProbe.Attempted
            ? "图片链路探针未执行"
            : imageProbe.Passed
                ? $"图片链路探针已通过（{imageProbe.EffectiveProviderEndpointId}/{imageProbe.EffectiveRouteKind}）"
                : "图片链路探针未通过";
        return $"{primarySummary}；{imageSummary}。结果仅作 pending_review 候选验证。";
    }

    private static AdminAiProviderSettingsTestResult CreateBlockedResult(
        AdminAiProviderSettingsContract settings,
        string model,
        string taskType,
        string reasoningEffort,
        string executionSlot,
        string executionGrade,
        string preset,
        string routingMode,
        IReadOnlyList<AiProviderRuntimeEndpoint> endpoints,
        IReadOnlyList<string> blockers,
        IReadOnlyList<string> auditTrail,
        bool usedModelRouting,
        string message)
    {
        return new AdminAiProviderSettingsTestResult(
            Status: "blocked",
            Mode: "draft_test",
            ProductionEligible: false,
            ProviderProfileId: settings.ProviderProfileId,
            ProviderType: settings.ProviderType,
            Model: model,
            TaskType: taskType,
            EffectiveReasoningEffort: reasoningEffort,
            EffectiveExecutionSlot: executionSlot,
            EffectiveExecutionGrade: executionGrade,
            EffectivePreset: preset,
            RoutingMode: routingMode,
            UsedModelRouting: usedModelRouting,
            ReviewStatus: "pending_review",
            Passed: false,
            CombinedPassed: false,
            EffectiveProviderEndpointId: "",
            EffectiveBaseUrl: "",
            HttpStatusCode: 0,
            Message: message,
            OutputJson: "{}",
            InputTokens: 0,
            OutputTokens: 0,
            CachedTokens: 0,
            Cost: 0,
            LatencyMs: 0,
            Blockers: blockers,
            Attempts: [],
            ImageProbe: CreateNotAttemptedImageProbe(
                GetFirstImageBaseUrl(endpoints),
                "当前门禁未满足，未执行图片链路探针。",
                blockers),
            AuditTrail: auditTrail);
    }

    private static string NormalizeTaskType(string? value, string fallback) =>
        string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();

    private static bool IsRetryableProviderFailure(int httpStatusCode)
    {
        return httpStatusCode == 0
            || httpStatusCode == StatusCodes.Status404NotFound
            || httpStatusCode == StatusCodes.Status408RequestTimeout
            || httpStatusCode == StatusCodes.Status429TooManyRequests
            || httpStatusCode >= StatusCodes.Status500InternalServerError;
    }

    private static string NormalizeModel(string? value, string fallback) =>
        string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();

    private static string NormalizeRoutingMode(string? value) =>
        string.IsNullOrWhiteSpace(value) ? "balanced" : value.Trim().ToLowerInvariant();

    private static void ApplyGatewayCompatibilityHeaders(HttpRequestMessage message)
    {
        message.Headers.UserAgent.ParseAdd(GatewayUserAgent);
        foreach (var mediaType in GatewayAcceptHeader.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            message.Headers.Accept.ParseAdd(mediaType);
        }
    }

    private static string NormalizeBaseUrl(string? overrideValue, string fallback)
    {
        var source = string.IsNullOrWhiteSpace(overrideValue) ? fallback : overrideValue.Trim();
        return CockpitGatewayPolicy.NormalizeRequired(source);
    }

    private static string NormalizeInputJson(string? value, string taskType)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            return value;
        }

        return taskType switch
        {
            "question_extraction" => "请根据题目图片 OCR 文本，输出结构化题目草稿。",
            "natural_language_paper_request" => "请把这段教师组卷需求解析成结构化蓝图。",
            "question_solving" => "请独立解答这道物理题，给出答案、关键步骤与可复核依据。",
            "answer_verification" => "请独立校验一道物理题答案与解析是否一致。",
            _ => "请给出初中物理知识点映射候选，并保留人工复核边界。"
        };
    }

    private static JsonDocument CreateConnectivitySmokeSchema() => JsonDocument.Parse("""
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["status"],
      "properties": {
        "status": { "type": "string" }
      }
    }
    """);

    private static (string outputJson, int inputTokens, int outputTokens, int cachedTokens) ParseSmokeResponse(string body)
    {
        try
        {
            using var document = JsonDocument.Parse(body);
            var root = document.RootElement;
            var usage = root.TryGetProperty("usage", out var usageElement) ? usageElement : default;
            var inputTokens = usage.ValueKind == JsonValueKind.Object && usage.TryGetProperty("input_tokens", out var inputTokenElement)
                ? inputTokenElement.GetInt32()
                : 0;
            var outputTokens = usage.ValueKind == JsonValueKind.Object && usage.TryGetProperty("output_tokens", out var outputTokenElement)
                ? outputTokenElement.GetInt32()
                : 0;
            var cachedTokens = usage.ValueKind == JsonValueKind.Object &&
                usage.TryGetProperty("input_tokens_details", out var detailsElement) &&
                detailsElement.TryGetProperty("cached_tokens", out var cachedTokenElement)
                ? cachedTokenElement.GetInt32()
                : 0;
            var outputJson = root.TryGetProperty("output_text", out var outputTextElement)
                ? outputTextElement.GetString() ?? "{}"
                : body;
            return (outputJson, inputTokens, outputTokens, cachedTokens);
        }
        catch
        {
            return (body, 0, 0, 0);
        }
    }

    private static bool BodyHasImageApiOutput(string body)
    {
        try
        {
            using var document = JsonDocument.Parse(body);
            if (!document.RootElement.TryGetProperty("data", out var data) || data.ValueKind != JsonValueKind.Array || data.GetArrayLength() == 0)
            {
                return false;
            }

            foreach (var item in data.EnumerateArray())
            {
                if (item.TryGetProperty("b64_json", out var outputElement) &&
                    outputElement.ValueKind == JsonValueKind.String &&
                    !string.IsNullOrWhiteSpace(outputElement.GetString()))
                {
                    return true;
                }
            }
        }
        catch
        {
        }

        return false;
    }

    private static bool BodyListsModel(string body, string modelName)
    {
        if (string.IsNullOrWhiteSpace(body) || string.IsNullOrWhiteSpace(modelName))
        {
            return false;
        }

        try
        {
            using var document = JsonDocument.Parse(body);
            if (!document.RootElement.TryGetProperty("data", out var data) || data.ValueKind != JsonValueKind.Array)
            {
                return false;
            }

            return data.EnumerateArray().Any(item =>
                item.ValueKind == JsonValueKind.Object &&
                item.TryGetProperty("id", out var id) &&
                id.ValueKind == JsonValueKind.String &&
                string.Equals(id.GetString(), modelName, StringComparison.OrdinalIgnoreCase));
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static string DescribeResponseFailure(string body, int httpStatusCode)
    {
        var errorMessage = TryReadErrorMessage(body);
        if (!string.IsNullOrWhiteSpace(errorMessage))
        {
            return $"HTTP {httpStatusCode}: {errorMessage}";
        }

        return $"HTTP {httpStatusCode}";
    }

    private static string TryReadErrorMessage(string body)
    {
        if (string.IsNullOrWhiteSpace(body))
        {
            return string.Empty;
        }

        try
        {
            using var document = JsonDocument.Parse(body);
            var root = document.RootElement;
            if (root.TryGetProperty("error", out var errorElement) &&
                errorElement.ValueKind == JsonValueKind.Object &&
                errorElement.TryGetProperty("message", out var nestedMessage) &&
                nestedMessage.ValueKind == JsonValueKind.String)
            {
                return nestedMessage.GetString() ?? string.Empty;
            }

            if (root.TryGetProperty("message", out var messageElement) &&
                messageElement.ValueKind == JsonValueKind.String)
            {
                return messageElement.GetString() ?? string.Empty;
            }
        }
        catch
        {
        }

        return string.Empty;
    }

    private sealed record StructuredSmokeExecutionResult(
        string Model,
        string ReasoningEffort,
        string PresetId,
        string ExecutionSlot,
        string ExecutionGrade,
        string ProviderEndpointId,
        string BaseUrl,
        bool Passed,
        int HttpStatusCode,
        string Message,
        string OutputJson,
        int InputTokens,
        int OutputTokens,
        int CachedTokens,
        int LatencyMs,
        IReadOnlyList<AdminAiProviderProbeAttempt> Attempts,
        IReadOnlyList<string> AuditTrail);
}

internal sealed class AiProviderProfilesDefaultsDocument
{
    public List<AiProviderProfilesDefaultsProfile>? ProviderProfiles { get; init; }
}

internal sealed class AiProviderProfilesDefaultsProfile
{
    public string? Id { get; init; }
    public string? BaseUrl { get; init; }
    public int? MaxConcurrency { get; init; }
    public int? MonthlyBudgetCny { get; init; }
}
