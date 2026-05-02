using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace K12QuestionGraph.Api.Data;

public sealed class KqgDbContextFactory : IDesignTimeDbContextFactory<KqgDbContext>
{
    public KqgDbContext CreateDbContext(string[] args)
    {
        var connectionString = Environment.GetEnvironmentVariable("KQG_CONNECTION_STRING")
            ?? "Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres";

        var options = new DbContextOptionsBuilder<KqgDbContext>()
            .UseNpgsql(connectionString)
            .UseSnakeCaseNamingConvention()
            .Options;

        return new KqgDbContext(options);
    }
}
