# REAL005 广州 2015-2025 真卷全流程闭环判定标准

- status: pass
- closure_status: not_closed
- criteria_count: 12
- full_closure_allowed: False

## 当前结论
REAL005 判定标准已安装并通过自检；当前真实状态是 not_closed，仍需完成 逐年逐题闭环证据。

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
