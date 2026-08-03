using System.Text.Json;
using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Application.Workflows.Contracts;

namespace K12QuestionGraph.Api.Tests;

public sealed class PaperEvidenceConstraintTests
{
    [Fact]
    public void MatchesAllEvidenceDimensionsWithoutTreatingProfileAsKnowledge()
    {
        var card = EvidenceCard("single_choice");

        Assert.True(PaperWorkflowService.MatchesEvidenceConstraints(
            card,
            ["K-PHY-1"],
            ["CR-PHY-1"],
            ["科学推理"],
            ["analyze"],
            ["experiment"],
            ["experimental"],
            ["PROFILE-GZ-1"]));
        Assert.False(PaperWorkflowService.MatchesEvidenceConstraints(
            card,
            ["PROFILE-GZ-1"],
            [],
            [],
            [],
            [],
            [],
            []));
    }

    [Fact]
    public void ReportsQuestionTypeShortagesWithoutRelaxingConstraints()
    {
        var blueprint = new[]
        {
            new PaperBlueprintServiceItem("single_choice", 2, 6m, ["力学"], "active", "approved"),
            new PaperBlueprintServiceItem("experiment", 1, 5m, ["实验"], "active", "approved")
        };

        var shortages = PaperWorkflowService.BuildConstraintShortages(blueprint, [EvidenceCard("single_choice")]);

        Assert.Collection(
            shortages,
            item =>
            {
                Assert.Equal("question_type:single_choice", item.Dimension);
                Assert.Equal(2, item.Required);
                Assert.Equal(1, item.Available);
                Assert.Equal("constraints_not_relaxed", item.Reason);
            },
            item =>
            {
                Assert.Equal("question_type:experiment", item.Dimension);
                Assert.Equal(1, item.Required);
                Assert.Equal(0, item.Available);
            });
    }

    [Fact]
    public void RestoresFrozenPreviewAndVersionReferencesFromConstraintsJson()
    {
        var snapshot = new PaperEvidenceConstraintSnapshot(
            "candidate",
            true,
            [Guid.Parse("11111111-2222-4333-8444-555555555555")],
            [new PaperVersionReferenceServiceItem(
                "curriculum_alignment",
                "CR-PHY-1",
                1,
                "linked",
                "pending_review",
                "retrospective_crosswalk:not_original_basis")],
            [new PaperConstraintExplanationServiceItem(
                "curriculum_requirement",
                ["CR-PHY-1"],
                1,
                "satisfied",
                "retrospective_alignment_is_disclosed_not_original_basis")],
            [],
            1);
        var json = JsonSerializer.Serialize(
            new { evidence = snapshot },
            new JsonSerializerOptions(JsonSerializerDefaults.Web));

        var restored = PaperWorkflowService.DeserializeEvidenceConstraintSnapshot(json);

        Assert.NotNull(restored);
        Assert.True(restored.PreviewMode);
        Assert.Equal("candidate", restored.EvidenceMode);
        Assert.Contains("not_original_basis", restored.VersionReferences[0].Provenance, StringComparison.Ordinal);
        Assert.Equal(1, restored.RetrospectiveAlignmentCount);
    }

    private static QuestionEvidenceCardDto EvidenceCard(string questionType)
    {
        var target = new QuestionAssessmentTargetEvidenceDto(
            Guid.Parse("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"),
            "AT-GZ-1",
            "whole_question",
            "分析实验数据",
            true,
            0.95m,
            "active",
            "approved",
            true,
            ["科学推理"],
            ["analyze"],
            ["experiment"],
            "experimental",
            ["diagram"],
            [new QuestionEvidenceKnowledgeDto("K-PHY-1", "密度测量", "primary", 0.95m, "active", "approved")],
            [new QuestionEvidenceRequirementDto(
                "CR-PHY-1",
                "会测量密度",
                "retrospective_crosswalk",
                false,
                "retrospective_crosswalk",
                Guid.Parse("bbbbbbbb-cccc-4ddd-8eee-ffffffffffff"),
                Guid.Parse("cccccccc-dddd-4eee-8fff-000000000000"),
                0.9m)],
            [],
            [new QuestionEvidenceProfileDto("PROFILE-GZ-1", "广州密度考查画像", "active", "stable")]);
        return new QuestionEvidenceCardDto(
            Guid.Parse("11111111-2222-4333-8444-555555555555"),
            1,
            "physics",
            "junior_middle_school",
            "grade_9",
            questionType,
            "usable",
            0.6,
            "question_estimated",
            [target],
            true);
    }
}
