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
    string LastUpdatedAt,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail);

public sealed record AdminAiProviderSettingsSaveRequest(
    string ProviderProfileId,
    string? BaseUrl,
    string? ApiKey,
    string? ImageBaseUrl,
    string? ImageApiKey,
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
    string LastUpdatedAt,
    string TeacherMessage,
    IReadOnlyList<string> AuditTrail);

public sealed record AdminAiProviderSettingsTestRequest(
    string TaskType,
    string? InputJson,
    string? Model,
    string? BaseUrlOverride);

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
    int HttpStatusCode,
    string Message,
    string OutputJson,
    int InputTokens,
    int OutputTokens,
    int CachedTokens,
    decimal Cost,
    int LatencyMs,
    IReadOnlyList<string> Blockers,
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
    int MaxConcurrency,
    int MonthlyBudgetCny,
    bool DisabledByDefault,
    bool AllowRealModelCalls,
    string DefaultSmokeTaskType,
    string DefaultSmokeModel,
    DateTimeOffset UpdatedAtUtc,
    string LastOperatorNote);

public interface IAiProviderSettingsStore
{
    Task<AdminAiProviderSettingsContract> GetAsync(CancellationToken cancellationToken);
    Task<AdminAiProviderSettingsSaveResult> SaveAsync(AdminAiProviderSettingsSaveRequest request, CancellationToken cancellationToken);
    Task<string> GetPlaintextSecretAsync(CancellationToken cancellationToken);
    Task<string> GetPlaintextImageSecretAsync(CancellationToken cancellationToken);
}

public interface IAiProviderSmokeTestService
{
    Task<AdminAiProviderSettingsTestResult> RunAsync(
        AdminAiProviderSettingsContract settings,
        AdminAiProviderSettingsTestRequest request,
        CancellationToken cancellationToken);
}

