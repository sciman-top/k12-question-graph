# NS103 · API contract snapshot

日期：2026-05-28。

## Result

- 状态：`pass`。
- API endpoint count: `67`。
- typed client function count: `32`。
- typed contract count: `57`。
- error code count: `65`。
- 本快照是静态 typed API snapshot，不宣称 OpenAPI runtime 已验证；后续若拉起 API 服务并抓取 `/openapi/v1.json`，可把 NS103 升级为 `runtime_verified`。

## API Endpoints

| Method | Route | Name | Source |
|---|---|---|---|
| GET | `/health` |  | `apps/api/Program.cs:59` |
| GET | `/source-documents/{id:guid}/quality-report` |  | `apps/api/Program.cs:1344` |
| GET | `/source-regions/{id:guid}/screenshot` |  | `apps/api/Program.cs:1505` |
| GET | `/source-regions/{id:guid}/page-screenshot` |  | `apps/api/Program.cs:1539` |
| GET | `/source-documents/{id:guid}/pages/{pageNumber:int:min(1)}/screenshot` |  | `apps/api/Program.cs:1597` |
| POST | `/source-documents/{id:guid}/cut-candidates/generate` |  | `apps/api/Program.cs:1634` |
| GET | `/source-documents/{id:guid}/cut-candidates` |  | `apps/api/Program.cs:1655` |
| GET | `/review-queue` |  | `apps/api/Program.cs:1681` |
| POST | `/review-queue/batch-resolve` |  | `apps/api/Program.cs:1728` |
| POST | `/review-queue/{id:guid}/resolve` |  | `apps/api/Program.cs:1786` |
| POST | `/review-queue/{id:guid}/reopen` |  | `apps/api/Program.cs:1829` |
| POST | `/review-workbench/actions` |  | `apps/api/Program.cs:1871` |
| POST | `/questions` |  | `apps/api/Program.cs:2114` |
| GET | `/questions` |  | `apps/api/Program.cs:2259` |
| GET | `/questions/{id:guid}` |  | `apps/api/Program.cs:2635` |
| GET | `/source-documents/{id:guid}/preview` |  | `apps/api/Program.cs:1305` |
| PATCH | `/questions/{id:guid}` |  | `apps/api/Program.cs:2658` |
| DELETE | `/questions/{id:guid}/assets/{assetId:guid}` |  | `apps/api/Program.cs:3013` |
| GET | `/questions/{id:guid}/sources` |  | `apps/api/Program.cs:3075` |
| POST | `/paper-baskets` |  | `apps/api/Program.cs:3132` |
| GET | `/paper-baskets/{id:guid}` |  | `apps/api/Program.cs:3224` |
| POST | `/score-imports` |  | `apps/api/Program.cs:3245` |
| POST | `/assessments/{assessmentId:guid}/item-score-mappings/preview` |  | `apps/api/Program.cs:3285` |
| POST | `/assessments/{assessmentId:guid}/score-evidence-analysis/preview` |  | `apps/api/Program.cs:3307` |
| POST | `/assessments/{assessmentId:guid}/commentary-report/export` |  | `apps/api/Program.cs:3330` |
| POST | `/paper-baskets/{id:guid}/export-preflight` |  | `apps/api/Program.cs:3357` |
| POST | `/paper-requests/parse` |  | `apps/api/Program.cs:3376` |
| POST | `/paper-blueprints` |  | `apps/api/Program.cs:3405` |
| POST | `/paper-blueprints/{id:guid}/confirm` |  | `apps/api/Program.cs:3451` |
| POST | `/paper-requests/replace-question` |  | `apps/api/Program.cs:3490` |
| POST | `/knowledge-version-explanations/resolve` |  | `apps/api/Program.cs:3552` |
| POST | `/questions/{id:guid}/assets` |  | `apps/api/Program.cs:2928` |
| POST | `/imports/{id:guid}/status` |  | `apps/api/Program.cs:3618` |
| PATCH | `/source-regions/{id:guid}` |  | `apps/api/Program.cs:1211` |
| GET | `/imports/{id:guid}` | `GetImportJob` | `apps/api/Program.cs:1148` |
| GET | `/health/db` | `DatabaseHealth` | `apps/api/Program.cs:79` |
| GET | `/health/ready` |  | `apps/api/Program.cs:92` |
| GET | `/knowledge-evidence/assessment-targets` |  | `apps/api/Program.cs:120` |
| GET | `/knowledge-evidence/observed-exam-evidence` |  | `apps/api/Program.cs:140` |
| GET | `/knowledge-evidence/regional-exam-profiles/{stableId}` | `GetRegionalExamProfile` | `apps/api/Program.cs:161` |
| GET | `/knowledge-evidence/questions` |  | `apps/api/Program.cs:173` |
| GET | `/knowledge-evidence/review-queue` |  | `apps/api/Program.cs:233` |
| GET | `/knowledge-evidence/reviews` | `ListCurriculumEvidenceReviews` | `apps/api/Program.cs:256` |
| GET | `/knowledge-evidence/reviews/{candidateId:guid}/replacement-options` | `ListCurriculumEvidenceReplacementOptions` | `apps/api/Program.cs:270` |
| GET | `/knowledge-evidence/reviews/readiness` | `GetCurriculumEvidenceReviewReadiness` | `apps/api/Program.cs:284` |
| POST | `/knowledge-evidence/reviews/decisions` |  | `apps/api/Program.cs:293` |
| POST | `/knowledge-evidence/reviews/batch-approve` |  | `apps/api/Program.cs:317` |
| POST | `/knowledge-evidence/reviews/decisions/{decisionId:guid}/undo` |  | `apps/api/Program.cs:341` |
| GET | `/api/admin/storage/summary` |  | `apps/api/Program.cs:369` |
| POST | `/source-documents/{id:guid}/regions` |  | `apps/api/Program.cs:1158` |
| POST | `/api/admin/cache/cleanup` | `AdminCacheCleanup` | `apps/api/Program.cs:390` |
| POST | `/api/admin/ai/provider-settings` | `SaveAdminAiProviderSettings` | `apps/api/Program.cs:408` |
| POST | `/api/admin/ai/provider-settings/test` | `TestAdminAiProviderSettings` | `apps/api/Program.cs:418` |
| POST | `/internal/ai/model-route` | `RouteAiModel` | `apps/api/Program.cs:430` |
| GET | `/internal/ai/providers` | `ListAiProviders` | `apps/api/Program.cs:443` |
| POST | `/internal/ai/jobs/stub` |  | `apps/api/Program.cs:449` |
| POST | `/ai-suggestions/enqueue` |  | `apps/api/Program.cs:537` |
| POST | `/ai-suggestions/{id:guid}/feedback` |  | `apps/api/Program.cs:649` |
| GET | `/feedback-events/eval-samples` |  | `apps/api/Program.cs:747` |
| POST | `/ai-suggestions/{id:guid}/confirm` |  | `apps/api/Program.cs:788` |
| POST | `/ai-suggestions/{id:guid}/undo-confirm` |  | `apps/api/Program.cs:894` |
| POST | `/files` |  | `apps/api/Program.cs:943` |
| GET | `/source-documents` |  | `apps/api/Program.cs:971` |
| PATCH | `/source-documents/{id:guid}/authorization` |  | `apps/api/Program.cs:1005` |
| POST | `/imports` |  | `apps/api/Program.cs:1098` |
| GET | `/api/admin/ai/provider-settings` | `GetAdminAiProviderSettings` | `apps/api/Program.cs:399` |
| POST | `/imports/{id:guid}/worker-smoke` |  | `apps/api/Program.cs:3665` |

