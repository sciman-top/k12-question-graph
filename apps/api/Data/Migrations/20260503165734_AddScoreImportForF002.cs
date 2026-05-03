using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddScoreImportForF002 : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "score_import_templates",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    template_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    display_name = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    version = table.Column<int>(type: "integer", nullable: false),
                    mode = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "draft_test"),
                    production_eligible = table.Column<bool>(type: "boolean", nullable: false),
                    synthetic_fixture = table.Column<bool>(type: "boolean", nullable: false),
                    review_status = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "pending_review"),
                    field_mapping = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    migration_policy = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_score_import_templates", x => x.id);
                    table.CheckConstraint("ck_score_import_templates_mode", "mode in ('draft_test','production')");
                    table.CheckConstraint("ck_score_import_templates_production_guard", "(production_eligible = false and mode = 'draft_test') or (production_eligible = true and mode = 'production')");
                    table.CheckConstraint("ck_score_import_templates_review_status", "review_status in ('auto_applied','pending_review','approved','rejected')");
                    table.CheckConstraint("ck_score_import_templates_version", "version >= 1");
                });

            migrationBuilder.CreateTable(
                name: "score_import_batches",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    assessment_id = table.Column<Guid>(type: "uuid", nullable: false),
                    template_id = table.Column<Guid>(type: "uuid", nullable: false),
                    mode = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "draft_test"),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "draft"),
                    source_file_name = table.Column<string>(type: "character varying(260)", maxLength: 260, nullable: false, defaultValue: ""),
                    production_eligible = table.Column<bool>(type: "boolean", nullable: false),
                    synthetic_fixture = table.Column<bool>(type: "boolean", nullable: false),
                    contains_student_pii = table.Column<bool>(type: "boolean", nullable: false),
                    row_count = table.Column<int>(type: "integer", nullable: false),
                    imported_count = table.Column<int>(type: "integer", nullable: false),
                    error_count = table.Column<int>(type: "integer", nullable: false),
                    error_summary = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'[]'::jsonb"),
                    metadata = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_score_import_batches", x => x.id);
                    table.CheckConstraint("ck_score_import_batches_counts", "row_count >= 0 and imported_count >= 0 and error_count >= 0 and row_count >= imported_count and row_count >= error_count");
                    table.CheckConstraint("ck_score_import_batches_mode", "mode in ('draft_test','production')");
                    table.CheckConstraint("ck_score_import_batches_pii_guard", "contains_student_pii = false");
                    table.CheckConstraint("ck_score_import_batches_production_guard", "(production_eligible = false and mode = 'draft_test') or (production_eligible = true and mode = 'production')");
                    table.CheckConstraint("ck_score_import_batches_status", "status in ('draft','imported','failed','archived')");
                    table.ForeignKey(
                        name: "fk_score_import_batches_assessments_assessment_id",
                        column: x => x.assessment_id,
                        principalTable: "assessments",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_score_import_batches_score_import_templates_template_id",
                        column: x => x.template_id,
                        principalTable: "score_import_templates",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "score_records",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    assessment_id = table.Column<Guid>(type: "uuid", nullable: false),
                    student_id = table.Column<Guid>(type: "uuid", nullable: false),
                    import_batch_id = table.Column<Guid>(type: "uuid", nullable: false),
                    student_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    total_score = table.Column<decimal>(type: "numeric", nullable: true),
                    max_score = table.Column<decimal>(type: "numeric", nullable: true),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "imported"),
                    synthetic_fixture = table.Column<bool>(type: "boolean", nullable: false),
                    contains_student_pii = table.Column<bool>(type: "boolean", nullable: false),
                    raw_row = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_score_records", x => x.id);
                    table.CheckConstraint("ck_score_records_pii_guard", "contains_student_pii = false");
                    table.CheckConstraint("ck_score_records_scores", "(total_score is null or total_score >= 0) and (max_score is null or max_score >= 0) and (total_score is null or max_score is null or total_score <= max_score)");
                    table.CheckConstraint("ck_score_records_status", "status in ('imported','excluded','invalid')");
                    table.ForeignKey(
                        name: "fk_score_records_assessments_assessment_id",
                        column: x => x.assessment_id,
                        principalTable: "assessments",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_score_records_score_import_batches_import_batch_id",
                        column: x => x.import_batch_id,
                        principalTable: "score_import_batches",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_score_records_students_student_id",
                        column: x => x.student_id,
                        principalTable: "students",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "item_scores",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    score_record_id = table.Column<Guid>(type: "uuid", nullable: false),
                    question_no = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    field_name = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    score = table.Column<decimal>(type: "numeric", nullable: false),
                    max_score = table.Column<decimal>(type: "numeric", nullable: false),
                    metadata = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_item_scores", x => x.id);
                    table.CheckConstraint("ck_item_scores_scores", "score >= 0 and max_score >= 0 and score <= max_score");
                    table.ForeignKey(
                        name: "fk_item_scores_score_records_score_record_id",
                        column: x => x.score_record_id,
                        principalTable: "score_records",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_item_scores_score_record_id_question_no",
                table: "item_scores",
                columns: new[] { "score_record_id", "question_no" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_score_import_batches_assessment_id_status",
                table: "score_import_batches",
                columns: new[] { "assessment_id", "status" });

            migrationBuilder.CreateIndex(
                name: "ix_score_import_batches_contains_student_pii",
                table: "score_import_batches",
                column: "contains_student_pii");

            migrationBuilder.CreateIndex(
                name: "ix_score_import_batches_template_id",
                table: "score_import_batches",
                column: "template_id");

            migrationBuilder.CreateIndex(
                name: "ix_score_import_templates_review_status",
                table: "score_import_templates",
                column: "review_status");

            migrationBuilder.CreateIndex(
                name: "ix_score_import_templates_template_key_version",
                table: "score_import_templates",
                columns: new[] { "template_key", "version" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_score_records_assessment_id_student_id",
                table: "score_records",
                columns: new[] { "assessment_id", "student_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_score_records_import_batch_id",
                table: "score_records",
                column: "import_batch_id");

            migrationBuilder.CreateIndex(
                name: "ix_score_records_student_id",
                table: "score_records",
                column: "student_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "item_scores");

            migrationBuilder.DropTable(
                name: "score_records");

            migrationBuilder.DropTable(
                name: "score_import_batches");

            migrationBuilder.DropTable(
                name: "score_import_templates");
        }
    }
}
