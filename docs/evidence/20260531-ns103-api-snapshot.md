# NS103 · API contract snapshot

日期：2026-05-28。

## Result

- 状态：`pass`。
- API endpoint count: `53`。
- typed client function count: `21`。
- typed contract count: `30`。
- error code count: `64`。
- 本快照是静态 typed API snapshot，不宣称 OpenAPI runtime 已验证；后续若拉起 API 服务并抓取 `/openapi/v1.json`，可把 NS103 升级为 `runtime_verified`。

## API Endpoints

| Method | Route | Name | Source |
|---|---|---|---|
| GET | `/health` |  | `apps/api/Program.cs:52` |
| GET | `/source-documents/{id:guid}/cut-candidates` |  | `apps/api/Program.cs:1340` |
| GET | `/review-queue` |  | `apps/api/Program.cs:1366` |
| POST | `/review-queue/batch-resolve` |  | `apps/api/Program.cs:1406` |
| POST | `/review-queue/{id:guid}/resolve` |  | `apps/api/Program.cs:1464` |
| POST | `/review-workbench/actions` |  | `apps/api/Program.cs:1507` |
| POST | `/questions` |  | `apps/api/Program.cs:1750` |
| GET | `/questions` |  | `apps/api/Program.cs:1895` |
| GET | `/questions/{id:guid}` |  | `apps/api/Program.cs:2198` |
| PATCH | `/questions/{id:guid}` |  | `apps/api/Program.cs:2221` |
| POST | `/questions/{id:guid}/assets` |  | `apps/api/Program.cs:2456` |
| DELETE | `/questions/{id:guid}/assets/{assetId:guid}` |  | `apps/api/Program.cs:2541` |
| GET | `/questions/{id:guid}/sources` |  | `apps/api/Program.cs:2603` |
| POST | `/paper-baskets` |  | `apps/api/Program.cs:2660` |
| GET | `/paper-baskets/{id:guid}` |  | `apps/api/Program.cs:2752` |
| POST | `/score-imports` |  | `apps/api/Program.cs:2773` |
| POST | `/assessments/{assessmentId:guid}/item-score-mappings/preview` |  | `apps/api/Program.cs:2813` |
| POST | `/assessments/{assessmentId:guid}/commentary-report/export` |  | `apps/api/Program.cs:2835` |
| POST | `/paper-baskets/{id:guid}/export-preflight` |  | `apps/api/Program.cs:2862` |
| POST | `/paper-requests/parse` |  | `apps/api/Program.cs:2881` |
| POST | `/paper-blueprints` |  | `apps/api/Program.cs:2910` |
| POST | `/paper-blueprints/{id:guid}/confirm` |  | `apps/api/Program.cs:2929` |
| POST | `/paper-requests/replace-question` |  | `apps/api/Program.cs:2965` |
| POST | `/knowledge-version-explanations/resolve` |  | `apps/api/Program.cs:3027` |
| POST | `/source-documents/{id:guid}/cut-candidates/generate` |  | `apps/api/Program.cs:1319` |
| POST | `/imports/{id:guid}/status` |  | `apps/api/Program.cs:3093` |
| GET | `/source-regions/{id:guid}/page-screenshot` |  | `apps/api/Program.cs:1283` |
| GET | `/source-documents/{id:guid}/quality-report` |  | `apps/api/Program.cs:1088` |
| GET | `/health/db` | `DatabaseHealth` | `apps/api/Program.cs:72` |
| GET | `/health/ready` |  | `apps/api/Program.cs:85` |
| GET | `/api/admin/storage/summary` |  | `apps/api/Program.cs:113` |
| POST | `/api/admin/cache/cleanup` | `AdminCacheCleanup` | `apps/api/Program.cs:134` |
| GET | `/api/admin/ai/provider-settings` | `GetAdminAiProviderSettings` | `apps/api/Program.cs:143` |
| POST | `/api/admin/ai/provider-settings` | `SaveAdminAiProviderSettings` | `apps/api/Program.cs:152` |
| POST | `/api/admin/ai/provider-settings/test` | `TestAdminAiProviderSettings` | `apps/api/Program.cs:162` |
| POST | `/internal/ai/model-route` | `RouteAiModel` | `apps/api/Program.cs:174` |
| GET | `/internal/ai/providers` | `ListAiProviders` | `apps/api/Program.cs:187` |
| POST | `/internal/ai/jobs/stub` |  | `apps/api/Program.cs:193` |
| POST | `/ai-suggestions/enqueue` |  | `apps/api/Program.cs:281` |
| POST | `/ai-suggestions/{id:guid}/feedback` |  | `apps/api/Program.cs:393` |
| GET | `/feedback-events/eval-samples` |  | `apps/api/Program.cs:491` |
| POST | `/ai-suggestions/{id:guid}/confirm` |  | `apps/api/Program.cs:532` |
| POST | `/ai-suggestions/{id:guid}/undo-confirm` |  | `apps/api/Program.cs:638` |
| POST | `/files` |  | `apps/api/Program.cs:687` |
| GET | `/source-documents` |  | `apps/api/Program.cs:715` |
| PATCH | `/source-documents/{id:guid}/authorization` |  | `apps/api/Program.cs:749` |
| POST | `/imports` |  | `apps/api/Program.cs:842` |
| GET | `/imports/{id:guid}` | `GetImportJob` | `apps/api/Program.cs:892` |
| POST | `/source-documents/{id:guid}/regions` |  | `apps/api/Program.cs:902` |
| PATCH | `/source-regions/{id:guid}` |  | `apps/api/Program.cs:955` |
| GET | `/source-documents/{id:guid}/preview` |  | `apps/api/Program.cs:1049` |
| GET | `/source-regions/{id:guid}/screenshot` |  | `apps/api/Program.cs:1249` |
| POST | `/imports/{id:guid}/worker-smoke` |  | `apps/api/Program.cs:3140` |

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
| `previewItemScoreMappings` | `ItemScoreMappingPreviewContract` |  |
| `getCutCandidates` | `CutCandidateListContract` |  |
| `createScoreImport` | `ScoreImportContract` |  |
| `runDocumentWorkerSmoke` | `ImportJobContract` | `/imports/${encodeURIComponent(id)}/worker-smoke` |
| `uploadImportFile` | `ImportJobContract` |  |
| `getImportJob` | `ImportJobContract` | `/imports/${encodeURIComponent(id)}` |
| `getSourceMaterials` | `SourceMaterialListContract` | `/source-documents${query}` |
| `testAdminAiProviderSettings` | `AdminAiProviderSettingsTestContract` |  |
| `saveAdminAiProviderSettings` | `AdminAiProviderSettingsSaveContract` |  |
| `getAdminAiProviderSettings` | `AdminAiProviderSettingsContract` |  |
| `getSourceDocumentPreview` | `SourceDocumentPreviewContract` |  |
| `exportCommentaryReport` | `CommentaryReportExportContract` |  |

## DTO Contracts

| Kind | Name |
|---|---|
| `type` | `ApiResult` |
| `interface` | `AdminAiProviderSettingsContract` |
| `interface` | `CommentaryReportExportContract` |
| `interface` | `ItemScoreMappingPreviewContract` |
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
| `interface` | `ReviewQueueItemContract` |
| `interface` | `ReviewQueuePayloadContract` |
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
| `interface` | `AdminAiProviderSettingsSaveContract` |
| `interface` | `AdminAiProviderSettingsTestContract` |

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
- `cloud_openai_candidate`
- `deny_invalid_admin_key`
- `dismissed`
- `draft`
- `draft_test`
- `draft_test_stub`
- `failed`
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
- `openai_compatible`
- `pending_review`
- `provider_request_failed`
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
