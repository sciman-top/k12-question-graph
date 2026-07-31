using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddObservedExamEvidenceModelForCEK019 : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "observed_error_evidence",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    stable_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    batch_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    assessment_target_id = table.Column<Guid>(type: "uuid", nullable: false),
                    source_region_id = table.Column<Guid>(type: "uuid", nullable: false),
                    record_kind = table.Column<string>(type: "character varying(48)", maxLength: 48, nullable: false, defaultValue: "summary_candidate"),
                    content = table.Column<string>(type: "text", nullable: false),
                    generation_method = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "rules"),
                    confidence = table.Column<decimal>(type: "numeric", nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "candidate"),
                    review_status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "pending_review"),
                    production_eligible = table.Column<bool>(type: "boolean", nullable: false),
                    evidence = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_observed_error_evidence", x => x.id);
                    table.CheckConstraint("ck_observed_error_confidence", "confidence >= 0 and confidence <= 1");
                    table.CheckConstraint("ck_observed_error_generation", "generation_method in ('source_quote','rules','ai','human')");
                    table.CheckConstraint("ck_observed_error_kind", "record_kind in ('verbatim_observation','summary_candidate','normalized_pattern_candidate')");
                    table.CheckConstraint("ck_observed_error_normalized_generation", "record_kind <> 'normalized_pattern_candidate' or generation_method in ('rules','ai','human')");
                    table.CheckConstraint("ck_observed_error_production_guard", "production_eligible = false or (status = 'active' and review_status = 'approved')");
                    table.CheckConstraint("ck_observed_error_review_status", "review_status in ('pending_review','approved','rejected')");
                    table.CheckConstraint("ck_observed_error_status", "status in ('candidate','reviewed','active','rejected')");
                    table.CheckConstraint("ck_observed_error_verbatim_generation", "record_kind <> 'verbatim_observation' or generation_method = 'source_quote'");
                    table.ForeignKey(
                        name: "fk_observed_error_evidence_assessment_targets_assessment_targe",
                        column: x => x.assessment_target_id,
                        principalTable: "assessment_targets",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_observed_error_evidence_source_regions_source_region_id",
                        column: x => x.source_region_id,
                        principalTable: "source_regions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "observed_performance_evidence",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    stable_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    batch_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    assessment_target_id = table.Column<Guid>(type: "uuid", nullable: false),
                    source_region_id = table.Column<Guid>(type: "uuid", nullable: false),
                    maximum_score = table.Column<decimal>(type: "numeric", nullable: true),
                    average_score = table.Column<decimal>(type: "numeric", nullable: true),
                    score_rate = table.Column<decimal>(type: "numeric", nullable: true),
                    difficulty_observed = table.Column<decimal>(type: "numeric", nullable: true),
                    discrimination = table.Column<decimal>(type: "numeric", nullable: true),
                    difficulty_direction = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "higher_is_easier"),
                    sample_scope = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    sample_size = table.Column<int>(type: "integer", nullable: true),
                    option_distribution = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'null'::jsonb"),
                    raw_statistics = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    confidence = table.Column<decimal>(type: "numeric", nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "candidate"),
                    review_status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "pending_review"),
                    production_eligible = table.Column<bool>(type: "boolean", nullable: false),
                    evidence = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_observed_performance_evidence", x => x.id);
                    table.CheckConstraint("ck_observed_performance_confidence", "confidence >= 0 and confidence <= 1");
                    table.CheckConstraint("ck_observed_performance_direction", "difficulty_direction = 'higher_is_easier'");
                    table.CheckConstraint("ck_observed_performance_discrimination", "discrimination is null or (discrimination >= -1 and discrimination <= 1)");
                    table.CheckConstraint("ck_observed_performance_has_metric", "maximum_score is not null or average_score is not null or score_rate is not null or difficulty_observed is not null or discrimination is not null or option_distribution <> 'null'::jsonb");
                    table.CheckConstraint("ck_observed_performance_production_guard", "production_eligible = false or (status = 'active' and review_status = 'approved')");
                    table.CheckConstraint("ck_observed_performance_rates", "(score_rate is null or (score_rate >= 0 and score_rate <= 1)) and (difficulty_observed is null or (difficulty_observed >= 0 and difficulty_observed <= 1))");
                    table.CheckConstraint("ck_observed_performance_review_status", "review_status in ('pending_review','approved','rejected')");
                    table.CheckConstraint("ck_observed_performance_sample_size", "sample_size is null or sample_size > 0");
                    table.CheckConstraint("ck_observed_performance_scores", "(maximum_score is null or maximum_score >= 0) and (average_score is null or average_score >= 0)");
                    table.CheckConstraint("ck_observed_performance_status", "status in ('candidate','reviewed','active','rejected')");
                    table.ForeignKey(
                        name: "fk_observed_performance_evidence_assessment_targets_assessment",
                        column: x => x.assessment_target_id,
                        principalTable: "assessment_targets",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_observed_performance_evidence_source_regions_source_region_",
                        column: x => x.source_region_id,
                        principalTable: "source_regions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "teaching_recommendations",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    stable_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    batch_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    assessment_target_id = table.Column<Guid>(type: "uuid", nullable: false),
                    source_region_id = table.Column<Guid>(type: "uuid", nullable: false),
                    content = table.Column<string>(type: "text", nullable: false),
                    author_kind = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "legacy_candidate"),
                    generation_method = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "rules"),
                    confidence = table.Column<decimal>(type: "numeric", nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "candidate"),
                    review_status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "pending_review"),
                    production_eligible = table.Column<bool>(type: "boolean", nullable: false),
                    evidence = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_teaching_recommendations", x => x.id);
                    table.CheckConstraint("ck_teaching_recommendations_ai_generation", "author_kind <> 'ai_candidate' or generation_method = 'ai'");
                    table.CheckConstraint("ck_teaching_recommendations_author", "author_kind in ('report_author','teacher','ai_candidate','legacy_candidate')");
                    table.CheckConstraint("ck_teaching_recommendations_confidence", "confidence >= 0 and confidence <= 1");
                    table.CheckConstraint("ck_teaching_recommendations_generation", "generation_method in ('source_quote','rules','ai','human')");
                    table.CheckConstraint("ck_teaching_recommendations_production_guard", "production_eligible = false or (status = 'active' and review_status = 'approved')");
                    table.CheckConstraint("ck_teaching_recommendations_report_author_generation", "author_kind <> 'report_author' or generation_method = 'source_quote'");
                    table.CheckConstraint("ck_teaching_recommendations_review_status", "review_status in ('pending_review','approved','rejected')");
                    table.CheckConstraint("ck_teaching_recommendations_status", "status in ('candidate','reviewed','active','rejected')");
                    table.ForeignKey(
                        name: "fk_teaching_recommendations_assessment_targets_assessment_targ",
                        column: x => x.assessment_target_id,
                        principalTable: "assessment_targets",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_teaching_recommendations_source_regions_source_region_id",
                        column: x => x.source_region_id,
                        principalTable: "source_regions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_observed_error_evidence_assessment_target_id",
                table: "observed_error_evidence",
                column: "assessment_target_id");

            migrationBuilder.CreateIndex(
                name: "ix_observed_error_evidence_batch_key",
                table: "observed_error_evidence",
                column: "batch_key");

            migrationBuilder.CreateIndex(
                name: "ix_observed_error_evidence_review_status",
                table: "observed_error_evidence",
                column: "review_status");

            migrationBuilder.CreateIndex(
                name: "ix_observed_error_evidence_source_region_id",
                table: "observed_error_evidence",
                column: "source_region_id");

            migrationBuilder.CreateIndex(
                name: "ix_observed_error_evidence_stable_key",
                table: "observed_error_evidence",
                column: "stable_key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_observed_performance_evidence_assessment_target_id",
                table: "observed_performance_evidence",
                column: "assessment_target_id");

            migrationBuilder.CreateIndex(
                name: "ix_observed_performance_evidence_batch_key",
                table: "observed_performance_evidence",
                column: "batch_key");

            migrationBuilder.CreateIndex(
                name: "ix_observed_performance_evidence_review_status",
                table: "observed_performance_evidence",
                column: "review_status");

            migrationBuilder.CreateIndex(
                name: "ix_observed_performance_evidence_source_region_id",
                table: "observed_performance_evidence",
                column: "source_region_id");

            migrationBuilder.CreateIndex(
                name: "ix_observed_performance_evidence_stable_key",
                table: "observed_performance_evidence",
                column: "stable_key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_teaching_recommendations_assessment_target_id",
                table: "teaching_recommendations",
                column: "assessment_target_id");

            migrationBuilder.CreateIndex(
                name: "ix_teaching_recommendations_batch_key",
                table: "teaching_recommendations",
                column: "batch_key");

            migrationBuilder.CreateIndex(
                name: "ix_teaching_recommendations_review_status",
                table: "teaching_recommendations",
                column: "review_status");

            migrationBuilder.CreateIndex(
                name: "ix_teaching_recommendations_source_region_id",
                table: "teaching_recommendations",
                column: "source_region_id");

            migrationBuilder.CreateIndex(
                name: "ix_teaching_recommendations_stable_key",
                table: "teaching_recommendations",
                column: "stable_key",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "observed_error_evidence");

            migrationBuilder.DropTable(
                name: "observed_performance_evidence");

            migrationBuilder.DropTable(
                name: "teaching_recommendations");
        }
    }
}
