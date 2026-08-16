namespace K12QuestionGraph.Api.Infrastructure.Queries;

internal readonly record struct PaginationWindow(int Page, int PageSize, int Offset)
{
    public static PaginationWindow Create(
        int? requestedPage,
        int? requestedPageSize,
        int defaultPageSize,
        int maxPageSize)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(defaultPageSize, 1);
        ArgumentOutOfRangeException.ThrowIfLessThan(maxPageSize, defaultPageSize);

        var pageSize = Math.Clamp(requestedPageSize ?? defaultPageSize, 1, maxPageSize);
        var page = Math.Max(requestedPage ?? 1, 1);
        var maxRepresentablePage = Math.Min(
            int.MaxValue,
            (int.MaxValue / (long)pageSize) + 1L);
        page = (int)Math.Min(page, maxRepresentablePage);
        var offset = checked((page - 1) * pageSize);

        return new PaginationWindow(page, pageSize, offset);
    }
}