## Typed Client Functions

| Function | Contract | Paths |
|---|---|---|
| `getReadyHealth` | `ReadyHealthContract` | `/health/ready` |
| `previewItemScoreMappings` | `ItemScoreMappingPreviewContract` |  |
| `confirmPaperBlueprintReview` | `PaperBlueprintConfirmContract` |  |
| `createPaperBlueprintReview` | `PaperBlueprintReviewContract` | `/paper-blueprints` |
| `replacePaperQuestion` | `PaperQuestionReplacementContract` |  |
| `searchQuestionEvidence` | `QuestionEvidenceSearchContract` |  |
| `searchQuestions` | `QuestionSearchContract` | `/questions?${query.toString()}` |
| `getQuestionSources` | `QuestionSourceReviewContract` |  |
| `updateSourceRegion` | `SourceRegionRevisionContract` |  |
| `updateQuestion` | `QuestionRevisionContract` |  |
| `getQuestion` | `QuestionDetailContract` | `/questions/${encodeURIComponent(questionId)}` |
| `undoCurriculumEvidenceDecision` | `CurriculumEvidenceDecisionContract` |  |
| `getCurriculumEvidenceReplacementOptions` | `CurriculumEvidenceReplacementOptionsContract` |  |
| `decideCurriculumEvidence` | `CurriculumEvidenceDecisionContract` |  |
| `getCurriculumEvidenceReviews` | `CurriculumEvidenceReviewListContract` |  |
| `reopenReviewQueueItem` | `ReviewQueueItemContract` |  |
| `resolveReviewQueueItem` | `ReviewQueueItemContract` |  |
| `getReviewQueueItems` | `ReviewQueueListContract` | `/review-queue?${query.toString()}` |
| `applyReviewWorkbenchAction` | `ReviewWorkbenchActionContract` | `/review-workbench/actions` |
| `generateCutCandidates` | `CutCandidateGenerationContract` |  |
| `getCutCandidates` | `CutCandidateListContract` |  |
| `getSourceDocumentPreview` | `SourceDocumentPreviewContract` |  |
| `createScoreImport` | `ScoreImportContract` |  |
| `runDocumentWorkerSmoke` | `ImportJobContract` | `/imports/${encodeURIComponent(id)}/worker-smoke` |
| `uploadImportFile` | `ImportJobContract` | `/imports` |
| `getImportJob` | `ImportJobContract` | `/imports/${encodeURIComponent(id)}` |
| `getSourceMaterials` | `SourceMaterialListContract` | `/source-documents${query}` |
| `testAdminAiProviderSettings` | `AdminAiProviderSettingsTestContract` |  |
| `saveAdminAiProviderSettings` | `AdminAiProviderSettingsSaveContract` |  |
| `getAdminAiProviderSettings` | `AdminAiProviderSettingsContract` |  |
| `previewScoreEvidenceAnalysis` | `ScoreEvidenceAnalysisContract` |  |
| `exportCommentaryReport` | `CommentaryReportExportContract` |  |

