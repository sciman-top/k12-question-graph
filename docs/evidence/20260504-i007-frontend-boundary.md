# I007 server-state 与 typed API boundary 证据

## Goal
- 当前落点：`apps/web/src/api/`、`apps/web/src/state/`、`apps/web/src/main.tsx`、`apps/web/src/App.tsx`、`apps/web/vite.config.ts`、`tools/run-i007-frontend-boundary-contract.ps1`。
- 目标归宿：前端明确 TanStack Query 只管理 server state；教师草稿仍是 UI 本地状态；高风险操作以 API contract 为事实源；UI 不直接依赖裸 JSON。
- 本轮 slice：前端边界和构建优化；仅新增 npm 依赖 `@tanstack/react-query`，不改数据库、真实资料、真实 AI、权限、备份恢复或 active switch。

## Changes
- 新增 `api/contracts.ts`：定义 `apiContractSnapshot`、`ApiResult<T>`、`ReadyHealthContract` 和 response normalizer。
- 新增 `api/client.ts` 与 `api/queries.ts`：`fetch` 返回 typed `ApiResult`，`useReadyHealthQuery` 作为 server-state 示例。
- 新增 `state/queryClient.ts` 与 `state/uiState.ts`：集中创建 `QueryClient`，明确 UI 草稿和高风险操作状态归属。
- `main.tsx` 接入 `QueryClientProvider`。
- `App.tsx` 展示服务状态和 `frontend-state-boundary` 合同条。
- `vite.config.ts` 使用 `manualChunks` 拆分 `react-vendor`、`antd-vendor`、`query-vendor` 和通用 vendor，处理 Vite chunk warning。

## Verification
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-i007-frontend-boundary-contract.ps1`
- `npm run build`
- `npm run lint`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gates.ps1`

## Risk And Rollback
- 风险等级：中。新增前端供应链依赖 `@tanstack/react-query`，但不触碰生产数据和后端行为。
- 供应链验证：`npm install` 后 `npm audit` 报告 `found 0 vulnerabilities`。
- 兼容性：typed boundary 是增量引入；现有教师 UI 行为保留。
- 回滚：Git 回滚上述文件，并回滚 `apps/web/package.json` 与 `apps/web/package-lock.json`。
