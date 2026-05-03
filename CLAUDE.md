# CLAUDE.md - k12-question-graph Claude Project Rules
**承接来源**: `GlobalUser/CLAUDE.md v9.51`
**共同项目规则**: `@AGENTS.md`
**适用范围**: 项目级（仓库根）
**最后更新**: 2026-05-04

## 1. 阅读指引
- 本文件通过 `@AGENTS.md` 承接 k12-question-graph 的共同项目规则，只追加 Claude Code 差异。
- 不在本文件复制项目事实、门禁、教师效率准入或动态资产规则；若共同规则要变，先改控制仓 `rules/projects/k12-question-graph/codex/AGENTS.md` 源文件并同步。
- 合并后的有效上下文必须能推出：当前落点、目标归宿、门禁顺序、证据路径和回滚入口。

## B. Claude 平台差异
- Claude Code 读取 `CLAUDE.md`；本文件用 `@AGENTS.md` import 共同规则，下面只写 Claude 差异。
- `CLAUDE.md` 是上下文，不是权限系统；阻断敏感文件读取、限制工具或固定 permission mode 时，修改 `.claude/settings*.json`、managed settings 或 hooks。
- `.claude/settings.json`、`.claude/hooks/` 中受管部分由控制仓一键治理下发；漂移时先整合 provenance，不在本文件复制 settings 或 hooks 规则。
- `CLAUDE.local.md` 只放本机个人偏好并保持 gitignored；不得作为项目规则真源。
- `--bare` 会跳过 `CLAUDE.md` 自动发现；使用该模式时必须显式提供本文件或 `AGENTS.md`。
- 交互诊断优先 `/status`、`/memory` 和 settings 来源；非交互时记录 `platform_na`，并用 `claude --version`、`claude --help`、文件路径和本轮读取证据替代。
- 修改 permissions、hooks、settings 或 tool matcher 时，先按当前 schema/help 验证语法；不要猜测通配符或工具名。
- 多文件编码任务可以先用 plan mode；低风险文档/规则修复保持 direct fix。

## D. 维护校验
- 本 wrapper 不改写 `AGENTS.md` 的 A/C/D 项目事实；如发现共同规则与 Claude 差异冲突，先按代码、gate 和 `AGENTS.md` 事实定位，再回写控制仓源文件。
