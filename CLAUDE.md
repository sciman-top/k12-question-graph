# CLAUDE.md - K12 Question Graph Project Rules

**承接来源**: `GlobalUser/CLAUDE.md v9.50`
**共同项目规则**: `@AGENTS.md`
**最后更新**: 2026-05-04

## Claude Code 差异

- Claude Code 读取 `CLAUDE.md`，不自动读取 `AGENTS.md`；本文件通过 `@AGENTS.md` 承接共同项目规则，下面只写 Claude 差异。
- 保持本文件短小；项目事实、门禁、P0/P1 范围和教师效率准入以 `AGENTS.md` 为准。
- 本仓已纳入 `governed-ai-coding-runtime` 目标仓 catalog；`.claude/settings.json` 与 `.claude/hooks/` 中的受管部分由控制仓一键治理下发，漂移时先整合 provenance，不在本文件复制 settings 或 hooks 规则。
- 若使用 `--bare`，Claude 会跳过 `CLAUDE.md` 自动发现；必须显式提供本文件或 `AGENTS.md`。
- 本仓已初始化 Git；开始代码级或多文件结构性变更前，必须先查看 `git status --short --branch`，并按 `AGENTS.md` 的回滚规则处理。
- 需要阻断敏感文件读取、限制工具或固定 permission mode 时，修改 `.claude/settings*.json`、managed settings 或 hooks，不要只在本文件追加自然语言规则。
- 交互诊断优先 `/status`、`/memory` 和当前 settings 来源；非交互时记录 `platform_na` 并用 `claude --version`、`claude --help`、文件路径和本轮读取证据替代。
- 修改 permissions、hooks、settings 或 tool matcher 时，先按当前 schema/help 验证语法；不要猜测通配符或工具名。
- 多文件编码任务可以先用 plan mode；低风险文档/规则修复保持 direct fix。
