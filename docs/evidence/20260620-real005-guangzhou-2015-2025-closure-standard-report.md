# REAL005 广州 2015-2025 真卷全流程闭环判定标准

- status: pass
- closure_status: not_closed
- criteria_count: 16
- full_closure_allowed: False

## 当前结论
REAL005 判定标准已安装并通过自检；当前真实状态是 not_closed，仍需完成 逐年逐题闭环证据。

## Closeout slices
- REAL005A: status=pass; criteria=RG001, RG002; blockers=无; next=REAL005A evidence is ready for manual closeout review.
- REAL005B: status=pass; criteria=RG003, RG004, RG005, RG006, RG007, RG008, RG009; blockers=无; next=REAL005B repo-side evidence is complete; advance REAL005C with real question search/export/analysis and rollback/privacy coverage.
- REAL005C: status=pass; criteria=RG010, RG011, RG012, RG013, RG014, RG015, RG016; blockers=无; next=REAL005C repo-side evidence is complete; advance to REAL005D outward closeout wording while keeping REAL005 not_closed until D is truthfully refreshed.
- REAL005D: status=blocked; criteria=DOCS, README, GO_NO_GO_CARD; blockers=closureStatus remains not_closed; truthful docs must continue to say not_closed; next=Do not rewrite outward completion wording until REAL005A/B/C are all closed.

## REAL005 细化切片
- REAL005B: next_detailed_slice=none; ready=False
  - REAL005B1: status=pass; reported=pass; ready=True; criteria=RG003; blockers=无
  - REAL005B2: status=pass; reported=pass; ready=True; criteria=RG004; blockers=无
  - REAL005B3: status=pass; reported=pass; ready=True; criteria=RG005; blockers=无
  - REAL005B4: status=pass; reported=pass; ready=True; criteria=RG006; blockers=无
  - REAL005B5: status=pass; reported=pass; ready=True; criteria=RG007; blockers=无
  - REAL005B6: status=pass; reported=pass; ready=True; criteria=RG008, RG009; blockers=无
- REAL005C: next_detailed_slice=none; ready=False
  - REAL005C1: status=pass; reported=pass; ready=True; criteria=RG010; blockers=无
  - REAL005C2: status=pass; reported=pass; ready=True; criteria=RG011; blockers=无
  - REAL005C3: status=pass; reported=pass; ready=True; criteria=RG012; blockers=无
  - REAL005C4: status=pass; reported=pass; ready=True; criteria=RG013, RG014, RG015; blockers=无
  - REAL005C5: status=pass; reported=pass; ready=True; criteria=RG016; blockers=无

## 阻断缺口
- real-guangzhou-2015-2025-dashboard: dashboard state is contract_done; gap=REAL005 当前仍为 not_closed；REAL005B 与 REAL005C 已完成，下一 open slice 为 REAL005D（闭环口径复核与对外文案收口）; next=complete yearly question evidence and update dashboard only after every REAL005 criterion is satisfied

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
