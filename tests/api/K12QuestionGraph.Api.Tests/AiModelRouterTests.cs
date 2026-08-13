using K12QuestionGraph.Api.Ai;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Options;

namespace K12QuestionGraph.Api.Tests;

public sealed class AiModelRouterTests
{
    [Fact]
    public void LowCostOnlyEscalatesForAllowedExplicitRisk()
    {
        var router = CreateRouter();

        var noRisk = router.Route(new("knowledge_tagging", "low_cost", "draft", 0.3m));
        var unrelatedRisk = router.Route(new("knowledge_tagging", "low_cost", "draft", 0.9m, new(SharedVisual: true)));
        var semanticRisk = router.Route(new("knowledge_tagging", "low_cost", "draft", 0.9m, new(SemanticConflict: true)));

        Assert.False(noRisk.Escalated);
        Assert.False(unrelatedRisk.Escalated);
        Assert.True(semanticRisk.Escalated);
        Assert.Equal("gpt-5.6-sol", semanticRisk.EffectiveModelName);
        Assert.Equal("medium", semanticRisk.EffectiveReasoningEffort);
        Assert.Equal(["semantic_conflict"], semanticRisk.EscalationReasons);
    }

    [Fact]
    public void BalancedEscalatesBelowRouteConfidenceThreshold()
    {
        var route = CreateRouter().Route(new("knowledge_tagging", "balanced", "draft", 0.79m));

        Assert.True(route.Escalated);
        Assert.Equal("gpt-5.6-terra", route.ModelName);
        Assert.Equal("high", route.ReasoningEffort);
        Assert.Equal("gpt-5.6-sol", route.EffectiveModelName);
        Assert.Equal("medium", route.EffectiveReasoningEffort);
        Assert.Contains("low_confidence", route.EscalationReasons);
    }

    [Fact]
    public void HighAccuracyEscalatesOnlyOptedInRoutes()
    {
        var optedIn = CreateRouter().Route(new("knowledge_tagging", "high_accuracy", "draft", 0.95m));
        var alreadyStrong = CreateRouter().Route(new("crop_candidate_generation", "high_accuracy", "draft", 0.95m));

        Assert.True(optedIn.Escalated);
        Assert.Contains("high_accuracy_mode", optedIn.EscalationReasons);
        Assert.False(alreadyStrong.Escalated);
    }

    [Fact]
    public void DeterministicRouteNeverEscalates()
    {
        var route = CreateRouter().Route(new("file_dedup", "high_accuracy", "active", 0.1m, new(SemanticConflict: true)));

        Assert.False(route.Escalated);
        Assert.Equal("none", route.EffectiveModelName);
        Assert.Empty(route.EscalationReasons);
    }

    [Fact]
    public void UnknownModeFailsClosed()
    {
        var exception = Assert.Throws<AiRouteException>(() =>
            CreateRouter().Route(new("knowledge_tagging", "fastest", "draft", 0.9m)));

        Assert.Equal("unknown_routing_mode", exception.Message);
    }

    private static AiModelRouter CreateRouter()
    {
        var routes = new Dictionary<string, AiRouteOptions>(StringComparer.OrdinalIgnoreCase)
        {
            ["file_dedup"] = new()
            {
                Handler = "rule",
                ModelRole = "local_deterministic",
                ModelName = "none",
                ReasoningEffort = "none"
            },
            ["knowledge_tagging"] = new()
            {
                Handler = "llm",
                ModelRole = "bulk_structuring",
                ModelName = "gpt-5.6-terra",
                ReasoningEffort = "high",
                EscalateToRole = "general_semantics",
                EscalateToModel = "gpt-5.6-sol",
                EscalateReasoningEffort = "medium",
                EscalateInHighAccuracy = true,
                EscalationSignals = ["semantic_conflict", "source_evidence_conflict"],
                RequireHumanReviewBelowConfidence = 0.8m
            },
            ["crop_candidate_generation"] = new()
            {
                Handler = "llm",
                ModelRole = "visual_document",
                ModelName = "gpt-5.6-terra",
                ReasoningEffort = "xhigh",
                EscalateToRole = "semantic_decision",
                EscalateToModel = "gpt-5.6-sol",
                EscalateReasoningEffort = "xhigh",
                EscalationSignals = ["semantic_conflict"]
            }
        };

        return new AiModelRouter(
            Options.Create(new AiRoutingOptions { Routes = routes }),
            new TestWebHostEnvironment());
    }

    private sealed class TestWebHostEnvironment : IWebHostEnvironment
    {
        public string ApplicationName { get; set; } = "tests";
        public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
        public string WebRootPath { get; set; } = Path.GetTempPath();
        public string EnvironmentName { get; set; } = "Tests";
        public string ContentRootPath { get; set; } = Path.Combine(Directory.GetCurrentDirectory(), "apps", "api");
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
