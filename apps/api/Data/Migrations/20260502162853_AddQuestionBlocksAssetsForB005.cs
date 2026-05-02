using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddQuestionBlocksAssetsForB005 : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "question_assets",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    question_item_id = table.Column<Guid>(type: "uuid", nullable: false),
                    file_asset_id = table.Column<Guid>(type: "uuid", nullable: true),
                    source_region_id = table.Column<Guid>(type: "uuid", nullable: true),
                    asset_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "image"),
                    purpose = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false, defaultValue: "question_content"),
                    metadata = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_question_assets", x => x.id);
                    table.ForeignKey(
                        name: "fk_question_assets_file_assets_file_asset_id",
                        column: x => x.file_asset_id,
                        principalTable: "file_assets",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_question_assets_question_items_question_item_id",
                        column: x => x.question_item_id,
                        principalTable: "question_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_question_assets_source_regions_source_region_id",
                        column: x => x.source_region_id,
                        principalTable: "source_regions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "question_blocks",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    question_item_id = table.Column<Guid>(type: "uuid", nullable: false),
                    block_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "text"),
                    sort_order = table.Column<int>(type: "integer", nullable: false),
                    content = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    source_region_id = table.Column<Guid>(type: "uuid", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_question_blocks", x => x.id);
                    table.CheckConstraint("ck_question_blocks_sort_order", "sort_order >= 0");
                    table.ForeignKey(
                        name: "fk_question_blocks_question_items_question_item_id",
                        column: x => x.question_item_id,
                        principalTable: "question_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_question_blocks_source_regions_source_region_id",
                        column: x => x.source_region_id,
                        principalTable: "source_regions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_question_assets_file_asset_id",
                table: "question_assets",
                column: "file_asset_id");

            migrationBuilder.CreateIndex(
                name: "ix_question_assets_question_item_id",
                table: "question_assets",
                column: "question_item_id");

            migrationBuilder.CreateIndex(
                name: "ix_question_assets_source_region_id",
                table: "question_assets",
                column: "source_region_id");

            migrationBuilder.CreateIndex(
                name: "ix_question_blocks_block_type",
                table: "question_blocks",
                column: "block_type");

            migrationBuilder.CreateIndex(
                name: "ix_question_blocks_question_item_id_sort_order",
                table: "question_blocks",
                columns: new[] { "question_item_id", "sort_order" });

            migrationBuilder.CreateIndex(
                name: "ix_question_blocks_source_region_id",
                table: "question_blocks",
                column: "source_region_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "question_assets");

            migrationBuilder.DropTable(
                name: "question_blocks");
        }
    }
}