public sealed class FileAiProviderSettingsStore(
    IConfiguration configuration,
    IDataProtectionProvider dataProtectionProvider,
    IWebHostEnvironment environment)
    : IAiProviderSettingsStore
{
    private const string SchemaVersion = "admin-ai-provider-settings.v0.1";
    private const string DefaultProviderProfileId = "cloud_openai_candidate";
    private const string DefaultProviderType = "openai_compatible";
    private const string DefaultCredentialMode = "dialog_secret_local_machine";
    private const string DefaultSmokeTaskType = "knowledge_tagging";
    private const string DefaultSmokeModel = "gpt-5.4-mini";
    private const string PrimaryEnvSecretName = "KQG_AI_OPENAI_KEY";
    private const string PrimaryEnvBaseUrlName = "KQG_AI_OPENAI_BASE_URL";
    private const string ImageEnvSecretName = "KQG_AI_IMAGE_OPENAI_KEY";
    private const string ImageEnvBaseUrlName = "KQG_AI_IMAGE_OPENAI_BASE_URL";
    private const string LegacyPrimaryEnvSecretName = "TEXT_PROVIDER_API_KEY";
    private const string LegacyPrimaryEnvBaseUrlName = "TEXT_PROVIDER_BASE_URL";
    private const string LegacyPrimaryEnvModelName = "TEXT_PROVIDER_MODEL";
    private const string LegacyImageEnvSecretName = "IMAGE_PROVIDER_API_KEY_1";
    private const string LegacyImageEnvBaseUrlName = "IMAGE_PROVIDER_BASE_URL";
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
            Normalize(request.ProviderProfileId, DefaultProviderProfileId),
            DefaultProviderType,
            NormalizeBaseUrl(request.BaseUrl),
            NormalizeOptionalBaseUrl(request.ImageBaseUrl),
            DefaultCredentialMode,
            secretCiphertext,
            imageSecretCiphertext,
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
            LastUpdatedAt: stored.UpdatedAtUtc.ToString("O"),
            TeacherMessage: "管理员 AI 设置已保存；默认单 key 生效，图片专用 key 留空时会复用主 key；本机仍只保留加密副本，试跑保持 pending_review。",
            AuditTrail: [
                "save_admin_ai_provider_settings",
                $"provider_profile={stored.ProviderProfileId}",
                $"allow_real_model_calls={stored.AllowRealModelCalls.ToString().ToLowerInvariant()}",
                $"secret_configured={(!string.IsNullOrWhiteSpace(plaintextPrimarySecret)).ToString().ToLowerInvariant()}",
                $"image_secret_configured={(!string.IsNullOrWhiteSpace(plaintextImageSecret)).ToString().ToLowerInvariant()}",
                $"image_uses_primary_secret={(string.IsNullOrWhiteSpace(UnprotectSecret(stored.ImageSecretCiphertext))).ToString().ToLowerInvariant()}"
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
            LastUpdatedAt: settings.UpdatedAtUtc.ToString("O"),
            TeacherMessage: "当前为管理员级本机 AI 设置；默认单 key，图片专用 key 可选覆盖；普通教师侧仍只看到简化模式。",
            AuditTrail: [
                "load_admin_ai_provider_settings",
                $"provider_profile={settings.ProviderProfileId}",
                $"secret_configured={(!string.IsNullOrWhiteSpace(plaintextSecret)).ToString().ToLowerInvariant()}",
                $"image_secret_configured={(!string.IsNullOrWhiteSpace(plaintextImageSecret)).ToString().ToLowerInvariant()}",
                $"image_uses_primary_secret={(string.IsNullOrWhiteSpace(explicitImageSecret)).ToString().ToLowerInvariant()}",
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
    IAiProviderSettingsStore settingsStore,
    IWebHostEnvironment environment)
    : IAiProviderSmokeTestService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<AdminAiProviderSettingsTestResult> RunAsync(
        AdminAiProviderSettingsContract settings,
        AdminAiProviderSettingsTestRequest request,
        CancellationToken cancellationToken)
    {
        var blockers = new List<string>();
        if (!settings.SecretConfigured)
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
                Model: string.IsNullOrWhiteSpace(request.Model) ? settings.DefaultSmokeModel : request.Model.Trim(),
                TaskType: NormalizeTaskType(request.TaskType, settings.DefaultSmokeTaskType),
                ReviewStatus: "pending_review",
                Passed: false,
                HttpStatusCode: 0,
                Message: "管理员 AI 设置未满足真实试跑前置条件；请启用 provider、配置密钥并明确允许 draft/test 试跑。",
                OutputJson: "{}",
                InputTokens: 0,
                OutputTokens: 0,
                CachedTokens: 0,
                Cost: 0,
                LatencyMs: 0,
                Blockers: blockers,
                AuditTrail: [
                    "test_admin_ai_provider_settings_blocked",
                    ..blockers
                ]);
        }

        var secret = await settingsStore.GetPlaintextSecretAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(secret))
        {
            return new AdminAiProviderSettingsTestResult(
                Status: "blocked",
                Mode: "draft_test",
                ProductionEligible: false,
                ProviderProfileId: settings.ProviderProfileId,
                ProviderType: settings.ProviderType,
                Model: string.IsNullOrWhiteSpace(request.Model) ? settings.DefaultSmokeModel : request.Model.Trim(),
                TaskType: NormalizeTaskType(request.TaskType, settings.DefaultSmokeTaskType),
                ReviewStatus: "pending_review",
                Passed: false,
                HttpStatusCode: 0,
                Message: "本机密钥解密失败，未执行云试跑。",
                OutputJson: "{}",
                InputTokens: 0,
                OutputTokens: 0,
                CachedTokens: 0,
                Cost: 0,
                LatencyMs: 0,
                Blockers: ["provider_secret_unavailable"],
                AuditTrail: [ "test_admin_ai_provider_settings_secret_unavailable" ]);
        }

        var taskType = NormalizeTaskType(request.TaskType, settings.DefaultSmokeTaskType);
        var schema = LoadSchemaForTaskType(taskType);
        var payload = new
        {
            model = NormalizeModel(request.Model, settings.DefaultSmokeModel),
            store = false,
            input = NormalizeInputJson(request.InputJson, taskType),
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

        using var message = new HttpRequestMessage(HttpMethod.Post, $"{NormalizeBaseUrl(request.BaseUrlOverride, settings.BaseUrl)}/responses");
        message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", secret);
        message.Content = new StringContent(JsonSerializer.Serialize(payload, JsonOptions), Encoding.UTF8, "application/json");

        var startedAt = DateTimeOffset.UtcNow;
        try
        {
            using var response = await httpClient.SendAsync(message, cancellationToken);
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            var latencyMs = (int)Math.Max(1, (DateTimeOffset.UtcNow - startedAt).TotalMilliseconds);
            var parsed = ParseSmokeResponse(body);
            return new AdminAiProviderSettingsTestResult(
                Status: response.IsSuccessStatusCode ? "ok" : "failed",
                Mode: "draft_test",
                ProductionEligible: false,
                ProviderProfileId: settings.ProviderProfileId,
                ProviderType: settings.ProviderType,
                Model: NormalizeModel(request.Model, settings.DefaultSmokeModel),
                TaskType: taskType,
                ReviewStatus: "pending_review",
                Passed: response.IsSuccessStatusCode,
                HttpStatusCode: (int)response.StatusCode,
                Message: response.IsSuccessStatusCode ? "结构化 smoke 试跑完成；结果仅作 pending_review 候选验证。" : $"云试跑失败：HTTP {(int)response.StatusCode}",
                OutputJson: parsed.outputJson,
                InputTokens: parsed.inputTokens,
                OutputTokens: parsed.outputTokens,
                CachedTokens: parsed.cachedTokens,
                Cost: 0,
                LatencyMs: latencyMs,
                Blockers: [],
                AuditTrail: [
                    "test_admin_ai_provider_settings",
                    $"task_type={taskType}",
                    $"http_status={(int)response.StatusCode}",
                    "review_status=pending_review"
                ]);
        }
        catch (Exception ex)
        {
            return new AdminAiProviderSettingsTestResult(
                Status: "failed",
                Mode: "draft_test",
                ProductionEligible: false,
                ProviderProfileId: settings.ProviderProfileId,
                ProviderType: settings.ProviderType,
                Model: NormalizeModel(request.Model, settings.DefaultSmokeModel),
                TaskType: taskType,
                ReviewStatus: "pending_review",
                Passed: false,
                HttpStatusCode: 0,
                Message: $"云试跑异常：{ex.Message}",
                OutputJson: "{}",
                InputTokens: 0,
                OutputTokens: 0,
                CachedTokens: 0,
                Cost: 0,
                LatencyMs: (int)Math.Max(1, (DateTimeOffset.UtcNow - startedAt).TotalMilliseconds),
                Blockers: ["provider_request_failed"],
                AuditTrail: [
                    "test_admin_ai_provider_settings_exception",
                    "provider_request_failed"
                ]);
        }
    }

    private static string NormalizeTaskType(string? value, string fallback) =>
        string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();

    private static string NormalizeModel(string? value, string fallback) =>
        string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();

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
            var outputJson = root.TryGetProperty("output_text", out var outputTextElement) &&
                outputTextElement.ValueKind == JsonValueKind.String
                ? outputTextElement.GetString() ?? "{}"
                : "{}";
            return (outputJson, inputTokens, outputTokens, cachedTokens);
        }
        catch
        {
            return ("{}", 0, 0, 0);
        }
    }
}

internal sealed class AiProviderProfilesDefaultsDocument
{
    public List<AiProviderProfilesDefaultsProfile> ProviderProfiles { get; init; } = [];
}

internal sealed class AiProviderProfilesDefaultsProfile
{
    public string Id { get; init; } = string.Empty;
    public string BaseUrl { get; init; } = "https://api.openai.com/v1";
    public int MaxConcurrency { get; init; } = 2;
    public int MonthlyBudgetCny { get; init; } = 300;
}
