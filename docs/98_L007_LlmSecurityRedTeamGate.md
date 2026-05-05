# 98 · L007 LLM Security Red-Team Gate

## 1. 目标

在任何真实模型调用试点前，先把 LLM 风险检查固定为可执行 gate，覆盖：

- prompt injection
- sensitive information disclosure
- insecure output handling
- supply chain / tool dependency risk
- vector or embedding weakness
- excessive agency

并与 `no active write`、人工审核和预算边界联动。

## 2. 最小检查清单

每次准备开启真实模型试点前，必须逐项记录 `pass/fail/na + evidence`：

| 风险项 | 最低控制 |
|---|---|
| prompt injection | 输入分层、系统提示固定、拒绝执行越权指令、低置信度转人工 |
| sensitive information disclosure | 学生 PII/成绩默认不外传、脱敏和最小化、日志去敏 |
| insecure output handling | AI 输出只进 `candidate/pending_review`，不自动写 `active` |
| supply chain/tool risk | provider/model/tool 版本可追溯，调用源与 hash 可审计 |
| vector/embedding weakness | 检索证据保留来源和置信度，冲突项进人工审核 |
| excessive agency | 禁止模型直接执行高风险写操作，必须显式人工确认 |

## 3. 对齐 OWASP / NIST

- OWASP LLM Top 10：重点对齐 prompt injection、数据泄露、不安全输出、过度代理、供应链风险。
- NIST AI RMF / GenAI Profile：重点对齐治理、可追溯、风险控制、人工监督与恢复能力。

## 4. 与仓库现状联动

- `docs/evidence/c002q0-outer-ai-readiness-report.json` 必须保持：
  - `allowProjectRuntimeRealModelCalls=false`
  - `noActiveWrite=true`
  - `humanReviewRequired=true`
- `docs/evidence/c002q-ai-extract-dry-run-report.json` 必须保持：
  - `allowRealModelCalls=false`
  - `externalAiCalls=0`
  - `reviewStatus=pending_review`

## 5. 执行命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-l007-llm-security-red-team-gate.ps1
```

