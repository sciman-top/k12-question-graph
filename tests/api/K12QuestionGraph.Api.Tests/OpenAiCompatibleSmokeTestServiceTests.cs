using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using K12QuestionGraph.Api.Ai;
using K12QuestionGraph.Api.Configuration;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Options;

namespace K12QuestionGraph.Api.Tests;

public sealed class OpenAiCompatibleSmokeTestServiceTests : IDisposable
{
    private readonly string testRoot = Path.Combine(Path.GetTempPath(), $"kqg-ai-smoke-{Guid.NewGuid():N}");

    [Fact]
    public async Task RoutedSmokeUsesEffectiveModelAndReasoningEffort()
    {
        var handler = new RecordingProviderHandler();
        using var httpClient = new HttpClient(handler);
        var store = CreateStore();
        await store.SaveAsync(CreateSaveRequest(), CancellationToken.None);
        var settings = await store.GetAsync(CancellationToken.None);
        var service = new OpenAiCompatibleSmokeTestService(
            httpClient,
            store,
            CreateEnvironment(),
            CreateRouter());

        var result = await service.RunAsync(
            settings,
            new AdminAiProviderSettingsTestRequest(
                TaskType: "question_solving",
                InputJson: "solve this",
                Model: "ignored-manual-model",
                BaseUrlOverride: null,
                ImageBaseUrlOverride: null,
                FallbackBaseUrlOverride: null,
                FallbackImageBaseUrlOverride: null,
                RoutingMode: "balanced",
                RiskSignals: new AiRouteRiskSignals(FormalExam: true),
                ExpectedConfidence: 0.9m,
                UseModelRouting: true),
            CancellationToken.None);

        Assert.True(result.Passed);
        Assert.True(result.CombinedPassed);
        Assert.Equal("gpt-5.6-sol", result.Model);
        Assert.Equal("xhigh", result.EffectiveReasoningEffort);
        Assert.True(result.UsedModelRouting);
        Assert.Contains("routing_source=effective_route", result.AuditTrail);
        Assert.NotNull(handler.ResponsesPayload);
        Assert.Equal("gpt-5.6-sol", handler.ResponsesPayload!.Value.GetProperty("model").GetString());
        Assert.Equal("xhigh", handler.ResponsesPayload.Value.GetProperty("reasoning").GetProperty("effort").GetString());
    }

    [Fact]
    public async Task ManualSmokeOverrideKeepsExplicitModelAndMarksRoutingSource()
    {
        var handler = new RecordingProviderHandler();
        using var httpClient = new HttpClient(handler);
        var store = CreateStore();
        await store.SaveAsync(CreateSaveRequest(), CancellationToken.None);
        var settings = await store.GetAsync(CancellationToken.None);
        var service = new OpenAiCompatibleSmokeTestService(
            httpClient,
            store,
            CreateEnvironment(),
            CreateRouter());

        var result = await service.RunAsync(
            settings,
            new AdminAiProviderSettingsTestRequest(
                TaskType: "question_solving",
                InputJson: "solve this",
                Model: "manual-model",
                BaseUrlOverride: null,
                ImageBaseUrlOverride: null,
                FallbackBaseUrlOverride: null,
                FallbackImageBaseUrlOverride: null,
                RoutingMode: "balanced",
                UseModelRouting: false),
            CancellationToken.None);

        Assert.True(result.Passed);
        Assert.Equal("manual-model", result.Model);
        Assert.Equal("medium", result.EffectiveReasoningEffort);
        Assert.False(result.UsedModelRouting);
        Assert.Contains("routing_source=manual_model_override", result.AuditTrail);
        Assert.Equal("manual-model", handler.ResponsesPayload!.Value.GetProperty("model").GetString());
        Assert.Equal("medium", handler.ResponsesPayload.Value.GetProperty("reasoning").GetProperty("effort").GetString());
    }

    [Fact]
    public async Task RoutingGlobalDisableBlocksAdminProbeBeforeAnyProviderRequest()
    {
        var handler = new RecordingProviderHandler();
        using var httpClient = new HttpClient(handler);
        var store = CreateStore();
        await store.SaveAsync(CreateSaveRequest(), CancellationToken.None);
        var settings = await store.GetAsync(CancellationToken.None);
        var service = new OpenAiCompatibleSmokeTestService(
            httpClient,
            store,
            CreateEnvironment(),
            CreateRouter(allowRealModelCalls: false));

        var result = await service.RunAsync(
            settings,
            new AdminAiProviderSettingsTestRequest(
                TaskType: "question_solving",
                InputJson: "solve this",
                Model: null,
                BaseUrlOverride: null,
                ImageBaseUrlOverride: null,
                FallbackBaseUrlOverride: null,
                FallbackImageBaseUrlOverride: null,
                UseModelRouting: true),
            CancellationToken.None);

        Assert.Equal("blocked", result.Status);
        Assert.Contains("real_model_calls_disabled", result.Blockers);
        Assert.Contains("routing_blocked_before_provider_request", result.AuditTrail);
        Assert.Equal(0, handler.RequestCount);
    }

