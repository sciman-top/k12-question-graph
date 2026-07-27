# REAL005B Reviewed Question Visibility

- status: pass
- checked_at: 2026-07-27T21:18:00
- api_visible_2016_2025_reviewed_questions: True
- source_document_count_2016_2025: 297
- source_region_count_2016_2025: 342
- guangzhou_non_2015_question_count: 234

## Conclusion
2015-2025 v2 real-question candidates are materialized into API-visible pending-review question/source state.

## Blockers
- none

## Usable Question Sample
- id=c810e3a0-4625-58a3-a338-07fdaaa2ded9; status=pending_review; questionNo=9; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=d5e3e5aa-9732-55ca-9adc-44a2388f585f; status=pending_review; questionNo=15; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=14cb14dc-d497-553f-a48f-2357f3b4ed85; status=pending_review; questionNo=5; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=f1d9fd57-a054-540b-91fa-96509b0c902d; status=pending_review; questionNo=7; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=da8304b1-66a6-5d80-a248-1ce729804f1d; status=pending_review; questionNo=8; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=85dc5ea3-44c8-5809-b647-0938e16fa06e; status=pending_review; questionNo=9; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=6111f908-adab-554f-b3d9-7ec9672a92a5; status=pending_review; questionNo=21; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=531ada86-084e-5cd3-a25c-20743b440c83; status=pending_review; questionNo=17; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=ae6a9b50-b79e-5094-96d5-ac32174fb534; status=pending_review; questionNo=20; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=f6dcaef7-37c5-439a-a7e7-3019de4be6cf; status=pending_review; questionNo=6; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=03c586f6-c1bb-523b-a1ac-263379bdc479; status=pending_review; questionNo=9; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=d177a469-e72a-5722-a14b-fa1c9208b70d; status=pending_review; questionNo=5; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=2e9fa385-5a24-40dd-9693-e94b2542299d; status=pending_review; questionNo=16; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=c25e429d-c6e9-5777-b28c-fec9e5b5c056; status=pending_review; questionNo=13; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=d2756965-8e72-58f0-837b-89782c465d2a; status=pending_review; questionNo=10; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=31773f3b-75c4-5670-ba7e-933e5a17d798; status=pending_review; questionNo=14; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=50b8514e-1957-5d82-84ce-670e44414d8a; status=pending_review; questionNo=2; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=561105ed-3326-5222-a766-f045b63bb61b; status=pending_review; questionNo=14; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=a36eabcf-2998-51b0-9ee7-5eae38f9c42d; status=pending_review; questionNo=17; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1
- id=367be94c-19f2-54e9-a16f-60335b6169b3; status=pending_review; questionNo=8; workflowKey=guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1

## Boundary
This diagnostic reads PostgreSQL state and existing CSV evidence only. It does not create, update, review, or promote any question, source, or audit row.
