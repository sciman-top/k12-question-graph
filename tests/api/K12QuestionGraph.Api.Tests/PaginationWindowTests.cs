using K12QuestionGraph.Api.Infrastructure.Queries;

namespace K12QuestionGraph.Api.Tests;

public class PaginationWindowTests
{
    [Theory]
    [InlineData(null, null, 1, 20, 0)]
    [InlineData(-5, 0, 1, 1, 0)]
    [InlineData(3, 25, 3, 25, 50)]
    [InlineData(2, 500, 2, 50, 50)]
    public void Create_NormalizesPageSizeAndOffset(
        int? requestedPage,
        int? requestedPageSize,
        int expectedPage,
        int expectedPageSize,
        int expectedOffset)
    {
        var result = PaginationWindow.Create(requestedPage, requestedPageSize, 20, 50);

        Assert.Equal(expectedPage, result.Page);
        Assert.Equal(expectedPageSize, result.PageSize);
        Assert.Equal(expectedOffset, result.Offset);
    }

    [Fact]
    public void Create_ClampsExtremePagesBeforeOffsetArithmetic()
    {
        var result = PaginationWindow.Create(int.MaxValue, 50, 20, 50);

        Assert.Equal(42_949_673, result.Page);
        Assert.Equal(2_147_483_600, result.Offset);
    }
}
