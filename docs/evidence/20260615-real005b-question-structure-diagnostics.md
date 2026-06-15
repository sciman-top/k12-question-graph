# REAL005B Question Structure Diagnostics

- status: pass
- real005b_status: partial
- checked_at: 2026-06-15T15:39:57.811730+00:00
- active_write: false
- external_ai_calls: 0

## Criteria
- RG003: status=pass; blockers=none
- RG004: status=pass; blockers=none
- RG005: status=pass; blockers=none
- RG006: status=blocked; blockers=2016_2025_per_question_structured_blocks_not_emitted_in_year_batch_report | 2015_questions_remain_pending_review | formula_table_image_fields_are_smoke_coverage_not_every_question_closure
- RG007: status=blocked; blockers=2015_tags_remain_pending_review | 2016_2025_per_question_tagging_suggestions_not_proven | teacher_confirmed_tag_terminal_status_not_present
- RG008: status=blocked; blockers=no_per_question_terminal_teacher_review_for_2015_2025 | 2015_review_smoke_restores_open_review_items | 2016_2025_review_queue_terminal_status_not_present
- RG009: status=blocked; blockers=2016_2025_reviewed_question_save_and_source_detail_smoke_not_present | all_years_reviewed_question_terminal_status_required_before_save_source_review_closure

## Boundary
This diagnostic only reads existing REAL001-REAL004 and REAL007-REAL011 evidence. It does not write database rows, close review items, call external AI, use student data, or replace teacher review.
