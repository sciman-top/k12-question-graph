using K12QuestionGraph.Api.Ai;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;

namespace K12QuestionGraph.Api.Tests;

public sealed class AdminAiProviderSettingsStoreTests : IDisposable
{
    private readonly string testRoot = Path.Combine(Path.GetTempPath(), $"kqg-ai-settings-{Guid.NewGuid():N}");

    [Fact]
    public async Task SaveAsync_AtomicallyReplacesAndRetainsLastKnownGoodBackup()
    {
        var store = CreateStore("keys-a");

        await store.SaveAsync(CreateRequest("first", "secret-one"), CancellationToken.None);
        await store.SaveAsync(CreateRequest("second", "secret-two"), CancellationToken.None);

        var settingsPath = GetSettingsPath();
        Assert.True(File.Exists(settingsPath));
        Assert.True(File.Exists(settingsPath + ".bak"));
        Assert.DoesNotContain("secret-two", await File.ReadAllTextAsync(settingsPath), StringComparison.Ordinal);
        Assert.Equal("second", (await store.GetAsync(CancellationToken.None)).ProviderProfileId);
    }

    [Fact]
    public async Task GetAsync_CorruptPrimaryFailsVisiblyInsteadOfResettingToDefaults()
    {
        var store = CreateStore("keys-b");
        await store.SaveAsync(CreateRequest("saved", "secret"), CancellationToken.None);
        await File.WriteAllTextAsync(GetSettingsPath(), "{broken-json");

        var error = await Assert.ThrowsAsync<InvalidDataException>(() => store.GetAsync(CancellationToken.None));

        Assert.Contains(".bak recovery copy", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task GetAsync_KeyRingDriftFailsVisiblyInsteadOfReturningEmptySecret()
    {
        var originalStore = CreateStore("keys-c1");
        await originalStore.SaveAsync(CreateRequest("saved", "secret"), CancellationToken.None);
        var driftedStore = CreateStore("keys-c2");

        await Assert.ThrowsAsync<System.Security.Cryptography.CryptographicException>(
            () => driftedStore.GetAsync(CancellationToken.None));
    }

    public void Dispose()
    {
        if (Directory.Exists(testRoot))
        {
            Directory.Delete(testRoot, recursive: true);
        }
    }

    private FileAiProviderSettingsStore CreateStore(string keyDirectory)
    {
        Directory.CreateDirectory(testRoot);
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["KqgPaths:DataRoot"] = testRoot
            })
            .Build();
        var keyRoot = Directory.CreateDirectory(Path.Combine(testRoot, keyDirectory));
        return new FileAiProviderSettingsStore(
            configuration,
            DataProtectionProvider.Create(keyRoot),
            new TestWebHostEnvironment());
    }

    private string GetSettingsPath() =>
        Path.Combine(testRoot, "config", "admin", "ai-provider-settings.local.json");

    private static AdminAiProviderSettingsSaveRequest CreateRequest(string profileId, string secret) =>
        new(
            profileId,
            "https://api.example.test/v1",
            secret,
            null,
            null,
            null,
            null,
            null,
            null,
            2,
            100,
            true,
            false,
            "knowledge_tagging",
            "test-model",
            "test");

    private sealed class TestWebHostEnvironment : IWebHostEnvironment
    {
        public string ApplicationName { get; set; } = "tests";
        public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
        public string WebRootPath { get; set; } = testContentRoot;
        public string EnvironmentName { get; set; } = "Tests";
        public string ContentRootPath { get; set; } = testContentRoot;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
        private static readonly string testContentRoot = Path.Combine(Directory.GetCurrentDirectory(), "apps", "api");
    }
}
