using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddAiJobCostLoggingForD002 : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "cached_tokens",
                table: "ai_jobs",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "input_hash",
                table: "ai_jobs",
                type: "character varying(128)",
                maxLength: 128,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "input_tokens",
                table: "ai_jobs",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "latency_ms",
                table: "ai_jobs",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "model_name",
                table: "ai_jobs",
                type: "character varying(128)",
                maxLength: 128,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "model_provider",
                table: "ai_jobs",
                type: "character varying(64)",
                maxLength: 64,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "output_tokens",
                table: "ai_jobs",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "review_status",
                table: "ai_jobs",
                type: "character varying(32)",
                maxLength: 32,
                nullable: false,
                defaultValue: "open");

            migrationBuilder.AddColumn<string>(
                name: "routing_version",
                table: "ai_jobs",
                type: "character varying(64)",
                maxLength: 64,
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "teacher_modified",
                table: "ai_jobs",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddCheckConstraint(
                name: "ck_ai_jobs_confidence",
                table: "ai_jobs",
                sql: "confidence is null or (confidence >= 0 and confidence <= 1)");

            migrationBuilder.AddCheckConstraint(
                name: "ck_ai_jobs_costs",
                table: "ai_jobs",
                sql: "(estimated_cost is null or estimated_cost >= 0) and (actual_cost is null or actual_cost >= 0)");

            migrationBuilder.AddCheckConstraint(
                name: "ck_ai_jobs_review_status",
                table: "ai_jobs",
                sql: "review_status in ('open','resolved','dismissed','pending_review')");

            migrationBuilder.AddCheckConstraint(
                name: "ck_ai_jobs_tokens",
                table: "ai_jobs",
                sql: "(input_tokens is null or input_tokens >= 0) and (output_tokens is null or output_tokens >= 0) and (cached_tokens is null or cached_tokens >= 0)");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "ck_ai_jobs_confidence",
                table: "ai_jobs");

            migrationBuilder.DropCheckConstraint(
                name: "ck_ai_jobs_costs",
                table: "ai_jobs");

            migrationBuilder.DropCheckConstraint(
                name: "ck_ai_jobs_review_status",
                table: "ai_jobs");

            migrationBuilder.DropCheckConstraint(
                name: "ck_ai_jobs_tokens",
                table: "ai_jobs");

            migrationBuilder.DropColumn(
                name: "cached_tokens",
                table: "ai_jobs");

            migrationBuilder.DropColumn(
                name: "input_hash",
                table: "ai_jobs");

            migrationBuilder.DropColumn(
                name: "input_tokens",
                table: "ai_jobs");

            migrationBuilder.DropColumn(
                name: "latency_ms",
                table: "ai_jobs");

            migrationBuilder.DropColumn(
                name: "model_name",
                table: "ai_jobs");

            migrationBuilder.DropColumn(
                name: "model_provider",
                table: "ai_jobs");

            migrationBuilder.DropColumn(
                name: "output_tokens",
                table: "ai_jobs");

            migrationBuilder.DropColumn(
                name: "review_status",
                table: "ai_jobs");

            migrationBuilder.DropColumn(
                name: "routing_version",
                table: "ai_jobs");

            migrationBuilder.DropColumn(
                name: "teacher_modified",
                table: "ai_jobs");
        }
    }
}
