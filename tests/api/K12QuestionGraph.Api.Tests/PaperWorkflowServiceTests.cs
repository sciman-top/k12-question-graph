using K12QuestionGraph.Api.Application.Workflows;

namespace K12QuestionGraph.Api.Tests;

public class PaperWorkflowServiceTests
{
    [Theory]
    [InlineData("image")]
    [InlineData("figure")]
    [InlineData("question_region_image")]
    [InlineData("QUESTION_REGION_IMAGE")]
    public void IsImageAssetType_AcceptsSupportedQuestionImages(string assetType)
    {
        Assert.True(PaperWorkflowService.IsImageAssetType(assetType));
    }

    [Theory]
    [InlineData("source_pdf")]
    [InlineData("answer_region")]
    [InlineData("")]
    public void IsImageAssetType_RejectsNonImageAssets(string assetType)
    {
        Assert.False(PaperWorkflowService.IsImageAssetType(assetType));
    }
}
