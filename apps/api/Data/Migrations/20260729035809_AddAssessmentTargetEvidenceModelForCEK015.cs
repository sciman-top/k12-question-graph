using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddAssessmentTargetEvidenceModelForCEK015 : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "assessment_targets",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    stable_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    batch_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    question_item_id = table.Column<Guid>(type: "uuid", nullable: false),
                    question_block_id = table.Column<Guid>(type: "uuid", nullable: true),
                    scope_type = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "whole_question"),
                    target_statement = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: false),
                    is_primary_target = table.Column<bool>(type: "boolean", nullable: false),
                    confidence = table.Column<decimal>(type: "numeric", nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "candidate"),
                    review_status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "pending_review"),
                    production_eligible = table.Column<bool>(type: "boolean", nullable: false),
                    metadata = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_assessment_targets", x => x.id);
                    table.CheckConstraint("ck_assessment_targets_confidence", "confidence >= 0 and confidence <= 1");
                    table.CheckConstraint("ck_assessment_targets_production_guard", "production_eligible = false or (status = 'active' and review_status = 'approved')");
                    table.CheckConstraint("ck_assessment_targets_review_status", "review_status in ('pending_review','approved','rejected')");
                    table.CheckConstraint("ck_assessment_targets_scope_block", "(scope_type = 'whole_question' and question_block_id is null) or (scope_type in ('subquestion','scoring_point') and question_block_id is not null)");
                    table.CheckConstraint("ck_assessment_targets_scope_type", "scope_type in ('whole_question','subquestion','scoring_point')");
                    table.CheckConstraint("ck_assessment_targets_status", "status in ('candidate','reviewed','active','rejected')");
                    table.ForeignKey(
                        name: "fk_assessment_targets_question_blocks_question_block_id",
                        column: x => x.question_block_id,
                        principalTable: "question_blocks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_assessment_targets_question_items_question_item_id",
                        column: x => x.question_item_id,
                        principalTable: "question_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "assessment_target_knowledge_mappings",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    assessment_target_id = table.Column<Guid>(type: "uuid", nullable: false),
                    domain_asset_version_id = table.Column<Guid>(type: "uuid", nullable: false),
                    role = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "primary"),
                    confidence = table.Column<decimal>(type: "numeric", nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "candidate"),
                    review_status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "pending_review"),
                    production_eligible = table.Column<bool>(type: "boolean", nullable: false),
                    evidence = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_assessment_target_knowledge_mappings", x => x.id);
                    table.CheckConstraint("ck_assessment_target_knowledge_confidence", "confidence >= 0 and confidence <= 1");
                    table.CheckConstraint("ck_assessment_target_knowledge_production_guard", "production_eligible = false or (status = 'active' and review_status = 'approved')");
                    table.CheckConstraint("ck_assessment_target_knowledge_review_status", "review_status in ('pending_review','approved','rejected')");
                    table.CheckConstraint("ck_assessment_target_knowledge_role", "role in ('primary','secondary','prerequisite')");
                    table.CheckConstraint("ck_assessment_target_knowledge_status", "status in ('candidate','reviewed','active','rejected')");
                    table.ForeignKey(
                        name: "fk_assessment_target_knowledge_mappings_assessment_targets_ass",
                        column: x => x.assessment_target_id,
                        principalTable: "assessment_targets",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_assessment_target_knowledge_mappings_domain_asset_versions_",
                        column: x => x.domain_asset_version_id,
                        principalTable: "domain_asset_versions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "curriculum_alignments",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    stable_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    assessment_target_id = table.Column<Guid>(type: "uuid", nullable: false),
                    curriculum_asset_version_id = table.Column<Guid>(type: "uuid", nullable: false),
                    source_document_id = table.Column<Guid>(type: "uuid", nullable: false),
                    source_region_id = table.Column<Guid>(type: "uuid", nullable: true),
                    alignment_type = table.Column<string>(type: "character varying(48)", maxLength: 48, nullable: false, defaultValue: "retrospective_crosswalk"),
                    standard_version = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    confidence = table.Column<decimal>(type: "numeric", nullable: false),
                    original_basis = table.Column<bool>(type: "boolean", nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "candidate"),
                    review_status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "pending_review"),
                    production_eligible = table.Column<bool>(type: "boolean", nullable: false),
                    evidence = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_curriculum_alignments", x => x.id);
                    table.CheckConstraint("ck_curriculum_alignments_confidence", "confidence >= 0 and confidence <= 1");
                    table.CheckConstraint("ck_curriculum_alignments_original_basis", "original_basis = false or alignment_type = 'source_cited'");
                    table.CheckConstraint("ck_curriculum_alignments_production_guard", "production_eligible = false or (status = 'active' and review_status = 'approved')");
                    table.CheckConstraint("ck_curriculum_alignments_review_status", "review_status in ('pending_review','approved','rejected')");
                    table.CheckConstraint("ck_curriculum_alignments_status", "status in ('candidate','reviewed','active','rejected')");
                    table.CheckConstraint("ck_curriculum_alignments_type", "alignment_type in ('source_cited','contemporaneous_inferred','retrospective_crosswalk')");
                    table.ForeignKey(
                        name: "fk_curriculum_alignments_assessment_targets_assessment_target_",
                        column: x => x.assessment_target_id,
                        principalTable: "assessment_targets",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_curriculum_alignments_domain_asset_versions_curriculum_asse",
                        column: x => x.curriculum_asset_version_id,
                        principalTable: "domain_asset_versions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_curriculum_alignments_source_documents_source_document_id",
                        column: x => x.source_document_id,
                        principalTable: "source_documents",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_curriculum_alignments_source_regions_source_region_id",
                        column: x => x.source_region_id,
                        principalTable: "source_regions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_assessment_target_knowledge_mappings_assessment_target_id",
                table: "assessment_target_knowledge_mappings",
                column: "assessment_target_id",
                unique: true,
                filter: "role = 'primary'");

            migrationBuilder.CreateIndex(
                name: "ix_assessment_target_knowledge_mappings_assessment_target_id_d",
                table: "assessment_target_knowledge_mappings",
                columns: new[] { "assessment_target_id", "domain_asset_version_id", "role" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_assessment_target_knowledge_mappings_domain_asset_version_id",
                table: "assessment_target_knowledge_mappings",
                column: "domain_asset_version_id");

            migrationBuilder.CreateIndex(
                name: "ix_assessment_target_knowledge_mappings_review_status",
                table: "assessment_target_knowledge_mappings",
                column: "review_status");

            migrationBuilder.CreateIndex(
                name: "ix_assessment_targets_batch_key",
                table: "assessment_targets",
                column: "batch_key");

            migrationBuilder.CreateIndex(
                name: "ix_assessment_targets_question_block_id",
                table: "assessment_targets",
                column: "question_block_id");

            migrationBuilder.CreateIndex(
                name: "ix_assessment_targets_question_item_id_scope_type",
                table: "assessment_targets",
                columns: new[] { "question_item_id", "scope_type" });

            migrationBuilder.CreateIndex(
                name: "ix_assessment_targets_review_status",
                table: "assessment_targets",
                column: "review_status");

            migrationBuilder.CreateIndex(
                name: "ix_assessment_targets_stable_key",
                table: "assessment_targets",
                column: "stable_key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_curriculum_alignments_assessment_target_id",
                table: "curriculum_alignments",
                column: "assessment_target_id");

            migrationBuilder.CreateIndex(
                name: "ix_curriculum_alignments_curriculum_asset_version_id",
                table: "curriculum_alignments",
                column: "curriculum_asset_version_id");

            migrationBuilder.CreateIndex(
                name: "ix_curriculum_alignments_review_status",
                table: "curriculum_alignments",
                column: "review_status");

            migrationBuilder.CreateIndex(
                name: "ix_curriculum_alignments_source_document_id",
                table: "curriculum_alignments",
                column: "source_document_id");

            migrationBuilder.CreateIndex(
                name: "ix_curriculum_alignments_source_region_id",
                table: "curriculum_alignments",
                column: "source_region_id");

            migrationBuilder.CreateIndex(
                name: "ix_curriculum_alignments_stable_key",
                table: "curriculum_alignments",
                column: "stable_key",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "assessment_target_knowledge_mappings");

            migrationBuilder.DropTable(
                name: "curriculum_alignments");

            migrationBuilder.DropTable(
                name: "assessment_targets");
        }
    }
}
