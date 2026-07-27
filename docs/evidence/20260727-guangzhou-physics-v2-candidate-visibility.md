# REAL005B Reviewed Question Visibility

- status: pass
- checked_at: 2026-07-27T20:50:52
- api_visible_2016_2025_reviewed_questions: True
- source_document_count_2016_2025: 297
- source_region_count_2016_2025: 342
- guangzhou_non_2015_question_count: 234

## Conclusion
2015-2025 v2 real-question candidates are materialized into API-visible pending-review question/source state.

## Blockers
- none

## Usable Question Sample
- id=ce5830d6-f9d9-54fb-8396-bace5183e1dd; status=pending_review; questionNo=10; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=f6dcaef7-37c5-439a-a7e7-3019de4be6cf; status=pending_review; questionNo=6; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=03c586f6-c1bb-523b-a1ac-263379bdc479; status=pending_review; questionNo=9; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=d177a469-e72a-5722-a14b-fa1c9208b70d; status=pending_review; questionNo=5; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=2e9fa385-5a24-40dd-9693-e94b2542299d; status=pending_review; questionNo=16; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=c25e429d-c6e9-5777-b28c-fec9e5b5c056; status=pending_review; questionNo=13; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=5f7b3d86-28de-5e9f-bc63-1d343b358a06; status=pending_review; questionNo=16; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=d2756965-8e72-58f0-837b-89782c465d2a; status=pending_review; questionNo=10; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=31773f3b-75c4-5670-ba7e-933e5a17d798; status=pending_review; questionNo=14; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=50b8514e-1957-5d82-84ce-670e44414d8a; status=pending_review; questionNo=2; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=561105ed-3326-5222-a766-f045b63bb61b; status=pending_review; questionNo=14; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=a36eabcf-2998-51b0-9ee7-5eae38f9c42d; status=pending_review; questionNo=17; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=5dd775aa-1c80-5384-92f4-b2965ef2c4f5; status=pending_review; questionNo=4; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=7118bc8f-7b08-5b4c-9a37-2d61f1234c43; status=pending_review; questionNo=15; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=ee812673-fe90-5486-8e5b-1a2290bf45ae; status=pending_review; questionNo=3; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=3cd9ab48-2604-56fc-bedb-cf7f1d8588a8; status=pending_review; questionNo=9; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=1d29d45c-3399-5cc5-a02b-9c5e8161e7c7; status=pending_review; questionNo=2; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=8a800849-59cf-4f8c-96fa-8184ea11c86f; status=pending_review; questionNo=17; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=4c24ea39-15b4-5190-8a50-63d93d4da04f; status=pending_review; questionNo=18; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=14cb14dc-d497-553f-a48f-2357f3b4ed85; status=pending_review; questionNo=5; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1

## Boundary
This diagnostic reads PostgreSQL state and existing CSV evidence only. It does not create, update, review, or promote any question, source, or audit row.
