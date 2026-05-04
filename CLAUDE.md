# CLAUDE.md — k12-question-graph（Claude 项目级 wrapper）
**项目**: k12-question-graph
**类型**: K-12 teacher-first question graph platform
**承接来源**: `GlobalUser/CLAUDE.md v9.52`
**共同项目规则**: `AGENTS.md`（下方独立 import 行）
**适用范围**: 项目级（仓库根）
**最后更新**: 2026-05-04

@AGENTS.md

## 1. 阅读指引
- 本文件通过上方 import 承接 k12-question-graph 的共同项目规则，只追加 Claude Code 差异。
- `AGENTS.md` 中的 `## B. Codex 平台差异` 只适用于 Codex；Claude 以本文件后续 `## B. Claude 平台差异` 为准。
- 不在本文件复制项目事实、门禁、证据、回滚或 `Global Rule -> Repo Action`；若共同规则要变，先改控制仓 `rules/projects/k12-question-graph/codex/AGENTS.md` 源文件并同步。
- 合并后的有效上下文必须能推出：当前落点、目标归宿、门禁顺序、证据路径和回滚入口。

## B. Claude 平台差异
- Claude Code 读取 `CLAUDE.md`；本文件用 `AGENTS.md` import 承接共同规则，下面只写 Claude 差异。
- `AGENTS.md` import 相对本文件解析；若 import 失败或未加载，先用 `/memory`、`/status` 或当前 help 取证。
- `CLAUDE.md` 是上下文，不是权限系统；敏感文件读取、工具限制、permission mode、sandbox、hooks 和环境变量必须落到 `.claude/settings*.json`、managed settings、hooks、MCP 或 CI。
- `.claude/settings.json`、`.claude/hooks/` 中受管部分由控制仓治理下发；漂移时先整合 provenance，不在本文件复制 settings 或 hooks 规则。
- `CLAUDE.local.md` 只放本机个人偏好并保持 gitignored；不得作为项目规则真源。
- 只适用于局部路径的 Claude 规则放 `.claude/rules/` 并用 `paths` frontmatter 限定；无 `paths` 的规则会常驻上下文。
- `--bare` 会跳过 `CLAUDE.md` 自动发现；使用该模式时必须显式提供本文件或 `AGENTS.md`。
- 修改 permissions、hooks、settings 或 tool matcher 时，先按当前 schema/help 验证语法；不要猜测通配符或工具名。
- 多文件高不确定性任务可先用 plan mode；低风险文档/规则修复保持 direct fix。

## D. 维护校验
- 本 wrapper 不改写 `AGENTS.md` 的 A/C/D 项目事实；如发现共同规则与 Claude 差异冲突，先按代码、gate 和 `AGENTS.md` 事实定位，再回写控制仓源文件。
