using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPaperBlueprintReviewForS009B : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "paper_blueprint_reviews",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    request_text = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: false),
                    subject = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "physics"),
                    stage = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "junior_middle_school"),
                    grade = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    textbook_version = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: true),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "pending_review"),
                    blueprint = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'[]'::jsonb"),
                    constraints = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    review_questions = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'[]'::jsonb"),
                    teacher_confirmed_by = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: true),
                    teacher_confirmed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    confirmed_paper_basket_id = table.Column<Guid>(type: "uuid", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_paper_blueprint_reviews", x => x.id);
                    table.CheckConstraint("ck_paper_blueprint_reviews_status", "status in ('pending_review','confirmed','rejected')");
                    table.ForeignKey(
                        name: "fk_paper_blueprint_reviews_paper_baskets_confirmed_paper_baske",
                        column: x => x.confirmed_paper_basket_id,
                        principalTable: "paper_baskets",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_paper_blueprint_reviews_confirmed_paper_basket_id",
                table: "paper_blueprint_reviews",
                column: "confirmed_paper_basket_id");

            migrationBuilder.CreateIndex(
                name: "ix_paper_blueprint_reviews_subject_stage_status",
                table: "paper_blueprint_reviews",
                columns: new[] { "subject", "stage", "status" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "paper_blueprint_reviews");
        }
    }
}