    public void Dispose()
    {
        if (Directory.Exists(testRoot))
        {
            Directory.Delete(testRoot, recursive: true);
        }
    }

    private FileAiProviderSettingsStore CreateStore()
    {
        Directory.CreateDirectory(testRoot);
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["KqgPaths:DataRoot"] = testRoot
            })
            .Build();
        var keyRoot = Directory.CreateDirectory(Path.Combine(testRoot, "keys"));
        return new FileAiProviderSettingsStore(
            configuration,
            DataProtectionProvider.Create(keyRoot),
            CreateEnvironment());
    }

    private static AdminAiProviderSettingsSaveRequest CreateSaveRequest() => new(
        ProviderProfileId: "smoke-test",
        BaseUrl: "https://provider.test/v1",
        ApiKey: "test-secret",
        ImageBaseUrl: null,
        ImageApiKey: null,
        FallbackBaseUrl: null,
        FallbackApiKey: null,
        FallbackImageBaseUrl: null,
        FallbackImageApiKey: null,
        MaxConcurrency: 2,
        MonthlyBudgetCny: 100,
        DisabledByDefault: false,
        AllowRealModelCalls: true,
        DefaultSmokeTaskType: "question_solving",
        DefaultSmokeModel: "gpt-5.6-sol",
        OperatorNote: "test");

    private static AiModelRouter CreateRouter(bool allowRealModelCalls = true)
    {
        var routes = new Dictionary<string, AiRouteOptions>(StringComparer.OrdinalIgnoreCase)
        {
            ["question_solving"] = new()
            {
                Handler = "llm",
                Stage = "solving",
                ModelRole = "semantic_decision",
                ModelName = "gpt-5.6-sol",
                ReasoningEffort = "xhigh",
                ModelTier = "strong",
                StructuredOutputSchema = "schemas/ai/answer_verification.schema.json",
                RequireHumanReviewBelowConfidence = 1.0m
            }
        };

        return new AiModelRouter(
            Options.Create(new AiRoutingOptions
            {
                AllowRealModelCalls = allowRealModelCalls,
                Routes = routes
            }),
            CreateEnvironment());
    }

    private static IWebHostEnvironment CreateEnvironment() => new TestWebHostEnvironment();

    private sealed class RecordingProviderHandler : HttpMessageHandler
    {
        public JsonElement? ResponsesPayload { get; private set; }
        public int RequestCount { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestCount++;
            var body = await request.Content!.ReadAsStringAsync(cancellationToken);
            if (request.RequestUri!.AbsolutePath.EndsWith("/responses", StringComparison.Ordinal))
            {
                using var document = JsonDocument.Parse(body);
                ResponsesPayload = document.RootElement.Clone();
                return JsonResponse("{\"output_text\":\"{}\",\"usage\":{\"input_tokens\":3,\"output_tokens\":2,\"input_tokens_details\":{\"cached_tokens\":0}}}");
            }

            if (request.RequestUri.AbsolutePath.EndsWith("/images/generations", StringComparison.Ordinal))
            {
                return JsonResponse("{\"data\":[{\"b64_json\":\"test-image\"}]}");
            }

            return new HttpResponseMessage(HttpStatusCode.NotFound);
        }

        private static HttpResponseMessage JsonResponse(string content) => new(HttpStatusCode.OK)
        {
            Content = new StringContent(content, System.Text.Encoding.UTF8, "application/json")
        };
    }

    private sealed class TestWebHostEnvironment : IWebHostEnvironment
    {
        public string ApplicationName { get; set; } = "tests";
        public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
        public string WebRootPath { get; set; } = RepoRoot;
        public string EnvironmentName { get; set; } = "Tests";
        public string ContentRootPath { get; set; } = Path.Combine(RepoRoot, "apps", "api");
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }

    private static string RepoRoot
    {
        get
        {
            var current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current is not null)
            {
                if (File.Exists(Path.Combine(current.FullName, "configs", "model_routing.defaults.yaml")))
                {
                    return current.FullName;
                }

                current = current.Parent;
            }

            throw new DirectoryNotFoundException("Could not locate the repository root for smoke tests.");
        }
    }
}
