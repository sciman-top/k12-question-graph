using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddKnowledgeOntologyForC001 : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "knowledge_nodes",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    subject = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "physics"),
                    stage = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "junior_middle_school"),
                    code = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    title = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    node_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "concept"),
                    level = table.Column<int>(type: "integer", nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "draft"),
                    version = table.Column<int>(type: "integer", nullable: false),
                    parent_id = table.Column<Guid>(type: "uuid", nullable: true),
                    metadata = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_knowledge_nodes", x => x.id);
                    table.CheckConstraint("ck_knowledge_nodes_level", "level >= 1");
                    table.CheckConstraint("ck_knowledge_nodes_status", "status in ('draft','active','deprecated','retired')");
                    table.CheckConstraint("ck_knowledge_nodes_version", "version >= 1");
                    table.ForeignKey(
                        name: "fk_knowledge_nodes_knowledge_nodes_parent_id",
                        column: x => x.parent_id,
                        principalTable: "knowledge_nodes",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "knowledge_edges",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    source_node_id = table.Column<Guid>(type: "uuid", nullable: false),
                    target_node_id = table.Column<Guid>(type: "uuid", nullable: false),
                    edge_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "parent_child"),
                    version = table.Column<int>(type: "integer", nullable: false),
                    metadata = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_knowledge_edges", x => x.id);
                    table.CheckConstraint("ck_knowledge_edges_not_self", "source_node_id <> target_node_id");
                    table.CheckConstraint("ck_knowledge_edges_type", "edge_type in ('parent_child','prerequisite','related')");
                    table.CheckConstraint("ck_knowledge_edges_version", "version >= 1");
                    table.ForeignKey(
                        name: "fk_knowledge_edges_knowledge_nodes_source_node_id",
                        column: x => x.source_node_id,
                        principalTable: "knowledge_nodes",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_knowledge_edges_knowledge_nodes_target_node_id",
                        column: x => x.target_node_id,
                        principalTable: "knowledge_nodes",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "knowledge_mappings",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    question_item_id = table.Column<Guid>(type: "uuid", nullable: false),
                    knowledge_node_id = table.Column<Guid>(type: "uuid", nullable: false),
                    mapping_source = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "manual"),
                    is_primary = table.Column<bool>(type: "boolean", nullable: false),
                    confidence = table.Column<decimal>(type: "numeric", nullable: true),
                    version = table.Column<int>(type: "integer", nullable: false),
                    evidence = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_knowledge_mappings", x => x.id);
                    table.CheckConstraint("ck_knowledge_mappings_confidence", "confidence is null or (confidence >= 0 and confidence <= 1)");
                    table.CheckConstraint("ck_knowledge_mappings_source", "mapping_source in ('manual','import','ai_suggested')");
                    table.CheckConstraint("ck_knowledge_mappings_version", "version >= 1");
                    table.ForeignKey(
                        name: "fk_knowledge_mappings_knowledge_nodes_knowledge_node_id",
                        column: x => x.knowledge_node_id,
                        principalTable: "knowledge_nodes",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_knowledge_mappings_question_items_question_item_id",
                        column: x => x.question_item_id,
                        principalTable: "question_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_question_items_primary_knowledge_id",
                table: "question_items",
                column: "primary_knowledge_id");

            migrationBuilder.CreateIndex(
                name: "ix_knowledge_edges_source_node_id_target_node_id_edge_type_ver",
                table: "knowledge_edges",
                columns: new[] { "source_node_id", "target_node_id", "edge_type", "version" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_knowledge_edges_target_node_id",
                table: "knowledge_edges",
                column: "target_node_id");

            migrationBuilder.CreateIndex(
                name: "ix_knowledge_mappings_knowledge_node_id",
                table: "knowledge_mappings",
                column: "knowledge_node_id");

            migrationBuilder.CreateIndex(
                name: "ix_knowledge_mappings_mapping_source",
                table: "knowledge_mappings",
                column: "mapping_source");

            migrationBuilder.CreateIndex(
                name: "ix_knowledge_mappings_question_item_id_knowledge_node_id_versi",
                table: "knowledge_mappings",
                columns: new[] { "question_item_id", "knowledge_node_id", "version" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_knowledge_nodes_parent_id",
                table: "knowledge_nodes",
                column: "parent_id");

            migrationBuilder.CreateIndex(
                name: "ix_knowledge_nodes_subject_stage_code_version",
                table: "knowledge_nodes",
                columns: new[] { "subject", "stage", "code", "version" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_knowledge_nodes_subject_stage_level",
                table: "knowledge_nodes",
                columns: new[] { "subject", "stage", "level" });

            migrationBuilder.AddForeignKey(
                name: "fk_question_items_knowledge_nodes_primary_knowledge_id",
                table: "question_items",
                column: "primary_knowledge_id",
                principalTable: "knowledge_nodes",
                principalColumn: "id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "fk_question_items_knowledge_nodes_primary_knowledge_id",
                table: "question_items");

            migrationBuilder.DropTable(
                name: "knowledge_edges");

            migrationBuilder.DropTable(
                name: "knowledge_mappings");

            migrationBuilder.DropTable(
                name: "knowledge_nodes");

            migrationBuilder.DropIndex(
                name: "ix_question_items_primary_knowledge_id",
                table: "question_items");
        }
    }
}
