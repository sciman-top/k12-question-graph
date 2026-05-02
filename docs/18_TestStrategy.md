# 18 · 测试策略

## 1. 核心思路

本项目必须建立黄金样本集。AI、OCR、切题、导出、成绩导入一旦修改，都要回归测试。

测试策略必须服务于最高原则：验证教师是否更省时，而不只是验证代码能运行。

## 2. 测试类型

| 类型 | 内容 |
|---|---|
| 单元测试 | 业务规则、分数计算、字段映射、权限 |
| 集成测试 | 文档导入、AI 任务、导出、备份恢复 |
| AI Evals | 切题、知识点标注、答案校验、组卷意图解析 |
| 导出回归 | Word/PDF/图片输出、公式、题图、分页 |
| 恢复演练 | 备份包恢复、WinPE 拷贝方案、hash 校验 |
| UX 验收 | 普通教师完成导入/组卷/成绩导入耗时 |
| 安全测试 | 权限越权、上传文件、备份访问 |
| 文档一致性测试 | README、路线图、任务清单、schema、配置是否互相矛盾 |

## 3. 黄金样本集

至少包括：

```text
含共用题图的物理试卷
含跨页题的 PDF
含公式密集的 docx
含表格题的试卷
含答案解析页的试卷
扫描版试卷
典型 Excel 成绩表
典型导出模板
```

建议目录：

```text
tests/fixtures/import-golden/
  README.md
  manifest.json
  shared-image/
  cross-page/
  formula-heavy/
  scanned/
  answer-separated/
  invalid/
```

每个样本目录至少包含：

```text
source 文件
expected_document_model.json
expected_regions.json
notes.md
privacy_and_license.md
```

`invalid/` 用于验证失败接管路径，例如损坏文件、类型不支持、页图缺失、Adapter 超时。

## 4. 验收指标

| 场景 | 指标 |
|---|---|
| 导入 | 高置信度自动入库比例、人工确认题数、切题准确率 |
| 组卷 | 10 分钟内生成可打印试卷，一键换题可撤销 |
| 导出 | 题号/公式/图片/表格不丢，WPS/Word 可打开 |
| 成绩导入 | 字段自动匹配成功率，异常提示准确 |
| 备份 | 可恢复，hash 校验通过 |
| AI 成本 | 单次导入/组卷成本可统计、可控 |

真实教师现场验收暂缓；P0/P1 只做代理流程验收、自动化样本回归和错误路径验证。

## 5. P0/P1 最小门禁

P0/P1 阶段必须建立并持续运行以下门禁：

```text
build: backend build + frontend build + worker syntax/import check
test: backend unit tests + frontend unit tests + worker unit tests
contract/invariant: JSON Schema 可解析 + API contract snapshot + migration 可创建
hotspot: upload/import job/file store/backup manifest 黄金路径测试
```

如果某个子项目尚未创建，必须在当次报告中按 `gate_na` 写明原因、替代验证、证据位置和过期条件。不能因为项目刚开始就跳过硬门禁。

## 6. 文档与 schema 门禁

编码前和修改规划文档后，至少检查：

- `tasks/backlog.csv` 能被 CSV parser 读取。
- `schemas/**/*.json` 均为合法 JSON。
- `configs/**/*.yaml` 均能被 YAML parser 读取；如果当前环境缺 YAML parser，按 `gate_na` 记录替代检查和过期条件。
- README、`docs/19_Roadmap.md`、`docs/20_TaskBreakdown.md` 的 P0/P1 任务编号一致。
- `docs/04_TechnologyStack.md` 与 `prompts/CODEX_CLI_HANDOFF.md` 的技术栈一致。
- `docs/26_References.md` 与 `sources/references.md` 的关键外部来源一致。

文档门禁通过后，需要在当次报告中写明：命令、退出码、关键输出、无法执行项的 `gate_na`、下一次必须恢复执行的条件。

## 7. 升级前门禁

升级前必须：

```text
创建数据库备份
创建文件仓库清单
检查剩余磁盘空间
确认无关键任务运行
运行核心回归测试
生成恢复点
```
