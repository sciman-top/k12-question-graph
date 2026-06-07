# 2026-06-07 · NS1304 工具链准入闭环

## Goal

把 `NS1304` 收口成一份可机读、可复跑的开源/免费工具链准入证据：

- 建立 `toolchain admission catalog`
- 复用 `NS1303` 运行画像、`J005/J006`、`NS304/NS305/NS306`
- 对当前主机输出 admitted / blocked / fallback 结论

## Changes

- `configs/toolchain-admission.catalog.yaml`
  - 新增开源/免费工具链 catalog。
- `tools/run-ns1304-toolchain-admission-contract.ps1`
  - 新增 admission contract，探测 CLI / Python module，并回写 fail-closed 结论。
- `tools/run-gates.ps1`
  - 接入 `NS1304`。
- `tools/README.md`
  - 补充 `NS1304` 入口和边界说明。
- `docs/evidence/20260607-ns1304-toolchain-profile.json`
  - 输出当前 host 的工具链准入结果。

## Verification

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-ns1304-toolchain-admission-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-automation-first-feature-contract-guard.ps1
```

结果：

- `NS1304`: `pass`
- `run-roadmap-guard.ps1`: `pass`
- `run-automation-first-feature-contract-guard.ps1`: `pass`

## Decision

- `tasks/non-site-implementation-plan.csv`
  - `NS1304 -> runtime_verified`
- `tasks/productization-roadmap.csv`
  - `NS1304 -> 已完成`
- `tasks/backlog.csv`
  - 暂不改 `NS13` 顶层待办状态。

## Risks

- 当前 host 仍缺 `Docling`、`PaddleOCR`、`OCRmyPDF`、`qpdf`、`Ghostscript`、`libvips`，因此只能维持 lighter profile 或人工接管，不宣称完整重型 OCR / PDF 工具链就绪。
- `ImageMagick` 当前只是 `available_but_not_admitted`，还没有被提升为默认链路。

## Rollback

```powershell
git restore tasks/non-site-implementation-plan.csv tasks/productization-roadmap.csv tools/run-gates.ps1 tools/README.md
Remove-Item -LiteralPath configs/toolchain-admission.catalog.yaml -Force
Remove-Item -LiteralPath tools/run-ns1304-toolchain-admission-contract.ps1 -Force
Remove-Item -LiteralPath docs/evidence/20260607-ns1304-toolchain-profile.json -Force
Remove-Item -LiteralPath docs/evidence/20260607-ns1304-toolchain-closure.md -Force
```
