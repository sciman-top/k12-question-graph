# GEMINI.md — k12-question-graph（Gemini 项目级 wrapper）
**项目**: k12-question-graph
**类型**: K-12 teacher-first question graph platform
**承接来源**: `GlobalUser/GEMINI.md v9.52`
**共同项目规则**: `AGENTS.md`（下方独立 import 行）
**适用范围**: 项目级（仓库根）
**最后更新**: 2026-05-04

@AGENTS.md

## 1. 阅读指引
- 本文件通过上方 import 承接 k12-question-graph 的共同项目规则，只追加 Gemini CLI 差异。
- `AGENTS.md` 中的 `## B. Codex 平台差异` 只适用于 Codex；Gemini 以本文件后续 `## B. Gemini 平台差异` 为准。
- 不在本文件复制项目事实、门禁、证据、回滚或 `Global Rule -> Repo Action`；若共同规则要变，先改控制仓 `rules/projects/k12-question-graph/codex/AGENTS.md` 源文件并同步。
- 合并后的有效上下文必须能推出：当前落点、目标归宿、门禁顺序、证据路径和回滚入口。

## B. Gemini 平台差异
- Gemini CLI 默认读取 `GEMINI.md`；本文件用 `AGENTS.md` import 承接共同规则，下面只写 Gemini 差异。
- 从仓库根或明确工作目录启动，并用 footer、`/memory show` 或当前可用的 `/memory` 帮助确认本文件与 `AGENTS.md` import 已加载。
- 修改 `.geminiignore`、`context.fileName`、policy 或 settings 后，必须重启 Gemini CLI 或用 `/memory reload`（若当前 help 显示 refresh 则用 refresh）复核实际加载；不支持时记录 `platform_na` 和替代证据。
- 如果 `context.fileName` 已配置同时加载 `AGENTS.md` 与 `GEMINI.md`，必须用 `/memory show` 证明没有重复加载；如重复，先调整 import 或配置再继续。
- 不要用 `/memory add` 写入项目临时规则；它会追加到全局 `~/.gemini/GEMINI.md`。
- 启用 Trusted Folders 时，未受信目录可能禁用项目 settings、`.env`、extensions、工具自动批准和自动 memory；先确认 trust 状态再判断规则失效。
- 权限和危险命令拦截优先使用 approval mode、policy engine、hooks、checkpoint/restore 或 CI；`GEMINI.md` 只写行为和验收。
- `checkpoint/restore` 只有在当前 settings 已启用时才能作为回滚证据；否则按 `AGENTS.md` 使用 Git、备份或补丁回滚。
- `plan` 适合研究和契约收口；转执行前重新确认风险、门禁和回滚。`yolo` 不作为默认模式。

## D. 维护校验
- 本 wrapper 不改写 `AGENTS.md` 的 A/C/D 项目事实；如发现共同规则与 Gemini 差异冲突，先按代码、gate 和 `AGENTS.md` 事实定位，再回写控制仓源文件。
