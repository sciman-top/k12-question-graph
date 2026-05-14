# REAL003 广州 2016-2025 真卷批量 dry-run

- status: dry_run_pass
- task: REAL003
- dry_run_only: true
- years_checked: [2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025]
- total_questions: 210
- total_answers: 210
- external_ai_calls: 0
- active_write: false

## 年度结果
- 2016: questions=24/24; answers=24/24; source_hashes=3; blockers=none
- 2017: questions=24/24; answers=24/24; source_hashes=3; blockers=none
- 2018: questions=24/24; answers=24/24; source_hashes=3; blockers=none
- 2019: questions=24/24; answers=24/24; source_hashes=3; blockers=none
- 2020: questions=24/24; answers=24/24; source_hashes=2; blockers=none
- 2021: questions=18/18; answers=18/18; source_hashes=3; blockers=none
- 2022: questions=18/18; answers=18/18; source_hashes=4; blockers=none
- 2023: questions=18/18; answers=18/18; source_hashes=3; blockers=none
- 2024: questions=18/18; answers=18/18; source_hashes=5; blockers=none
- 2025: questions=18/18; answers=18/18; source_hashes=4; blockers=none

## 接管与回滚
- 所有候选题保持 pending_review，不写 active。
- 逐年 rollbackSql 已写入 JSON report。
- REAL003 只证明批量 dry-run 计划和来源/答案覆盖，不证明教师验收。
