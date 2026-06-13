# REAL005 广州 2015-2025 真卷全流程闭环判定标准

- status: pass
- closure_status: not_closed
- criteria_count: 16
- full_closure_allowed: False

## 当前结论
REAL005 判定标准已安装并通过自检；当前真实状态是 not_closed，仍需完成 逐年逐题闭环证据。

## Closeout slices
- REAL005A: status=blocked; criteria=RG001, RG002; blockers=RG001 source manifest coverage is still blocked for years: 2020 | RG002 adapter diagnostics are incomplete for years: 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025; next=补齐逐年 paper+answer source anchors and per-year adapter diagnostics before advancing REAL005A.
- REAL005B: status=blocked_by_previous_slice; criteria=RG003, RG004, RG005, RG006, RG007, RG008, RG009; blockers=REAL005A is not yet closed; do not interpret question-structure and review coverage as a closeable slice yet.; next=Only evaluate per-question structure/review closure after REAL005A source+adapter coverage is complete.
- REAL005C: status=blocked_by_previous_slice; criteria=RG010, RG011, RG012, RG013, RG014, RG015, RG016; blockers=REAL005A and REAL005B remain open; usage/export/analysis closure cannot be promoted ahead of earlier slices.; next=Keep REAL005C blocked until source coverage and per-question review closure are both complete.
- REAL005D: status=blocked; criteria=DOCS, README, GO_NO_GO_CARD; blockers=closureStatus remains not_closed; truthful docs must continue to say not_closed; next=Do not rewrite outward completion wording until REAL005A/B/C are all closed.

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
