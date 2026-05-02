using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddSourceRegionsForB003 : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "source_regions",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    source_document_id = table.Column<Guid>(type: "uuid", nullable: false),
                    page_number = table.Column<int>(type: "integer", nullable: false),
                    x = table.Column<decimal>(type: "numeric", nullable: false),
                    y = table.Column<decimal>(type: "numeric", nullable: false),
                    width = table.Column<decimal>(type: "numeric", nullable: false),
                    height = table.Column<decimal>(type: "numeric", nullable: false),
                    coordinate_unit = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "percent"),
                    screenshot_relative_path = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: true),
                    region_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "preview"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_source_regions", x => x.id);
                    table.CheckConstraint("ck_source_regions_bbox", "x >= 0 and y >= 0 and width > 0 and height > 0");
                    table.CheckConstraint("ck_source_regions_coordinate_unit", "coordinate_unit in ('pixel','point','percent')");
                    table.CheckConstraint("ck_source_regions_page_number", "page_number >= 1");
                    table.ForeignKey(
                        name: "fk_source_regions_source_documents_source_document_id",
                        column: x => x.source_document_id,
                        principalTable: "source_documents",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_source_regions_source_document_id_page_number",
                table: "source_regions",
                columns: new[] { "source_document_id", "page_number" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "source_regions");
        }
    }
}
