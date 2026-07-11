# 全仓深审问题台账（2026-06-24）

## 兼容边界
- HTTP 路由名、成功响应字段、数据库 / migration 语义、`C002/C002R` 生命周期、证据 JSON/CSV/YAML 结构、教师主工作流默认不变。
- 本轮允许的外部可见变化仅限：更清晰的错误响应、更严格的 fail-closed、更稳定的异常处理、更安全的依赖版本。

## Critical
- 无。

## High
- [apps/api/Program.cs](/D:/CODE/k12-question-graph/.worktrees/codex/full-repo-hardening/apps/api/Program.cs) 约 6500 行，路由、DTO、helper、配置扩展、管理员 AI 设置与安全守卫混杂，触发条件是任一功能增量修改；风险是回归范围失控、异常路径遗漏、难以补测试。建议分离共享 helper、管理员 AI 设置、健康检查/存储辅助和 endpoint registration。验证：`dotnet build apps/api/K12QuestionGraph.Api.csproj`。
- [apps/web/src/App.tsx](/D:/CODE/k12-question-graph/.worktrees/codex/full-repo-hardening/apps/web/src/App.tsx) 约 2000 行，容器、状态、真实 API 交互和 UI 混杂；触发条件是任一教师工作流或真卷复核变更；风险是状态耦合、失败态静默错误、合同锚点难维护。建议拆分 shell、feature container 和 workflow hooks。验证：`npm --prefix apps/web run lint`、`npm --prefix apps/web run build`。
- 当前缺少常规后端 / 前端测试项目，主要依赖脚本 smoke；触发条件是 API/前端字段或状态机微调；风险是脚本未覆盖时静默回归。建议补最小单测基线，优先覆盖 contracts、worker 和共享 helper。验证：新增 `dotnet test`、前端测试命令。
- `tools/` 下存在多处 `catch {}` 静默吞错；触发条件是本地 API 探活、清理、回滚恢复失败；风险是错误被掩盖，脚本报告假通过。建议限定仅对探活轮询保留吞错，其余场景改为显式说明或记录失败。验证：PowerShell parse sweep + 代表性 smoke。
- 前端依赖 `vite 8.0.10` 命中 Windows 安全告警；触发条件是本地 dev server/Windows 路径处理；风险是已知漏洞继续留存。建议升级到包含补丁的 `8.0.16+`。验证：`npm audit`、`npm --prefix apps/web run build`。

## Medium
- [workers/document/worker.py](/D:/CODE/k12-question-graph/.worktrees/codex/full-repo-hardening/workers/document/worker.py) 解析能力集中在单文件，异常返回与临时目录清理主要靠局部 `finally`；建议补 fixture 级测试和更明确的错误分类。
- [apps/web/src/api/client.ts](/D:/CODE/k12-question-graph/.worktrees/codex/full-repo-hardening/apps/web/src/api/client.ts) 重复请求封装较多，HTTP 失败与响应结构失败都映射成宽泛 `network_error`；建议统一为共享 request helper，区分 `network_error` / `http_error` / `invalid_response`。
- [apps/web/src/api/contracts.ts](/D:/CODE/k12-question-graph/.worktrees/codex/full-repo-hardening/apps/web/src/api/contracts.ts) 解析器过大且默认值偏宽松；风险是接口字段漂移被静默吞掉。建议拆出 reader helper 和针对关键 contract 的回归测试。
- [tools/run-repo-preflight.ps1](/D:/CODE/k12-question-graph/.worktrees/codex/full-repo-hardening/tools/run-repo-preflight.ps1) 内嵌本地 API 检测、暂停和恢复逻辑，`run-gates.ps1` 也重复实现类似流程；建议抽共享 helper。

## Low
- 若干 DTO/Response record 仍与路由同处一个文件，短期可用但不利于维护；在大文件拆分阶段顺带外提即可。
- `tests/` 目前主要是 fixture 与 manifest，结构清晰但缺少执行型测试入口；作为本轮测试基线补齐。
