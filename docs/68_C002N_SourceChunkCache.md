# 68 · C002N 来源 chunk 缓存证据

## 目标

C002N 为后续 C002O/C002P/C002Q 建立本地优先的来源证据层：在不调用外部 AI、不激活正式知识体系的前提下，把已准入的 33 份广州物理来源 PDF 转成可复跑、可定位、可估算 token 的页级 chunk/cache。

## 入口

```powershell
.\tools\run-c002n-source-chunk-cache.ps1
```

该入口连续执行两次 `tools/c002n_source_chunk_cache.py`：

- 第一次抽取 PDF 文本并写入 `tmp/c002n-source-chunk-cache`。
- 第二次复跑验证同一 source hash 命中缓存。
- 摘要证据写入 `docs/evidence/c002n-source-chunk-cache-report.json`。

`tmp/` 已被 `.gitignore` 忽略，缓存和原文不提交进 Git。

## 当前证据

截至 2026-05-03，专项 gate 结果：

- `sourceCount`: 33
- `pageCount`: 1478
- `chunkCount`: 1478
- `cacheHitSourceCount`: 33
- `externalAiCalls`: 0
- `summaryChinese.title`: `C002N 来源 chunk 缓存报告`

PDF 工具输出了若干 Poppler 解析警告，例如 `Bad Annot Text Markup QuadPoints`，但命令退出码为 0，且 33 份来源均有非空页级抽取结果。该警告记录为来源 PDF 标注结构质量提示，不阻断 C002N。

## 边界

- 本任务只做 L0 本地确定性抽取、hash、cache、token 估算和中文摘要。
- 不调用真实模型。
- 不写入 `active` 动态资产。
- 不把 chunk 文本本身写入提交证据；提交报告只保留 hash、计数、块类型和少量定位摘要。
- 后续 C002O 才定义语义提炼 schema/eval。
