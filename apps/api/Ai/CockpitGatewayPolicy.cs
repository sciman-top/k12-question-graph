namespace K12QuestionGraph.Api.Ai;

/// <summary>
/// Keeps Cockpit credentials on the local API service. This project has no
/// external-provider profile: a different provider must be introduced as an
/// explicit, separately credentialed profile rather than an URL override.
/// </summary>
public static class CockpitGatewayPolicy
{
    public const string LocalBaseUrl = "http://127.0.0.1:45335/v1";

    public static string NormalizeRequired(string? value)
    {
        var normalized = string.IsNullOrWhiteSpace(value)
            ? LocalBaseUrl
            : value.Trim().TrimEnd('/');

        if (!string.Equals(normalized, LocalBaseUrl, StringComparison.OrdinalIgnoreCase))
        {
            throw new AiProviderSettingsException("cockpit_local_gateway_required");
        }

        return LocalBaseUrl;
    }

    public static string NormalizeOptional(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? string.Empty : NormalizeRequired(value);
    }
}

public sealed class AiProviderSettingsException(string message) : Exception(message);
