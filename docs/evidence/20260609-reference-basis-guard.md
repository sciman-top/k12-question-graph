# Reference Basis Guard

- status: pass
- checked_at: 2026-06-11T21:16:07
- validation_mode: Local
- requirements_path: tasks/reference-basis-requirements.csv
- module_map_path: tasks/reference-basis-module-map.csv
- snapshot_manifest_path: sources/reference-shelf.manifest.snapshot.json
- row_count: 20
- module_row_count: 13
- community_task_count: 10
- effective_manifest_source: external
- snapshot_entry_count: 23
- external_entry_count: 23
- snapshot_parity: match
- physical_external_check: True

## Covered Tasks
- S004
- S010
- S011
- REAL010
- NS1301
- NS1302
- NS1303
- NS1304
- NS1305
- NS1306
- NS1307
- NS1308
- O008
- P001
- P003
- P005
- P006
- R001
- R002
- R007

## Covered Modules
- API_HOST_AND_WORKFLOW_BOUNDARY
- WEB_TEACHER_WORKBENCH
- EXPORT_ARTIFACT_CHAIN_AND_FIDELITY
- SCORE_ANALYSIS_AND_COMMENTARY
- AI_ROUTING_AND_EVAL
- DOCUMENT_IMPORT_OCR_FORMULA
- QUESTION_BANK_DOMAIN_ASSET_GOVERNANCE
- WINDOWS_SERVICE_INSTALLER_OPERATIONS
- BACKUP_RESTORE_RELEASE_EVIDENCE
- VISUAL_SURROGATE_AND_UI_VERIFICATION
- SEARCH_RETRIEVAL_ADMISSION
- QUEUE_BACKGROUND_SERVICE_ADMISSION
- INTEROP_PROFILE_AND_EDU_GOVERNANCE

## Boundary
This guard proves that guarded tasks and module surfaces have declared official references plus reference-basis anchors.
Local mode also requires the external corpus to exist on disk. CI mode falls back to the snapshot manifest and only verifies the repo-side declarations, docs, and mappings.
It does not prove the implementation used those references correctly, so feature-specific contracts and review are still required.
