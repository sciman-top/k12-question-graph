# GEMINI.md - K12 Question Graph Project Rules

**承接来源**: `GlobalUser/GEMINI.md v9.48`
**共同项目规则**: `@AGENTS.md`
**最后更新**: 2026-05-02

## Gemini CLI 差异

- Gemini CLI 默认读取 `GEMINI.md`；本文件通过 `@AGENTS.md` 承接共同项目规则，下面只写 Gemini 差异。
- 保持本文件短小；项目事实、门禁、P0/P1 范围和教师效率准入以 `AGENTS.md` 为准。
- 本仓当前不是 Git 仓库；Gemini 的项目根识别通常依赖 `.git`，因此在初始化 Git 前必须从 `D:\CODE\k12-question-graph` 启动，并用 footer 或 `/memory show` 确认本文件已加载。
- 修改 `.geminiignore`、`context.fileName`、policy 或 settings 后，必须重启 Gemini CLI 或用 `/memory refresh` 复核实际加载。
- 不要用 `/memory add` 写入项目临时规则；它会追加到全局 `~/.gemini/GEMINI.md`。
- 权限和危险命令拦截优先使用 approval mode、policy engine、hooks、checkpoint/restore 或 CI；`GEMINI.md` 只写行为和验收。
- `plan` 适合 A000/A000A 研究和契约收口；转执行前重新确认风险、门禁和回滚。`yolo` 不作为本仓默认模式。
