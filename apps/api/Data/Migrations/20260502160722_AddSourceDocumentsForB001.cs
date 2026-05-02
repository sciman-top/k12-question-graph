using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddSourceDocumentsForB001 : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "source_documents",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    file_asset_id = table.Column<Guid>(type: "uuid", nullable: false),
                    source_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "unknown"),
                    source_title = table.Column<string>(type: "character varying(260)", maxLength: 260, nullable: false, defaultValue: ""),
                    owner_scope = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "teacher_private"),
                    license_or_permission = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false, defaultValue: "unknown"),
                    sharing_allowed = table.Column<bool>(type: "boolean", nullable: false),
                    contains_student_pii = table.Column<bool>(type: "boolean", nullable: false),
                    anonymization_status = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "not_applicable"),
                    external_ai_allowed = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_source_documents", x => x.id);
                    table.CheckConstraint("ck_source_documents_anonymization_status", "anonymization_status in ('none','anonymized','synthetic','not_applicable')");
                    table.ForeignKey(
                        name: "fk_source_documents_file_assets_file_asset_id",
                        column: x => x.file_asset_id,
                        principalTable: "file_assets",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_file_assets_sha256_size_bytes",
                table: "file_assets",
                columns: new[] { "sha256", "size_bytes" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_source_documents_contains_student_pii",
                table: "source_documents",
                column: "contains_student_pii");

            migrationBuilder.CreateIndex(
                name: "ix_source_documents_file_asset_id",
                table: "source_documents",
                column: "file_asset_id");

            migrationBuilder.CreateIndex(
                name: "ix_source_documents_owner_scope",
                table: "source_documents",
                column: "owner_scope");

            migrationBuilder.CreateIndex(
                name: "ix_source_documents_source_type",
                table: "source_documents",
                column: "source_type");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "source_documents");

            migrationBuilder.DropIndex(
                name: "ix_file_assets_sha256_size_bytes",
                table: "file_assets");
        }
    }
}
