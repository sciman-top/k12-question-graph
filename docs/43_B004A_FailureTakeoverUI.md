# 43 · B004A Failure Takeover UI 证据

执行日期：2026-05-03。

## 1. 完成范围

- 在 `导入确认` 区域新增失败接管面板。
- 明确显示失败诊断：
  - `adapter_failed`
  - stderr 摘要
- 教师在 Adapter/OCR/AI 失败后仍可执行：
  - 框选。
  - 拆分。
  - 合并。
  - 跳过当前页。
  - 重跑 Adapter。
- 操作写入修订记录，避免原始文件、SourceRegion 和 diagnostics 丢失。
- 当前是本地状态 UI prototype，不触发真实 OCR/AI，也不写数据库。

## 2. UI Contract

`tools/run-gates.ps1` 检查这些稳定标记：

```text
data-flow="failure-takeover"
data-action="manual-box"
data-action="takeover-split"
data-action="takeover-merge"
data-action="skip-page"
data-action="rerun-adapter"
adapter_failed
```

## 3. Gate 结果

命令：

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-gates.ps1
```

关键输出应包含：

```text
frontend build: pass
frontend lint: pass
b004 manual review ui contract: pass
b004a failure takeover ui contract: pass
```

## 4. 回滚

代码/文档回滚：

```powershell
git restore --source=HEAD -- apps/web/src/App.tsx apps/web/src/App.css tools/run-gates.ps1 tasks/backlog.csv docs/43_B004A_FailureTakeoverUI.md
```

B004A 不新增数据库 migration。
