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
        Assert.Equal("gpt-5.6-sol", route.ModelName);
        Assert.Equal("medium", route.ReasoningEffort);
        Assert.Equal("gpt-5.6-sol", route.EffectiveModelName);
        Assert.Equal("medium", route.EffectiveReasoningEffort);
        Assert.Contains("low_confidence", route.EscalationReasons);
    }

    [Fact]
    public void RouteResolvesExecutionSlotGradeAndPresetAsOneSelection()
    {
        var route = CreateRouter().Route(new("knowledge_tagging", "balanced", "draft", 0.79m));

        Assert.Equal("bulk_prefilter", route.ExecutionSlot);
        Assert.Equal("balanced", route.ExecutionGrade);
        Assert.Equal("sol", route.Preset);
        Assert.Equal("gpt-5.6-sol", route.ModelName);
        Assert.Equal("medium", route.ReasoningEffort);
        Assert.Equal("engineering_review", route.EffectiveExecutionSlot);
        Assert.Equal("balanced", route.EffectiveExecutionGrade);
        Assert.Equal("sol", route.EffectivePreset);
    }

    [Fact]
    public void UnknownConfiguredExecutionSlotFailsClosed()
    {
        var exception = Assert.Throws<AiRouteException>(() =>
            CreateRouter("removed_slot").Route(new("knowledge_tagging", "balanced", "draft", 0.95m)));

        Assert.Equal("unknown_execution_slot", exception.Message);
    }

    [Fact]
    public void PinnedLunaPresetResolvesEveryRouteToLunaOnly()
    {
        var router = CreateRouter(pinnedPresetId: "luna");

        var route = router.Route(new("knowledge_tagging", "balanced", "draft", 0.95m));
        var candidates = router.GetFailoverCandidates(
            "gpt-5.6-sol",
            "medium",
            "bulk_prefilter",
            "balanced");

        Assert.Equal("luna", route.Preset);
        Assert.Equal("gpt-5.6-luna", route.ModelName);
        Assert.Equal("high", route.ReasoningEffort);
        Assert.Single(candidates);
        Assert.Equal("luna", candidates[0].PresetId);
        Assert.Equal("gpt-5.6-luna", candidates[0].ModelName);
        Assert.Equal("high", candidates[0].ReasoningEffort);
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

    [Theory]
    [InlineData("low_cost")]
    [InlineData("balanced")]
    [InlineData("high_accuracy")]
    public void QuestionSolvingRemainsPinnedToSolXhighForEveryMode(string mode)
    {
        var route = CreateRouter().Route(new(
            "question_solving",
            mode,
            "draft",
            0.1m,
            new(
                CrossPage: true,
                SharedVisual: true,
                FormulaOrTable: true,
                SemanticConflict: true,
                MultipleConstraints: true,
                FormalExam: true,
                SourceEvidenceConflict: true)));

        Assert.Equal("semantic_decision", route.ModelRole);
        Assert.Equal("high_risk_adjudication", route.ExecutionSlot);
        Assert.Equal("quality", route.ExecutionGrade);
        Assert.Equal("sol", route.Preset);
        Assert.Equal("gpt-5.6-sol", route.ModelName);
        Assert.Equal("xhigh", route.ReasoningEffort);
        Assert.Equal(route.ModelRole, route.EffectiveModelRole);
        Assert.Equal(route.ModelName, route.EffectiveModelName);
        Assert.Equal(route.ReasoningEffort, route.EffectiveReasoningEffort);
        Assert.False(route.Escalated);
        Assert.Empty(route.EscalationReasons);
        Assert.Null(route.EscalateToRole);
        Assert.Null(route.EscalateToModel);
        Assert.Null(route.EscalateReasoningEffort);
        Assert.True(route.RequiresHumanReview);
        Assert.False(route.ProductionEligible);
    }

    [Fact]
    public void UnknownModeFailsClosed()
    {
        var exception = Assert.Throws<AiRouteException>(() =>
            CreateRouter().Route(new("knowledge_tagging", "fastest", "draft", 0.9m)));

        Assert.Equal("unknown_routing_mode", exception.Message);
    }

    [Fact]
    public void FailoverCandidatesPreferSolThenTerraThenLuna()
    {
        var candidates = CreateRouter().GetFailoverCandidates("gpt-5.6-sol", "xhigh");

        Assert.Equal(
            ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"],
            candidates.Select(x => x.ModelName).ToArray());
        Assert.Equal(["xhigh", "xhigh", "xhigh"], candidates.Select(x => x.ReasoningEffort).ToArray());
        Assert.False(candidates[0].IsFallback);
        Assert.All(candidates.Skip(1), candidate => Assert.True(candidate.IsFallback));
    }

    [Fact]
    public void TerraFailureOrderChecksSolBeforeLunaAndFallsBackUnsupportedEffortToMedium()
    {
        var candidates = CreateRouter().GetFailoverCandidates("gpt-5.6-terra", "low");

        Assert.Equal(
            ["gpt-5.6-terra", "gpt-5.6-sol", "gpt-5.6-luna"],
            candidates.Select(x => x.ModelName).ToArray());
        Assert.Equal(["medium", "low", "medium"], candidates.Select(x => x.ReasoningEffort).ToArray());
    }

    [Fact]
    public void FailoverPreservesSlotAndGradeWhileRebindingPresetEffort()
    {
        var candidates = CreateRouter().GetFailoverCandidates(
            "gpt-5.6-terra",
            "high",
            "bulk_prefilter",
            "balanced");

        Assert.Equal(["terra", "sol", "luna"], candidates.Select(x => x.PresetId).ToArray());
        Assert.Equal(["high", "medium", "high"], candidates.Select(x => x.ReasoningEffort).ToArray());
        Assert.All(candidates, candidate =>
        {
            Assert.Equal("bulk_prefilter", candidate.ExecutionSlot);
            Assert.Equal("balanced", candidate.ExecutionGrade);
        });
    }

    [Fact]
    public void EveryExecutionSlotUsesOnlyTheActiveSolPreset()
    {
        var router = CreateRouter();
        var routes = new[]
        {
            router.Route(new("knowledge_tagging", "balanced", "draft", 0.95m)),
            router.Route(new("crop_candidate_generation", "balanced", "draft", 0.95m)),
            router.Route(new("question_solving", "balanced", "draft", 0.95m))
        };

        Assert.All(routes, route =>
        {
            Assert.Equal("sol", route.Preset);
            Assert.Equal("gpt-5.6-sol", route.ModelName);
        });
        Assert.Equal(["medium", "xhigh", "xhigh"], routes.Select(route => route.ReasoningEffort).ToArray());
    }

    [Theory]
    [InlineData("mechanical_cleanup", "economy", "low", "medium", "medium")]
    [InlineData("bulk_prefilter", "balanced", "medium", "high", "high")]
    [InlineData("engineering_review", "balanced", "medium", "high", "high")]
    [InlineData("visual_review", "quality", "xhigh", "xhigh", "xhigh")]
    [InlineData("high_risk_adjudication", "quality", "xhigh", "xhigh", "xhigh")]
    public void EverySlotKeepsItsGradeAcrossSingleModelPresetFailover(
        string slot,
        string grade,
        string solEffort,
        string terraEffort,
        string lunaEffort)
    {
        var candidates = CreateRouter().GetFailoverCandidates(
            "gpt-5.6-sol",
            "medium",
            slot,
            grade);

        Assert.Equal(["sol", "terra", "luna"], candidates.Select(candidate => candidate.PresetId).ToArray());
        Assert.Equal(
            ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"],
            candidates.Select(candidate => candidate.ModelName).ToArray());
        Assert.Equal([solEffort, terraEffort, lunaEffort], candidates.Select(candidate => candidate.ReasoningEffort).ToArray());
        Assert.All(candidates, candidate =>
        {
            Assert.Equal(slot, candidate.ExecutionSlot);
            Assert.Equal(grade, candidate.ExecutionGrade);
        });
    }

    private static AiModelRouter CreateRouter(
        string? knowledgeTaggingExecutionSlot = null,
        string? pinnedPresetId = null)
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
                ExecutionSlot = knowledgeTaggingExecutionSlot ?? "bulk_prefilter",
                ExecutionGrade = "balanced",
                ModelName = "gpt-5.6-sol",
                ReasoningEffort = "medium",
                EscalateToRole = "general_semantics",
                EscalateToExecutionSlot = "engineering_review",
                EscalateToExecutionGrade = "balanced",
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
                ExecutionSlot = "visual_review",
                ExecutionGrade = "quality",
                ModelName = "gpt-5.6-sol",
                ReasoningEffort = "xhigh",
                EscalateToRole = "semantic_decision",
                EscalateToExecutionSlot = "high_risk_adjudication",
                EscalateToExecutionGrade = "quality",
                EscalateToModel = "gpt-5.6-sol",
                EscalateReasoningEffort = "xhigh",
                EscalationSignals = ["semantic_conflict"]
            },
            ["question_solving"] = new()
            {
                Handler = "llm",
                ModelRole = "semantic_decision",
                ExecutionSlot = "high_risk_adjudication",
                ExecutionGrade = "quality",
                ModelName = "gpt-5.6-sol",
                ReasoningEffort = "xhigh",
                ModelTier = "strong",
                RequireHumanReviewBelowConfidence = 1.0m
            }
        };

        return new AiModelRouter(
            Options.Create(new AiRoutingOptions
            {
                Routes = routes,
                ModelPresets = new Dictionary<string, AiModelPresetOptions>(StringComparer.OrdinalIgnoreCase)
                {
                    ["sol"] = new() { ModelName = "gpt-5.6-sol", ReasoningEfforts = ["xhigh", "medium", "low"], GradeToReasoningEffort = new() { ["quality"] = "xhigh", ["balanced"] = "medium", ["economy"] = "low" } },
                    ["terra"] = new() { ModelName = "gpt-5.6-terra", ReasoningEfforts = ["xhigh", "high", "medium"], GradeToReasoningEffort = new() { ["quality"] = "xhigh", ["balanced"] = "high", ["economy"] = "medium" } },
                    ["luna"] = new() { ModelName = "gpt-5.6-luna", ReasoningEfforts = ["xhigh", "high", "medium"], GradeToReasoningEffort = new() { ["quality"] = "xhigh", ["balanced"] = "high", ["economy"] = "medium" } }
                },
                ExecutionSlots = new Dictionary<string, AiExecutionSlotOptions>(StringComparer.OrdinalIgnoreCase)
                {
                    ["mechanical_cleanup"] = new() { DefaultGrade = "economy" },
                    ["bulk_prefilter"] = new() { DefaultGrade = "balanced" },
                    ["engineering_review"] = new() { DefaultGrade = "balanced" },
                    ["visual_review"] = new() { DefaultGrade = "quality" },
                    ["high_risk_adjudication"] = new() { DefaultGrade = "quality" }
                },
                ModelFailover = new() { PreferredPresetOrder = ["sol", "terra", "luna"], PinnedPresetId = pinnedPresetId }
            }),
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
