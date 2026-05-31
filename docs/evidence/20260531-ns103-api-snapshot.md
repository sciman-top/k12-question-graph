# NS103 · API contract snapshot

日期：2026-05-28。

## Result

- 状态：`pass`。
- API endpoint count: `50`。
- typed client function count: `18`。
- typed contract count: `27`。
- error code count: `64`。
- 本快照是静态 typed API snapshot，不宣称 OpenAPI runtime 已验证；后续若拉起 API 服务并抓取 `/openapi/v1.json`，可把 NS103 升级为 `runtime_verified`。

## API Endpoints

| Method | Route | Name | Source |
|---|---|---|---|
| GET | `/health` |  | `apps/api/Program.cs:45` |
| POST | `/review-queue/batch-resolve` |  | `apps/api/Program.cs:1368` |
| POST | `/review-queue/{id:guid}/resolve` |  | `apps/api/Program.cs:1426` |
| POST | `/review-workbench/actions` |  | `apps/api/Program.cs:1469` |
| POST | `/questions` |  | `apps/api/Program.cs:1712` |
| GET | `/questions` |  | `apps/api/Program.cs:1857` |
| GET | `/questions/{id:guid}` |  | `apps/api/Program.cs:2160` |
| PATCH | `/questions/{id:guid}` |  | `apps/api/Program.cs:2183` |
| POST | `/questions/{id:guid}/assets` |  | `apps/api/Program.cs:2418` |
| DELETE | `/questions/{id:guid}/assets/{assetId:guid}` |  | `apps/api/Program.cs:2503` |
| GET | `/questions/{id:guid}/sources` |  | `apps/api/Program.cs:2565` |
| POST | `/paper-baskets` |  | `apps/api/Program.cs:2622` |
| GET | `/paper-baskets/{id:guid}` |  | `apps/api/Program.cs:2714` |
| POST | `/score-imports` |  | `apps/api/Program.cs:2735` |
| POST | `/assessments/{assessmentId:guid}/item-score-mappings/preview` |  | `apps/api/Program.cs:2775` |
| POST | `/assessments/{assessmentId:guid}/commentary-report/export` |  | `apps/api/Program.cs:2797` |
| POST | `/paper-baskets/{id:guid}/export-preflight` |  | `apps/api/Program.cs:2824` |
| POST | `/paper-requests/parse` |  | `apps/api/Program.cs:2843` |
| POST | `/paper-blueprints` |  | `apps/api/Program.cs:2872` |
| POST | `/paper-blueprints/{id:guid}/confirm` |  | `apps/api/Program.cs:2891` |
| POST | `/paper-requests/replace-question` |  | `apps/api/Program.cs:2927` |
| POST | `/knowledge-version-explanations/resolve` |  | `apps/api/Program.cs:2989` |
| GET | `/review-queue` |  | `apps/api/Program.cs:1328` |
| GET | `/source-documents/{id:guid}/cut-candidates` |  | `apps/api/Program.cs:1302` |
| POST | `/source-documents/{id:guid}/cut-candidates/generate` |  | `apps/api/Program.cs:1281` |
| GET | `/source-regions/{id:guid}/page-screenshot` |  | `apps/api/Program.cs:1245` |
| GET | `/health/db` | `DatabaseHealth` | `apps/api/Program.cs:65` |
| GET | `/health/ready` |  | `apps/api/Program.cs:78` |
| GET | `/api/admin/storage/summary` |  | `apps/api/Program.cs:106` |
| POST | `/api/admin/cache/cleanup` | `AdminCacheCleanup` | `apps/api/Program.cs:127` |
| POST | `/internal/ai/model-route` | `RouteAiModel` | `apps/api/Program.cs:136` |
| GET | `/internal/ai/providers` | `ListAiProviders` | `apps/api/Program.cs:149` |
| POST | `/internal/ai/jobs/stub` |  | `apps/api/Program.cs:155` |
| POST | `/ai-suggestions/enqueue` |  | `apps/api/Program.cs:243` |
| POST | `/ai-suggestions/{id:guid}/feedback` |  | `apps/api/Program.cs:355` |
| GET | `/feedback-events/eval-samples` |  | `apps/api/Program.cs:453` |
| POST | `/imports/{id:guid}/status` |  | `apps/api/Program.cs:3055` |
| POST | `/ai-suggestions/{id:guid}/confirm` |  | `apps/api/Program.cs:494` |
| POST | `/files` |  | `apps/api/Program.cs:649` |
| GET | `/source-documents` |  | `apps/api/Program.cs:677` |
| PATCH | `/source-documents/{id:guid}/authorization` |  | `apps/api/Program.cs:711` |
| POST | `/imports` |  | `apps/api/Program.cs:804` |
| GET | `/imports/{id:guid}` | `GetImportJob` | `apps/api/Program.cs:854` |
| POST | `/source-documents/{id:guid}/regions` |  | `apps/api/Program.cs:864` |
| PATCH | `/source-regions/{id:guid}` |  | `apps/api/Program.cs:917` |
| GET | `/source-documents/{id:guid}/preview` |  | `apps/api/Program.cs:1011` |
| GET | `/source-documents/{id:guid}/quality-report` |  | `apps/api/Program.cs:1050` |
| GET | `/source-regions/{id:guid}/screenshot` |  | `apps/api/Program.cs:1211` |
| POST | `/ai-suggestions/{id:guid}/undo-confirm` |  | `apps/api/Program.cs:600` |
| POST | `/imports/{id:guid}/worker-smoke` |  | `apps/api/Program.cs:3102` |

