using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace K12QuestionGraph.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddDomainAssetVersioningForC002A : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "ck_knowledge_nodes_status",
                table: "knowledge_nodes");

            migrationBuilder.CreateTable(
                name: "domain_asset_versions",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    asset_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    stable_id = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    version = table.Column<int>(type: "integer", nullable: false),
                    display_name = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "draft"),
                    authority = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "bootstrap"),
                    effective_scope = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    source_evidence = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    metadata = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_domain_asset_versions", x => x.id);
                    table.CheckConstraint("ck_domain_asset_versions_authority", "authority in ('bootstrap','source_derived','school_approved','policy')");
                    table.CheckConstraint("ck_domain_asset_versions_status", "status in ('draft','candidate','reviewed','active','deprecated','merged','superseded')");
                    table.CheckConstraint("ck_domain_asset_versions_version", "version >= 1");
                });

            migrationBuilder.CreateTable(
                name: "domain_asset_migrations",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    migration_key = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    status = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "draft"),
                    from_asset_version_id = table.Column<Guid>(type: "uuid", nullable: true),
                    to_asset_version_id = table.Column<Guid>(type: "uuid", nullable: true),
                    impact_report = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    rollback_snapshot = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    created_by = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false, defaultValue: "system"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    applied_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    rolled_back_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_domain_asset_migrations", x => x.id);
                    table.CheckConstraint("ck_domain_asset_migrations_not_self", "from_asset_version_id is null or to_asset_version_id is null or from_asset_version_id <> to_asset_version_id");
                    table.CheckConstraint("ck_domain_asset_migrations_status", "status in ('draft','dry_run','pending_review','applied','rolled_back','rejected')");
                    table.ForeignKey(
                        name: "fk_domain_asset_migrations_domain_asset_versions_from_asset_ve",
                        column: x => x.from_asset_version_id,
                        principalTable: "domain_asset_versions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_domain_asset_migrations_domain_asset_versions_to_asset_vers",
                        column: x => x.to_asset_version_id,
                        principalTable: "domain_asset_versions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "domain_asset_mappings",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    source_asset_version_id = table.Column<Guid>(type: "uuid", nullable: false),
                    target_asset_version_id = table.Column<Guid>(type: "uuid", nullable: false),
                    mapping_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "equivalent"),
                    confidence = table.Column<decimal>(type: "numeric", nullable: false),
                    review_status = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false, defaultValue: "pending_review"),
                    auto_applied = table.Column<bool>(type: "boolean", nullable: false),
                    evidence = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    migration_id = table.Column<Guid>(type: "uuid", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    reviewed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_domain_asset_mappings", x => x.id);
                    table.CheckConstraint("ck_domain_asset_mappings_auto_review", "(auto_applied = false) or (review_status = 'auto_applied')");
                    table.CheckConstraint("ck_domain_asset_mappings_confidence", "confidence >= 0 and confidence <= 1");
                    table.CheckConstraint("ck_domain_asset_mappings_not_self", "source_asset_version_id <> target_asset_version_id");
                    table.CheckConstraint("ck_domain_asset_mappings_review_status", "review_status in ('auto_applied','pending_review','approved','rejected')");
                    table.CheckConstraint("ck_domain_asset_mappings_type", "mapping_type in ('equivalent','split','merge','broader','narrower','renamed','deprecated')");
                    table.ForeignKey(
                        name: "fk_domain_asset_mappings_domain_asset_migrations_migration_id",
                        column: x => x.migration_id,
                        principalTable: "domain_asset_migrations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "fk_domain_asset_mappings_domain_asset_versions_source_asset_ve",
                        column: x => x.source_asset_version_id,
                        principalTable: "domain_asset_versions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_domain_asset_mappings_domain_asset_versions_target_asset_ve",
                        column: x => x.target_asset_version_id,
                        principalTable: "domain_asset_versions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.AddCheckConstraint(
                name: "ck_knowledge_nodes_status",
                table: "knowledge_nodes",
                sql: "status in ('draft','candidate','reviewed','active','deprecated','merged','superseded')");

            migrationBuilder.CreateIndex(
                name: "ix_domain_asset_mappings_migration_id",
                table: "domain_asset_mappings",
                column: "migration_id");

            migrationBuilder.CreateIndex(
                name: "ix_domain_asset_mappings_review_status",
                table: "domain_asset_mappings",
                column: "review_status");

            migrationBuilder.CreateIndex(
                name: "ix_domain_asset_mappings_source_asset_version_id_target_asset_",
                table: "domain_asset_mappings",
                columns: new[] { "source_asset_version_id", "target_asset_version_id", "mapping_type" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_domain_asset_mappings_target_asset_version_id",
                table: "domain_asset_mappings",
                column: "target_asset_version_id");

            migrationBuilder.CreateIndex(
                name: "ix_domain_asset_migrations_from_asset_version_id",
                table: "domain_asset_migrations",
                column: "from_asset_version_id");

            migrationBuilder.CreateIndex(
                name: "ix_domain_asset_migrations_migration_key",
                table: "domain_asset_migrations",
                column: "migration_key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_domain_asset_migrations_status",
                table: "domain_asset_migrations",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "ix_domain_asset_migrations_to_asset_version_id",
                table: "domain_asset_migrations",
                column: "to_asset_version_id");

            migrationBuilder.CreateIndex(
                name: "ix_domain_asset_versions_asset_type_stable_id_version",
                table: "domain_asset_versions",
                columns: new[] { "asset_type", "stable_id", "version" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_domain_asset_versions_asset_type_status",
                table: "domain_asset_versions",
                columns: new[] { "asset_type", "status" });

            migrationBuilder.CreateIndex(
                name: "ix_domain_asset_versions_authority",
                table: "domain_asset_versions",
                column: "authority");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "domain_asset_mappings");

            migrationBuilder.DropTable(
                name: "domain_asset_migrations");

            migrationBuilder.DropTable(
                name: "domain_asset_versions");

            migrationBuilder.DropCheckConstraint(
                name: "ck_knowledge_nodes_status",
                table: "knowledge_nodes");

            migrationBuilder.AddCheckConstraint(
                name: "ck_knowledge_nodes_status",
                table: "knowledge_nodes",
                sql: "status in ('draft','active','deprecated','retired')");
        }
    }
}
