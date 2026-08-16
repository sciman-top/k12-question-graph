using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace K12QuestionGraph.Api.Tests;

public class QueryableJsonProjectionModelTests
{
    [Fact]
    public void Model_MapsJsonProjectionsAsIndexedComputedColumns()
    {
        var options = new DbContextOptionsBuilder<KqgDbContext>()
            .UseNpgsql("Host=127.0.0.1;Database=model_only")
            .Options;
        using var context = new KqgDbContext(options);

        var questionItem = context.Model.FindEntityType(typeof(QuestionItem));
        var reviewQueueItem = context.Model.FindEntityType(typeof(ReviewQueueItem));

        Assert.NotNull(questionItem);
        Assert.NotNull(reviewQueueItem);

        var questionNoProjection = questionItem.FindProperty(nameof(QuestionItem.QuestionNo))!.GetComputedColumnSql();
        Assert.Contains("custom_fields", questionNoProjection);
        Assert.Contains("BETWEEN -2147483648 AND 2147483647", questionNoProjection);
        Assert.Contains("sourceDocumentId", reviewQueueItem.FindProperty(nameof(ReviewQueueItem.SourceDocumentId))!.GetComputedColumnSql());
        Assert.Contains("questionItemId", reviewQueueItem.FindProperty(nameof(ReviewQueueItem.QuestionItemId))!.GetComputedColumnSql());

        Assert.Contains(questionItem.GetIndexes(), index =>
            index.Properties.Select(property => property.Name).SequenceEqual([nameof(QuestionItem.QuestionNo)]));
        Assert.Contains(reviewQueueItem.GetIndexes(), index =>
            index.Properties.Select(property => property.Name).SequenceEqual([nameof(ReviewQueueItem.SourceDocumentId)]));
        Assert.Contains(reviewQueueItem.GetIndexes(), index =>
            index.Properties.Select(property => property.Name).SequenceEqual([nameof(ReviewQueueItem.QuestionItemId)]));
    }
}
