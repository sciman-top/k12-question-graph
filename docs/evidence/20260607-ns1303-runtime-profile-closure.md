# 2026-06-07 · NS1303 运行画像与配置差异闭环

## Goal

把 `NS1303` 从“已有分散诊断脚本”收口成一份可复跑、可被安装器/控制面板消费的运行画像证据：

- 复跑只读 `host capability diagnostic`
- 复跑只读 `worker profile diagnostic`
- 生成 `localSystemProfile + workerOcrProfile + aiNetworkProfile + aiLocalModelProfile + searchProfile + queueProfile` 的 draft config diff

## Changes

- `tools/run-ns1303-runtime-profile-contract.ps1`
  - 新增 `NS1303` guard，汇总 host/worker 诊断并输出 draft overlay diff。
- `tools/run-gates.ps1`
  - 接入 `NS1303`。
- `tools/README.md`
  - 补充 `NS1303` 入口和边界说明。
- `docs/evidence/20260607-ns1303-worker-profile-diagnostic-report.json`
- `docs/evidence/20260607-ns1303-host-capability-diagnostic-report.json`
- `docs/evidence/20260607-ns1303-runtime-profile.json`
  - 形成可复跑的配置差异证据。

## Verification

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-ns1303-runtime-profile-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-automation-first-feature-contract-guard.ps1
```

结果：

- `NS1303`: `pass`
- `run-roadmap-guard.ps1`: `pass`
- `run-automation-first-feature-contract-guard.ps1`: `pass`

## Decision

- `tasks/non-site-implementation-plan.csv`
  - `NS1303 -> runtime_verified`
- `tasks/productization-roadmap.csv`
  - `NS1303 -> 已完成`
- `tasks/backlog.csv`
  - 暂不改顶层 `NS13` 状态，继续保留为主线入口。

## Risks

- 当前输出的是 `draft_overlay_only`，不代表已自动写入 `appsettings.json` 或控制面板真实保存配置。
- 仍未替代目标机上的系统服务安装、驱动/runtime 变更、云 token 配置、本地模型下载和生产默认切换。

## Rollback

```powershell
git restore tasks/non-site-implementation-plan.csv tasks/productization-roadmap.csv tools/run-gates.ps1 tools/README.md
Remove-Item -LiteralPath docs/evidence/20260607-ns1303-runtime-profile-closure.md -Force
Remove-Item -LiteralPath docs/evidence/20260607-ns1303-runtime-profile.json -Force
Remove-Item -LiteralPath docs/evidence/20260607-ns1303-host-capability-diagnostic-report.json -Force
Remove-Item -LiteralPath docs/evidence/20260607-ns1303-worker-profile-diagnostic-report.json -Force
Remove-Item -LiteralPath tools/run-ns1303-runtime-profile-contract.ps1 -Force
```
