# 61 · E002 Natural Language Paper Request

## 1. 完成范围

E002 建立自然语言组卷的 draft/test 起点：教师输入组卷需求后，系统展示“系统理解”、细目表草稿、待确认问题和生产边界。

当前实现不调用真实 AI，不生成正式试卷，不把 draft 动态资产写成生产口径。

## 2. 合同

- API: `POST /paper-requests/parse`
- UI marker: `data-flow="paper-request-understanding"`
- Schema: `schemas/ai/natural_language_paper_request.schema.json`
- Mode: `draft_test`
- `productionEligible`: `false`
- `allowRealModelCalls`: `false`
- 知识点/题型/难度/细目表均按 draft 动态资产处理。

## 3. 验证

独立命令：

```powershell
.\tools\run-e002-paper-request-contract.ps1
```

Full gate：

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-gates.ps1
```

## 4. 后续归宿

E003 在此基础上实现一键换题与撤销。正式知识点、正式题库和生产组卷口径仍由 C002 source-derived activation guard 控制。
