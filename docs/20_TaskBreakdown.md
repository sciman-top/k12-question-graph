# 20 · AI 可执行任务拆解规范

本文件不再复制全部历史任务和 evidence。任务顺序、依赖和状态以 `tasks/backlog.csv` 为唯一机器真源；当前队列看 `tasks/todo.md`；已完成切片的详细事实由对应文档、evidence 和 Git 历史追溯。

## 1. 任务粒度

任务应是边界清晰、风险可控、可验证、可回滚的最大合理切片。不要机械拆成文件级小任务，也不要把产品功能、治理重构、现场验收和发布混成一个切片。

## 2. 必填字段

每个可编码任务必须声明：

- task ID、parent、objective 和 user outcome；
- current truth、preconditions 和 depends_on；
- in scope、out of scope、write-set 和 protected paths；
- implementation steps 和兼容要求；
- acceptance criteria；
- Quick/Slice/Release/Onsite profile；
- focused/stateful verifier 和副作用；
- evidence policy；
- rollback、truth boundary 和 next task。

Automation-first 是所有待办的必填合同：每个 open task 必须在 `tasks/automation-first-contract.csv` 中声明 deterministic precheck、dedicated surface、AI/agent 允许范围、exception policy 和 evidence command；缺少覆盖的待办任务不得继续实现。

## 3. 完成条件

只有同时满足以下条件才能标记 repo-side 完成：

1. write-set 内实现已落盘；
2. focused verification 新鲜通过；
3. contract/invariant/hotspot 有真实证据；
4. 文档和机器任务状态已同步；
5. 不存在未说明的兼容、数据、隐私或回滚缺口；
6. 完成声明未越过 repo-side/release/onsite/live 边界。

## 4. 阻断分流

- 外部授权、版权、真实身份签字、生产 active：fail-closed，记录外部阻断。
- stateful gate 未授权：记录完整 `gate_na`，继续无状态替代验证。
- verifier 本身失败：先区分产品失败、环境失败和门禁缺陷。
- 多真源冲突：先核代码、运行事实和 backlog，再修投影。
- same issue 连续失败两次：转 clarify_required，不继续堆补丁。

## 5. NS1306 AI/agent 工具执行合同

`configs/agent-tool-orchestration.allowlist.json` 是工具与 runbook 准入真源。AI/agent 只承担外层编排、调用、结果汇总和异常分流，只能调用 manifest 中的 allowlisted tool/runbook；所有未列入项默认拒绝，不得从文档描述推导额外权限。

production active write、restore apply、release decision 和真实学生数据外传必须取得明确人工审批。工具不可用、前置条件不满足或输出合同失败时，agent 必须 fail-closed，保留失败证据并回到对应任务，不能自动越过准入、数据、发布或现场验收边界。

## 6. 当前任务族

- VGOV-001..010：验证治理减负已完成并退出活跃合同；日常入口为 changed-path Slice，Release 为 focused core，legacy monolith 与兼容审计已删除。
- P001..P006：真实现场与发布闭环。
- Q001..Q005、R001..R007：P006 后触发式 Later。

详细顺序、状态、验收和 verifier 见 `tasks/backlog.csv`。

## 7. 历史任务

旧 A/B/C/D/E/F/G、S、NS、REAL 和 CEK 的长篇实施记录不再在本文件重复维护。需要追溯时按 task ID 搜索：

```powershell
rg -n "<TASK_ID>" tasks docs tools tests apps
```

历史“已完成”只证明当时记录的层级，不能自动推导当前 production/live 状态。
