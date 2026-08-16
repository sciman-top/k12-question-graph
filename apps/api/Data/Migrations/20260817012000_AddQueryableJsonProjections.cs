using K12QuestionGraph.Api.Data;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations;

[DbContext(typeof(KqgDbContext))]
[Migration("20260817012000_AddQueryableJsonProjections")]
public partial class AddQueryableJsonProjections : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<int>(
            name: "question_no",
            table: "question_items",
            type: "integer",
            nullable: true,
            computedColumnSql: "CASE WHEN custom_fields ->> 'questionNo' ~ '^-?[0-9]+$' AND length(custom_fields ->> 'questionNo') <= 11 THEN CASE WHEN (custom_fields ->> 'questionNo')::bigint BETWEEN -2147483648 AND 2147483647 THEN (custom_fields ->> 'questionNo')::integer ELSE NULL END ELSE NULL END",
            stored: true);

        migrationBuilder.AddColumn<Guid>(
            name: "question_item_id",
            table: "review_queue_items",
            type: "uuid",
            nullable: true,
            computedColumnSql: "CASE WHEN payload ->> 'questionItemId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN (payload ->> 'questionItemId')::uuid ELSE NULL END",
            stored: true);

        migrationBuilder.AddColumn<Guid>(
            name: "source_document_id",
            table: "review_queue_items",
            type: "uuid",
            nullable: true,
            computedColumnSql: "CASE WHEN payload ->> 'sourceDocumentId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN (payload ->> 'sourceDocumentId')::uuid ELSE NULL END",
            stored: true);

        migrationBuilder.CreateIndex(
            name: "ix_question_items_question_no",
            table: "question_items",
            column: "question_no");

        migrationBuilder.CreateIndex(
            name: "ix_review_queue_items_question_item_id",
            table: "review_queue_items",
            column: "question_item_id");

        migrationBuilder.CreateIndex(
            name: "ix_review_queue_items_source_document_id",
            table: "review_queue_items",
            column: "source_document_id");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(
            name: "ix_question_items_question_no",
            table: "question_items");

        migrationBuilder.DropIndex(
            name: "ix_review_queue_items_question_item_id",
            table: "review_queue_items");

        migrationBuilder.DropIndex(
            name: "ix_review_queue_items_source_document_id",
            table: "review_queue_items");

        migrationBuilder.DropColumn(
            name: "question_no",
            table: "question_items");

        migrationBuilder.DropColumn(
            name: "question_item_id",
            table: "review_queue_items");

        migrationBuilder.DropColumn(
            name: "source_document_id",
            table: "review_queue_items");
    }
}