## DTO Contracts

| Kind | Name |
|---|---|
| `type` | `ApiResult` |
| `interface` | `QuestionEvidenceSearchParams` |
| `interface` | `QuestionEvidenceKnowledgeContract` |
| `interface` | `QuestionEvidenceRequirementContract` |
| `interface` | `QuestionObservedDifficultyContract` |
| `interface` | `QuestionEvidenceProfileContract` |
| `interface` | `QuestionAssessmentTargetEvidenceContract` |
| `interface` | `QuestionEvidenceCardContract` |
| `interface` | `QuestionEvidenceSearchContract` |
| `interface` | `PaperBlueprintRowContract` |
| `interface` | `PaperBlueprintReviewContract` |
| `interface` | `PaperBlueprintConfirmContract` |
| `interface` | `PaperDraftQuestionContract` |
| `interface` | `PaperQuestionReplacementContract` |
| `interface` | `ImportJobContract` |
| `interface` | `ScoreImportContract` |
| `interface` | `ItemScoreMappingPreviewRowContract` |
| `interface` | `ItemScoreMappingPreviewContract` |
| `interface` | `ScoreEvidenceAnalysisContract` |
| `interface` | `ScoreEvidenceDimensionContract` |
| `interface` | `CommentaryReportExportContract` |
| `interface` | `AdminAiProviderSettingsContract` |
| `interface` | `AdminAiProviderEndpointContract` |
| `interface` | `AdminAiProviderSettingsSaveContract` |
| `interface` | `AdminAiProviderProbeAttemptContract` |
| `interface` | `AdminAiProviderImageProbeAttemptContract` |
| `type` | `QuestionEvidenceMode` |
| `interface` | `AdminAiProviderImageProbeResultContract` |
| `interface` | `QuestionSearchParams` |
| `interface` | `QuestionCardContract` |
| `type` | `ReadyHealthStatus` |
| `interface` | `ReadyHealthContract` |
| `interface` | `SourceMaterialContract` |
| `interface` | `SourceMaterialListContract` |
| `interface` | `SourcePreviewRegionContract` |
| `interface` | `SourcePreviewPageContract` |
| `interface` | `SourceDocumentPreviewContract` |
| `interface` | `CutCandidateContract` |
| `interface` | `CutCandidateListContract` |
| `interface` | `CutCandidateGenerationContract` |
| `interface` | `ReviewWorkbenchActionContract` |
| `interface` | `ReviewQueuePayloadContract` |
| `interface` | `ReviewQueueItemContract` |
| `interface` | `ReviewQueueListContract` |
| `interface` | `CurriculumEvidenceReviewItemContract` |
| `interface` | `CurriculumEvidenceReviewListContract` |
| `interface` | `CurriculumEvidenceReplacementOptionContract` |
| `interface` | `CurriculumEvidenceReplacementOptionsContract` |
| `interface` | `CurriculumEvidenceDecisionContract` |
| `interface` | `QuestionSourceRegionContract` |
| `interface` | `QuestionBlockContract` |
| `interface` | `QuestionDetailContract` |
| `interface` | `QuestionRevisionContract` |
| `interface` | `SourceRegionRevisionContract` |
| `interface` | `QuestionSourceReviewContract` |
| `interface` | `QuestionSearchContract` |
| `interface` | `AdminAiProviderSettingsTestContract` |

