# 105 · 角色审批与例外矩阵

日期：2026-06-06。

## 1. 角色定义

| 角色 | 主要职责 |
|---|---|
| 普通教师 | 导入、审核、组卷、成绩、分析等高频任务 |
| 备课组长 | 组内题库质量、共享与审核协同 |
| 审核员 | 候选结果复核、退回、审计抽查 |
| 管理员 | 系统配置、备份恢复、权限、激活、发布前置 |
| 试点支持负责人 | 现场支持、故障接管、回滚执行、发布现场协调 |
| 数据责任方代表 | 确认真实数据授权、对外传输边界和发布责任 |

## 2. 高风险动作审批矩阵

| 动作 | 执行角色 | 必要复核 | 最低证据 | 回滚入口 |
|---|---|---|---|---|
| 上传授权或脱敏来源资料到 `SourceDocument` | 普通教师 / 备课组长 / 管理员 | 来源不清或校级共享前需备课组长或管理员复核 | 来源类型、授权边界、hash、传播限制 | 删除测试数据或恢复 `SourceDocument/FileAsset` snapshot |
| 题目确认、合并、拆分、重裁、保存 | 普通教师 / 审核员 | 高风险批量操作需审核日志抽查 | audit、来源回看、失败接管记录 | 撤销、修订历史、source region audit |
| 候选知识资产审核 apply | 审核员 / 备课组长 | 管理员复核激活前阻断项 | review decision、impact report、rollback snapshot | candidate rollback / reviewed rollback |
| `active switch` 或生产默认版本切换 | 管理员 | 数据责任方代表或发布负责人复核 | backup manifest、active guard、变更说明、回滚快照 | active rollback snapshot |
| AI provider/profile 启用或默认切换 | 管理员 | AI 负责人或发布负责人复核 | profile diff、eval、成本、隐私、no-active-write、secret redaction | 禁用 profile / 恢复旧 profile |
| 生产 restore / 覆盖式恢复 | 管理员 + 试点支持负责人 | 数据责任方代表复核 | restore drill、恢复窗口、受影响范围、回滚说明 | restore manifest / pre-restore backup |
| 进入现场试点 | 试点支持负责人 | 数据责任方代表 + 发布负责人复核 | `P003/P004` 证据、授权、支持人、回滚路径 | 试点停止、版本回退、数据 restore |
| `P006` 发布裁决 | 发布负责人 | 数据责任方代表 + 管理员复核 | `docs/109_ReleaseGoNoGoCard.md`、gate、backup/restore、效率、隐私、权限 | 撤销 tag candidate、恢复上一个发布包 |

## 3. 普通教师不得单独执行的动作

- `active switch`
- provider 默认切换
- 生产 restore
- 发布裁决
- 关闭隐私或 no-active-write 守卫
- 扩大普通教师默认可见治理面

## 4. 例外处理

只有在小团队或现场应急场景中，单人兼任多角色才允许走例外。例外记录必须包含：

| 字段 | 要求 |
|---|---|
| `exception_id` | 唯一编号 |
| `reason` | 为什么不能按正常双角色链执行 |
| `scope` | 只影响哪一个动作和哪一段时间 |
| `owner` | 谁对例外负责 |
| `expires_at` | 到期时间 |
| `recovery_plan` | 如何回到常规审批链 |
| `evidence_link` | 证据路径 |

## 5. 实施规则

1. 权限模型、UI 显示面和运行脚本必须同时遵守本矩阵。
2. 若脚本、API 或 UI 允许了更宽权限，以更严格的矩阵为准，并修复实现。
3. 现场试点前必须把本矩阵映射到 `P003-P006` 证据中。
