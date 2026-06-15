# REAL005B Reviewed Question Visibility

- status: pass
- checked_at: 2026-06-16T01:29:53
- api_visible_2016_2025_reviewed_questions: False
- source_document_count_2016_2025: 2
- source_region_count_2016_2025: 1
- guangzhou_non_2015_question_count: 0

## Conclusion
2016-2025 quality-review CSV evidence exists, but current database/API state does not expose reviewed real questions for RG009 save/detail/source-review smoke.

## Blockers
- no_2016_2025_real_questions_materialized_into_question_items

## Usable Question Sample
- id=027acbf1-4692-49b1-9adb-5ae7f06e31a3; status=usable; questionNo=4; workflowKey=guangzhou_2015_real_ingest_v1
- id=84eac67d-c612-4ba5-bb7d-e871cbde356f; status=usable; questionNo=3; workflowKey=guangzhou_2015_real_ingest_v1
- id=ace44579-b70c-4c64-b36a-2852ba86ef97; status=usable; questionNo=2; workflowKey=guangzhou_2015_real_ingest_v1

## Boundary
This diagnostic reads PostgreSQL state and existing CSV evidence only. It does not create, update, review, or promote any question, source, or audit row.
