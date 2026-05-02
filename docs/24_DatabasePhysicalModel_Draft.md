# 24 · 数据库物理模型草案

## 1. PostgreSQL 扩展

建议启用：

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;
```

P0 若本机 PostgreSQL 尚未安装 `vector`，允许先记录 `gate_na`，但迁移必须保留后续启用扩展的位置。

## 2. 关键表

```text
users
teacher_preferences
file_assets
import_jobs
source_documents
source_regions
question_items
question_blocks
question_assets
shared_materials
knowledge_nodes
knowledge_edges
knowledge_mappings
papers
paper_sections
paper_questions
students
class_groups
exams
score_records
item_scores
analysis_reports
ai_jobs
ai_results
review_queue_items
feedback_events
backup_jobs
cache_records
custom_field_definitions
job_events
```

## 3. JSONB 用途

- QuestionItem.custom_fields。
- QuestionItem.blocks_snapshot。
- AIResult.output_json。
- TeacherPreference.settings。
- BackupJob.manifest。
- ExportTemplate.config。

## 4. 文件不进数据库

大文件只存路径、hash、大小、mime、状态。

## 5. 版本化字段

知识图谱、标签定义、prompt、规则、导出模板都要有 version 和 status。

## 6. 审计字段

所有核心表建议包含：

```text
created_at
created_by
updated_at
updated_by
is_deleted
deleted_at
deleted_by
```

## 7. P0 Job Store 字段

`import_jobs`、`ai_jobs`、`backup_jobs` 至少包含：

```text
id
job_type
status
priority
file_asset_id
payload_json
result_json
attempt_count
max_attempts
idempotency_key
locked_by
locked_until
started_at
finished_at
last_error_code
last_error_message
created_at
updated_at
```

状态最少支持：

```text
queued
running
succeeded
failed
cancelled
retry_waiting
```

`job_events` 用于记录状态变更、重试、取消、错误、人工接管和 Worker diagnostics。

## 8. P0 约束与索引

P0 migration 不只创建表，还必须创建最低约束，防止坏数据进入事实源。

### 8.1 文件资产

```text
file_assets.sha256 NOT NULL
file_assets.size_bytes >= 0
file_assets.mime_type NOT NULL
file_assets.storage_path NOT NULL
unique(sha256, size_bytes)
index(status)
index(created_at)
```

重复上传不复制大文件；若同一 hash/size 已存在，创建引用或返回 `duplicate_of_file_asset_id`。

### 8.2 Job Store

```text
status in queued/running/succeeded/failed/cancelled/retry_waiting
attempt_count >= 0
max_attempts >= 1
locked_until is null or locked_by is not null
unique(job_type, idempotency_key) where idempotency_key is not null
index(status, priority, created_at)
index(locked_until)
index(file_asset_id)
```

状态转移由应用层和测试共同保证，最低允许转移：

```text
queued -> running
running -> succeeded
running -> failed
running -> retry_waiting
retry_waiting -> queued
queued/running/retry_waiting -> cancelled
failed -> retry_waiting
```

禁止：

```text
succeeded -> running
cancelled -> running
failed -> succeeded
```

### 8.3 SourceRegion

```text
source_regions.page_number >= 1
source_regions.x >= 0
source_regions.y >= 0
source_regions.width > 0
source_regions.height > 0
source_regions.coordinate_unit in pixel, point, percent
index(source_document_id, page_number)
```

坐标必须明确单位；截图缺失时不得静默显示空白，API 必须返回明确错误。

### 8.4 SourceDocument 来源与隐私约束

```text
source_documents.source_type NOT NULL
source_documents.owner_scope NOT NULL
source_documents.sharing_allowed NOT NULL default false
source_documents.contains_student_pii NOT NULL default false
source_documents.anonymization_status in none, anonymized, synthetic, not_applicable
source_documents.license_or_permission NOT NULL default 'unknown'
index(source_type)
index(owner_scope)
index(contains_student_pii)
```

未知来源或含真实学生 PII 且未匿名化的资料，应用层默认禁止校级共享、公开导出和外部 AI 调用。

### 8.5 Soft delete

核心表使用 `is_deleted` 时，默认查询必须排除已删除记录。物理删除只允许发生在：

```text
已无业务引用
已进入回收站超过保留期
已有成功备份或明确无需备份
管理员高风险确认
```

### 8.6 Migration 与 seed

- P0 migration 必须可在空库创建。
- P0 seed 只放系统必需默认值：管理员占位、默认教师偏好、默认题型/状态、默认存储策略。
- migration 回滚必须至少能删除 P0 新建表和扩展引用；不能回滚的步骤必须写明原因和恢复方式。
