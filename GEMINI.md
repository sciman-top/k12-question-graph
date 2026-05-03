# GEMINI.md - K12 Question Graph Project Rules

**承接来源**: `GlobalUser/GEMINI.md v9.50`
**共同项目规则**: `@AGENTS.md`
**最后更新**: 2026-05-04

## Gemini CLI 差异

- Gemini CLI 默认读取 `GEMINI.md`；本文件通过 `@AGENTS.md` 承接共同项目规则，下面只写 Gemini 差异。
- 保持本文件短小；项目事实、门禁、P0/P1 范围和教师效率准入以 `AGENTS.md` 为准。
- 本仓已纳入 `governed-ai-coding-runtime` 目标仓 catalog；Gemini 项目规则仍只通过本文件与 `@AGENTS.md` 承接，不从 `.governed-ai/` 自动加载项目规则。
- 本仓已初始化 Git；Gemini 的项目根识别通常依赖 `.git`，仍建议从仓库根或明确工作目录启动，并用 footer、`/memory show` 或 `/memory list` 确认本文件与 `AGENTS.md` import 已加载。
- 修改 `.geminiignore`、`context.fileName`、policy 或 settings 后，必须重启 Gemini CLI 或用 `/memory refresh` 复核实际加载。
- 不要用 `/memory add` 写入项目临时规则；它会追加到全局 `~/.gemini/GEMINI.md`。
- 权限和危险命令拦截优先使用 approval mode、policy engine、hooks、checkpoint/restore 或 CI；`GEMINI.md` 只写行为和验收。
- `checkpoint/restore` 只有在当前 settings 已启用时才能作为回滚证据；否则按 `AGENTS.md` 使用 Git、备份或补丁回滚。
- `plan` 适合 A000/A000A 研究和契约收口；转执行前重新确认风险、门禁和回滚。`yolo` 不作为本仓默认模式。
