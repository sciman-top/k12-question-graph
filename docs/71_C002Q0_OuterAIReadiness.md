# 71 · C002Q0 Outer AI Readiness

C002Q0 承接 C002N/C002O/C002P，只建立真实模型调用与 outer subagent 编排 readiness。它不启用项目内生产真实模型调用，不写入 `active`，也不把 subagent 变成教师端或项目运行时依赖。

## 1. 入口

```powershell
.\tools\run-c002q0-outer-ai-readiness.ps1
```

默认 manifest：

```text
configs/ai-evals/c002q0-outer-ai-readiness.sample.json
```

默认证据：

```text
docs/evidence/c002q0-outer-ai-readiness-report.json
```

## 2. 校验范围

- C002N chunk/hash/cache 报告必须通过，且外部 AI 调用为 0。
- C002O schema/eval 报告必须通过，且 `allowRealModelCalls=false`、`productionEligible=false`。
- C002P 预算门禁必须通过，证明 full source 超出 C002Q dry-run 上限，full extraction 必须人工预算确认。
- manifest 必须记录 batch、模型角色、reasoning、预算、sample rate、输入/输出 artifact、evidence anchor、cache hit、no active write 和人工审核边界。
- C002Q dry-run sample 不得超过 C002P 上限：4 个 source documents、32 个 chunks、120000 input tokens、20000 output tokens、3 个 L4 items。
- subagent 只允许作为外层并行执行与复核编排方式，不成为项目运行时依赖。

## 3. 边界

C002Q0 只证明下一步 C002Q 可以在显式 dry-run 边界下执行小批量外层 AI 提炼。C002Q 输出仍只能是 `candidate/pending_review/production_eligible=false`，不得覆盖 C002K，不得进入 `active`，也不得代表正式 C002 完成。

项目内真实模型调用仍受 `configs/model_routing.defaults.yaml` 的 `p0_p1_boundary.allow_real_model_calls=false`、D001-D003 合同、AIJob 成本日志、人工审核、rollback/evidence gate 和 production guard 控制。
