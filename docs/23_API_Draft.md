# 23 · API 草案

## 1. 认证

```text
GET  /health
POST /api/auth/login
POST /api/auth/logout
GET  /api/me
```

## 2. 文件与导入

```text
POST /api/files/upload
GET  /api/files/{id}
POST /api/import-jobs
GET  /api/import-jobs
GET  /api/import-jobs/{id}
POST /api/import-jobs/{id}/run
POST /api/import-jobs/{id}/cancel
POST /api/import-jobs/{id}/retry
GET  /api/review-queue
PATCH /api/review-queue/{id}
```

## 3. 试题

```text
GET    /api/questions
POST   /api/questions
GET    /api/questions/{id}
PATCH  /api/questions/{id}
POST   /api/questions/{id}/feedback
POST   /api/questions/{id}/status
```

## 4. 知识点

```text
GET  /api/knowledge/nodes
POST /api/knowledge/nodes
GET  /api/knowledge/mappings
POST /api/knowledge/mappings/suggest
PATCH /api/knowledge/mappings/{id}
```

## 5. 组卷

```text
POST /api/papers/natural-language-plan
POST /api/papers/generate
GET  /api/papers/{id}
PATCH /api/papers/{id}
POST /api/papers/{id}/replace-question
POST /api/papers/{id}/export
```

## 6. 成绩与分析

```text
POST /api/exams
POST /api/exams/{id}/score-import
GET  /api/exams/{id}/analysis
POST /api/exams/{id}/reports/export
POST /api/exams/{id}/tiered-practice
```

## 7. 运维

```text
POST /api/admin/backup/run
GET  /api/admin/backup/jobs
GET  /api/admin/jobs
POST /api/admin/backup/verify
POST /api/admin/cache/cleanup
GET  /api/admin/storage/summary
GET  /api/admin/ai-cost/summary
```

## 8. 说明

API 名称可在编码阶段调整，但业务边界不应随意变更。

P0/P1 期间必须先实现 `/health`、`/api/files/upload`、`/api/import-jobs`、`/api/import-jobs/{id}` 和备份 manifest 相关最小接口；其他接口只作为后续边界草案。

## 9. P0 API 契约

P0 编码前必须把以下约定固化到 OpenAPI 文档和 contract snapshot。

### 9.1 通用约定

| 项 | 约定 |
|---|---|
| Content-Type | JSON 接口使用 `application/json`；文件上传使用 `multipart/form-data` |
| ID | 服务端生成稳定 ID；编码阶段可用 UUID/ULID，但必须全局统一 |
| 时间 | API 返回 UTC ISO-8601 字符串 |
| 命名 | JSON 字段使用 camelCase |
| 错误 | 使用 ProblemDetails 风格响应，扩展字段含 `errorCode`、`traceId`、`details` |
| 幂等 | 创建类接口支持 `Idempotency-Key` header；重复 key 返回已有资源或 `409` |
| 分页 | 列表接口使用 `pageSize`、`cursor`；响应返回 `nextCursor` |

### 9.2 P0 DTO 草案

`POST /api/files/upload`

```json
{
  "file": "<multipart file>",
  "sourceType": "upload",
  "originalFileName": "physics-paper.docx"
}
```

响应：

```json
{
  "fileAssetId": "file_01",
  "sha256": "...",
  "sizeBytes": 12345,
  "mimeType": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "storagePath": "file_store/original/...",
  "duplicateOfFileAssetId": null
}
```

`POST /api/import-jobs`

```json
{
  "fileAssetId": "file_01",
  "importMode": "documentStub",
  "teacherPreferenceId": "pref_01"
}
```

响应：

```json
{
  "importJobId": "job_01",
  "status": "queued",
  "fileAssetId": "file_01",
  "idempotencyKey": "client-key",
  "createdAt": "2026-05-02T00:00:00Z"
}
```

`GET /api/import-jobs/{id}`

```json
{
  "id": "job_01",
  "status": "queued",
  "attemptCount": 0,
  "maxAttempts": 3,
  "lockedBy": null,
  "lockedUntil": null,
  "lastErrorCode": null,
  "lastErrorMessage": null,
  "result": null
}
```

### 9.3 P0 错误码

| errorCode | HTTP | 场景 |
|---|---:|---|
| `KQG_VALIDATION_FAILED` | 400 | 请求字段缺失或格式不合法 |
| `KQG_UNAUTHORIZED` | 401 | 未登录或 token 无效 |
| `KQG_FORBIDDEN` | 403 | 当前角色不可访问资源 |
| `KQG_NOT_FOUND` | 404 | 资源不存在或已删除 |
| `KQG_CONFLICT` | 409 | 幂等键冲突、状态冲突、重复操作 |
| `KQG_PAYLOAD_TOO_LARGE` | 413 | 上传文件超过限制 |
| `KQG_UNSUPPORTED_FILE_TYPE` | 415 | 上传类型不在允许列表 |
| `KQG_JOB_NOT_RETRYABLE` | 409 | 当前任务状态不允许 retry |
| `KQG_BACKUP_VERIFY_FAILED` | 500 | 备份 manifest/hash 校验失败 |

### 9.4 Contract gate

P0 gate 必须包含：

```text
OpenAPI 可生成
P0 DTO snapshot 可对比
ProblemDetails 错误响应快照可对比
Idempotency-Key 重复请求测试
upload/import job happy path 测试
```