## Error Codes

- `action_required`
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
- `curriculum_evidence_candidate_not_found`
- `cut_candidates_not_found`
- `decision_required`
- `empty_file`
- `file_asset_missing`
- `historical_knowledge_stable_id_required`
- `historical_knowledge_version_required`
- `input_file_asset_missing`
- `invalid_block_type`
- `invalid_difficulty_estimated`
- `invalid_page_screenshot_relative_path`
- `invalid_review_status`
- `invalid_screenshot_relative_path`
- `invalid_status_transition`
- `item_ids_required`
- `knowledge_node_not_found`
- `knowledge_node_required_for_confirm`
- `merge_requires_at_least_two_candidates`
- `missing_file`
- `missing_input_json`
- `paper_basket_items_required`
- `paper_basket_question_missing`
- `primary_knowledge_missing`
- `primary_knowledge_update_conflict`
- `question_asset_not_found`
- `question_block_missing`
- `question_not_found`
- `question_source_screenshot_missing`
- `real_model_calls_not_allowed_in_draft_test`
- `real_model_provider_not_allowed_in_draft_test`
- `reason_required`
- `regional_exam_profile_not_found`
- `review_queue_item_already_open`
- `review_queue_item_not_found`
- `review_queue_item_not_open`
- `reviewed_by_required`
- `source_document_id_required`
- `source_document_not_found`
- `source_document_page_screenshot_missing`
- `source_file_missing`
- `source_region_document_missing`
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
- `dismissed`
- `draft`
- `draft_test`
- `draft_test_stub`
- `invalid_bbox`
- `invalid_block_type`
- `invalid_coordinate_unit`
- `invalid_difficulty_estimated`
- `invalid_difficulty_range`
- `invalid_evidence_mode`
- `invalid_page_number`
- `invalid_page_screenshot_relative_path`
- `invalid_response`
- `invalid_review_status`
- `invalid_screenshot_relative_path`
- `invalid_status_transition`
- `manual_review_pending`
- `open`
- `pending_review`
- `pending_teacher_confirmation`
- `real_model_calls_not_allowed_in_draft_test`
- `real_model_provider_not_allowed_in_draft_test`
- `reopened`
- `review_queue_item_already_open`
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