## Typed Client Functions

| Function | Contract | Paths |
|---|---|---|
| `getReadyHealth` | `ReadyHealthContract` | `/health/ready` |
| `confirmPaperBlueprintReview` | `PaperBlueprintConfirmContract` |  |
| `createPaperBlueprintReview` | `PaperBlueprintReviewContract` | `/paper-blueprints` |
| `searchQuestions` | `QuestionSearchContract` | `/questions?${query.toString()}` |
| `getQuestionSources` | `QuestionSourceReviewContract` |  |
| `resolveReviewQueueItem` | `ReviewQueueItemContract` |  |
| `getReviewQueueItems` | `ReviewQueueListContract` | `/review-queue?${query.toString()}` |
| `applyReviewWorkbenchAction` | `ReviewWorkbenchActionContract` |  |
| `generateCutCandidates` | `CutCandidateGenerationContract` |  |
| `getCutCandidates` | `CutCandidateListContract` |  |
| `getSourceDocumentPreview` | `SourceDocumentPreviewContract` |  |
| `createScoreImport` | `ScoreImportContract` |  |
| `runDocumentWorkerSmoke` | `ImportJobContract` | `/imports/${encodeURIComponent(id)}/worker-smoke` |
| `uploadImportFile` | `ImportJobContract` |  |
| `getImportJob` | `ImportJobContract` | `/imports/${encodeURIComponent(id)}` |
| `getSourceMaterials` | `SourceMaterialListContract` | `/source-documents${query}` |
| `previewItemScoreMappings` | `ItemScoreMappingPreviewContract` |  |
| `exportCommentaryReport` | `CommentaryReportExportContract` |  |

## DTO Contracts

| Kind | Name |
|---|---|
| `type` | `ApiResult` |
| `interface` | `ItemScoreMappingPreviewRowContract` |
| `interface` | `ScoreImportContract` |
| `interface` | `ImportJobContract` |
| `interface` | `PaperBlueprintConfirmContract` |
| `interface` | `PaperBlueprintReviewContract` |
| `interface` | `PaperBlueprintRowContract` |
| `interface` | `QuestionSearchContract` |
| `interface` | `QuestionCardContract` |
| `interface` | `QuestionSourceReviewContract` |
| `interface` | `QuestionSourceRegionContract` |
| `interface` | `ReviewQueueListContract` |
| `interface` | `ItemScoreMappingPreviewContract` |
| `interface` | `ReviewQueueItemContract` |
| `interface` | `ReviewWorkbenchActionContract` |
| `interface` | `CutCandidateGenerationContract` |
| `interface` | `CutCandidateListContract` |
| `interface` | `CutCandidateContract` |
| `interface` | `SourceDocumentPreviewContract` |
| `interface` | `SourcePreviewPageContract` |
| `interface` | `SourcePreviewRegionContract` |
| `interface` | `SourceMaterialListContract` |
| `interface` | `SourceMaterialContract` |
| `interface` | `ReadyHealthContract` |
| `type` | `ReadyHealthStatus` |
| `interface` | `ReviewQueuePayloadContract` |
| `interface` | `CommentaryReportExportContract` |

