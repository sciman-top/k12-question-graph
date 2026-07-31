# 课程标准与考情 C002R 生产激活决策记录

- 决策：`NO-GO`
- 候选修订：`cek024_curriculum_exam_candidate_v1`
- 决策时间：`<yyyy-MM-ddTHH:mm:sszzz>`
- 管理员：`<authenticated-admin-id>`
- 教师审核记录：`<evidence-link>`
- 备份 manifest：`<verified-manifest-path>`
- 影响报告：`docs/evidence/cek024-curriculum-exam-c002r-plan.json`
- 隔离演练：`docs/evidence/cek027-curriculum-exam-c002r-isolated-drill.json`

## 硬门禁

- [ ] 真实教师审核已完成，所有 968 个审核对象均有可追溯决定和理由。
- [ ] 管理员身份认证与授权已由系统证明，不以请求中的 `reviewer/actorRole` 代替。
- [ ] CEK-20 ErrorPattern 候选已持久化并完成独立审核，或有明确的版本化排除决定。
- [ ] CEK-33 浏览器、桌面/移动视觉和证据回看验收通过。
- [ ] CEK-34 full gate 在当前环境重新确认影响后通过。
- [ ] backup manifest、六类 rollback snapshot 和恢复命令均已复核。
- [ ] `REAL005`、现场验收和 release Go/No-Go 状态与实际一致。

任一项未满足时保持 `NO-GO`。CEK-27 的 `drill_reviewer` 只证明隔离回滚机制，不构成教师审核或生产授权。

## 生产切换

本模板不包含可直接执行的生产切换命令。只有全部硬门禁满足、另获用户明确授权后，才生成绑定精确数据库、候选版本、备份 manifest 和回滚窗口的一次性管理员命令。

## 回滚判据

- active 资产、映射、目标、画像及历史分析指纹恢复到切换前值。
- 题目、试卷、导出、成绩模板和历史分析不发生静默重写。
- 回滚后重新运行健康检查、历史版本解释合同和受影响产品门禁。
