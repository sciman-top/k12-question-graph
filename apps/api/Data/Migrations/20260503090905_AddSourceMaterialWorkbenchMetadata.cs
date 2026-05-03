using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddSourceMaterialWorkbenchMetadata : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "edition_or_version",
                table: "source_documents",
                type: "character varying(128)",
                maxLength: 128,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "grade_or_scope",
                table: "source_documents",
                type: "character varying(128)",
                maxLength: 128,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "material_batch_key",
                table: "source_documents",
                type: "character varying(160)",
                maxLength: 160,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<bool>(
                name: "may_use_for_exam_point_extraction",
                table: "source_documents",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "may_use_for_knowledge_extraction",
                table: "source_documents",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "may_use_for_trend_analysis",
                table: "source_documents",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "region",
                table: "source_documents",
                type: "character varying(128)",
                maxLength: 128,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<int>(
                name: "year",
                table: "source_documents",
                type: "integer",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "ix_source_documents_source_type_region_year",
                table: "source_documents",
                columns: new[] { "source_type", "region", "year" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ix_source_documents_source_type_region_year",
                table: "source_documents");

            migrationBuilder.DropColumn(
                name: "edition_or_version",
                table: "source_documents");

            migrationBuilder.DropColumn(
                name: "grade_or_scope",
                table: "source_documents");

            migrationBuilder.DropColumn(
                name: "material_batch_key",
                table: "source_documents");

            migrationBuilder.DropColumn(
                name: "may_use_for_exam_point_extraction",
                table: "source_documents");

            migrationBuilder.DropColumn(
                name: "may_use_for_knowledge_extraction",
                table: "source_documents");

            migrationBuilder.DropColumn(
                name: "may_use_for_trend_analysis",
                table: "source_documents");

            migrationBuilder.DropColumn(
                name: "region",
                table: "source_documents");

            migrationBuilder.DropColumn(
                name: "year",
                table: "source_documents");
        }
    }
}
