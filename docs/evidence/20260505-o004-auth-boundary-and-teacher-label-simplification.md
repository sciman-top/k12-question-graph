# O004 权限边界与教师标签简化证据

日期：2026-05-05

## 依据

- I008 已要求普通教师默认面不暴露治理、测试和工程术语。
- O004 已要求 `/api/admin/*` 与 `/internal/ai/*` 在试点或 live 前必须有 authentication/authorization 角色守卫。
- 本轮目标是做小步代码收口，不引入真实登录系统，不改数据库 active 数据。

## 变更

- `apps/api/Program.cs` 新增 `UseAdminInternalEndpointGuard()`：
  - 保护 `/api/admin/*` 与 `/internal/ai/*`。
  - 非开发环境必须配置 `AdminInternalGuard:ApiKey`，请求必须带 `X-KQG-Admin-Key`。
  - 开发 draft/test 只有在 `AdminInternalGuard:AllowUnguardedDraftTest=true` 时才显式放行，并返回 `X-KQG-Auth-Boundary` 响应头。
  - 密钥比较使用 `CryptographicOperations.FixedTimeEquals`。
- `apps/api/appsettings.json` 默认 `AllowUnguardedDraftTest=false`。
- `apps/api/appsettings.Development.json` 显式声明开发 draft/test 可放行。
- `tools/run-o004-admin-internal-auth-boundary-contract.ps1` 新增运行时合同：
  - production + configured key 下，无 key 返回 401。
  - wrong key 返回 403。
  - correct key 返回 200。
- `tools/run-gates.ps1` 纳入 O004 合同。
- `apps/web/src/ui/teacherLabels.ts` 集中教师可见标签映射。
- `tools/run-i008-teacher-simplification-contract.ps1` 追加检查集中教师标签文件。

## 验证

```powershell
dotnet build apps\api\K12QuestionGraph.Api.csproj
npm --prefix apps\web run build
npm --prefix apps\web run lint
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-o004-admin-internal-auth-boundary-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-i008-teacher-simplification-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-local-first-ai-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-roadmap-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-gates.ps1
```

结果：全部 pass。`tools/run-gates.ps1` 覆盖 backend build、frontend build/lint、I001-I008、O004、J/K/C/D/E/F/G 合同、P1 API smoke、P1 proxy scenario 和 backup verify。

## 回滚

- 代码和配置默认 Git 回滚。
- 本轮未执行 DB migration、active 切换、真实 AI 调用或真实学生数据写入。
- 若 O004 守卫影响本机开发，应只检查 `appsettings.Development.json` 的 `AllowUnguardedDraftTest`，不要把 production 默认改成放行。
