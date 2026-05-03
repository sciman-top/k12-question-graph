using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddAssessmentModelForF001 : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "assessments",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    assessment_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    title = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    subject = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "physics"),
                    stage = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "junior_middle_school"),
                    grade = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: ""),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "draft"),
                    mode = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "draft_test"),
                    production_eligible = table.Column<bool>(type: "boolean", nullable: false),
                    synthetic_fixture = table.Column<bool>(type: "boolean", nullable: false),
                    contains_student_pii = table.Column<bool>(type: "boolean", nullable: false),
                    anonymization_status = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "synthetic"),
                    student_portal_enabled = table.Column<bool>(type: "boolean", nullable: false),
                    blueprint = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    metadata = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_assessments", x => x.id);
                    table.CheckConstraint("ck_assessments_anonymization_status", "anonymization_status in ('none','anonymized','synthetic')");
                    table.CheckConstraint("ck_assessments_mode", "mode in ('draft_test','production')");
                    table.CheckConstraint("ck_assessments_no_portal_for_draft", "(mode <> 'draft_test') or (student_portal_enabled = false)");
                    table.CheckConstraint("ck_assessments_production_guard", "(production_eligible = false and mode = 'draft_test') or (production_eligible = true and mode = 'production')");
                    table.CheckConstraint("ck_assessments_status", "status in ('draft','pending_review','ready','archived')");
                });

            migrationBuilder.CreateTable(
                name: "class_groups",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    class_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    display_name = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false, defaultValue: ""),
                    stage = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "junior_middle_school"),
                    grade = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: ""),
                    school_year = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: ""),
                    synthetic_fixture = table.Column<bool>(type: "boolean", nullable: false),
                    contains_student_pii = table.Column<bool>(type: "boolean", nullable: false),
                    anonymization_status = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "synthetic"),
                    metadata = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_class_groups", x => x.id);
                    table.CheckConstraint("ck_class_groups_anonymization_status", "anonymization_status in ('none','anonymized','synthetic')");
                    table.CheckConstraint("ck_class_groups_pii_guard", "(contains_student_pii = false) or (anonymization_status in ('anonymized','synthetic'))");
                });

            migrationBuilder.CreateTable(
                name: "students",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    student_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    display_code = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false, defaultValue: ""),
                    stage = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "junior_middle_school"),
                    grade = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: ""),
                    synthetic_fixture = table.Column<bool>(type: "boolean", nullable: false),
                    contains_student_pii = table.Column<bool>(type: "boolean", nullable: false),
                    anonymization_status = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "synthetic"),
                    student_portal_enabled = table.Column<bool>(type: "boolean", nullable: false),
                    metadata = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_students", x => x.id);
                    table.CheckConstraint("ck_students_anonymization_status", "anonymization_status in ('none','anonymized','synthetic')");
                    table.CheckConstraint("ck_students_no_portal_for_synthetic", "(synthetic_fixture = false) or (student_portal_enabled = false)");
                    table.CheckConstraint("ck_students_pii_guard", "(contains_student_pii = false) or (anonymization_status in ('anonymized','synthetic'))");
                });

            migrationBuilder.CreateTable(
                name: "assessment_enrollments",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    assessment_id = table.Column<Guid>(type: "uuid", nullable: false),
                    class_group_id = table.Column<Guid>(type: "uuid", nullable: false),
                    student_id = table.Column<Guid>(type: "uuid", nullable: false),
                    seat_no = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: ""),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "enrolled"),
                    synthetic_fixture = table.Column<bool>(type: "boolean", nullable: false),
                    contains_student_pii = table.Column<bool>(type: "boolean", nullable: false),
                    score_summary = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_assessment_enrollments", x => x.id);
                    table.CheckConstraint("ck_assessment_enrollments_pii_guard", "contains_student_pii = false");
                    table.CheckConstraint("ck_assessment_enrollments_status", "status in ('enrolled','excluded','absent')");
                    table.ForeignKey(
                        name: "fk_assessment_enrollments_assessments_assessment_id",
                        column: x => x.assessment_id,
                        principalTable: "assessments",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_assessment_enrollments_class_groups_class_group_id",
                        column: x => x.class_group_id,
                        principalTable: "class_groups",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_assessment_enrollments_students_student_id",
                        column: x => x.student_id,
                        principalTable: "students",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_assessment_enrollments_assessment_id_student_id",
                table: "assessment_enrollments",
                columns: new[] { "assessment_id", "student_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_assessment_enrollments_class_group_id",
                table: "assessment_enrollments",
                column: "class_group_id");

            migrationBuilder.CreateIndex(
                name: "ix_assessment_enrollments_student_id",
                table: "assessment_enrollments",
                column: "student_id");

            migrationBuilder.CreateIndex(
                name: "ix_assessments_assessment_key",
                table: "assessments",
                column: "assessment_key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_assessments_contains_student_pii",
                table: "assessments",
                column: "contains_student_pii");

            migrationBuilder.CreateIndex(
                name: "ix_assessments_subject_stage_status",
                table: "assessments",
                columns: new[] { "subject", "stage", "status" });

            migrationBuilder.CreateIndex(
                name: "ix_class_groups_class_key",
                table: "class_groups",
                column: "class_key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_class_groups_contains_student_pii",
                table: "class_groups",
                column: "contains_student_pii");

            migrationBuilder.CreateIndex(
                name: "ix_class_groups_stage_grade_school_year",
                table: "class_groups",
                columns: new[] { "stage", "grade", "school_year" });

            migrationBuilder.CreateIndex(
                name: "ix_students_contains_student_pii",
                table: "students",
                column: "contains_student_pii");

            migrationBuilder.CreateIndex(
                name: "ix_students_stage_grade",
                table: "students",
                columns: new[] { "stage", "grade" });

            migrationBuilder.CreateIndex(
                name: "ix_students_student_key",
                table: "students",
                column: "student_key",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "assessment_enrollments");

            migrationBuilder.DropTable(
                name: "assessments");

            migrationBuilder.DropTable(
                name: "class_groups");

            migrationBuilder.DropTable(
                name: "students");
        }
    }
}
