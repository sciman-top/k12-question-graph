using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddCutCandidateModelForS005A : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "cut_candidates",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    source_document_id = table.Column<Guid>(type: "uuid", nullable: false),
                    source_region_id = table.Column<Guid>(type: "uuid", nullable: true),
                    suggested_question_item_id = table.Column<Guid>(type: "uuid", nullable: true),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "pending_review"),
                    confidence = table.Column<decimal>(type: "numeric", nullable: false),
                    segment_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "question_stem"),
                    sequence_no = table.Column<int>(type: "integer", nullable: false),
                    candidate_payload = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    failure_reason = table.Column<string>(type: "character varying(1024)", maxLength: 1024, nullable: false, defaultValue: ""),
                    takeover_action = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "manual_review"),
                    metadata = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_cut_candidates", x => x.id);
                    table.CheckConstraint("ck_cut_candidates_confidence", "confidence >= 0 and confidence <= 1");
                    table.CheckConstraint("ck_cut_candidates_sequence_no", "sequence_no >= 0");
                    table.CheckConstraint("ck_cut_candidates_status", "status in ('pending_review','needs_split','needs_merge','accepted','rejected','retry_required')");
                    table.CheckConstraint("ck_cut_candidates_takeover_action", "takeover_action in ('manual_review','split','merge','skip','rerun')");
                    table.ForeignKey(
                        name: "fk_cut_candidates_question_items_suggested_question_item_id",
                        column: x => x.suggested_question_item_id,
                        principalTable: "question_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "fk_cut_candidates_source_documents_source_document_id",
                        column: x => x.source_document_id,
                        principalTable: "source_documents",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_cut_candidates_source_regions_source_region_id",
                        column: x => x.source_region_id,
                        principalTable: "source_regions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateIndex(
                name: "ix_cut_candidates_source_document_id_status",
                table: "cut_candidates",
                columns: new[] { "source_document_id", "status" });

            migrationBuilder.CreateIndex(
                name: "ix_cut_candidates_source_region_id",
                table: "cut_candidates",
                column: "source_region_id");

            migrationBuilder.CreateIndex(
                name: "ix_cut_candidates_suggested_question_item_id",
                table: "cut_candidates",
                column: "suggested_question_item_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "cut_candidates");
        }
    }
}
