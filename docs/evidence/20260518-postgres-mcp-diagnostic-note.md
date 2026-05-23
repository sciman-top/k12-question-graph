# 2026-05-18 Postgres MCP Diagnostic Note

规则ID=R1/R4/R8/E5
风险等级=低；仅文档说明，不修改数据库、MCP 配置、凭据、应用代码或 gate。

## 变更

- 在 `README.md` 的“当前启动与门禁”补充本机 `postgres` MCP 与本仓 PostgreSQL 数据库的关系。
- 明确当前本机验证目标为 `127.0.0.1:5432/k12_question_graph`。
- 明确不在仓库、日志或证据中写入明文密码或完整连接串。
- 明确 `postgres` MCP 仅用于代理侧只读诊断和排障，不是 API、Web、gate、安装器或现场发布的运行前置。

## 依据

- `D:\CODE\skills-manager` 中的 `postgres` MCP 已通过 wrapper、tools/list 和只读 query 验证。
- 只读验证结果显示 `current_database()` 为 `k12_question_graph`。
- 本仓已有运行入口仍以 `KQG_CONNECTION_STRING`、`PGPASSWORD`、pgpass 和本仓脚本为准。

## 验证

- docs-only 变更，无 build/test/full gate 需求。
- 替代验证：`git diff --check`。

## 回滚

- `git checkout -- README.md docs/evidence/20260518-postgres-mcp-diagnostic-note.md`
