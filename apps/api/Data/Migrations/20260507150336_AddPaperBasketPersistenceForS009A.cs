using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPaperBasketPersistenceForS009A : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "paper_baskets",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    title = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    subject = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "physics"),
                    stage = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "junior_middle_school"),
                    grade = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "draft"),
                    knowledge_version_status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "active"),
                    knowledge_version = table.Column<int>(type: "integer", nullable: false, defaultValue: 1),
                    structure = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_paper_baskets", x => x.id);
                    table.CheckConstraint("ck_paper_baskets_knowledge_version", "knowledge_version >= 1");
                    table.CheckConstraint("ck_paper_baskets_status", "status in ('draft','ready','archived')");
                });

            migrationBuilder.CreateTable(
                name: "paper_basket_items",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    paper_basket_id = table.Column<Guid>(type: "uuid", nullable: false),
                    question_item_id = table.Column<Guid>(type: "uuid", nullable: false),
                    section_no = table.Column<int>(type: "integer", nullable: false),
                    question_no = table.Column<int>(type: "integer", nullable: false),
                    sub_question_no = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: true),
                    score = table.Column<decimal>(type: "numeric", nullable: false),
                    sort_order = table.Column<int>(type: "integer", nullable: false),
                    knowledge_version_status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "active"),
                    knowledge_version = table.Column<int>(type: "integer", nullable: false, defaultValue: 1),
                    snapshot = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_paper_basket_items", x => x.id);
                    table.CheckConstraint("ck_paper_basket_items_knowledge_version", "knowledge_version >= 1");
                    table.CheckConstraint("ck_paper_basket_items_question_no", "question_no >= 1");
                    table.CheckConstraint("ck_paper_basket_items_score", "score >= 0");
                    table.CheckConstraint("ck_paper_basket_items_section_no", "section_no >= 1");
                    table.CheckConstraint("ck_paper_basket_items_sort_order", "sort_order >= 0");
                    table.ForeignKey(
                        name: "fk_paper_basket_items_paper_baskets_paper_basket_id",
                        column: x => x.paper_basket_id,
                        principalTable: "paper_baskets",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_paper_basket_items_question_items_question_item_id",
                        column: x => x.question_item_id,
                        principalTable: "question_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_paper_basket_items_paper_basket_id_sort_order",
                table: "paper_basket_items",
                columns: new[] { "paper_basket_id", "sort_order" });

            migrationBuilder.CreateIndex(
                name: "ix_paper_basket_items_question_item_id",
                table: "paper_basket_items",
                column: "question_item_id");

            migrationBuilder.CreateIndex(
                name: "ix_paper_baskets_subject_stage_status",
                table: "paper_baskets",
                columns: new[] { "subject", "stage", "status" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "paper_basket_items");

            migrationBuilder.DropTable(
                name: "paper_baskets");
        }
    }
}
