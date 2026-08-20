using System.Net.Http.Headers;
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
    string? FallbackImageBaseUrlOverride);

public sealed record AdminAiProviderProbeAttempt(
    string ProviderEndpointId,
    string BaseUrl,
    string RouteKind,
    string EndpointPath,
    string Model,
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
    private const string PrimaryEnvSecretName = "KQG_AI_OPENAI_KEY";
    private const string PrimaryEnvBaseUrlName = "KQG_AI_OPENAI_BASE_URL";
    private const string ImageEnvSecretName = "KQG_AI_IMAGE_OPENAI_KEY";
    private const string ImageEnvBaseUrlName = "KQG_AI_IMAGE_OPENAI_BASE_URL";
    private const string LegacyPrimaryEnvSecretName = "TEXT_PROVIDER_API_KEY";
    private const string LegacyPrimaryEnvBaseUrlName = "TEXT_PROVIDER_BASE_URL";
    private const string LegacyPrimaryEnvModelName = "TEXT_PROVIDER_MODEL";
    private const string LegacyImageEnvSecretName = "IMAGE_PROVIDER_API_KEY_1";
    private const string LegacyImageEnvBaseUrlName = "IMAGE_PROVIDER_BASE_URL";
    private const string FallbackEnvSecretName = "KQG_AI_FALLBACK_1_OPENAI_KEY";
    private const string FallbackEnvBaseUrlName = "KQG_AI_FALLBACK_1_OPENAI_BASE_URL";
    private const string FallbackImageEnvSecretName = "KQG_AI_FALLBACK_1_IMAGE_OPENAI_KEY";
    private const string FallbackImageEnvBaseUrlName = "KQG_AI_FALLBACK_1_IMAGE_OPENAI_BASE_URL";
    private const string LegacyFallbackEnvSecretName = "TEXT_PROVIDER_FALLBACK_1_API_KEY";
    private const string LegacyFallbackEnvBaseUrlName = "TEXT_PROVIDER_FALLBACK_1_BASE_URL";
    private const string LegacyFallbackImageEnvSecretName = "IMAGE_PROVIDER_FALLBACK_1_API_KEY_1";
    private const string LegacyFallbackImageEnvBaseUrlName = "IMAGE_PROVIDER_FALLBACK_1_BASE_URL";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web) { WriteIndented = true };
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

        var existing = await LoadStoredAsync(cancellationToken);
        var normalizedSecret = request.ApiKey?.Trim();
        var normalizedImageSecret = request.ImageApiKey?.Trim();
        var normalizedFallbackSecret = request.FallbackApiKey?.Trim();
        var normalizedFallbackImageSecret = request.FallbackImageApiKey?.Trim();
        var secretCiphertext = string.IsNullOrWhiteSpace(normalizedSecret)
            ? existing.SecretCiphertext
            : ProtectSecret(normalizedSecret);
        var imageSecretCiphertext = normalizedImageSecret is null
            ? existing.ImageSecretCiphertext
            : string.IsNullOrWhiteSpace(normalizedImageSecret)
                ? string.Empty
                : ProtectSecret(normalizedImageSecret);
        var fallbackSecretCiphertext = string.IsNullOrWhiteSpace(normalizedFallbackSecret)
            ? existing.FallbackSecretCiphertext
            : ProtectSecret(normalizedFallbackSecret);
        var fallbackImageSecretCiphertext = normalizedFallbackImageSecret is null
            ? existing.FallbackImageSecretCiphertext
            : string.IsNullOrWhiteSpace(normalizedFallbackImageSecret)
                ? string.Empty
                : ProtectSecret(normalizedFallbackImageSecret);
        var now = DateTimeOffset.UtcNow;
        var stored = new StoredAdminAiProviderSettings(
            SchemaVersion,
            Normalize(request.ProviderProfileId, DefaultProviderProfileId),
            DefaultProviderType,
            NormalizeBaseUrl(request.BaseUrl),
            NormalizeOptionalBaseUrl(request.ImageBaseUrl),
            DefaultCredentialMode,
            secretCiphertext,
            imageSecretCiphertext,
            NormalizeOptionalBaseUrl(request.FallbackBaseUrl),
            NormalizeOptionalBaseUrl(request.FallbackImageBaseUrl),
            fallbackSecretCiphertext,
            fallbackImageSecretCiphertext,
            NormalizeRange(request.MaxConcurrency, 1, 8, fallback: existing.MaxConcurrency),
            NormalizeRange(request.MonthlyBudgetCny, 0, 100000, fallback: existing.MonthlyBudgetCny),
            request.DisabledByDefault,
            request.AllowRealModelCalls,
            Normalize(request.DefaultSmokeTaskType, existing.DefaultSmokeTaskType),
            Normalize(request.DefaultSmokeModel, existing.DefaultSmokeModel),
            now,
            Normalize(request.OperatorNote, existing.LastOperatorNote));

        Directory.CreateDirectory(Path.GetDirectoryName(GetSettingsFilePath())!);
        await File.WriteAllTextAsync(
            GetSettingsFilePath(),
            JsonSerializer.Serialize(stored, JsonOptions),
            Encoding.UTF8,
            cancellationToken);

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
            TeacherMessage: "管理员 AI 设置已保存；主备网关按顺序自动试跑，图片专用 key 留空时会复用同一路文本 key；本机仍只保留加密副本，试跑保持 pending_review。",
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
            return loaded is null ? BuildDefault() : NormalizeLoaded(loaded);
        }
        catch
        {
            return BuildDefault();
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
            TeacherMessage: "当前为管理员级本机 AI 设置；主备网关会按顺序试跑，图片专用 key 可选覆盖；普通教师侧仍只看到简化模式。",
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
        var envFallbackSecret = ReadFirstEnvironmentValue(FallbackEnvSecretName, LegacyFallbackEnvSecretName);
        var envFallbackBaseUrl = ReadFirstEnvironmentValue(FallbackEnvBaseUrlName, LegacyFallbackEnvBaseUrlName);
        var envFallbackImageSecret = ReadFirstEnvironmentValue(FallbackImageEnvSecretName, LegacyFallbackImageEnvSecretName);
        var envFallbackImageBaseUrl = ReadFirstEnvironmentValue(FallbackImageEnvBaseUrlName, LegacyFallbackImageEnvBaseUrlName);
        var envDefaultSmokeModel = ReadFirstEnvironmentValue(LegacyPrimaryEnvModelName);
        return new StoredAdminAiProviderSettings(
            SchemaVersion,
            DefaultProviderProfileId,
            DefaultProviderType,
            NormalizeBaseUrl(string.IsNullOrWhiteSpace(envPrimaryBaseUrl) ? defaults.baseUrl : envPrimaryBaseUrl),
            NormalizeOptionalBaseUrl(envImageBaseUrl),
            DefaultCredentialMode,
            string.IsNullOrWhiteSpace(envPrimarySecret) ? string.Empty : ProtectSecret(envPrimarySecret),
            string.IsNullOrWhiteSpace(envImageSecret) ? string.Empty : ProtectSecret(envImageSecret),
            NormalizeOptionalBaseUrl(envFallbackBaseUrl),
            NormalizeOptionalBaseUrl(envFallbackImageBaseUrl),
            string.IsNullOrWhiteSpace(envFallbackSecret) ? string.Empty : ProtectSecret(envFallbackSecret),
            string.IsNullOrWhiteSpace(envFallbackImageSecret) ? string.Empty : ProtectSecret(envFallbackImageSecret),
            defaults.maxConcurrency,
            defaults.monthlyBudgetCny,
            true,
            false,
            DefaultSmokeTaskType,
            Normalize(envDefaultSmokeModel, DefaultSmokeModel),
            DateTimeOffset.MinValue,
            string.Empty);
    }

    private StoredAdminAiProviderSettings NormalizeLoaded(StoredAdminAiProviderSettings loaded)
    {
        var defaults = LoadDefaultsFromYaml();
        return loaded with
        {
            ProviderProfileId = Normalize(loaded.ProviderProfileId, DefaultProviderProfileId),
            ProviderType = Normalize(loaded.ProviderType, DefaultProviderType),
            BaseUrl = NormalizeBaseUrl(string.IsNullOrWhiteSpace(loaded.BaseUrl) ? defaults.baseUrl : loaded.BaseUrl),
            ImageBaseUrl = NormalizeOptionalBaseUrl(loaded.ImageBaseUrl),
            FallbackBaseUrl = NormalizeOptionalBaseUrl(loaded.FallbackBaseUrl),
            FallbackImageBaseUrl = NormalizeOptionalBaseUrl(loaded.FallbackImageBaseUrl),
            FallbackSecretCiphertext = NormalizeOptionalCiphertext(loaded.FallbackSecretCiphertext),
            FallbackImageSecretCiphertext = NormalizeOptionalCiphertext(loaded.FallbackImageSecretCiphertext),
            CredentialMode = Normalize(loaded.CredentialMode, DefaultCredentialMode),
            MaxConcurrency = NormalizeRange(loaded.MaxConcurrency, 1, 8, defaults.maxConcurrency),
            MonthlyBudgetCny = NormalizeRange(loaded.MonthlyBudgetCny, 0, 100000, defaults.monthlyBudgetCny),
            DefaultSmokeTaskType = Normalize(loaded.DefaultSmokeTaskType, DefaultSmokeTaskType),
            DefaultSmokeModel = Normalize(loaded.DefaultSmokeModel, DefaultSmokeModel),
        };
    }

    private (string baseUrl, int maxConcurrency, int monthlyBudgetCny) LoadDefaultsFromYaml()
    {
        var repoRoot = Path.GetFullPath(Path.Combine(environment.ContentRootPath, "..", ".."));
        var yamlPath = Path.Combine(repoRoot, "configs", "ai-provider-profiles.defaults.yaml");
        if (!File.Exists(yamlPath))
        {
            return ("https://api.openai.com/v1", 2, 300);
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
                profile?.BaseUrl ?? "https://api.openai.com/v1",
                profile?.MaxConcurrency ?? 2,
                profile?.MonthlyBudgetCny ?? 300);
        }
        catch
        {
            return ("https://api.openai.com/v1", 2, 300);
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
        var normalized = Normalize(value, "https://api.openai.com/v1");
        return normalized.TrimEnd('/');
    }

    private static string NormalizeOptionalBaseUrl(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? string.Empty : value.Trim().TrimEnd('/');
    }

    private static string NormalizeOptionalCiphertext(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? string.Empty : value;
    }

    private IReadOnlyList<AdminAiProviderEndpointContract> BuildEndpointContracts(StoredAdminAiProviderSettings settings)
    {
        var primarySecret = UnprotectSecret(settings.SecretCiphertext);
        var primaryImageSecret = ResolveEffectiveImageSecret(primarySecret, settings.ImageSecretCiphertext);
        var explicitPrimaryImageSecret = UnprotectSecret(settings.ImageSecretCiphertext);
        var fallbackSecret = UnprotectSecret(settings.FallbackSecretCiphertext);
        var fallbackImageSecret = ResolveEffectiveImageSecret(fallbackSecret, settings.FallbackImageSecretCiphertext);
        var explicitFallbackImageSecret = UnprotectSecret(settings.FallbackImageSecretCiphertext);
        var endpoints = new List<AdminAiProviderEndpointContract>
        {
            new(
                EndpointId: "primary",
                Label: "主网关",
                IsFallback: false,
                BaseUrl: settings.BaseUrl,
                ImageBaseUrl: ResolveEffectiveImageBaseUrl(settings.BaseUrl, settings.ImageBaseUrl),
                MaskedSecret: MaskSecret(primarySecret),
                SecretConfigured: !string.IsNullOrWhiteSpace(primarySecret),
                MaskedImageSecret: MaskSecret(primaryImageSecret),
                ImageSecretConfigured: !string.IsNullOrWhiteSpace(primaryImageSecret),
                ImageUsesTextSecret: string.IsNullOrWhiteSpace(explicitPrimaryImageSecret))
        };

        if (!string.IsNullOrWhiteSpace(settings.FallbackBaseUrl) ||
            !string.IsNullOrWhiteSpace(settings.FallbackImageBaseUrl) ||
            !string.IsNullOrWhiteSpace(fallbackSecret) ||
            !string.IsNullOrWhiteSpace(explicitFallbackImageSecret))
        {
            endpoints.Add(new AdminAiProviderEndpointContract(
                EndpointId: "fallback_1",
                Label: "备用网关 1",
                IsFallback: true,
                BaseUrl: settings.FallbackBaseUrl,
                ImageBaseUrl: ResolveEffectiveImageBaseUrl(settings.FallbackBaseUrl, settings.FallbackImageBaseUrl),
                MaskedSecret: MaskSecret(fallbackSecret),
                SecretConfigured: !string.IsNullOrWhiteSpace(fallbackSecret),
                MaskedImageSecret: MaskSecret(fallbackImageSecret),
                ImageSecretConfigured: !string.IsNullOrWhiteSpace(fallbackImageSecret),
                ImageUsesTextSecret: string.IsNullOrWhiteSpace(explicitFallbackImageSecret)));
        }

        return endpoints;
    }

    private IReadOnlyList<AiProviderRuntimeEndpoint> BuildRuntimeEndpoints(StoredAdminAiProviderSettings settings)
    {
        var primarySecret = UnprotectSecret(settings.SecretCiphertext);
        var primaryImageSecret = ResolveEffectiveImageSecret(primarySecret, settings.ImageSecretCiphertext);
        var fallbackSecret = UnprotectSecret(settings.FallbackSecretCiphertext);
        var fallbackImageSecret = ResolveEffectiveImageSecret(fallbackSecret, settings.FallbackImageSecretCiphertext);
        var endpoints = new List<AiProviderRuntimeEndpoint>
        {
            new(
                EndpointId: "primary",
                Label: "主网关",
                IsFallback: false,
                BaseUrl: settings.BaseUrl,
                Secret: primarySecret,
                ImageBaseUrl: ResolveEffectiveImageBaseUrl(settings.BaseUrl, settings.ImageBaseUrl),
                ImageSecret: primaryImageSecret)
        };

        if (!string.IsNullOrWhiteSpace(settings.FallbackBaseUrl) ||
            !string.IsNullOrWhiteSpace(settings.FallbackImageBaseUrl) ||
            !string.IsNullOrWhiteSpace(fallbackSecret) ||
            !string.IsNullOrWhiteSpace(fallbackImageSecret))
        {
            endpoints.Add(new AiProviderRuntimeEndpoint(
                EndpointId: "fallback_1",
                Label: "备用网关 1",
                IsFallback: true,
                BaseUrl: settings.FallbackBaseUrl,
                Secret: fallbackSecret,
                ImageBaseUrl: ResolveEffectiveImageBaseUrl(settings.FallbackBaseUrl, settings.FallbackImageBaseUrl),
                ImageSecret: fallbackImageSecret));
        }

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
        catch
        {
            return string.Empty;
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
    IWebHostEnvironment environment)
{
    private const string ImageProbePrompt = "Generate a simple flat icon of a blue paper plane on a white background.";
    private const string ImageProbeFallbackModel = "gpt-image-2";
    private const string GatewayUserAgent = "codex_exec/k12-question-graph";
    private const string GatewayAcceptHeader = "application/json, text/event-stream";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<AdminAiProviderSettingsTestResult> RunAsync(
        AdminAiProviderSettingsContract settings,
        AdminAiProviderSettingsTestRequest request,
        CancellationToken cancellationToken)
    {
        var normalizedModel = NormalizeModel(request.Model, settings.DefaultSmokeModel);
        var normalizedTaskType = NormalizeTaskType(request.TaskType, settings.DefaultSmokeTaskType);
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

        if (blockers.Count > 0)
        {
            return new AdminAiProviderSettingsTestResult(
                Status: "blocked",
                Mode: "draft_test",
                ProductionEligible: false,
                ProviderProfileId: settings.ProviderProfileId,
                ProviderType: settings.ProviderType,
                Model: normalizedModel,
                TaskType: normalizedTaskType,
                ReviewStatus: "pending_review",
                Passed: false,
                CombinedPassed: false,
                EffectiveProviderEndpointId: "",
                EffectiveBaseUrl: "",
                HttpStatusCode: 0,
                Message: "管理员 AI 设置未满足真实试跑前置条件；请启用 provider、配置密钥并明确允许 draft/test 试跑。",
                OutputJson: "{}",
                InputTokens: 0,
                OutputTokens: 0,
                CachedTokens: 0,
                Cost: 0,
                LatencyMs: 0,
                Blockers: blockers,
                Attempts: [],
                ImageProbe: CreateNotAttemptedImageProbe(
                    GetFirstImageBaseUrl(runtimeEndpoints),
                    "主配置前置条件未满足，未执行图片链路探针。",
                    blockers),
                AuditTrail: [
                    "test_admin_ai_provider_settings_blocked",
                    ..blockers
                ]);
        }

        var smokeResult = await RunStructuredSmokeWithFallbackAsync(
            runtimeEndpoints,
            normalizedModel,
            normalizedTaskType,
            request.InputJson,
            cancellationToken);
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
            Model: normalizedModel,
            TaskType: normalizedTaskType,
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
                $"fallback_attempt_count={Math.Max(0, smokeResult.Attempts.Count - 1)}"
            ]);
    }

    private async Task<StructuredSmokeExecutionResult> RunStructuredSmokeWithFallbackAsync(
        IReadOnlyList<AiProviderRuntimeEndpoint> endpoints,
        string model,
        string taskType,
        string? inputJson,
        CancellationToken cancellationToken)
    {
        var attempts = new List<AdminAiProviderProbeAttempt>();
        StructuredSmokeExecutionResult? lastResult = null;

        foreach (var endpoint in endpoints)
        {
            if (string.IsNullOrWhiteSpace(endpoint.BaseUrl) || string.IsNullOrWhiteSpace(endpoint.Secret))
            {
                var skippedAttempt = new AdminAiProviderProbeAttempt(
                    ProviderEndpointId: endpoint.EndpointId,
                    BaseUrl: endpoint.BaseUrl,
                    RouteKind: "responses_structured",
                    EndpointPath: "/responses",
                    Model: model,
                    Passed: false,
                    HttpStatusCode: 0,
                    LatencyMs: 0,
                    Message: "endpoint base URL 或 key 未配置，已跳过。");
                attempts.Add(skippedAttempt);
                continue;
            }

            var result = await RunStructuredSmokeAsync(
                endpoint,
                model,
                taskType,
                inputJson,
                cancellationToken);
            attempts.Add(new AdminAiProviderProbeAttempt(
                ProviderEndpointId: endpoint.EndpointId,
                BaseUrl: endpoint.BaseUrl,
                RouteKind: "responses_structured",
                EndpointPath: "/responses",
                Model: model,
                Passed: result.Passed,
                HttpStatusCode: result.HttpStatusCode,
                LatencyMs: result.LatencyMs,
                Message: result.Message));
            lastResult = result;
            if (result.Passed)
            {
                return result with
                {
                    Attempts = attempts,
                    AuditTrail = [
                        ..result.AuditTrail,
                        $"selected_provider_endpoint={endpoint.EndpointId}",
                        $"selected_provider_base_url={endpoint.BaseUrl}"
                    ]
                };
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

    private async Task<StructuredSmokeExecutionResult> RunStructuredSmokeAsync(
        AiProviderRuntimeEndpoint endpoint,
        string model,
        string taskType,
        string? inputJson,
        CancellationToken cancellationToken)
    {
        using var schema = LoadSchemaForTaskType(taskType);
        var payload = new
        {
            model,
            store = false,
            reasoning = new
            {
                effort = "medium"
            },
            input = NormalizeInputJson(inputJson, taskType),
            text = new
            {
                format = new
                {
                    type = "json_schema",
                    name = $"{taskType}_smoke_result",
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
                    $"task_type={taskType}",
                    $"provider_endpoint={endpoint.EndpointId}",
                    $"http_status={(int)response.StatusCode}",
                    "review_status=pending_review"
                ]);
        }
        catch (Exception ex)
        {
            return new StructuredSmokeExecutionResult(
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

                if (endpoint.EndpointId == "fallback_1")
                {
                    var baseUrl = NormalizeBaseUrl(request.FallbackBaseUrlOverride, endpoint.BaseUrl);
                    var imageBaseUrl = NormalizeBaseUrl(request.FallbackImageBaseUrlOverride, endpoint.ImageBaseUrl);
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
            Message: $"图片链路探针未通过：已尝试 {attempts.Count} 条主备图片路径。",
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

    private static string NormalizeTaskType(string? value, string fallback) =>
        string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();

    private static string NormalizeModel(string? value, string fallback) =>
        string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();

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
        return source.TrimEnd('/');
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

    private JsonDocument LoadSchemaForTaskType(string taskType)
    {
        var repoRoot = Path.GetFullPath(Path.Combine(environment.ContentRootPath, "..", ".."));
        var schemaRelativePath = taskType switch
        {
            "question_extraction" => Path.Combine("schemas", "ai", "question_extraction.schema.json"),
            "natural_language_paper_request" => Path.Combine("schemas", "ai", "natural_language_paper_request.schema.json"),
            "question_solving" => Path.Combine("schemas", "ai", "answer_verification.schema.json"),
            "answer_verification" => Path.Combine("schemas", "ai", "answer_verification.schema.json"),
            _ => Path.Combine("schemas", "ai", "knowledge_mapping.schema.json")
        };
        var schemaText = File.ReadAllText(Path.Combine(repoRoot, schemaRelativePath), Encoding.UTF8);
        return JsonDocument.Parse(schemaText);
    }

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
