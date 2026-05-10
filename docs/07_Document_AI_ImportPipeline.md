# 07 · 试题导入与 AI 入库流水线

## 1. 目标

把杂乱的 Word/PDF/图片试卷低人工成本地变成结构化题目。规则、脚本和专用 Adapter 默认处理确定性部分；AI 只处理语义候选、复杂映射和异常复核，人工只处理系统标出的异常。

## 2. 总流程

```text
上传文件
→ 文件 hash 去重
→ 文档安全检查
→ 文档优化/压缩/缩略图
→ 文档解析：OpenXML/OMML → PDF text/layout → Docling → PaddleOCR
→ 页面与版面块识别
→ 题号锚点识别
→ 题目边界预测
→ 题干/选项/小问/答案/解析分离
→ 公式/图片/表格/共用材料识别
→ AI 结构化校正
→ 知识点/题型/难度/来源标注
→ 答案解析初步校验
→ 查重与相似题检测
→ 质量信号计算
→ 自动入库 / 人工确认队列
```

## 3. 专用 Adapter 选择顺序

OCR 和公式识别是专用功能，不是 AI agent。导入流水线必须按以下顺序选择最低成本、最高可追溯的工具：

1. `.docx` 优先读取 OpenXML，公式优先保留 OMML/MathML/LaTeX 表示，图片只作为兜底证据。
2. 文本型 PDF 优先抽取原生 text stream、页码、阅读顺序和 layout block；只有无文本或质量不足时才进入 OCR。
3. Docling 用作结构化文档和版面编排层，输出必须转成 `DocumentModel`、`PageModel`、`LayoutBlock`、`SourceRegion` 和 `AdapterDiagnostic`。
4. 扫描版 PDF 和图片默认走本地 PaddleOCR PP-OCRv5 / PP-StructureV3；低置信度进入 `pending_review`，不得伪装成自动通过。
5. 图片公式和扫描公式默认评估 PaddleOCR FormulaRecognition，先用 `PP-FormulaNet_plus-M` 做质量基线，再按 golden set 证据决定是否评估 `PP-FormulaNet_plus-L`。
6. Mathpix、Azure Document Intelligence 等云端服务只允许作为对照或兜底候选；启用前必须有授权、隐私、成本、缓存、失败回滚和人工确认证据。

## 3.1 Worker 环境与部署档位

文档解析 worker 是外部进程 adapter，允许使用独立 `venv`、`uv`、`conda`、WSL 或 Docker 环境，但必须通过稳定 profile 调用，不能让普通教师配置 Python/OCR 参数。

默认准入顺序：

1. `direct_venv_lite`：API 直接调用独立虚拟环境中的 `python.exe`，适合当前 RapidOCR/ONNX CPU 默认档。
2. `uv_venv_lite`：用 `uv` 创建和同步 `.venv`，但 API 仍调用 `.venv\Scripts\python.exe`；`uv run` 只允许出现在安装、诊断或非生产 launcher 中。
3. `conda_paddle_cpu`：为 PaddleOCR/PP-Structure 建独立 conda env，API 指向 env 内 `python.exe`；不得依赖交互式 shell 激活。
4. `wsl_or_docker_heavy`：只用于依赖重、Linux 更稳定或批处理吞吐有证据的 OCR/公式识别档；必须先有路径映射、volume mount、timeout、UTF-8、模型缓存和失败接管合同。

每个 profile 的运行输出必须进入 `AdapterDiagnostic`：profile 名称、解释器或 launcher、工具版本、模型版本/路径、关键环境变量、输入输出 hash、耗时、warnings/errors。切换默认 profile 前必须用 golden set 对比 OCR 文本、公式、表格、题图、人工接管量和耗时；不能因为“新引擎更强”就直接替换默认实现。

代理执行边界：本地低风险依赖安装、profile 写入、模型缓存目录初始化、诊断脚本和合同门禁由代理执行；需要管理员权限、系统驱动、Docker/WSL 安装、GPU runtime、云端 token 或真实材料授权时暂停确认。安装完成不等于生产准入，只有 profile diagnostic、golden set、人工接管和 full gate 通过后才可作为默认导入路径。

新系统部署时，导入流水线不得假设旧机器的引擎仍然适用。安装器必须先运行 worker profile diagnostic，并根据本机硬件和依赖重新选择 `direct_venv_lite`、`uv_venv_lite`、`conda_paddle_cpu` 或 `wsl_or_docker_heavy`；任何缺失引擎都必须保持人工接管路径可用。

worker profile 只是本地系统配置的一部分。进入 P001 或新电脑安装时，还必须先运行 host capability diagnostic，把 runtime、PostgreSQL、存储备份、导出打印、AI 网络、本地小模型、搜索、后台任务和安全 profile 一并推荐出来；文档导入只消费其中的 `workerOcrProfile`、`storageBackupProfile`、`exportPrintProfile`、`aiNetworkProfile` 和可选 `aiLocalModelProfile`。`aiLocalModelProfile` 只能提供 OCR 文本清理、题干规范化、知识点/难度和讲评草稿候选，不得绕过全局本地系统诊断单独切换 OCR 引擎，也不得替代 OCR/公式识别专用引擎或直接写入 active 数据。

## 4. 人工低成本预处理

对人容易、对 AI 贵的任务，应提供快捷手动处理：

- 合并跨页题。
- 拖拽题图关联到题目或题组。
- 标记答案解析开始位置。
- 删除水印页/空白页。
- 标记共用材料对应题号。

这些操作应写入用户教程，因为能显著降低 AI token 消耗。

## 5. 置信度策略

| 置信度 | 处理 |
|---:|---|
| ≥ 0.90 | 自动入库 |
| 0.75-0.90 | 自动入库，进入抽检池 |
| 0.60-0.75 | 人工确认 |
| < 0.60 | 不入库，标记失败/需重扫 |

每个环节单独记录：切题、OCR、公式、表格、答案、知识点、难度、查重。

## 6. ReviewQueueItem

字段：

```text
id
item_type: cut/question_image/formula/answer/knowledge/difficulty/table/shared_material
question_id/source_document_id
ai_result_id
confidence
suspected_issue
suggested_action
priority
assigned_to
status
```

## 7. 教师操作按钮

导入确认页应提供：

```text
[确认]
[批量确认]
[合并为一题]
[拆分为两题]
[这张图属于本题]
[这张图属于第 N-M 题]
[标记答案开始]
[标记解析开始]
[跳过此页]
[重跑解析/AI]
```

## 8. 人工修改自动反馈

教师修改任何 AI 结果，程序自动 diff 旧值/新值，生成 FeedbackEvent。教师最多点一个原因标签，不额外填表。

## 9. 失败降级

| 失败 | 降级 |
|---|---|
| AI 不可用 | 手动切题和入库 |
| OCR 失败 | 保留原图，允许手动输入 |
| 公式识别失败 | 保存截图，LaTeX 待补 |
| 图文归属失败 | 拖拽关联 |
| 文档解析失败 | 原始文件存档，人工框选 |
