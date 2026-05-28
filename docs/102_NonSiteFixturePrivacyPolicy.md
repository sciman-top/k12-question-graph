# 102 · 非现场 fixture 与授权/脱敏材料政策

日期：2026-05-28。

## 1. 结论

AI 推荐：NS0-NS9 默认先使用 synthetic fixture 和授权/脱敏材料推进仓库内落地；真实学生数据、未授权版权材料和未脱敏资料不得进入 Git、prompt、fixture、日志、备份包或外部 AI。

理由：非现场能力需要可复跑、可回滚、可审计的证据；现场材料只能在授权、脱敏和删除边界明确后作为 `non_site_validated` 证据，不能作为普通 fixture 混入仓库。

当前落点：`docs/102_NonSiteFixturePrivacyPolicy.md`、`tests/golden-import/privacy_and_license.md`、`sources/raw/.gitignore`。

目标归宿：为 `tasks/non-site-implementation-plan.csv` 的 NS005、NS203、NS705、NS901 和 NS902 提供共同数据边界。

## A. 材料分类

| 分类 | 定义 | 允许位置 | 可证明状态 | 禁止边界 |
|---|---|---|---|---|
| `synthetic_fixture` | 人工构造、无真实学生、无真实学校原文、无版权敏感原文的样例 | `tests/golden-import/`、`tests/e2e/`、临时 `tmp/` | `contract_only`、局部 `repo_landed` 或 `runtime_verified` | 不能单独证明 `non_site_validated` |
| `authorized_anonymized_material` | 有来源授权，且已移除学生姓名、证件号、学号、班级可识别组合、联系方式等 PII 的材料 | 原文放本机 staging 或 ignored `sources/raw/`；Git 只留 hash、摘要、授权边界和证据 | 可用于 `runtime_verified`；端到端闭环后可支撑 `non_site_validated` | 不得把原文或可逆脱敏映射提交进 Git |
| `authorized_real_source_material` | 有来源授权但仍可能含教材、真题、校本试卷或版权敏感表达的资料 | 原文放本机 staging、文件仓库或 ignored source 目录；Git 只留 manifest/evidence 摘要 | 可用于导入、解析、来源证据和质量报告 | 未经授权不得复制传播；不得直接作为公开 fixture |
| `real_student_data` | 学生身份、成绩、班级、学籍、学情、可重识别日志或截图 | 仅在 P001/P002 以后按授权、最小化、保留/删除计划处理 | 不作为 NS0-NS9 默认证据 | 当前阶段不得进入 Git、prompt、外部 AI 或普通日志 |
| `public_or_open_material` | 公共领域或明确可再分发许可的材料 | 可进入 fixture 前仍需记录 license、source URL/hash 和用途 | 可用于 fixture 或 E2E，取决于授权 | 不能把“网上可见”当成“可提交/可训练/可外传” |

## B. 默认使用规则

- 默认 fixture 类型是 `synthetic_fixture`。
- `tests/golden-import/` 只放可提交、可复跑、无 PII、无版权敏感原文的样例。
- 真实或授权脱敏材料的原文默认留在本机 staging、文件仓库或 ignored `sources/raw/`；Git 中只记录来源类型、hash、脱敏说明、授权范围、用途和删除边界。
- `sources/raw/` 是本地暂存区，不是证据归档区；本轮新增 `.gitignore`，防止误提交原始资料。
- 证据文件可以记录命令输出、计数、hash、失败类型和教师效率判断，但不得粘贴完整真题、学生成绩明细、可识别截图或未脱敏原文。
- 如果证据必须引用真实材料，只引用最小片段、定位信息、hash 或人工复核结论；可复现路径放在本机 staging 说明里。

## C. AI 与外部服务边界

- 外部 AI/OCR/云服务默认关闭，只有在授权、成本、缓存、隐私和回滚边界明确后才能作为可禁用路径。
- AI 输出默认只能进入 `candidate`、`draft`、`test` 或 `pending_review`，不得直接写 `active`。
- `real_student_data` 和未脱敏材料不得发送给外部 AI。
- 对授权或脱敏材料使用 AI 时，证据必须记录：模型/路由、输入分类、脱敏状态、输出状态、成本边界、缓存策略和删除/禁用路径。

## D. 完成态判定

- `synthetic_fixture` 通过只能证明合同、解析器或 UI/API 局部能力，不足以把模块标为 `non_site_validated`。
- `repo_landed` 需要指向代码、脚本、UI/API/worker/tool 或可运行 smoke 证据。
- `runtime_verified` 需要真实本机运行证据，且不得依赖未授权材料。
- `non_site_validated` 需要授权或脱敏材料覆盖非现场端到端路径，并记录耗时、失败、接管点、回滚和教师效率。
- 若材料授权、脱敏、删除或外部传输边界不清，任务保持 `planned`、`contract_only` 或 `blocked_by_onsite`，不能靠历史完成态升级。

## E. 检查清单

- 是否没有真实学生姓名、学号、证件号、联系方式、班级花名册、成绩单或可重识别组合。
- 是否没有未授权教材、真题、商业资料、校本试卷原文或大段截图进入 Git。
- 是否记录了 source type、hash、license/authorization、pii boundary、用途和删除边界。
- 是否区分了 synthetic、authorized anonymized、authorized real source 和 real student data。
- 是否确认外部 AI/OCR 默认为关闭，真实或未脱敏材料不外传。
- 是否能用 Git 或本机 staging 删除/回滚本轮新增材料。

## F. 回滚

本政策为文档与本地隔离规则，回滚命令：

```powershell
git restore -- docs/102_NonSiteFixturePrivacyPolicy.md tests/golden-import/privacy_and_license.md tasks/non-site-implementation-plan.csv
git clean -f -- docs/evidence/20260528-ns005-fixture-policy.md sources/raw/.gitignore
```

