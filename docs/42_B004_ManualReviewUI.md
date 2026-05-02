# 42 · B004 Manual Review UI 证据

执行日期：2026-05-03。

## 1. 完成范围

- 在 `apps/web` 工作台新增 `导入确认` 区域。
- 提供两页来源预览占位，显示页码与可点击 SourceRegion。
- 提供人工确认操作：
  - 合并跨页题片段。
  - 拆分误切题片段。
  - 关联共用题图/表。
  - 撤销到初始状态。
- 保留修订记录，降低教师额外填写负担。
- 当前是本地状态 UI prototype，不写数据库，不接真实切题算法。

## 2. UI Contract

`tools/run-gates.ps1` 检查这些稳定标记：

```text
data-flow="manual-review"
data-action="merge"
data-action="split"
data-action="associate"
data-action="undo"
修订记录
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
```

## 4. 回滚

代码/文档回滚：

```powershell
git restore --source=HEAD -- apps/web/src/App.tsx apps/web/src/App.css tools/run-gates.ps1 tasks/backlog.csv docs/42_B004_ManualReviewUI.md
```

B004 不新增数据库 migration。
