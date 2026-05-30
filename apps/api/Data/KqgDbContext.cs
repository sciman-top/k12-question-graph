using K12QuestionGraph.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace K12QuestionGraph.Api.Data;

public sealed class KqgDbContext(DbContextOptions<KqgDbContext> options) : DbContext(options)
{
    public DbSet<TeacherPreference> TeacherPreferences => Set<TeacherPreference>();

    public DbSet<FileAsset> FileAssets => Set<FileAsset>();

    public DbSet<SourceDocument> SourceDocuments => Set<SourceDocument>();

    public DbSet<SourceRegion> SourceRegions => Set<SourceRegion>();

    public DbSet<Student> Students => Set<Student>();

    public DbSet<ClassGroup> ClassGroups => Set<ClassGroup>();

    public DbSet<Assessment> Assessments => Set<Assessment>();

    public DbSet<AssessmentEnrollment> AssessmentEnrollments => Set<AssessmentEnrollment>();

    public DbSet<ScoreImportTemplate> ScoreImportTemplates => Set<ScoreImportTemplate>();

    public DbSet<ScoreImportBatch> ScoreImportBatches => Set<ScoreImportBatch>();

    public DbSet<ScoreRecord> ScoreRecords => Set<ScoreRecord>();

    public DbSet<ItemScore> ItemScores => Set<ItemScore>();

    public DbSet<ImportJob> ImportJobs => Set<ImportJob>();

    public DbSet<AIJob> AIJobs => Set<AIJob>();

    public DbSet<FeedbackEvent> FeedbackEvents => Set<FeedbackEvent>();

    public DbSet<ReviewQueueItem> ReviewQueueItems => Set<ReviewQueueItem>();

    public DbSet<BackupJob> BackupJobs => Set<BackupJob>();

    public DbSet<QuestionItem> QuestionItems => Set<QuestionItem>();

    public DbSet<KnowledgeNode> KnowledgeNodes => Set<KnowledgeNode>();

    public DbSet<KnowledgeEdge> KnowledgeEdges => Set<KnowledgeEdge>();

    public DbSet<KnowledgeMapping> KnowledgeMappings => Set<KnowledgeMapping>();

    public DbSet<DomainAssetVersion> DomainAssetVersions => Set<DomainAssetVersion>();

    public DbSet<DomainAssetMapping> DomainAssetMappings => Set<DomainAssetMapping>();

    public DbSet<DomainAssetMigration> DomainAssetMigrations => Set<DomainAssetMigration>();

    public DbSet<QuestionBlock> QuestionBlocks => Set<QuestionBlock>();

    public DbSet<QuestionAsset> QuestionAssets => Set<QuestionAsset>();

    public DbSet<PaperBasket> PaperBaskets => Set<PaperBasket>();

    public DbSet<PaperBasketItem> PaperBasketItems => Set<PaperBasketItem>();

    public DbSet<PaperBlueprintReview> PaperBlueprintReviews => Set<PaperBlueprintReview>();

    public DbSet<CutCandidate> CutCandidates => Set<CutCandidate>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasPostgresExtension("pgcrypto");

