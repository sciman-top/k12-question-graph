# ADR-015: Proportionate verification and curated current evidence

**状态**: accepted
**日期**: 2026-10-26

## 背景

旧的 Slice 路由只选模块，随后运行整个模块的测试：只改一个 API 文件也会执行全部 266 个 API 测试；前端也同样重跑全量 Vitest。实际测量和仓库历史都表明，这种“选模块但不选测试”的方式让日常编码被无关验证占满，而治理文档仍规定逐 task 的验证字段，形成第二套选择逻辑。

同时，`CloseoutInvariants.psm1` 虽已集中共享检查，roadmap、evidence index、closeout、remote evidence 和 no-active-write 仍各自重复读取 CurrentClosure 与 Release 卡。证据目录保留大量同结论的历史快照，增加了审计难度，却没有持续提供新的验收事实。

## 决定

1. 日常 Slice 默认按变更模块运行，显式 `-FocusedTests` 时再使用计划 `tools/verification/TestSelection.psm1` 选择直接相关测试。无法形成封闭、唯一映射的共享契约、入口和未知源码仍回退模块全量。CI 的聚焦测试失败可回退模块全量；真实聚焦断言失败不会被静默掩盖。
2. 验证选型只有一个机器真源：`configs/verification/slice-selection.rules.json` 的 changed-path 规则与 focused-test 选择器；不再要求逐 task 维护第二套 `verification_profile` 字段。
3. 当前收口状态只由 `tools/verification/CurrentTruth.psm1` 读取和校验。`docs/evidence/index.json` 是 current evidence 的唯一路由；下游 guard 消费该 receipt，不重复重述同一组 `REAL005`、P001-P006、`No-Go` 事实。
4. 证据持续保留在 Git 历史，但 `docs/evidence/` 采用 current-first：同结论的重复执行更新 current receipt，不新增日期化快照；只有来源、commit、环境或验收边界发生实质变化时才新增历史记录。
5. 备份恢复、确认包和选择器回归必须由对应脚本路由实际执行；只写了回归脚本而没有调用入口，不算覆盖。

## 后果

- 单模块编码缩短反馈闭环，共享或高风险变更仍保持保守回退。
- 当前状态可追溯到单一 receipt；历史记录不再参与默认判断。
- 新模块如果没有可界定的直接测试，会显式走全量，不冒漏测风险。
- CI 需要 PowerShell 7；仓库已声明 Windows 自动化默认使用 `pwsh`。
