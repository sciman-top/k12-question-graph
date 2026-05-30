using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddFeedbackEventsForNS505 : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "feedback_events",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    ai_job_id = table.Column<Guid>(type: "uuid", nullable: true),
                    task_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    entity_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    entity_id = table.Column<Guid>(type: "uuid", nullable: true),
                    field_key = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    before_value = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    after_value = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    ai_confidence = table.Column<double>(type: "double precision", nullable: true),
                    reason_tag = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: true),
                    teacher_id = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    prompt_version = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    schema_version = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    model = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: true),
                    accepted_for_eval = table.Column<bool>(type: "boolean", nullable: false),
                    metadata = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_feedback_events", x => x.id);
                    table.CheckConstraint("ck_feedback_events_ai_confidence", "ai_confidence is null or (ai_confidence >= 0 and ai_confidence <= 1)");
                    table.ForeignKey(
                        name: "fk_feedback_events_ai_jobs_ai_job_id",
                        column: x => x.ai_job_id,
                        principalTable: "ai_jobs",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateIndex(
                name: "ix_feedback_events_accepted_for_eval",
                table: "feedback_events",
                column: "accepted_for_eval");

            migrationBuilder.CreateIndex(
                name: "ix_feedback_events_ai_job_id",
                table: "feedback_events",
                column: "ai_job_id");

            migrationBuilder.CreateIndex(
                name: "ix_feedback_events_created_at",
                table: "feedback_events",
                column: "created_at");

            migrationBuilder.CreateIndex(
                name: "ix_feedback_events_task_type",
                table: "feedback_events",
                column: "task_type");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "feedback_events");
        }
    }
}
