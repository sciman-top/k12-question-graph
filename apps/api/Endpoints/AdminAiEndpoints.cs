using K12QuestionGraph.Api.Ai;

namespace K12QuestionGraph.Api.Endpoints;

public static class AdminAiEndpoints
{
    public static IEndpointRouteBuilder MapAdminAiEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/admin/ai/provider-settings", async (
            FileAiProviderSettingsStore settingsStore,
            CancellationToken cancellationToken) =>
        {
            var settings = await settingsStore.GetAsync(cancellationToken);
            return Results.Ok(settings);
        })
        .WithName("GetAdminAiProviderSettings");

        endpoints.MapPost("/api/admin/ai/provider-settings", async (
            AdminAiProviderSettingsSaveRequest request,
            FileAiProviderSettingsStore settingsStore,
            CancellationToken cancellationToken) =>
        {
            var result = await settingsStore.SaveAsync(request, cancellationToken);
            return Results.Ok(result);
        })
        .WithName("SaveAdminAiProviderSettings");

        endpoints.MapPost("/api/admin/ai/provider-settings/test", async (
            AdminAiProviderSettingsTestRequest request,
            FileAiProviderSettingsStore settingsStore,
            OpenAiCompatibleSmokeTestService smokeTestService,
            CancellationToken cancellationToken) =>
        {
            var settings = await settingsStore.GetAsync(cancellationToken);
            var result = await smokeTestService.RunAsync(settings, request, cancellationToken);
            return Results.Ok(result);
        })
        .WithName("TestAdminAiProviderSettings");

        return endpoints;
    }
}
