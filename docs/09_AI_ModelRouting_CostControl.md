# 09 · AI 模型路由与成本控制

## 1. 核心原则

模型路由是系统内置模块，不是使用建议。普通教师不需要知道模型名称和 token 策略。

## 2. 处理层级

```text
规则/本地算法
→ 本地 OCR/文档解析
→ 小模型
→ 中模型
→ 强模型
→ 人工确认
```

## 3. 任务路由

| 任务 | 默认策略 |
|---|---|
| 文件去重 | hash 规则 |
| 总分/题号连续检查 | 程序规则 |
| 普通 OCR | 本地 OCR |
| 版面初解析 | Docling/PaddleOCR |
| 知识点候选 | 小/中模型 |
| 自然语言组卷 | 中模型 + 结构化输出 |
| 答案校验 | 中/强模型，正式题更严格 |
| 疑难图文关系 | 强模型或人工 |
| 批量标注 | Batch |
| Embedding | 批量、缓存、去重 |

## 4. AIJob 记录

```text
job_type
input_hash
model_provider
model_name
prompt_version
schema_version
output_json
confidence
input_tokens
output_tokens
cached_tokens
cost
latency_ms
review_status
teacher_modified
```

## 5. 成本控制策略

1. 本地 OCR 优先。
2. 规则优先处理确定性任务。
3. 只发送必要上下文。
4. 固定知识点体系、题型定义、JSON Schema 放 prompt 前缀，利用缓存。
5. 同一输入 + 同一 prompt 版本 + 同一模型结果复用。
6. 大批量任务走 Batch。
7. 低价值任务不用强模型。
8. 人工已经标记的结果不再重复让 AI 判断。
9. 任务级显示预计成本：低/中/高。

## 6. 教师可见界面

普通教师只看到：

```text
低成本模式 / 均衡模式 / 高准确模式
本次任务预计成本：低/中/高
建议：先手动标记共用题图，可降低 AI 费用
```

不要显示复杂模型参数。

## 7. 结构化输出

所有 AI 业务输出必须遵循 JSON Schema。禁止把自由文本直接作为数据库业务字段。

## 8. P0/P1 边界

P0/P1 不接真实模型作为完成条件，只建立：

- JSON Schema。
- AIJob/AIResult 数据结构。
- prompt_version/schema_version/cost/confidence 字段。
- Worker/Adapter 占位返回。
- 黄金样本目录与 eval 入口预留。

真实 AI 调用、Batch、Evals、prompt caching 优化进入 P3；如果 P1 必须临时调用 AI，只能作为可替换 adapter，且不能绕过人工确认队列。

## 9. Prompt caching 与成本字段

稳定内容放请求前缀：

- 系统任务说明。
- 初中物理题型定义。
- 知识点 schema。
- JSON Schema。
- 评分和置信度规则。

动态内容放后面：

- 当前文档页内容。
- 当前题目候选。
- 教师本次操作上下文。

AIJob 必须记录 `cached_tokens`，如果 provider 不返回该字段，按 `platform_na` 记录并保留替代成本证据。