        ConfigureTeacherPreference(modelBuilder.Entity<TeacherPreference>());
        ConfigureFileAsset(modelBuilder.Entity<FileAsset>());
        ConfigureSourceDocument(modelBuilder.Entity<SourceDocument>());
        ConfigureSourceRegion(modelBuilder.Entity<SourceRegion>());
        ConfigureStudent(modelBuilder.Entity<Student>());
        ConfigureClassGroup(modelBuilder.Entity<ClassGroup>());
        ConfigureAssessment(modelBuilder.Entity<Assessment>());
        ConfigureAssessmentEnrollment(modelBuilder.Entity<AssessmentEnrollment>());
        ConfigureScoreImportTemplate(modelBuilder.Entity<ScoreImportTemplate>());
        ConfigureScoreImportBatch(modelBuilder.Entity<ScoreImportBatch>());
        ConfigureScoreRecord(modelBuilder.Entity<ScoreRecord>());
        ConfigureItemScore(modelBuilder.Entity<ItemScore>());
        ConfigureImportJob(modelBuilder.Entity<ImportJob>());
        ConfigureAIJob(modelBuilder.Entity<AIJob>());
        ConfigureFeedbackEvent(modelBuilder.Entity<FeedbackEvent>());
        ConfigureReviewQueueItem(modelBuilder.Entity<ReviewQueueItem>());
        ConfigureBackupJob(modelBuilder.Entity<BackupJob>());
        ConfigureQuestionItem(modelBuilder.Entity<QuestionItem>());
        ConfigureKnowledgeNode(modelBuilder.Entity<KnowledgeNode>());
        ConfigureKnowledgeEdge(modelBuilder.Entity<KnowledgeEdge>());
        ConfigureKnowledgeMapping(modelBuilder.Entity<KnowledgeMapping>());
        ConfigureDomainAssetVersion(modelBuilder.Entity<DomainAssetVersion>());
        ConfigureDomainAssetMapping(modelBuilder.Entity<DomainAssetMapping>());
        ConfigureDomainAssetMigration(modelBuilder.Entity<DomainAssetMigration>());
        ConfigureQuestionBlock(modelBuilder.Entity<QuestionBlock>());
        ConfigureQuestionAsset(modelBuilder.Entity<QuestionAsset>());
        ConfigurePaperBasket(modelBuilder.Entity<PaperBasket>());
        ConfigurePaperBasketItem(modelBuilder.Entity<PaperBasketItem>());
        ConfigurePaperBlueprintReview(modelBuilder.Entity<PaperBlueprintReview>());
        ConfigureCutCandidate(modelBuilder.Entity<CutCandidate>());
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
        entity.HasIndex(x => new { x.Sha256, x.SizeBytes }).IsUnique();
        entity.HasIndex(x => new { x.StorageScope, x.RelativePath }).IsUnique();
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.OriginalFileName).HasMaxLength(260).IsRequired();
        entity.Property(x => x.RelativePath).HasMaxLength(512).IsRequired();
        entity.Property(x => x.StorageScope).HasMaxLength(64).HasDefaultValue("original");
        entity.Property(x => x.ContentType).HasMaxLength(128).HasDefaultValue("application/octet-stream");
        entity.Property(x => x.Sha256).HasMaxLength(64).IsRequired();
        entity.Property(x => x.SourceMetadata).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
    }

    private static void ConfigureSourceDocument(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<SourceDocument> entity)
    {
        entity.ToTable("source_documents");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => x.FileAssetId);
        entity.HasIndex(x => x.SourceType);
        entity.HasIndex(x => new { x.SourceType, x.Region, x.Year });
        entity.HasIndex(x => x.OwnerScope);
        entity.HasIndex(x => x.ContainsStudentPii);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.SourceType).HasMaxLength(64).HasDefaultValue("unknown");
        entity.Property(x => x.SourceTitle).HasMaxLength(260).HasDefaultValue(string.Empty);
        entity.Property(x => x.Region).HasMaxLength(128).HasDefaultValue(string.Empty);
        entity.Property(x => x.GradeOrScope).HasMaxLength(128).HasDefaultValue(string.Empty);
        entity.Property(x => x.EditionOrVersion).HasMaxLength(128).HasDefaultValue(string.Empty);
        entity.Property(x => x.MaterialBatchKey).HasMaxLength(160).HasDefaultValue(string.Empty);
        entity.Property(x => x.OwnerScope).HasMaxLength(64).HasDefaultValue("teacher_private");
        entity.Property(x => x.LicenseOrPermission).HasMaxLength(256).HasDefaultValue("unknown");
        entity.Property(x => x.AnonymizationStatus).HasMaxLength(64).HasDefaultValue("not_applicable");
        entity.HasOne<FileAsset>().WithMany().HasForeignKey(x => x.FileAssetId).OnDelete(DeleteBehavior.Restrict);
        entity.ToTable(x => x.HasCheckConstraint("ck_source_documents_anonymization_status", "anonymization_status in ('none','anonymized','synthetic','not_applicable')"));
    }

    private static void ConfigureSourceRegion(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<SourceRegion> entity)
    {
        entity.ToTable("source_regions");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.SourceDocumentId, x.PageNumber });
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.CoordinateUnit).HasMaxLength(32).HasDefaultValue("percent");
        entity.Property(x => x.ScreenshotRelativePath).HasMaxLength(512);
        entity.Property(x => x.RegionType).HasMaxLength(64).HasDefaultValue("preview");
        entity.HasOne<SourceDocument>().WithMany().HasForeignKey(x => x.SourceDocumentId).OnDelete(DeleteBehavior.Cascade);
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_source_regions_page_number", "page_number >= 1");
            x.HasCheckConstraint("ck_source_regions_bbox", "x >= 0 and y >= 0 and width > 0 and height > 0");
            x.HasCheckConstraint("ck_source_regions_coordinate_unit", "coordinate_unit in ('pixel','point','percent')");
        });
    }

    private static void ConfigureStudent(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<Student> entity)
    {
        entity.ToTable("students");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => x.StudentKey).IsUnique();
        entity.HasIndex(x => new { x.Stage, x.Grade });
        entity.HasIndex(x => x.ContainsStudentPii);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.StudentKey).HasMaxLength(160).IsRequired();
        entity.Property(x => x.DisplayCode).HasMaxLength(128).HasDefaultValue(string.Empty);
        entity.Property(x => x.Stage).HasMaxLength(64).HasDefaultValue("junior_middle_school");
        entity.Property(x => x.Grade).HasMaxLength(64).HasDefaultValue(string.Empty);
        entity.Property(x => x.AnonymizationStatus).HasMaxLength(64).HasDefaultValue("synthetic");
        entity.Property(x => x.Metadata).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_students_anonymization_status", "anonymization_status in ('none','anonymized','synthetic')");
            x.HasCheckConstraint("ck_students_pii_guard", "(contains_student_pii = false) or (anonymization_status in ('anonymized','synthetic'))");
            x.HasCheckConstraint("ck_students_no_portal_for_synthetic", "(synthetic_fixture = false) or (student_portal_enabled = false)");
        });
    }

    private static void ConfigureClassGroup(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<ClassGroup> entity)
    {
        entity.ToTable("class_groups");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => x.ClassKey).IsUnique();
        entity.HasIndex(x => new { x.Stage, x.Grade, x.SchoolYear });
        entity.HasIndex(x => x.ContainsStudentPii);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.ClassKey).HasMaxLength(160).IsRequired();
        entity.Property(x => x.DisplayName).HasMaxLength(160).HasDefaultValue(string.Empty);
        entity.Property(x => x.Stage).HasMaxLength(64).HasDefaultValue("junior_middle_school");
        entity.Property(x => x.Grade).HasMaxLength(64).HasDefaultValue(string.Empty);
        entity.Property(x => x.SchoolYear).HasMaxLength(32).HasDefaultValue(string.Empty);
        entity.Property(x => x.AnonymizationStatus).HasMaxLength(64).HasDefaultValue("synthetic");
        entity.Property(x => x.Metadata).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_class_groups_anonymization_status", "anonymization_status in ('none','anonymized','synthetic')");
            x.HasCheckConstraint("ck_class_groups_pii_guard", "(contains_student_pii = false) or (anonymization_status in ('anonymized','synthetic'))");
        });
    }

    private static void ConfigureAssessment(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<Assessment> entity)
    {
        entity.ToTable("assessments");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => x.AssessmentKey).IsUnique();
        entity.HasIndex(x => new { x.Subject, x.Stage, x.Status });
        entity.HasIndex(x => x.ContainsStudentPii);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.AssessmentKey).HasMaxLength(160).IsRequired();
        entity.Property(x => x.Title).HasMaxLength(256).IsRequired();
        entity.Property(x => x.Subject).HasMaxLength(64).HasDefaultValue("physics");
        entity.Property(x => x.Stage).HasMaxLength(64).HasDefaultValue("junior_middle_school");
        entity.Property(x => x.Grade).HasMaxLength(64).HasDefaultValue(string.Empty);
        entity.Property(x => x.Status).HasMaxLength(32).HasDefaultValue(AssessmentStatuses.Draft);
        entity.Property(x => x.Mode).HasMaxLength(32).HasDefaultValue("draft_test");
        entity.Property(x => x.AnonymizationStatus).HasMaxLength(64).HasDefaultValue("synthetic");
        entity.Property(x => x.Blueprint).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.Property(x => x.Metadata).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_assessments_status", "status in ('draft','pending_review','ready','archived')");
            x.HasCheckConstraint("ck_assessments_mode", "mode in ('draft_test','production')");
            x.HasCheckConstraint("ck_assessments_anonymization_status", "anonymization_status in ('none','anonymized','synthetic')");
            x.HasCheckConstraint("ck_assessments_production_guard", "(production_eligible = false and mode = 'draft_test') or (production_eligible = true and mode = 'production')");
            x.HasCheckConstraint("ck_assessments_no_portal_for_draft", "(mode <> 'draft_test') or (student_portal_enabled = false)");
        });
    }

    private static void ConfigureAssessmentEnrollment(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<AssessmentEnrollment> entity)
    {
        entity.ToTable("assessment_enrollments");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.AssessmentId, x.StudentId }).IsUnique();
        entity.HasIndex(x => x.ClassGroupId);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.SeatNo).HasMaxLength(32).HasDefaultValue(string.Empty);
        entity.Property(x => x.Status).HasMaxLength(32).HasDefaultValue("enrolled");
        entity.Property(x => x.ScoreSummary).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.HasOne<Assessment>().WithMany().HasForeignKey(x => x.AssessmentId).OnDelete(DeleteBehavior.Cascade);
        entity.HasOne<ClassGroup>().WithMany().HasForeignKey(x => x.ClassGroupId).OnDelete(DeleteBehavior.Restrict);
        entity.HasOne<Student>().WithMany().HasForeignKey(x => x.StudentId).OnDelete(DeleteBehavior.Restrict);
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_assessment_enrollments_status", "status in ('enrolled','excluded','absent')");
            x.HasCheckConstraint("ck_assessment_enrollments_pii_guard", "contains_student_pii = false");
        });
    }

    private static void ConfigureScoreImportTemplate(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<ScoreImportTemplate> entity)
    {
        entity.ToTable("score_import_templates");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.TemplateKey, x.Version }).IsUnique();
        entity.HasIndex(x => x.ReviewStatus);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.TemplateKey).HasMaxLength(160).IsRequired();
        entity.Property(x => x.DisplayName).HasMaxLength(256).IsRequired();
        entity.Property(x => x.Mode).HasMaxLength(32).HasDefaultValue("draft_test");
        entity.Property(x => x.ReviewStatus).HasMaxLength(64).HasDefaultValue(DomainAssetReviewStatuses.PendingReview);
        entity.Property(x => x.FieldMapping).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.Property(x => x.MigrationPolicy).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_score_import_templates_version", "version >= 1");
            x.HasCheckConstraint("ck_score_import_templates_mode", "mode in ('draft_test','production')");
            x.HasCheckConstraint("ck_score_import_templates_review_status", "review_status in ('auto_applied','pending_review','approved','rejected')");
            x.HasCheckConstraint("ck_score_import_templates_production_guard", "(production_eligible = false and mode = 'draft_test') or (production_eligible = true and mode = 'production')");
        });
    }

    private static void ConfigureScoreImportBatch(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<ScoreImportBatch> entity)
    {
        entity.ToTable("score_import_batches");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.AssessmentId, x.Status });
        entity.HasIndex(x => x.TemplateId);
        entity.HasIndex(x => x.ContainsStudentPii);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.Mode).HasMaxLength(32).HasDefaultValue("draft_test");
        entity.Property(x => x.Status).HasMaxLength(32).HasDefaultValue(ScoreImportStatuses.Draft);
        entity.Property(x => x.SourceFileName).HasMaxLength(260).HasDefaultValue(string.Empty);
        entity.Property(x => x.ErrorSummary).HasColumnType("jsonb").HasDefaultValueSql("'[]'::jsonb");
        entity.Property(x => x.Metadata).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.HasOne<Assessment>().WithMany().HasForeignKey(x => x.AssessmentId).OnDelete(DeleteBehavior.Cascade);
        entity.HasOne<ScoreImportTemplate>().WithMany().HasForeignKey(x => x.TemplateId).OnDelete(DeleteBehavior.Restrict);
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_score_import_batches_mode", "mode in ('draft_test','production')");
            x.HasCheckConstraint("ck_score_import_batches_status", "status in ('draft','imported','failed','archived')");
            x.HasCheckConstraint("ck_score_import_batches_counts", "row_count >= 0 and imported_count >= 0 and error_count >= 0 and row_count >= imported_count and row_count >= error_count");
            x.HasCheckConstraint("ck_score_import_batches_pii_guard", "contains_student_pii = false");
            x.HasCheckConstraint("ck_score_import_batches_production_guard", "(production_eligible = false and mode = 'draft_test') or (production_eligible = true and mode = 'production')");
        });
    }

    private static void ConfigureScoreRecord(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<ScoreRecord> entity)
    {
        entity.ToTable("score_records");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.AssessmentId, x.StudentId }).IsUnique();
        entity.HasIndex(x => x.ImportBatchId);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.StudentKey).HasMaxLength(160).IsRequired();
        entity.Property(x => x.Status).HasMaxLength(32).HasDefaultValue("imported");
        entity.Property(x => x.RawRow).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.HasOne<Assessment>().WithMany().HasForeignKey(x => x.AssessmentId).OnDelete(DeleteBehavior.Cascade);
        entity.HasOne<Student>().WithMany().HasForeignKey(x => x.StudentId).OnDelete(DeleteBehavior.Restrict);
        entity.HasOne<ScoreImportBatch>().WithMany().HasForeignKey(x => x.ImportBatchId).OnDelete(DeleteBehavior.Cascade);
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_score_records_status", "status in ('imported','excluded','invalid')");
            x.HasCheckConstraint("ck_score_records_scores", "(total_score is null or total_score >= 0) and (max_score is null or max_score >= 0) and (total_score is null or max_score is null or total_score <= max_score)");
            x.HasCheckConstraint("ck_score_records_pii_guard", "contains_student_pii = false");
        });
    }

    private static void ConfigureItemScore(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<ItemScore> entity)
    {
        entity.ToTable("item_scores");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.ScoreRecordId, x.QuestionNo }).IsUnique();
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.QuestionNo).HasMaxLength(64).IsRequired();
        entity.Property(x => x.FieldName).HasMaxLength(128).IsRequired();
        entity.Property(x => x.Metadata).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.HasOne<ScoreRecord>().WithMany().HasForeignKey(x => x.ScoreRecordId).OnDelete(DeleteBehavior.Cascade);
        entity.ToTable(x => x.HasCheckConstraint("ck_item_scores_scores", "score >= 0 and max_score >= 0 and score <= max_score"));
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
        entity.Property(x => x.ModelProvider).HasMaxLength(64);
        entity.Property(x => x.ModelName).HasMaxLength(128);
        entity.Property(x => x.RoutingVersion).HasMaxLength(64);
        entity.Property(x => x.PromptVersion).HasMaxLength(64);
        entity.Property(x => x.SchemaVersion).HasMaxLength(64);
        entity.Property(x => x.InputHash).HasMaxLength(128);
        entity.Property(x => x.ReviewStatus).HasMaxLength(32).HasDefaultValue(ReviewStatuses.Open);
        entity.Property(x => x.Input).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.Property(x => x.Result).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_ai_jobs_status", "status in ('queued','running','succeeded','failed','cancelled','retry_waiting')");
            x.HasCheckConstraint("ck_ai_jobs_confidence", "confidence is null or (confidence >= 0 and confidence <= 1)");
            x.HasCheckConstraint("ck_ai_jobs_costs", "(estimated_cost is null or estimated_cost >= 0) and (actual_cost is null or actual_cost >= 0)");
            x.HasCheckConstraint("ck_ai_jobs_tokens", "(input_tokens is null or input_tokens >= 0) and (output_tokens is null or output_tokens >= 0) and (cached_tokens is null or cached_tokens >= 0)");
            x.HasCheckConstraint("ck_ai_jobs_review_status", "review_status in ('open','resolved','dismissed','pending_review')");
        });
    }

    private static void ConfigureFeedbackEvent(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<FeedbackEvent> entity)
    {
        entity.ToTable("feedback_events");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => x.TaskType);
        entity.HasIndex(x => x.AcceptedForEval);
        entity.HasIndex(x => x.CreatedAt);
        entity.HasIndex(x => x.AIJobId);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.TaskType).HasMaxLength(64).IsRequired();
        entity.Property(x => x.EntityType).HasMaxLength(64).IsRequired();
        entity.Property(x => x.FieldKey).HasMaxLength(128).IsRequired();
        entity.Property(x => x.BeforeValue).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.Property(x => x.AfterValue).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.Property(x => x.ReasonTag).HasMaxLength(128);
        entity.Property(x => x.TeacherId).HasMaxLength(128).IsRequired();
        entity.Property(x => x.PromptVersion).HasMaxLength(64);
        entity.Property(x => x.SchemaVersion).HasMaxLength(64);
        entity.Property(x => x.Model).HasMaxLength(128);
        entity.Property(x => x.Metadata).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.HasOne<AIJob>().WithMany().HasForeignKey(x => x.AIJobId).OnDelete(DeleteBehavior.SetNull);
        entity.ToTable(x => x.HasCheckConstraint("ck_feedback_events_ai_confidence", "ai_confidence is null or (ai_confidence >= 0 and ai_confidence <= 1)"));
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
        entity.HasOne<KnowledgeNode>().WithMany().HasForeignKey(x => x.PrimaryKnowledgeId).OnDelete(DeleteBehavior.SetNull);
        entity.ToTable(x => x.HasCheckConstraint("ck_question_items_status", "status in ('draft','pending_review','usable','recommended','needs_improvement','paused','retired')"));
    }

    private static void ConfigureKnowledgeNode(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<KnowledgeNode> entity)
    {
        entity.ToTable("knowledge_nodes");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.Subject, x.Stage, x.Code, x.Version }).IsUnique();
        entity.HasIndex(x => new { x.Subject, x.Stage, x.Level });
        entity.HasIndex(x => x.ParentId);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.Subject).HasMaxLength(64).HasDefaultValue("physics");
        entity.Property(x => x.Stage).HasMaxLength(64).HasDefaultValue("junior_middle_school");
        entity.Property(x => x.Code).HasMaxLength(128).IsRequired();
        entity.Property(x => x.Title).HasMaxLength(256).IsRequired();
        entity.Property(x => x.NodeType).HasMaxLength(64).HasDefaultValue("concept");
        entity.Property(x => x.Status).HasMaxLength(32).HasDefaultValue(KnowledgeStatuses.Draft);
        entity.Property(x => x.Metadata).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.HasOne<KnowledgeNode>().WithMany().HasForeignKey(x => x.ParentId).OnDelete(DeleteBehavior.Restrict);
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_knowledge_nodes_level", "level >= 1");
            x.HasCheckConstraint("ck_knowledge_nodes_version", "version >= 1");
            x.HasCheckConstraint("ck_knowledge_nodes_status", "status in ('draft','candidate','reviewed','active','deprecated','merged','superseded')");
        });
    }

    private static void ConfigureKnowledgeEdge(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<KnowledgeEdge> entity)
    {
        entity.ToTable("knowledge_edges");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.SourceNodeId, x.TargetNodeId, x.EdgeType, x.Version }).IsUnique();
        entity.HasIndex(x => x.TargetNodeId);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.EdgeType).HasMaxLength(64).HasDefaultValue(KnowledgeEdgeTypes.ParentChild);
        entity.Property(x => x.Metadata).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.HasOne<KnowledgeNode>().WithMany().HasForeignKey(x => x.SourceNodeId).OnDelete(DeleteBehavior.Restrict);
        entity.HasOne<KnowledgeNode>().WithMany().HasForeignKey(x => x.TargetNodeId).OnDelete(DeleteBehavior.Restrict);
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_knowledge_edges_not_self", "source_node_id <> target_node_id");
            x.HasCheckConstraint("ck_knowledge_edges_version", "version >= 1");
            x.HasCheckConstraint("ck_knowledge_edges_type", "edge_type in ('parent_child','prerequisite','related')");
        });
    }

    private static void ConfigureKnowledgeMapping(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<KnowledgeMapping> entity)
    {
        entity.ToTable("knowledge_mappings");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.QuestionItemId, x.KnowledgeNodeId, x.Version }).IsUnique();
        entity.HasIndex(x => x.KnowledgeNodeId);
        entity.HasIndex(x => x.MappingSource);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.MappingSource).HasMaxLength(64).HasDefaultValue(KnowledgeMappingSources.Manual);
        entity.Property(x => x.Evidence).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.HasOne<QuestionItem>().WithMany().HasForeignKey(x => x.QuestionItemId).OnDelete(DeleteBehavior.Cascade);
        entity.HasOne<KnowledgeNode>().WithMany().HasForeignKey(x => x.KnowledgeNodeId).OnDelete(DeleteBehavior.Restrict);
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_knowledge_mappings_confidence", "confidence is null or (confidence >= 0 and confidence <= 1)");
            x.HasCheckConstraint("ck_knowledge_mappings_version", "version >= 1");
            x.HasCheckConstraint("ck_knowledge_mappings_source", "mapping_source in ('manual','import','ai_suggested')");
        });
    }

    private static void ConfigureDomainAssetVersion(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<DomainAssetVersion> entity)
    {
        entity.ToTable("domain_asset_versions");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.AssetType, x.StableId, x.Version }).IsUnique();
        entity.HasIndex(x => new { x.AssetType, x.Status });
        entity.HasIndex(x => x.Authority);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.AssetType).HasMaxLength(64).IsRequired();
        entity.Property(x => x.StableId).HasMaxLength(160).IsRequired();
        entity.Property(x => x.DisplayName).HasMaxLength(256).IsRequired();
        entity.Property(x => x.Status).HasMaxLength(32).HasDefaultValue(DomainAssetStatuses.Draft);
        entity.Property(x => x.Authority).HasMaxLength(64).HasDefaultValue(DomainAssetAuthorities.Bootstrap);
        entity.Property(x => x.EffectiveScope).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.Property(x => x.SourceEvidence).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.Property(x => x.Metadata).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_domain_asset_versions_version", "version >= 1");
            x.HasCheckConstraint("ck_domain_asset_versions_status", "status in ('draft','candidate','reviewed','active','deprecated','merged','superseded')");
            x.HasCheckConstraint("ck_domain_asset_versions_authority", "authority in ('bootstrap','source_derived','school_approved','policy')");
        });
    }

    private static void ConfigureDomainAssetMapping(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<DomainAssetMapping> entity)
    {
        entity.ToTable("domain_asset_mappings");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.SourceAssetVersionId, x.TargetAssetVersionId, x.MappingType }).IsUnique();
        entity.HasIndex(x => x.TargetAssetVersionId);
        entity.HasIndex(x => x.ReviewStatus);
        entity.HasIndex(x => x.MigrationId);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.MappingType).HasMaxLength(64).HasDefaultValue(DomainAssetMappingTypes.Equivalent);
        entity.Property(x => x.ReviewStatus).HasMaxLength(64).HasDefaultValue(DomainAssetReviewStatuses.PendingReview);
        entity.Property(x => x.Evidence).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.HasOne<DomainAssetVersion>().WithMany().HasForeignKey(x => x.SourceAssetVersionId).OnDelete(DeleteBehavior.Restrict);
        entity.HasOne<DomainAssetVersion>().WithMany().HasForeignKey(x => x.TargetAssetVersionId).OnDelete(DeleteBehavior.Restrict);
        entity.HasOne<DomainAssetMigration>().WithMany().HasForeignKey(x => x.MigrationId).OnDelete(DeleteBehavior.SetNull);
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_domain_asset_mappings_not_self", "source_asset_version_id <> target_asset_version_id");
            x.HasCheckConstraint("ck_domain_asset_mappings_confidence", "confidence >= 0 and confidence <= 1");
            x.HasCheckConstraint("ck_domain_asset_mappings_type", "mapping_type in ('equivalent','split','merge','broader','narrower','renamed','deprecated')");
            x.HasCheckConstraint("ck_domain_asset_mappings_review_status", "review_status in ('auto_applied','pending_review','approved','rejected')");
            x.HasCheckConstraint("ck_domain_asset_mappings_auto_review", "(auto_applied = false) or (review_status = 'auto_applied')");
        });
    }

    private static void ConfigureDomainAssetMigration(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<DomainAssetMigration> entity)
    {
        entity.ToTable("domain_asset_migrations");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => x.MigrationKey).IsUnique();
        entity.HasIndex(x => x.Status);
        entity.HasIndex(x => x.FromAssetVersionId);
        entity.HasIndex(x => x.ToAssetVersionId);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.MigrationKey).HasMaxLength(160).IsRequired();
        entity.Property(x => x.Status).HasMaxLength(64).HasDefaultValue(DomainAssetMigrationStatuses.Draft);
        entity.Property(x => x.ImpactReport).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.Property(x => x.RollbackSnapshot).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.Property(x => x.CreatedBy).HasMaxLength(128).HasDefaultValue("system");
        entity.HasOne<DomainAssetVersion>().WithMany().HasForeignKey(x => x.FromAssetVersionId).OnDelete(DeleteBehavior.Restrict);
        entity.HasOne<DomainAssetVersion>().WithMany().HasForeignKey(x => x.ToAssetVersionId).OnDelete(DeleteBehavior.Restrict);
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_domain_asset_migrations_status", "status in ('draft','dry_run','pending_review','applied','rolled_back','rejected')");
            x.HasCheckConstraint("ck_domain_asset_migrations_not_self", "from_asset_version_id is null or to_asset_version_id is null or from_asset_version_id <> to_asset_version_id");
        });
    }

    private static void ConfigureQuestionBlock(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<QuestionBlock> entity)
    {
        entity.ToTable("question_blocks");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.QuestionItemId, x.SortOrder });
        entity.HasIndex(x => x.BlockType);
        entity.HasIndex(x => x.SourceRegionId);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.BlockType).HasMaxLength(64).HasDefaultValue("text");
        entity.Property(x => x.Content).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.HasOne<QuestionItem>().WithMany().HasForeignKey(x => x.QuestionItemId).OnDelete(DeleteBehavior.Cascade);
        entity.HasOne<SourceRegion>().WithMany().HasForeignKey(x => x.SourceRegionId).OnDelete(DeleteBehavior.Restrict);
        entity.ToTable(x => x.HasCheckConstraint("ck_question_blocks_sort_order", "sort_order >= 0"));
    }

    private static void ConfigureQuestionAsset(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<QuestionAsset> entity)
    {
        entity.ToTable("question_assets");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => x.QuestionItemId);
        entity.HasIndex(x => x.FileAssetId);
        entity.HasIndex(x => x.SourceRegionId);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.AssetType).HasMaxLength(64).HasDefaultValue("image");
        entity.Property(x => x.Purpose).HasMaxLength(128).HasDefaultValue("question_content");
        entity.Property(x => x.Metadata).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.HasOne<QuestionItem>().WithMany().HasForeignKey(x => x.QuestionItemId).OnDelete(DeleteBehavior.Cascade);
        entity.HasOne<FileAsset>().WithMany().HasForeignKey(x => x.FileAssetId).OnDelete(DeleteBehavior.Restrict);
        entity.HasOne<SourceRegion>().WithMany().HasForeignKey(x => x.SourceRegionId).OnDelete(DeleteBehavior.Restrict);
    }

    private static void ConfigurePaperBasket(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<PaperBasket> entity)
    {
        entity.ToTable("paper_baskets");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.Subject, x.Stage, x.Status });
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.Title).HasMaxLength(256).IsRequired();
        entity.Property(x => x.Subject).HasMaxLength(64).HasDefaultValue("physics");
        entity.Property(x => x.Stage).HasMaxLength(64).HasDefaultValue("junior_middle_school");
        entity.Property(x => x.Grade).HasMaxLength(64);
        entity.Property(x => x.Status).HasMaxLength(32).HasDefaultValue("draft");
        entity.Property(x => x.KnowledgeVersionStatus).HasMaxLength(32).HasDefaultValue(KnowledgeStatuses.Active);
        entity.Property(x => x.KnowledgeVersion).HasDefaultValue(1);
        entity.Property(x => x.Structure).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_paper_baskets_status", "status in ('draft','ready','archived')");
            x.HasCheckConstraint("ck_paper_baskets_knowledge_version", "knowledge_version >= 1");
        });
    }

    private static void ConfigurePaperBasketItem(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<PaperBasketItem> entity)
    {
        entity.ToTable("paper_basket_items");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.PaperBasketId, x.SortOrder });
        entity.HasIndex(x => x.QuestionItemId);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.SubQuestionNo).HasMaxLength(32);
        entity.Property(x => x.KnowledgeVersionStatus).HasMaxLength(32).HasDefaultValue(KnowledgeStatuses.Active);
        entity.Property(x => x.KnowledgeVersion).HasDefaultValue(1);
        entity.Property(x => x.Snapshot).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.HasOne<PaperBasket>().WithMany().HasForeignKey(x => x.PaperBasketId).OnDelete(DeleteBehavior.Cascade);
        entity.HasOne<QuestionItem>().WithMany().HasForeignKey(x => x.QuestionItemId).OnDelete(DeleteBehavior.Restrict);
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_paper_basket_items_section_no", "section_no >= 1");
            x.HasCheckConstraint("ck_paper_basket_items_question_no", "question_no >= 1");
            x.HasCheckConstraint("ck_paper_basket_items_score", "score >= 0");
            x.HasCheckConstraint("ck_paper_basket_items_sort_order", "sort_order >= 0");
            x.HasCheckConstraint("ck_paper_basket_items_knowledge_version", "knowledge_version >= 1");
        });
    }

    private static void ConfigurePaperBlueprintReview(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<PaperBlueprintReview> entity)
    {
        entity.ToTable("paper_blueprint_reviews");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.Subject, x.Stage, x.Status });
        entity.HasIndex(x => x.ConfirmedPaperBasketId);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.RequestText).HasMaxLength(2048).IsRequired();
        entity.Property(x => x.Subject).HasMaxLength(64).HasDefaultValue("physics");
        entity.Property(x => x.Stage).HasMaxLength(64).HasDefaultValue("junior_middle_school");
        entity.Property(x => x.Grade).HasMaxLength(64);
        entity.Property(x => x.TextbookVersion).HasMaxLength(128);
        entity.Property(x => x.Status).HasMaxLength(32).HasDefaultValue(WorkflowReviewStatuses.PendingReview);
        entity.Property(x => x.Blueprint).HasColumnType("jsonb").HasDefaultValueSql("'[]'::jsonb");
        entity.Property(x => x.Constraints).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.Property(x => x.ReviewQuestions).HasColumnType("jsonb").HasDefaultValueSql("'[]'::jsonb");
        entity.Property(x => x.TeacherConfirmedBy).HasMaxLength(128);
        entity.HasOne<PaperBasket>().WithMany().HasForeignKey(x => x.ConfirmedPaperBasketId).OnDelete(DeleteBehavior.Restrict);
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_paper_blueprint_reviews_status", "status in ('pending_review','confirmed','rejected')");
        });
    }

    private static void ConfigureCutCandidate(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<CutCandidate> entity)
    {
        entity.ToTable("cut_candidates");
        entity.HasKey(x => x.Id);
        entity.HasIndex(x => new { x.SourceDocumentId, x.Status });
        entity.HasIndex(x => x.SourceRegionId);
        entity.HasIndex(x => x.SuggestedQuestionItemId);
        entity.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        entity.Property(x => x.Status).HasMaxLength(32).HasDefaultValue(CutCandidateStatuses.PendingReview);
        entity.Property(x => x.SegmentType).HasMaxLength(64).HasDefaultValue("question_stem");
        entity.Property(x => x.CandidatePayload).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.Property(x => x.FailureReason).HasMaxLength(1024).HasDefaultValue(string.Empty);
        entity.Property(x => x.TakeoverAction).HasMaxLength(64).HasDefaultValue("manual_review");
        entity.Property(x => x.Metadata).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        entity.HasOne<SourceDocument>().WithMany().HasForeignKey(x => x.SourceDocumentId).OnDelete(DeleteBehavior.Cascade);
        entity.HasOne<SourceRegion>().WithMany().HasForeignKey(x => x.SourceRegionId).OnDelete(DeleteBehavior.SetNull);
        entity.HasOne<QuestionItem>().WithMany().HasForeignKey(x => x.SuggestedQuestionItemId).OnDelete(DeleteBehavior.SetNull);
        entity.ToTable(x =>
        {
            x.HasCheckConstraint("ck_cut_candidates_confidence", "confidence >= 0 and confidence <= 1");
            x.HasCheckConstraint("ck_cut_candidates_sequence_no", "sequence_no >= 0");
            x.HasCheckConstraint("ck_cut_candidates_status", "status in ('pending_review','needs_split','needs_merge','accepted','rejected','retry_required')");
            x.HasCheckConstraint("ck_cut_candidates_takeover_action", "takeover_action in ('manual_review','split','merge','skip','rerun')");
        });
    }
}
