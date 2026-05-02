using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class InitialP0 : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterDatabase()
                .Annotation("Npgsql:PostgresExtension:pgcrypto", ",,");

            migrationBuilder.CreateTable(
                name: "ai_jobs",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    job_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "queued"),
                    idempotency_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    model_route = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: true),
                    prompt_version = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    schema_version = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    estimated_cost = table.Column<decimal>(type: "numeric", nullable: true),
                    actual_cost = table.Column<decimal>(type: "numeric", nullable: true),
                    confidence = table.Column<double>(type: "double precision", nullable: true),
                    input = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    result = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    finished_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_ai_jobs", x => x.id);
                    table.CheckConstraint("ck_ai_jobs_status", "status in ('queued','running','succeeded','failed','cancelled','retry_waiting')");
                });

            migrationBuilder.CreateTable(
                name: "backup_jobs",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "queued"),
                    manifest_path = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: true),
                    manifest_sha256 = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    error_message = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    finished_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_backup_jobs", x => x.id);
                    table.CheckConstraint("ck_backup_jobs_status", "status in ('queued','running','succeeded','failed')");
                });

            migrationBuilder.CreateTable(
                name: "file_assets",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    original_file_name = table.Column<string>(type: "character varying(260)", maxLength: 260, nullable: false),
                    relative_path = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: false),
                    storage_scope = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "original"),
                    content_type = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false, defaultValue: "application/octet-stream"),
                    sha256 = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    size_bytes = table.Column<long>(type: "bigint", nullable: false),
                    source_metadata = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_file_assets", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "question_items",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    subject = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "physics"),
                    stage = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "junior_middle_school"),
                    grade = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    question_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    default_score = table.Column<decimal>(type: "numeric", nullable: true),
                    difficulty_estimated = table.Column<double>(type: "double precision", nullable: true),
                    difficulty_observed = table.Column<double>(type: "double precision", nullable: true),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "draft"),
                    primary_knowledge_id = table.Column<Guid>(type: "uuid", nullable: true),
                    blocks = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'[]'::jsonb"),
                    custom_fields = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    quality_signals = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_question_items", x => x.id);
                    table.CheckConstraint("ck_question_items_status", "status in ('draft','pending_review','usable','recommended','needs_improvement','paused','retired')");
                });

            migrationBuilder.CreateTable(
                name: "review_queue_items",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    review_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "open"),
                    payload = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    resolved_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_review_queue_items", x => x.id);
                    table.CheckConstraint("ck_review_queue_items_status", "status in ('open','resolved','dismissed')");
                });

            migrationBuilder.CreateTable(
                name: "teacher_preferences",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    teacher_key = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    preference_key = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    preference_value = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_teacher_preferences", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "import_jobs",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    input_file_asset_id = table.Column<Guid>(type: "uuid", nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "queued"),
                    idempotency_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    locked_by = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: true),
                    locked_until = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    attempt_count = table.Column<int>(type: "integer", nullable: false),
                    max_attempts = table.Column<int>(type: "integer", nullable: false),
                    last_error_code = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    last_error_message = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    input = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    started_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    finished_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_import_jobs", x => x.id);
                    table.CheckConstraint("ck_import_jobs_status", "status in ('queued','running','succeeded','failed','cancelled','retry_waiting')");
                    table.ForeignKey(
                        name: "fk_import_jobs_file_assets_input_file_asset_id",
                        column: x => x.input_file_asset_id,
                        principalTable: "file_assets",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_ai_jobs_idempotency_key",
                table: "ai_jobs",
                column: "idempotency_key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_ai_jobs_status",
                table: "ai_jobs",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "ix_backup_jobs_status",
                table: "backup_jobs",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "ix_file_assets_sha256",
                table: "file_assets",
                column: "sha256");

            migrationBuilder.CreateIndex(
                name: "ix_file_assets_storage_scope_relative_path",
                table: "file_assets",
                columns: new[] { "storage_scope", "relative_path" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_import_jobs_idempotency_key",
                table: "import_jobs",
                column: "idempotency_key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_import_jobs_input_file_asset_id",
                table: "import_jobs",
                column: "input_file_asset_id");

            migrationBuilder.CreateIndex(
                name: "ix_import_jobs_status",
                table: "import_jobs",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "ix_question_items_subject_stage_status",
                table: "question_items",
                columns: new[] { "subject", "stage", "status" });

            migrationBuilder.CreateIndex(
                name: "ix_review_queue_items_status",
                table: "review_queue_items",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "ix_teacher_preferences_teacher_key_preference_key",
                table: "teacher_preferences",
                columns: new[] { "teacher_key", "preference_key" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ai_jobs");

            migrationBuilder.DropTable(
                name: "backup_jobs");

            migrationBuilder.DropTable(
                name: "import_jobs");

            migrationBuilder.DropTable(
                name: "question_items");

            migrationBuilder.DropTable(
                name: "review_queue_items");

            migrationBuilder.DropTable(
                name: "teacher_preferences");

            migrationBuilder.DropTable(
                name: "file_assets");
        }
    }
}
