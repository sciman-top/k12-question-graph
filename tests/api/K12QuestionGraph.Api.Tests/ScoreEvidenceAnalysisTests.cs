using K12QuestionGraph.Api.Application.Workflows;

namespace K12QuestionGraph.Api.Tests;

public sealed class ScoreEvidenceAnalysisTests
{
    [Fact]
    public void BlocksStudentPiiBeforeProducingAnalysisLayers()
    {
        var result = ScoreAnalysisWorkflowService.BuildScoreEvidenceAnalysis(new ScoreEvidenceAnalysisInput(
            Guid.NewGuid(),
            "真实名单成绩",
            ContainsStudentPii: true,
            [ReadyItem()]));

        Assert.Equal("blocked", result.Status);
        Assert.True(result.RealStudentDataUsed);
        Assert.False(result.ProductionEligible);
        Assert.False(result.WritesProductionHistory);
        Assert.Empty(result.ScoreDerivedPerformance);
        Assert.Contains(result.BlockingIssues, x => x.Codes.Contains("student_pii_detected"));
        Assert.Contains("pii_detected_analysis_blocked", result.AuditTrail);
        Assert.DoesNotContain("no_real_student_data", result.AuditTrail);
    }

    [Fact]
    public void BlocksMissingOrAmbiguousReviewedEvidenceMappings()
    {
        var missingTarget = ReadyItem() with
        {
            AssessmentTargetId = null,
            AssessmentTargetStableKey = null,
            TargetStatement = null,
            IssueCodes = ["assessment_target_not_reviewed"]
        };
        var ambiguousVersion = ReadyItem("Q2") with
        {
            Knowledge = null,
            IssueCodes = ["knowledge_version_ambiguous"]
        };

        var result = ScoreAnalysisWorkflowService.BuildScoreEvidenceAnalysis(new ScoreEvidenceAnalysisInput(
            Guid.NewGuid(),
            "阻断样例",
            ContainsStudentPii: false,
            [missingTarget, ambiguousVersion]));

        Assert.Equal("blocked", result.Status);
        Assert.Empty(result.ScoreDerivedPerformance);
        Assert.Contains(result.BlockingIssues, x => x.Scope == "Q1" && x.Codes.Contains("assessment_target_not_reviewed"));
        Assert.Contains(result.BlockingIssues, x => x.Scope == "Q2" && x.Codes.Contains("knowledge_version_ambiguous"));
    }

    [Fact]
    public void SeparatesScoreContextAssociationAndTeacherDiagnosisSemantics()
    {
        var first = ReadyItem("Q1", scoreRate: 0.5m, scoreRecordCount: 20);
        var second = ReadyItem("Q2", scoreRate: 0.75m, scoreRecordCount: 20) with
        {
            ObservedContexts = [],
            ErrorAssociations = [],
            TeachingRecommendations = []
        };

        var result = ScoreAnalysisWorkflowService.BuildScoreEvidenceAnalysis(new ScoreEvidenceAnalysisInput(
            Guid.NewGuid(),
            "八年级物理",
            ContainsStudentPii: false,
            [first, second]));

        Assert.Equal("ready", result.Status);
        Assert.False(result.ProductionEligible);
        Assert.False(result.WritesProductionHistory);
        Assert.Equal(2, result.ScoreDerivedPerformance.Count);
        Assert.All(result.ScoreDerivedPerformance, x => Assert.Equal("score_derived_performance", x.EvidenceRole));
        Assert.Equal(0.625m, Assert.Single(result.KnowledgeMastery).ScoreRate);
        Assert.Equal("score_derived_ability_performance", Assert.Single(result.AbilityPerformance).EvidenceRole);
        Assert.Equal("historical_year_report_context_not_current_cohort_measurement", Assert.Single(result.ObservedContexts).ContextRole);
        Assert.Equal("reviewed_association_not_cause", Assert.Single(result.ErrorPatternAssociations).Relation);
        Assert.Equal("pending_teacher_confirmation", Assert.Single(result.ErrorPatternAssociations).DiagnosisStatus);
        Assert.Equal("report_author", Assert.Single(result.TeachingRecommendations).AuthorKind);
        Assert.Equal("source_authored_recommendation_not_curriculum_fact", Assert.Single(result.TeachingRecommendations).FactRole);
        Assert.Empty(result.TeacherConfirmedDiagnoses);
        Assert.Equal("pending_teacher_confirmation", result.DiagnosisStatus);
    }

    private static ScoreEvidenceAnalysisItemInput ReadyItem(
        string questionNo = "Q1",
        decimal scoreRate = 0.5m,
        int scoreRecordCount = 20)
    {
        var targetId = Guid.Parse("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee");
        var sourceRegionId = Guid.Parse("11111111-2222-4333-8444-555555555555");
        return new ScoreEvidenceAnalysisItemInput(
            questionNo,
            scoreRecordCount,
            scoreRate,
            Guid.Parse("aaaaaaaa-1111-4222-8333-bbbbbbbbbbbb"),
            targetId,
            "AT-GZ-READY-1",
            "根据实验数据进行解释",
            ["科学推理"],
            ["分析"],
            new ScoreEvidenceKnowledgeInput(
                targetId,
                Guid.Parse("cccccccc-1111-4222-8333-dddddddddddd"),
                "KN-MECHANICS-1",
                "力与运动",
                3,
                "reviewed",
                "primary",
                "reviewed",
                "approved"),
            [new ScoreEvidenceObservedContextInput(
                Guid.Parse("10000000-1111-4222-8333-444444444444"),
                0.52m,
                0.48m,
                "higher_is_easier",
                "guangzhou_2024",
                sourceRegionId,
                "historical_year_report_context_not_current_cohort_measurement")],
            [new ScoreEvidenceErrorAssociationInput(
                Guid.Parse("20000000-1111-4222-8333-444444444444"),
                "summary_candidate",
                "变量控制不完整",
                sourceRegionId,
                "reviewed_association_not_cause")],
            [new ScoreEvidenceTeachingRecommendationInput(
                Guid.Parse("30000000-1111-4222-8333-444444444444"),
                "先复核变量控制，再比较实验数据。",
                "report_author",
                "verbatim",
                sourceRegionId,
                "source_authored_recommendation_not_curriculum_fact")],
            IssueCodes: []);
    }
}