## Error Codes

- `action_required`
- `admin_internal_guard_not_configured`
- `ai_provider_not_registered`
- `ai_suggestion_not_confirmed`
- `ai_suggestion_not_found`
- `ai_suggestion_not_reviewable`
- `artifact_id_required`
- `artifact_type_required`
- `assessment_not_found`
- `asset_label_required_for_associate`
- `candidate_ids_required`
- `confirmed_question_not_found`
- `current_knowledge_stable_ids_required`
- `current_knowledge_version_required`
- `current_question_required`
- `cut_candidates_not_found`
- `decision_required`
- `empty_file`
- `file_asset_missing`
- `historical_knowledge_stable_id_required`
- `historical_knowledge_version_required`
- `input_file_asset_missing`
- `invalid_admin_internal_key`
- `invalid_block_type`
- `invalid_difficulty_estimated`
- `invalid_page_screenshot_relative_path`
- `invalid_screenshot_relative_path`
- `invalid_status_transition`
- `item_ids_required`
- `knowledge_node_not_found`
- `knowledge_node_required_for_confirm`
- `merge_requires_at_least_two_candidates`
- `missing_admin_internal_key`
- `missing_file`
- `missing_input_json`
- `missing_operator_id`
- `missing_operator_role`
- `paper_basket_items_required`
- `paper_basket_question_missing`
- `primary_knowledge_missing`
- `question_asset_not_found`
- `question_block_missing`
- `question_not_found`
- `question_source_screenshot_missing`
- `real_model_calls_not_allowed_in_draft_test`
- `real_model_provider_not_allowed_in_draft_test`
- `reason_required`
- `review_queue_item_not_found`
- `review_queue_item_not_open`
- `reviewed_by_required`
- `role_not_authorized`
- `source_document_id_required`
- `source_document_not_found`
- `source_file_missing`
- `source_region_missing`
- `source_region_not_found`
- `source_region_page_screenshot_missing`
- `source_region_screenshot_missing`
- `source_region_screenshot_not_available`
- `split_requires_exactly_one_candidate`
- `suggestion_type_required`
- `teacher_confirmed_by_required`
- `teacher_request_required`
- `unsupported_action`

## Status Literals

- `ai_suggestion_pending_review`
- `allow_draft_test_bypass`
- `deny_invalid_admin_key`
- `dismissed`
- `draft`
- `draft_test`
- `draft_test_stub`
- `invalid_admin_internal_key`
- `invalid_bbox`
- `invalid_block_type`
- `invalid_coordinate_unit`
- `invalid_difficulty_estimated`
- `invalid_page_number`
- `invalid_page_screenshot_relative_path`
- `invalid_response`
- `invalid_screenshot_relative_path`
- `invalid_status_transition`
- `manual_review_pending`
- `open`
- `pending_review`
- `real_model_calls_not_allowed_in_draft_test`
- `real_model_provider_not_allowed_in_draft_test`
- `review_queue_item_not_open`
- `table_block_low_confidence_or_pending_review`
- `worker_failed`

## Compatibility Notes

- 普通教师 UI 继续消费 `apps/web/src/api/contracts.ts` 的 normalized typed contracts，不直接依赖裸 JSON shape。
- `ApiResult<T>` 仍以 `network_error` / `invalid_response` 收口前端错误面，避免页面散落 HTTP 细节。
- 本轮不新增、删除或重命名 API endpoint；只生成快照证据。
- `MapOpenApi()` 仍只在 Development 环境暴露；runtime OpenAPI 抓取留给后续验证。

## Verification

```powershell
dotnet build apps/api/K12QuestionGraph.Api.csproj
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-ns103-api-snapshot.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-non-site-implementation-plan-guard.ps1
```

## Rollback

```powershell
git restore tools/run-ns103-api-snapshot.ps1 tasks/non-site-implementation-plan.csv
git clean -f -- docs/evidence/20260528-ns103-api-snapshot.md
```
