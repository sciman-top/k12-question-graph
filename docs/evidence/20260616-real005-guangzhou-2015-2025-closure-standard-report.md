# REAL005 广州 2015-2025 真卷全流程闭环判定标准

- status: pass
- closure_status: not_closed
- criteria_count: 16
- full_closure_allowed: False

## 当前结论
REAL005 判定标准已安装并通过自检；当前真实状态是 not_closed，仍需完成 逐年逐题闭环证据。

## Closeout slices
- REAL005A: status=pass; criteria=RG001, RG002; blockers=无; next=REAL005A evidence is ready for manual closeout review.
- REAL005B: status=partial; criteria=RG003, RG004, RG005, RG006, RG007, RG008, RG009; blockers=RG009:2016_2025_reviewed_questions_not_materialized_for_api_source_review; next=REAL005B remains partial until RG004-RG009 have per-question source anchors, structured fields, teacher review terminal status, and source-review save/detail evidence.
- REAL005C: status=blocked_by_previous_slice; criteria=RG010, RG011, RG012, RG013, RG014, RG015, RG016; blockers=REAL005A and REAL005B remain open; usage/export/analysis closure cannot be promoted ahead of earlier slices.; next=Keep REAL005C blocked until source coverage and per-question review closure are both complete.
- REAL005D: status=blocked; criteria=DOCS, README, GO_NO_GO_CARD; blockers=closureStatus remains not_closed; truthful docs must continue to say not_closed; next=Do not rewrite outward completion wording until REAL005A/B/C are all closed.

## REAL005 细化切片
- REAL005B: next_detailed_slice=REAL005B6; ready=True
  - REAL005B1: status=pass; reported=pass; ready=True; criteria=RG003; blockers=无
  - REAL005B2: status=pass; reported=pass; ready=True; criteria=RG004; blockers=无
  - REAL005B3: status=pass; reported=pass; ready=True; criteria=RG005; blockers=无
  - REAL005B4: status=pass; reported=pass; ready=True; criteria=RG006; blockers=无
  - REAL005B5: status=pass; reported=pass; ready=True; criteria=RG007; blockers=无
  - REAL005B6: status=blocked; reported=blocked; ready=True; criteria=RG008, RG009; blockers=RG009:2016_2025_reviewed_questions_not_materialized_for_api_source_review
- REAL005C: next_detailed_slice=REAL005C1; ready=False
  - REAL005C1: status=blocked_by_previous_slice; reported=not_evaluated; ready=False; criteria=RG010; blockers=waiting_for_dependency:REAL005B6 | criteria_not_evaluated:RG010
  - REAL005C2: status=blocked_by_previous_slice; reported=not_evaluated; ready=False; criteria=RG011; blockers=waiting_for_dependency:REAL005C1 | criteria_not_evaluated:RG011
  - REAL005C3: status=blocked_by_previous_slice; reported=not_evaluated; ready=False; criteria=RG012; blockers=waiting_for_dependency:REAL005C2 | criteria_not_evaluated:RG012
  - REAL005C4: status=blocked_by_previous_slice; reported=not_evaluated; ready=False; criteria=RG013, RG014, RG015; blockers=waiting_for_dependency:REAL005C3 | criteria_not_evaluated:RG013+RG014+RG015
  - REAL005C5: status=blocked_by_previous_slice; reported=not_evaluated; ready=False; criteria=RG016; blockers=waiting_for_dependency:REAL005C4 | criteria_not_evaluated:RG016

## 阻断缺口
- real-guangzhou-2015-2025-dashboard: dashboard state is contract_done; gap=REAL005 当前只能输出 not_closed 缺逐年逐题闭环证据; next=complete yearly question evidence and update dashboard only after every REAL005 criterion is satisfied

## 判定标准
- RG001 source_manifest: source manifest report with 11 years and paper answer hash coverage
- RG002 adapter_extraction: adapter diagnostic report per year
- RG003 question_count: year batch ingest report with expected_count actual_count missing_question_numbers
- RG004 answer_alignment: answer coverage report with per-question source anchor
- RG005 visual_regions: source region and asset report with no placeholder bbox except time-boxed gate_na
- RG006 structured_question: question structure report and review queue reason
- RG007 knowledge_tagging: tagging suggestion report with confidence source and no_active_write
- RG008 teacher_review: review audit report with per-question terminal status and edited fields
- RG009 question_save_source_review: API/UI smoke using real reviewed questions
- RG010 search_paper_export: search paper export smoke with real question ids
- RG011 analysis_reference: analysis smoke with real reviewed question ids and no formal history write
- RG012 rollback_and_privacy: rollback privacy and AI boundary report
- RG013 layout_noise_cleanup: layout noise report with per-page noise region and retained region counts
- RG014 formula_fidelity: formula fidelity report with OMML/LaTeX/fallback coverage
- RG015 table_structuring: table structure report with rows columns sourceRegion confidence reviewStatus
- RG016 edit_recrop_audit: edit and recrop audit report
