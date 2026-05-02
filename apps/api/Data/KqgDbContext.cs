using K12QuestionGraph.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace K12QuestionGraph.Api.Data;

public sealed class KqgDbContext(DbContextOptions<KqgDbContext> options) : DbContext(options)
{
    public DbSet<TeacherPreference> TeacherPreferences => Set<TeacherPreference>();

    public DbSet<FileAsset> FileAssets => Set<FileAsset>();

    public DbSet<ImportJob> ImportJobs => Set<ImportJob>();

    public DbSet<AIJob> AIJobs => Set<AIJob>();

    public DbSet<ReviewQueueItem> ReviewQueueItems => Set<ReviewQueueItem>();

    public DbSet<BackupJob> BackupJobs => Set<BackupJob>();

    public DbSet<QuestionItem> QuestionItems => Set<QuestionItem>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasPostgresExtension("pgcrypto");

        ConfigureTeacherPreference(modelBuilder.Entity<TeacherPreference>());
        ConfigureFileAsset(modelBuilder.Entity<FileAsset>());
        ConfigureImportJob(modelBuilder.Entity<ImportJob>());
        ConfigureAIJob(modelBuilder.Entity<AIJob>());
        ConfigureReviewQueueItem(modelBuilder.Entity<ReviewQueueItem>());
        ConfigureBackupJob(modelBuilder.Entity<BackupJob>());
        ConfigureQuestionItem(modelBuilder.Entity<QuestionItem>());
    }

    private static void ConfigureTeacherPreference(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<TeacherPreference> entity)
    {
        entity.ToTable("teacher_preferences");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.TeacherKey, x.PreferenceKey }).IsUnique();
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.TeacherKey).HasMaxLength(128).IsRequired();
        entity.Property(x => x.PreferenceKey).HasMaxLength(128).IsRequired();
        entity.Property(x => x.PreferenceValue).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
    }

    private static void ConfigureFileAsset(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<FileAsset> entity)
    {
        entity.ToTable("file_assets");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => x.Sha256);
        entity.HasIndex(x => new { x.StorageScope, x.RelativePath }).IsUnique();
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.OriginalFileName).HasMaxLength(260).IsRequired();
        entity.Property(x => x.RelativePath).HasMaxLength(512).IsRequired();
        entity.Property(x => x.StorageScope).HasMaxLength(64).HasDefaultValue("original");
        entity.Property(x => x.ContentType).HasMaxLength(128).HasDefaultValue("application/octet-stream");
        entity.Property(x => x.Sha256).HasMaxLength(64).IsRequired();
        entity.Property(x => x.SourceMetadata).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
    }

    private static void ConfigureImportJob(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<ImportJob> entity)
    {
        entity.ToTable("import_jobs");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => x.Status);
        entity.HasIndex(x => x.IdempotencyKey).IsUnique();
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.Status).HasMaxLength(32).HasDefaultValue(JobStatuses.Queued);
        entity.Property(x => x.IdempotencyKey).HasMaxLength(160).IsRequired();
        entity.Property(x => x.LockedBy).HasMaxLength(128);
        entity.Property(x => x.LastErrorCode).HasMaxLength(64);
        entity.Property(x => x.LastErrorMessage).HasMaxLength(2048);
        entity.Property(x => x.Input).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.HasOne<FileAsset>().WithMany().HasForeignKey(x => x.InputFileAssetId).OnDelete(DeleteBehavior.Restrict);
        entity.ToTable(x => x.HasCheckConstraint("ck_import_jobs_status", "status in ('queued','running','succeeded','failed','cancelled','retry_waiting')"));
    }

    private static void ConfigureAIJob(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<AIJob> entity)
    {
        entity.ToTable("ai_jobs");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => x.Status);
        entity.HasIndex(x => x.IdempotencyKey).IsUnique();
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.JobType).HasMaxLength(64).IsRequired();
        entity.Property(x => x.Status).HasMaxLength(32).HasDefaultValue(JobStatuses.Queued);
        entity.Property(x => x.IdempotencyKey).HasMaxLength(160).IsRequired();
        entity.Property(x => x.ModelRoute).HasMaxLength(128);
        entity.Property(x => x.PromptVersion).HasMaxLength(64);
        entity.Property(x => x.SchemaVersion).HasMaxLength(64);
        entity.Property(x => x.Input).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.Property(x => x.Result).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.ToTable(x => x.HasCheckConstraint("ck_ai_jobs_status", "status in ('queued','running','succeeded','failed','cancelled','retry_waiting')"));
    }

    private static void ConfigureReviewQueueItem(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<ReviewQueueItem> entity)
    {
        entity.ToTable("review_queue_items");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => x.Status);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.ReviewType).HasMaxLength(64).IsRequired();
        entity.Property(x => x.Status).HasMaxLength(32).HasDefaultValue(ReviewStatuses.Open);
        entity.Property(x => x.Payload).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.ToTable(x => x.HasCheckConstraint("ck_review_queue_items_status", "status in ('open','resolved','dismissed')"));
    }

    private static void ConfigureBackupJob(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<BackupJob> entity)
    {
        entity.ToTable("backup_jobs");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => x.Status);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.Status).HasMaxLength(32).HasDefaultValue(BackupStatuses.Queued);
        entity.Property(x => x.ManifestPath).HasMaxLength(512);
        entity.Property(x => x.ManifestSha256).HasMaxLength(64);
        entity.Property(x => x.ErrorMessage).HasMaxLength(2048);
        entity.ToTable(x => x.HasCheckConstraint("ck_backup_jobs_status", "status in ('queued','running','succeeded','failed')"));
    }

    private static void ConfigureQuestionItem(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<QuestionItem> entity)
    {
        entity.ToTable("question_items");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.Subject, x.Stage, x.Status });
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.Subject).HasMaxLength(64).HasDefaultValue("physics");
        entity.Property(x => x.Stage).HasMaxLength(64).HasDefaultValue("junior_middle_school");
        entity.Property(x => x.Grade).HasMaxLength(64);
        entity.Property(x => x.QuestionType).HasMaxLength(64);
        entity.Property(x => x.Status).HasMaxLength(32).HasDefaultValue(QuestionStatuses.Draft);
        entity.Property(x => x.Blocks).HasColumnType("jsonb").HasDefaultValueSql("'[]'::jsonb");
        entity.Property(x => x.CustomFields).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.Property(x => x.QualitySignals).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.ToTable(x => x.HasCheckConstraint("ck_question_items_status", "status in ('draft','pending_review','usable','recommended','needs_improvement','paused','retired')"));
    }
}
