# 74 · E003 一键换题与撤销

E003 在 E002 自然语言组卷草稿基础上建立 draft/test 换题合同。目标是验证教师在试卷草稿中可以一键替换题目，并且可以撤销回原题。

当前实现不生成正式试卷，不依赖正式 C002 active，不调用真实模型，也不写生产组卷口径。

## 合同

- API: `POST /paper-requests/replace-question`
- UI marker: `data-flow="paper-question-replacement"`
- Mode: `draft_test`
- `productionEligible`: `false`
- `allowRealModelCalls`: `false`
- 换题必须保持：
  - 同知识点。
  - 同题型。
  - 相近难度。
  - 同分值。
  - 当前卷不重复。
  - 近期未用。
- 响应必须包含 `undo.undoToken`、`beforeQuestion`、`afterQuestion` 和 `revertAction`。

## 验证

独立命令：

```powershell
.\tools\run-e003-question-replacement-contract.ps1
```

Full gate：

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-gates.ps1
```

## 后续归宿

E004 在此基础上做 Word/PDF 导出 MVP。正式知识点、正式题库和生产试卷语义仍由 C002 source-derived activation guard 控制。

## 回滚

```powershell
git restore --source=HEAD -- apps/api/Program.cs apps/web/src/App.tsx apps/web/src/App.css README.md docs/20_TaskBreakdown.md tasks/backlog.csv tools/README.md tools/run-gates.ps1
git clean -f -- tools/run-e003-question-replacement-contract.ps1 docs/74_E003_QuestionReplacementUndo.md
```
